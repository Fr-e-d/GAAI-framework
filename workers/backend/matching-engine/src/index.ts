// ── callibrate-matching Worker ─────────────────────────────────────────────────
// Compute-heavy operations: Vectorize semantic search, D1 edge cache, scoring.
// Accessed from callibrate-core via Service Binding (MATCHING_SERVICE) — zero network hop.
//
// Routes:
//   POST /match           — full scoring pipeline for a prospect
//   POST /embed           — upsert a single expert embedding into Vectorize
//   POST /admin/reindex   — batch reindex all expert embeddings

import type { MatchingEnv } from './env';
import { createSql } from './db';
import { loadExpertPool } from './expertPool';
import {
  buildEmbeddingText,
  buildProspectEmbeddingText,
  upsertExpertEmbedding,
  queryVectorize,
  embedStrings,
  computeTagEmbeddings,
  computeAlignmentsFromPrecomputed,
} from './vectorize';
import { loadOutcomeEmbeddings, upsertOutcomeEmbedding } from './d1ExpertPool';
import { scoreMatch, applyReliabilityModifier } from './score';
import {
  DEFAULT_WEIGHTS,
  type ExpertProfile,
  type ExpertPreferences,
  type ProspectRequirements,
  type MatchingWeights,
  type MatchResult,
  type QualityTier,
  type ProspectRow,
  type SatelliteConfigRow,
  type ExpertRow,
  type BillingExclusion,
} from './types';
import { calculateLeadPrice } from './pricing';

// ── Helpers ───────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number): Response {
  return jsonResponse({ error }, status);
}

function deriveQualityTier(compositeScore: number | null): QualityTier {
  if (!compositeScore || compositeScore === 0) return 'new';
  if (compositeScore <= 25) return 'rising';
  if (compositeScore <= 60) return 'established';
  return 'top';
}

function writeDataPoint(
  env: MatchingEnv,
  params: { endpoint: string; satelliteId: string; latencyMs: number; poolSize: number; topScore: number; meanScore: number },
): void {
  try {
    env.MATCHING_ANALYTICS?.writeDataPoint({
      blobs: [params.satelliteId, params.endpoint],
      doubles: [params.latencyMs, params.poolSize, params.topScore, params.meanScore],
    });
  } catch { /* analytics must never impact request path */ }
}

// ── POST /match ───────────────────────────────────────────────────────────────
// Full scoring pipeline: load prospect → load weights → load pool →
// Vectorize pre-filter → score candidates → write top-20 matches → return results

