import type { Json } from '../types/database';
import type { Env } from '../types/env';
import {
  DEFAULT_WEIGHTS,
  type ExpertPreferences,
  type ExpertProfile,
  type MatchResult,
  type MatchingWeights,
  type ProspectRequirements,
  type QualityTier,
  type ScoreBreakdown,
} from '../types/matching';
import { scoreMatch, applyReliabilityModifier } from '../matching/score';
import { writeMatchingDataPoint } from '../lib/matchingAnalytics';
import { createSql } from '../lib/db';
import { loadExpertPool } from '../lib/expertPool';
import type { ProspectRow, MatchRow, SatelliteConfigRow, ExpertRow } from '../types/db';
import { calculateLeadPrice } from '../lib/pricing';
import { loadBillingData, applyBillingFilters } from '../lib/billingFilter';
import { loadAdmissibilityData, applyAdmissibilityFilters } from '../lib/admissibilityFilter';
import type { ProspectContext } from '../lib/admissibilityFilter';
import type { ProspectRequirements as _PR } from '../types/matching';
import { deriveQualityTier } from '../lib/qualityTier';

// ── Helpers ───────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

// ── POST /api/matches/compute ─────────────────────────────────────────────────
// AC7: loads prospect + available experts, scores, stores top-20, returns results
// AC10 (B2 fix): uses loadExpertPool(env) instead of direct DB query for experts