async function handleMatch(request: Request, env: MatchingEnv, ctx: ExecutionContext): Promise<Response> {
  const startTime = Date.now();

  let body: { prospect_id?: unknown; satellite_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { prospect_id, satellite_id } = body;
  if (typeof prospect_id !== 'string' || !prospect_id) {
    return errorResponse('prospect_id is required', 422);
  }

  const sql = createSql(env);

  // Load prospect requirements
  const [prospect] = await sql<Pick<ProspectRow, 'id' | 'requirements' | 'satellite_id'>[]>`
    SELECT id, requirements, satellite_id FROM prospects WHERE id = ${prospect_id}`;
  if (!prospect) return errorResponse('Prospect not found', 404);

  // Resolve matching weights (satellite override or default)
  const effectiveSatelliteId = typeof satellite_id === 'string' && satellite_id
    ? satellite_id
    : prospect.satellite_id;
  let weights: MatchingWeights = DEFAULT_WEIGHTS;

  if (typeof effectiveSatelliteId === 'string' && effectiveSatelliteId) {
    const [satConfig] = await sql<Pick<SatelliteConfigRow, 'matching_weights'>[]>`
      SELECT matching_weights FROM satellite_configs WHERE id = ${effectiveSatelliteId}`;
    if (satConfig?.matching_weights && typeof satConfig.matching_weights === 'object') {
      weights = satConfig.matching_weights as unknown as MatchingWeights;
    }
  }

  // Load expert pool (Cache API L1 → D1 → Hyperdrive)
  const expertPool = await loadExpertPool(env);
  if (expertPool.length === 0) {
    return jsonResponse({ computed: 0, top_matches: [] });
  }

  const requirements = (prospect.requirements ?? {}) as ProspectRequirements;

  // AC1: calculate leadPrice once for this match request
  const budgetMax = (requirements.budget_range as { max?: number } | undefined)?.max ?? null;
  const leadPriceResult = calculateLeadPrice(budgetMax, {
    budget_max: budgetMax,
    timeline_days: null,
    skills: requirements.skills_needed ?? [],
  });
  const leadPrice = leadPriceResult.amount;

  // AC2–AC4: load billing data and apply filter (live Hyperdrive queries)
  const poolExpertIds = expertPool.map((e) => e.id);
  const billingRows = await sql<
    { id: string; credit_balance: number; max_lead_price: number | null; spending_limit: number | null }[]
  >`SELECT id, credit_balance, max_lead_price, spending_limit FROM experts WHERE id = ANY(${poolExpertIds})`;

  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);
  const spendRows = await sql<{ expert_id: string; monthly_spend: number }[]>`
    SELECT expert_id, COALESCE(SUM(ABS(amount)), 0)::integer AS monthly_spend
    FROM credit_transactions
    WHERE type = 'lead_debit'
      AND expert_id = ANY(${poolExpertIds})
      AND created_at >= ${monthStart.toISOString()}
    GROUP BY expert_id`;

  // Build billing map
  const billingMap = new Map<string, { credit_balance: number; max_lead_price: number | null; spending_limit: number | null; monthly_spend: number }>();
  for (const row of billingRows) {
    billingMap.set(row.id, { credit_balance: row.credit_balance, max_lead_price: row.max_lead_price, spending_limit: row.spending_limit, monthly_spend: 0 });
  }
  for (const row of spendRows) {
    const existing = billingMap.get(row.expert_id);
    if (existing) existing.monthly_spend = row.monthly_spend;
  }

  // Apply billing filter
  const billingExcluded: BillingExclusion[] = [];
  const eligible = expertPool.filter((expert) => {
    const billing = billingMap.get(expert.id) ?? { credit_balance: 0, max_lead_price: null, spending_limit: null, monthly_spend: 0 };
    if (billing.credit_balance < leadPrice) {
      billingExcluded.push({ expert_id: expert.id, reason: 'insufficient_balance' });
      return false;
    }
    if (billing.max_lead_price !== null && leadPrice > billing.max_lead_price) {
      billingExcluded.push({ expert_id: expert.id, reason: 'max_lead_price_exceeded' });
      return false;
    }
    if (billing.spending_limit !== null && billing.monthly_spend + leadPrice > billing.spending_limit) {
      billingExcluded.push({ expert_id: expert.id, reason: 'spending_limit_reached' });
      return false;
    }
    return true;
  });

  // AC7: all experts excluded → return empty results (HTTP 200)
  if (eligible.length === 0) {
    return jsonResponse({ computed: 0, top_matches: [], billing_excluded: billingExcluded });
  }

  // Vectorize semantic pre-filter
  let candidates = eligible;
  let similarityMap = new Map<string, number>();

  try {
    const embeddingText = buildProspectEmbeddingText(requirements);
    const embeddingResult = await env.AI.run('@cf/baai/bge-base-en-v1.5', {
      text: [embeddingText],
    }) as { data: number[][] };
    const vector = embeddingResult.data[0];

    if (vector && vector.length > 0) {
      const topK = 100; // cap candidates — D1 outcome embeddings load bounded to ~6 MB regardless of pool size
      similarityMap = await queryVectorize(env, vector, topK);
      if (similarityMap.size > 0) {
        const candidateIds = new Set(similarityMap.keys());
        const filtered = eligible.filter((e) => candidateIds.has(e.id));
        if (filtered.length > 0) candidates = filtered;
      }
    }
  } catch (err) {
    // Vectorize unavailable — fall back to deterministic scoring over full eligible pool
    console.error('matching: Vectorize query failed, falling back to deterministic scoring', err);
    candidates = eligible;
    similarityMap = new Map();
  }

  // AC9/E06S37: Compute outcome alignment using pre-computed expert tag embeddings from D1.
  // Expert embeddings are stored at profile-save time (/embed, /admin/reindex) — never at match time.
  // Only the prospect's desired_outcomes (max 5 strings) are embedded here: 1 AI call regardless of pool size.
  let outcomeAlignmentMap = new Map<string, number>();
  const desiredOutcomes = (requirements.desired_outcomes ?? []).filter((s): s is string => typeof s === 'string');
  if (desiredOutcomes.length > 0 && candidates.length > 0 && env.EXPERT_DB) {
    try {
      const candidateIds = candidates.map((c) => c.id);
      const expertEmbeddingsMap = await loadOutcomeEmbeddings(env.EXPERT_DB, candidateIds);
      if (expertEmbeddingsMap.size > 0) {
        const desiredEmbeddings = await embedStrings(env.AI, desiredOutcomes);
        outcomeAlignmentMap = computeAlignmentsFromPrecomputed(expertEmbeddingsMap, desiredEmbeddings);
      }
    } catch (err) {
      console.error('matching: outcome alignment computation failed, skipping', err);
    }
  }

  // Score each candidate
  const scored = candidates.map((expert) => {
    const profile: ExpertProfile = {
      ...((expert.profile ?? {}) as ExpertProfile),
      rate_min: expert.rate_min,
      rate_max: expert.rate_max,
    };
    const prefs = (expert.preferences ?? {}) as ExpertPreferences;
    const semanticSimilarity = similarityMap.get(expert.id);
    // AC11/E06S37: pass pre-computed outcome alignment (null if no data for this expert)
    const outcomeAlignment = outcomeAlignmentMap.has(expert.id)
      ? (outcomeAlignmentMap.get(expert.id) ?? null)
      : null;
    const raw = scoreMatch(profile, prefs, requirements, weights, semanticSimilarity, outcomeAlignment);
    const matchScore = applyReliabilityModifier(raw, {
      composite_score: expert.composite_score,
      total_leads: expert.total_leads,
    });
    return { expert, matchScore };
  });

  scored.sort((a, b) => b.matchScore.score - a.matchScore.score);
  const top20 = scored.slice(0, 20);

  // Upsert matches (delete old, insert fresh)
  if (top20.length > 0) {
    await sql`DELETE FROM matches WHERE prospect_id = ${prospect_id}`;
    for (const { expert, matchScore } of top20) {
      await sql`
        INSERT INTO matches (prospect_id, expert_id, score, score_breakdown, status, expires_at)
        VALUES (${prospect_id}, ${expert.id}, ${matchScore.score}, ${JSON.stringify(matchScore.breakdown)}::jsonb, 'active', ${new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()})
        ON CONFLICT DO NOTHING`;
    }
  }

  // Analytics
  const allScores = scored.map((s) => s.matchScore.score);
  const topScore = top20[0]?.matchScore.score ?? 0;
  const meanScore = allScores.length > 0 ? allScores.reduce((a, b) => a + b, 0) / allScores.length : 0;
  writeDataPoint(env, {
    endpoint: '/match',
    satelliteId: effectiveSatelliteId ?? '',
    latencyMs: Date.now() - startTime,
    poolSize: eligible.length,
    topScore,
    meanScore,
  });

  // Build anonymized result list
  const topMatches: MatchResult[] = top20.map(({ expert, matchScore }) => {
    const profile = (expert.profile ?? {}) as ExpertProfile;
    return {
      match_id: '',
      expert_id: expert.id,
      score: matchScore.score,
      score_breakdown: matchScore.breakdown,
      quality_tier: deriveQualityTier(expert.composite_score),
      skills: profile.skills ?? [],
      industries: profile.industries ?? [],
      project_types: profile.project_types ?? [],
      languages: profile.languages ?? [],
      rate_min: expert.rate_min ?? null,
      rate_max: expert.rate_max ?? null,
    };
  });

  return jsonResponse({ computed: top20.length, top_matches: topMatches, billing_excluded: billingExcluded });
}

// ── POST /embed ───────────────────────────────────────────────────────────────
// Fire-and-forget expert embedding upsert.

async function handleEmbed(request: Request, env: MatchingEnv, ctx: ExecutionContext): Promise<Response> {
  let body: {
    expert_id?: unknown;
    profile?: unknown;
    rate_min?: unknown;
    rate_max?: unknown;
    availability?: unknown;
    outcome_tags?: unknown; // E06S37: pre-compute and store tag embeddings in D1
  };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  if (typeof body.expert_id !== 'string' || !body.expert_id) {
    return errorResponse('expert_id is required', 422);
  }

  const expertId = body.expert_id;

  upsertExpertEmbedding(env, ctx, expertId, {
    profile: (body.profile ?? {}) as { skills?: string[]; industries?: string[]; project_types?: string[]; languages?: string[] },
    rate_min: typeof body.rate_min === 'number' ? body.rate_min : null,
    rate_max: typeof body.rate_max === 'number' ? body.rate_max : null,
    availability: typeof body.availability === 'string' ? body.availability : null,
  });

  // Store pre-computed outcome_tags embeddings in D1 (fire-and-forget).
  // Eliminates on-the-fly embedding of expert tags at match time.
  const outcomeTags = Array.isArray(body.outcome_tags)
    ? (body.outcome_tags as unknown[]).filter((s): s is string => typeof s === 'string')
    : [];
  if (outcomeTags.length > 0 && env.EXPERT_DB) {
    ctx.waitUntil(
      (async () => {
        try {
          const embeddings = await computeTagEmbeddings(env.AI, outcomeTags);
          await upsertOutcomeEmbedding(env.EXPERT_DB!, expertId, embeddings);
        } catch (err) {
          console.error('matching: outcome tag embedding storage failed for expert', expertId, err);
        }
      })()
    );
  }

  return jsonResponse({ ok: true });
}