export async function handleMatchCompute(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  let body: { prospect_id?: unknown; satellite_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { prospect_id, satellite_id } = body;

  if (typeof prospect_id !== 'string' || !prospect_id) {
    return errorResponse('prospect_id is required', 422, { prospect_id: 'must be a non-empty string' });
  }

  const sql = createSql(env);

  // Load prospect (needed for effectiveSatelliteId in notifications)
  const [prospect] = await sql<Pick<ProspectRow, 'id' | 'requirements' | 'satellite_id'>[]>`
    SELECT id, requirements, satellite_id FROM prospects WHERE id = ${prospect_id}`;
  if (!prospect) return errorResponse('Prospect not found', 404);

  const effectiveSatelliteId = satellite_id ?? prospect.satellite_id;

  // AC4 (E06S24): Delegate to callibrate-matching via Service Binding (zero network hop)
  // AC6: Fallback to local deterministic scoring when MATCHING_SERVICE not bound
  if (env.MATCHING_SERVICE) {
    const matchResp = await env.MATCHING_SERVICE.fetch(
      new Request('https://matching/match', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prospect_id, satellite_id }),
      })
    );
    if (!matchResp.ok) return matchResp;
    const matchBody = await matchResp.json() as {
      computed: number;
      top_matches: unknown[];
      billing_excluded?: { expert_id: string; reason: string }[];
      admissibility_excluded?: { expert_id: string; reason: string }[];
    };
    const billingExcluded = matchBody.billing_excluded ?? [];
    if (billingExcluded.length > 0) {
      const reqs = (prospect.requirements ?? {}) as { budget_range?: { max?: number } };
      const lpResult = calculateLeadPrice(reqs.budget_range?.max ?? null, { budget_max: reqs.budget_range?.max ?? null });
      for (const ex of billingExcluded) {
        ctx.waitUntil(
          env.EMAIL_NOTIFICATIONS.send({
            type: 'expert.billing.lead_missed',
            expert_id: ex.expert_id,
            reason: ex.reason as 'insufficient_balance' | 'max_lead_price_exceeded' | 'spending_limit_reached',
            prospect_vertical: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : '',
            budget_tier: lpResult.tier,
          })
        );
      }
    }
    const admissibilityExcluded = matchBody.admissibility_excluded ?? [];
    for (const ex of admissibilityExcluded) {
      ctx.waitUntil(
        env.EMAIL_NOTIFICATIONS.send({
          type: 'expert.admissibility.lead_missed',
          expert_id: ex.expert_id,
          reason: ex.reason,
          prospect_vertical: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : '',
        })
      );
    }
    return new Response(
      JSON.stringify({
        computed: matchBody.computed,
        top_matches: matchBody.top_matches,
        admissibility_excluded: admissibilityExcluded.length,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // AC6 Fallback: local scoring without Vectorize (MATCHING_SERVICE not available in dev/test)
  const startTime = Date.now();

  // Resolve matching weights (satellite override or default)
  let weights: MatchingWeights = DEFAULT_WEIGHTS;

  if (typeof effectiveSatelliteId === 'string' && effectiveSatelliteId) {
    const [satConfig] = await sql<Pick<SatelliteConfigRow, 'matching_weights'>[]>`
      SELECT matching_weights FROM satellite_configs WHERE id = ${effectiveSatelliteId}`;

    if (satConfig?.matching_weights && typeof satConfig.matching_weights === 'object') {
      weights = satConfig.matching_weights as unknown as MatchingWeights;
    }
  }

  // B2 fix (AC10): Load experts via loadExpertPool (KV-cached) instead of direct DB query
  const expertPool = await loadExpertPool(env);
  if (expertPool.length === 0) {
    return jsonResponse({ computed: 0, top_matches: [] });
  }

  // Score each expert using the pool (includes pre-computed total_leads)
  const requirements = (prospect.requirements ?? {}) as ProspectRequirements;

  // AC1: calculate leadPrice once
  const budgetMax = requirements.budget_range?.max ?? null;
  const lpResult = calculateLeadPrice(budgetMax, { budget_max: budgetMax });
  const leadPrice = lpResult.amount;

  // AC2–AC4: apply billing filter
  const billingMap = await loadBillingData(env, expertPool.map((e) => e.id));
  const { eligible: billingEligible, excluded: billingExcluded } = applyBillingFilters(expertPool, billingMap, leadPrice);

  // AC6: fire-and-forget billing exclusion notifications
  for (const ex of billingExcluded) {
    ctx.waitUntil(
      env.EMAIL_NOTIFICATIONS.send({
        type: 'expert.billing.lead_missed',
        expert_id: ex.expert_id,
        reason: ex.reason,
        prospect_vertical: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : '',
        budget_tier: lpResult.tier,
      })
    );
  }

  // AC4 (E06S36): apply admissibility filter AFTER billing, BEFORE scoring
  const admissibilityMap = await loadAdmissibilityData(env, billingEligible.map((e) => e.id));
  const prospectCtx: ProspectContext = {
    industry: (requirements as { industry?: string }).industry ?? null,
    vertical: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : null,
    timeline: (requirements as { timeline?: string }).timeline ?? null,
    budget_max: requirements.budget_range?.max ?? null,
    skills_needed: requirements.skills_needed ?? [],
    methodology: (requirements as { methodology?: string[] }).methodology ?? [],
  };
  const { eligible, excluded: admissibilityExcluded } = applyAdmissibilityFilters(
    billingEligible,
    admissibilityMap,
    prospectCtx,
  );

  // AC6 (E06S36): fire-and-forget admissibility exclusion notifications
  for (const ex of admissibilityExcluded) {
    ctx.waitUntil(
      env.EMAIL_NOTIFICATIONS.send({
        type: 'expert.admissibility.lead_missed',
        expert_id: ex.expert_id,
        reason: ex.reason,
        prospect_vertical: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : '',
      })
    );
  }

  // AC7: all excluded → empty results
  if (eligible.length === 0) {
    return jsonResponse({ computed: 0, top_matches: [], admissibility_excluded: admissibilityExcluded.length });
  }

  const scored = eligible.map((expert) => {
    const profile: ExpertProfile = {
      ...((expert.profile ?? {}) as ExpertProfile),
      rate_min: expert.rate_min,
      rate_max: expert.rate_max,
    };
    const prefs = (expert.preferences ?? {}) as ExpertPreferences;
    const raw = scoreMatch(profile, prefs, requirements, weights);
    const matchScore = applyReliabilityModifier(raw, {
      composite_score: expert.composite_score,
      total_leads: expert.total_leads,
    });

    return { expert, matchScore };
  });

  // Sort by score DESC, take top 20
  scored.sort((a, b) => b.matchScore.score - a.matchScore.score);
  const top20 = scored.slice(0, 20);

  // Upsert into matches table: delete existing, then insert fresh
  if (top20.length > 0) {
    await sql`DELETE FROM matches WHERE prospect_id = ${prospect_id}`;

    for (const { expert, matchScore } of top20) {
      await sql`
        INSERT INTO matches (prospect_id, expert_id, score, score_breakdown, status, expires_at)
        VALUES (${prospect_id}, ${expert.id}, ${matchScore.score}, ${JSON.stringify(matchScore.breakdown)}::jsonb, 'active', ${new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()})
        ON CONFLICT DO NOTHING`;
    }
  }

  // Build anonymized MatchResult list
  const topMatches: MatchResult[] = top20.map(({ expert, matchScore }) => {
    const profile = (expert.profile ?? {}) as ExpertProfile;
    return {
      match_id: '', // not yet persisted ID — caller can use GET to retrieve with IDs
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

  // AC2/AC3: fire-and-forget analytics — does not block response
  const meanScore =
    scored.length > 0
      ? scored.reduce((sum, s) => sum + s.matchScore.score, 0) / scored.length
      : 0;
  writeMatchingDataPoint(env, {
    endpoint: '/api/matches/compute',
    satelliteId: typeof effectiveSatelliteId === 'string' ? effectiveSatelliteId : '',
    latencyMs: Date.now() - startTime,
    poolSize: eligible.length,
    topScore: top20[0]?.matchScore.score ?? 0,
    meanScore,
  });

  return jsonResponse({
    computed: top20.length,
    top_matches: topMatches,
    admissibility_excluded: admissibilityExcluded.length,
  });
}

// ── GET /api/matches/:prospect_id ─────────────────────────────────────────────
// AC8: returns top-5 matches per page, sorted by score DESC then composite_score DESC
// AC9: anonymized — no display_name, avatar_url, cal_username
// AC12: quality_tier derived from composite_score

export async function handleMatchGet(request: Request, env: Env, prospectId: string): Promise<Response> {
  const url = new URL(request.url);
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10) || 1);
  const pageSize = 5;
  const offset = (page - 1) * pageSize;

  const sql = createSql(env);

  // Fetch matches (excluding expired), sorted by score DESC, paginated
  const matches = await sql<Pick<MatchRow, 'id' | 'expert_id' | 'score' | 'score_breakdown'>[]>`
    SELECT id, expert_id, score, score_breakdown FROM matches
    WHERE prospect_id = ${prospectId} AND status != 'expired'
    ORDER BY score DESC
    LIMIT ${pageSize} OFFSET ${offset}`;

  if (!matches || matches.length === 0) {
    return jsonResponse({ results: [], page, page_size: pageSize, total: 0 });
  }

  // Fetch expert composite_score and profile for tiebreaker and anonymized fields
  const expertIds = matches.map((m) => m.expert_id).filter(Boolean) as string[];
  const experts = await sql<Pick<ExpertRow, 'id' | 'composite_score' | 'profile' | 'rate_min' | 'rate_max'>[]>`
    SELECT id, composite_score, profile, rate_min, rate_max FROM experts WHERE id = ANY(${expertIds})`;

  const expertMap = new Map(experts.map((e) => [e.id, e]));

  // Build anonymized results — AC9: no display_name, avatar_url, cal_username
  const results: MatchResult[] = matches.map((match) => {
    const expert = expertMap.get(match.expert_id ?? '');
    const profile = (expert?.profile ?? {}) as ExpertProfile;

    return {
      match_id: match.id,
      expert_id: match.expert_id ?? '',
      score: match.score ?? 0,
      score_breakdown: (match.score_breakdown ?? {}) as unknown as ScoreBreakdown,
      quality_tier: deriveQualityTier(expert?.composite_score ?? null),
      skills: profile.skills ?? [],
      industries: profile.industries ?? [],
      project_types: profile.project_types ?? [],
      languages: profile.languages ?? [],
      rate_min: expert?.rate_min ?? null,
      rate_max: expert?.rate_max ?? null,
    };
  });

  // Secondary sort: composite_score DESC as tiebreaker (within same score)
  results.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    const aExpert = expertMap.get(a.expert_id);
    const bExpert = expertMap.get(b.expert_id);
    return (bExpert?.composite_score ?? 0) - (aExpert?.composite_score ?? 0);
  });

  return jsonResponse({ results, page, page_size: pageSize });
}