// ── POST /admin/reindex ───────────────────────────────────────────────────────
// Batch reindex all expert embeddings. Auth check is done in Core before calling this.

async function handleAdminReindex(request: Request, env: MatchingEnv, ctx: ExecutionContext): Promise<Response> {
  const sql = createSql(env);

  const experts = await sql<Pick<ExpertRow, 'id' | 'profile' | 'rate_min' | 'rate_max' | 'availability' | 'outcome_tags'>[]>`
    SELECT id, profile, rate_min, rate_max, availability, outcome_tags FROM experts
    WHERE availability != 'unavailable'`;

  const total = experts.length;

  ctx.waitUntil(
    (async () => {
      for (const expert of experts) {
        try {
          // Vectorize: profile text embedding (skills, industries, etc.)
          const text = buildEmbeddingText((expert.profile ?? {}) as { skills?: string[]; industries?: string[]; project_types?: string[]; languages?: string[] });
          const result = await env.AI.run('@cf/baai/bge-base-en-v1.5', {
            text: [text],
          }) as { data: number[][] };
          const vector = result.data[0];
          if (!vector || vector.length === 0) {
            console.warn('reindex: empty embedding for expert', expert.id);
            continue;
          }
          const metadata: Record<string, string | number | boolean> = { expert_id: expert.id };
          if (expert.rate_min != null) metadata.rate_min = expert.rate_min;
          if (expert.rate_max != null) metadata.rate_max = expert.rate_max;
          if (expert.availability != null) metadata.availability = expert.availability;
          await env.VECTORIZE.upsert([{ id: expert.id, values: vector, metadata }]);

          // D1: outcome_tags embeddings pre-computation (E06S37 scalability fix)
          const outcomeTags = expert.outcome_tags ?? [];
          if (outcomeTags.length > 0 && env.EXPERT_DB) {
            try {
              const embeddings = await computeTagEmbeddings(env.AI, outcomeTags);
              await upsertOutcomeEmbedding(env.EXPERT_DB, expert.id, embeddings);
            } catch (err) {
              console.error('reindex: outcome embedding failed for expert', expert.id, err);
            }
          }
        } catch (err) {
          console.error('reindex: failed for expert', expert.id, err);
        }
      }
    })()
  );

  return jsonResponse({ queued: total }, 202);
}

// ── Worker entry ─────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: MatchingEnv, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;
    const { method } = request;

    if (method === 'POST' && pathname === '/match') {
      return handleMatch(request, env, ctx);
    }

    if (method === 'POST' && pathname === '/embed') {
      return handleEmbed(request, env, ctx);
    }

    if (method === 'POST' && pathname === '/admin/reindex') {
      return handleAdminReindex(request, env, ctx);
    }

    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  },
} satisfies ExportedHandler<MatchingEnv>;
