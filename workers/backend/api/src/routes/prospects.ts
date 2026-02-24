// ── Satellite funnel — prospect routes ────────────────────────────────────────
// AC2/AC3: POST /api/prospects/submit
// AC4/AC5/AC6: GET /api/prospects/:id/matches?token=xxx
// AC7/AC8: POST /api/prospects/:id/identify
// AC10: consistent error shape { error: string, details?: object }

import type { Json } from '../types/database';
import type { Env } from '../types/env';
import { checkRateLimit } from '../lib/rateLimit';
import {
  DEFAULT_WEIGHTS,
  type ExpertPreferences,
  type ExpertProfile,
  type MatchingWeights,
  type ProspectRequirements,
  type ScoreBreakdown,
} from '../types/matching';
import { scoreMatch, applyReliabilityModifier } from '../matching/score';
import { signProspectToken, verifyProspectToken } from '../lib/jwt';
import { loadExpertPool } from '../lib/expertPool';
import { writeMatchingDataPoint } from '../lib/matchingAnalytics';
import { createSql } from '../lib/db';
import type { ProspectRow, MatchRow, SatelliteConfigRow, ExpertRow } from '../types/db';
import { captureEvent } from '../lib/posthog';
import { calculateLeadPrice } from '../lib/pricing';
import { loadBillingData, applyBillingFilters } from '../lib/billingFilter';
import { loadAdmissibilityData, applyAdmissibilityFilters } from '../lib/admissibilityFilter';
import type { ProspectContext } from '../lib/admissibilityFilter';


// ── Helpers ───────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

// Basic email format validation (RFC-permissive, sufficient for MVP)
function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

async function verifyTurnstile(token: string, ip: string, secretKey: string): Promise<boolean> {
  const body = new URLSearchParams({
    secret: secretKey,
    response: token,
    remoteip: ip,
  });
  try {
    const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      body,
    });
    if (!res.ok) return false;
    const data = await res.json() as { success: boolean };
    return data.success === true;
  } catch {
    return false;
  }
}

// Extract required field keys from quiz_schema JSONB.
// Supports three formats:
//   Format A (DB format): { fields: [{ id: string, required?: boolean, ... }] }
//   Format B (legacy):    { questions: [{ key: string, required?: boolean, ... }] }
//   Format C (dict):      { field_key: { required: boolean, ... }, ... }
function extractRequiredKeys(quizSchema: Json): string[] {
  if (!quizSchema || typeof quizSchema !== 'object' || Array.isArray(quizSchema)) return [];

  const schema = quizSchema as Record<string, Json>;

  // Format A: { fields: [{ id, required }, ...] } — actual DB format (verified from staging)
  if (Array.isArray(schema['fields'])) {
    return (schema['fields'] as Json[])
      .filter((f): f is Record<string, Json> => typeof f === 'object' && f !== null && !Array.isArray(f))
      .filter((f) => f['required'] === true)
      .map((f) => String(f['id'] ?? ''))
      .filter(Boolean);
  }

  // Format B: { questions: [{ key, required }, ...] } — legacy array format
  if (Array.isArray(schema['questions'])) {
    return (schema['questions'] as Json[])
      .filter((q): q is Record<string, Json> => typeof q === 'object' && q !== null && !Array.isArray(q))
      .filter((q) => q['required'] === true)
      .map((q) => String(q['key'] ?? ''))
      .filter(Boolean);
  }

  // Format C: { field_key: { required: boolean, ... }, ... } — dict format
  return Object.entries(schema)
    .filter(([, v]) => typeof v === 'object' && v !== null && !Array.isArray(v) && (v as Record<string, Json>)['required'] === true)
    .map(([k]) => k);
}

// Normalize quiz_answers to ProspectRequirements (pick known matching fields).
function normalizeRequirements(quizAnswers: Record<string, unknown>): ProspectRequirements {
  const r: ProspectRequirements = {};

  if (typeof quizAnswers['challenge'] === 'string') r.challenge = quizAnswers['challenge'];
  if (Array.isArray(quizAnswers['skills_needed'])) {
    r.skills_needed = (quizAnswers['skills_needed'] as unknown[]).filter((s): s is string => typeof s === 'string');
  }
  if (typeof quizAnswers['industry'] === 'string') r.industry = quizAnswers['industry'];
  if (typeof quizAnswers['timeline'] === 'string') r.timeline = quizAnswers['timeline'];
  if (typeof quizAnswers['company_size'] === 'string') r.company_size = quizAnswers['company_size'];
  if (Array.isArray(quizAnswers['languages'])) {
    r.languages = (quizAnswers['languages'] as unknown[]).filter((l): l is string => typeof l === 'string');
  }
  if (Array.isArray(quizAnswers['desired_outcomes'])) {
    r.desired_outcomes = (quizAnswers['desired_outcomes'] as unknown[]).filter((o): o is string => typeof o === 'string').slice(0, 5);
  }
  if (
    quizAnswers['budget_range'] &&
    typeof quizAnswers['budget_range'] === 'object' &&
    !Array.isArray(quizAnswers['budget_range'])
  ) {
    const br = quizAnswers['budget_range'] as Record<string, unknown>;
    if (typeof br['max'] === 'number') {
      r.budget_range = {
        max: br['max'],
        ...(typeof br['min'] === 'number' ? { min: br['min'] } : {}),
      };
    }
  }

  return r;
}

// ── POST /api/prospects/submit ─────────────────────────────────────────────────

export async function handleProspectSubmit(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const startTime = Date.now();

  // AC3: Rate limit public endpoint (30 req/min per IP)
  const rateCheck = await checkRateLimit(request, env);
  if (!rateCheck.allowed) {
    return errorResponse('Too Many Requests', 429);
  }

  let body: {
    satellite_id?: unknown;
    quiz_answers?: unknown;
    utm_source?: unknown;
    utm_campaign?: unknown;
    'cf-turnstile-response'?: unknown;
  };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  // AC4: Turnstile token required
  const turnstileToken = body['cf-turnstile-response'];
  if (typeof turnstileToken !== 'string' || !turnstileToken) {
    return errorResponse('Validation failed', 422, { 'cf-turnstile-response': 'required' });
  }

  // AC5: Verify Turnstile token
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const turnstileOk = await verifyTurnstile(turnstileToken, ip, env.TURNSTILE_SECRET_KEY);
  if (!turnstileOk) {
    return errorResponse('Bot verification failed', 422);
  }

  const { satellite_id, quiz_answers, utm_source, utm_campaign } = body;

  // Validate satellite_id
  if (typeof satellite_id !== 'string' || !satellite_id) {
    return errorResponse('Validation failed', 422, { satellite_id: 'required' });
  }

  // Validate quiz_answers is an object
  if (!quiz_answers || typeof quiz_answers !== 'object' || Array.isArray(quiz_answers)) {
    return errorResponse('Validation failed', 422, { quiz_answers: 'must be an object' });
  }

  const sql = createSql(env);

  // Load satellite config
  const [satellite] = await sql<Pick<SatelliteConfigRow, 'quiz_schema' | 'matching_weights'>[]>`
    SELECT quiz_schema, matching_weights FROM satellite_configs WHERE id = ${satellite_id}`;

  if (!satellite) return errorResponse('Satellite not found', 404);

  // AC2: validate quiz_answers has all required keys from quiz_schema
  const requiredKeys = extractRequiredKeys(satellite.quiz_schema);
  const answers = quiz_answers as Record<string, unknown>;
  const missingFields = requiredKeys.filter((k) => !(k in answers) || answers[k] === null || answers[k] === undefined || answers[k] === '');

  if (missingFields.length > 0) {
    return errorResponse('Validation failed', 422, { missing_fields: missingFields });
  }

  // Normalize quiz_answers → requirements JSONB
  const requirements = normalizeRequirements(answers);

  // AC3: create prospect row
  const [prospect] = await sql<Pick<ProspectRow, 'id'>[]>`
    INSERT INTO prospects (satellite_id, quiz_answers, requirements, status, utm_source, utm_campaign)
    VALUES (${satellite_id}, ${JSON.stringify(answers)}::jsonb, ${JSON.stringify(requirements)}::jsonb, 'anonymous', ${typeof utm_source === 'string' ? utm_source : null}, ${typeof utm_campaign === 'string' ? utm_campaign : null})
    RETURNING id`;

  if (!prospect) return errorResponse('Database error', 500);

  // AC1/AC3: load expert pool from KV (with DB fallback)
  const experts = await loadExpertPool(env);

  // Resolve matching weights from satellite config or fall back to defaults
  let weights: MatchingWeights = DEFAULT_WEIGHTS;
  if (satellite.matching_weights && typeof satellite.matching_weights === 'object' && !Array.isArray(satellite.matching_weights)) {
    weights = satellite.matching_weights as unknown as MatchingWeights;
  }

  // AC4 (E06S24): Delegate scoring to callibrate-matching via Service Binding (zero network hop)
  // AC6: Fallback to local deterministic scoring when MATCHING_SERVICE not bound
  if (env.MATCHING_SERVICE) {
    try {
      const matchResp = await env.MATCHING_SERVICE.fetch(
        new Request('https://matching/match', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ prospect_id: prospect.id, satellite_id }),
        })
      );
      if (matchResp.ok) {
        const matchBody = await matchResp.json() as {
          computed: number;
          top_matches: unknown[];
          billing_excluded?: { expert_id: string; reason: string }[];
          admissibility_excluded?: { expert_id: string; reason: string }[];
        };
        const billingExcluded = matchBody.billing_excluded ?? [];
        if (billingExcluded.length > 0) {
          const lpResult = calculateLeadPrice(
            requirements.budget_range?.max ?? null,
            { budget_max: requirements.budget_range?.max ?? null }
          );
          for (const ex of billingExcluded) {
            ctx.waitUntil(
              env.EMAIL_NOTIFICATIONS.send({
                type: 'expert.billing.lead_missed',
                expert_id: ex.expert_id,
                reason: ex.reason as 'insufficient_balance' | 'max_lead_price_exceeded' | 'spending_limit_reached',
                prospect_vertical: satellite_id,
                budget_tier: lpResult.tier,
              })
            );
          }
        }
        const admissibilityExcludedMS = matchBody.admissibility_excluded ?? [];
        for (const ex of admissibilityExcludedMS) {
          ctx.waitUntil(
            env.EMAIL_NOTIFICATIONS.send({
              type: 'expert.admissibility.lead_missed',
              expert_id: ex.expert_id,
              reason: ex.reason,
              prospect_vertical: satellite_id,
            })
          );
        }
        const { token, expiresAt } = await signProspectToken(prospect.id, env.PROSPECT_TOKEN_SECRET, 'prospect:submit');
        return jsonResponse({ prospect_id: prospect.id, token, token_expires_at: expiresAt });
      }
      console.error('prospect submit: MATCHING_SERVICE returned', matchResp.status, '— falling back to local scoring');
    } catch (err) {
      console.error('prospect submit: MATCHING_SERVICE.fetch failed, falling back to local scoring', err);
    }
  }

  // AC6 Fallback: local deterministic scoring (no Vectorize/AI — those bindings live in Matching Worker)

  // AC1: calculate leadPrice once
  const budgetMax = requirements.budget_range?.max ?? null;
  const lpResultFallback = calculateLeadPrice(budgetMax, { budget_max: budgetMax });
  const leadPrice = lpResultFallback.amount;

  // AC2–AC4: apply billing filter
  const billingMapFallback = await loadBillingData(env, experts.map((e) => e.id));
  const { eligible: billingEligibleFallback, excluded: billingExcludedFallback } = applyBillingFilters(experts, billingMapFallback, leadPrice);

  // AC6: fire-and-forget billing exclusion notifications
  for (const ex of billingExcludedFallback) {
    ctx.waitUntil(
      env.EMAIL_NOTIFICATIONS.send({
        type: 'expert.billing.lead_missed',
        expert_id: ex.expert_id,
        reason: ex.reason,
        prospect_vertical: satellite_id,
        budget_tier: lpResultFallback.tier,
      })
    );
  }

  // AC4 (E06S36): apply admissibility filter AFTER billing, BEFORE scoring
  const admissibilityMapFallback = await loadAdmissibilityData(env, billingEligibleFallback.map((e) => e.id));
  const prospectCtxFallback: ProspectContext = {
    industry: requirements.industry ?? null,
    vertical: satellite_id,
    timeline: requirements.timeline ?? null,
    budget_max: requirements.budget_range?.max ?? null,
    skills_needed: requirements.skills_needed ?? [],
    methodology: (requirements as unknown as { methodology?: string[] }).methodology ?? [],
  };
  const { eligible, excluded: admissibilityExcludedFallback } = applyAdmissibilityFilters(
    billingEligibleFallback,
    admissibilityMapFallback,
    prospectCtxFallback,
  );

  // AC6 (E06S36): fire-and-forget admissibility exclusion notifications
  for (const ex of admissibilityExcludedFallback) {
    ctx.waitUntil(
      env.EMAIL_NOTIFICATIONS.send({
        type: 'expert.admissibility.lead_missed',
        expert_id: ex.expert_id,
        reason: ex.reason,
        prospect_vertical: satellite_id,
      })
    );
  }

  // AC7: all excluded → still return token (prospect was submitted successfully)
  if (eligible.length === 0) {
    const { token, expiresAt } = await signProspectToken(prospect.id, env.PROSPECT_TOKEN_SECRET, 'prospect:submit');
    return jsonResponse({ prospect_id: prospect.id, token, token_expires_at: expiresAt });
  }

  const similarityMap = new Map<string, number>();
  const scoredResults: { score: number }[] = [];
  if (eligible.length > 0) {
    const matchRows = eligible.map((expert) => {
      const profile: ExpertProfile = {
        ...((expert.profile ?? {}) as ExpertProfile),
        rate_min: expert.rate_min,
        rate_max: expert.rate_max,
      };
      const prefs = (expert.preferences ?? {}) as ExpertPreferences;
      // AC4/AC5: pass per-expert cosine similarity; undefined in fallback path → deterministic-only
      const semanticSimilarity = similarityMap.get(expert.id);
      const raw = scoreMatch(profile, prefs, requirements, weights, semanticSimilarity);
      const { score, breakdown } = applyReliabilityModifier(raw, {
        composite_score: expert.composite_score,
        total_leads: expert.total_leads,
      });

      scoredResults.push({ score });
      return {
        prospect_id: prospect.id,
        expert_id: expert.id,
        score,
        score_breakdown: breakdown as unknown as Json,
        status: 'active',
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      };
    });

    // B1 fix: sort by score DESC and take top 20
    const top20Rows = matchRows
      .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
      .slice(0, 20);

    // AC3: INSERT top 20 scored results
    for (const row of top20Rows) {
      await sql`
        INSERT INTO matches (prospect_id, expert_id, score, score_breakdown, status, expires_at)
        VALUES (${row.prospect_id}, ${row.expert_id}, ${row.score}, ${JSON.stringify(row.score_breakdown)}::jsonb, ${row.status}, ${row.expires_at})
        ON CONFLICT DO NOTHING`;
    }
  }

  // Analytics for fallback path
  const topScore = scoredResults.length > 0 ? Math.max(...scoredResults.map((r) => r.score)) : 0;
  const meanScore =
    scoredResults.length > 0
      ? scoredResults.reduce((sum, r) => sum + r.score, 0) / scoredResults.length
      : 0;
  writeMatchingDataPoint(env, {
    endpoint: '/api/prospects/submit',
    satelliteId: satellite_id,
    latencyMs: Date.now() - startTime,
    poolSize: eligible.length,
    topScore,
    meanScore,
  });

  // Sign JWT token (24h TTL)
  const { token, expiresAt } = await signProspectToken(prospect.id, env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `prospect:${prospect.id}`,
    event: 'prospect.form_submitted',
    properties: {
      satellite_id,
      utm_source: typeof utm_source === 'string' ? utm_source : null,
      utm_campaign: typeof utm_campaign === 'string' ? utm_campaign : null,
      quiz_field_count: Object.keys(answers).length,
    },
  }));

  return jsonResponse({
    prospect_id: prospect.id,
    token,
    token_expires_at: expiresAt,
  });
}

// ── GET /api/prospects/:id/matches?token=xxx ───────────────────────────────────

export async function handleProspectMatches(
  request: Request,
  env: Env,
  prospectId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  // AC3: Rate limit public endpoint
  const rateCheck = await checkRateLimit(request, env);
  if (!rateCheck.allowed) {
    return errorResponse('Too Many Requests', 429);
  }

  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  // AC4: token required
  if (!token) {
    return errorResponse('Forbidden', 403);
  }

  // AC4: validate token
  const tokenValid = await verifyProspectToken(token, prospectId, env.PROSPECT_TOKEN_SECRET, 'prospect:matches');
  if (!tokenValid) {
    return errorResponse('Forbidden', 403);
  }

  const sql = createSql(env);

  // AC5: load all matches for prospect, ordered by score DESC
  const matches = await sql<Pick<MatchRow, 'id' | 'expert_id' | 'score' | 'score_breakdown'>[]>`
    SELECT id, expert_id, score, score_breakdown FROM matches
    WHERE prospect_id = ${prospectId} AND status != 'expired'
    ORDER BY score DESC`;

  // AC6: defensive guard — empty matches table
  if (!matches || matches.length === 0) {
    return jsonResponse({ status: 'computing', estimated_seconds: 5 }, 202);
  }

  // Load expert profiles for anonymized fields
  const expertIds = matches.map((m) => m.expert_id).filter((id): id is string => Boolean(id));
  const experts = await sql<Pick<ExpertRow, 'id' | 'composite_score' | 'profile' | 'rate_min' | 'rate_max'>[]>`
    SELECT id, composite_score, profile, rate_min, rate_max FROM experts WHERE id = ANY(${expertIds})`;

  const expertMap = new Map(experts.map((e) => [e.id, e]));

  // AC5: anonymized expert cards — no display_name, avatar_url, cal_username
  const anonymizedMatches = matches.map((match, idx) => {
    const expert = expertMap.get(match.expert_id ?? '');
    const profile = (expert?.profile ?? {}) as ExpertProfile;
    const breakdown = (match.score_breakdown ?? {}) as unknown as ScoreBreakdown;

    return {
      rank: idx + 1,
      score: match.score ?? 0,
      score_breakdown: breakdown,
      skills: profile.skills ?? [],
      industries: profile.industries ?? [],
      project_types: profile.project_types ?? [],
      languages: profile.languages ?? [],
      rate_min: expert?.rate_min ?? null,
      rate_max: expert?.rate_max ?? null,
    };
  });

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `prospect:${prospectId}`,
    event: 'prospect.matches_viewed',
    properties: {
      match_count: anonymizedMatches.length,
      top_score: anonymizedMatches[0]?.score ?? 0,
    },
  }));

  return jsonResponse({ matches: anonymizedMatches });
}

// ── POST /api/prospects/:id/identify ──────────────────────────────────────────

export async function handleProspectIdentify(
  request: Request,
  env: Env,
  prospectId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  // AC3: Rate limit public endpoint
  const rateCheck = await checkRateLimit(request, env);
  if (!rateCheck.allowed) {
    return errorResponse('Too Many Requests', 429);
  }

  let body: { email?: unknown; token?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { email, token } = body;

  // AC7: validate token
  if (typeof token !== 'string' || !token) {
    return errorResponse('Forbidden', 403);
  }

  const tokenValid = await verifyProspectToken(token, prospectId, env.PROSPECT_TOKEN_SECRET, 'prospect:identify');
  if (!tokenValid) {
    return errorResponse('Forbidden', 403);
  }

  // AC7: validate email format
  if (typeof email !== 'string' || !email || !isValidEmail(email)) {
    return errorResponse('Validation failed', 422, { email: 'must be a valid email address' });
  }

  const sql = createSql(env);

  // AC8: check if prospect already identified
  const [prospect] = await sql<Pick<ProspectRow, 'id' | 'email'>[]>`
    SELECT id, email FROM prospects WHERE id = ${prospectId}`;

  if (!prospect) return errorResponse('Prospect not found', 404);

  if (prospect.email !== null) {
    return errorResponse('Prospect already identified', 409);
  }

  // AC7: update prospect with email + status
  await sql`UPDATE prospects SET email = ${email}, status = 'identified' WHERE id = ${prospectId}`;

  // Load matches to get expert_ids, sorted by score DESC
  const matches = await sql<Pick<MatchRow, 'expert_id' | 'score'>[]>`
    SELECT expert_id, score FROM matches
    WHERE prospect_id = ${prospectId} AND status != 'expired'
    ORDER BY score DESC`;

  const expertIds = matches
    .map((m) => m.expert_id)
    .filter((id): id is string => Boolean(id));

  if (expertIds.length === 0) {
    return jsonResponse({ experts: [] });
  }

  // AC7: load full expert profiles
  const expertRows = await sql<Pick<ExpertRow, 'id' | 'display_name' | 'headline' | 'bio' | 'profile' | 'rate_min' | 'rate_max' | 'cal_username'>[]>`
    SELECT id, display_name, headline, bio, profile, rate_min, rate_max, cal_username FROM experts WHERE id = ANY(${expertIds})`;

  const expertMap = new Map(expertRows.map((e) => [e.id, e]));
  const matchScoreMap = new Map(matches.map((m) => [m.expert_id ?? '', m.score ?? 0]));

  // AC7: full profiles with booking_url
  const expertProfiles = expertIds
    .map((expertId) => {
      const expert = expertMap.get(expertId);
      if (!expert) return null;
      const profile = (expert.profile ?? {}) as ExpertProfile;

      return {
        display_name: expert.display_name,
        headline: expert.headline,
        bio: expert.bio,
        skills: profile.skills ?? [],
        industries: profile.industries ?? [],
        rate_min: expert.rate_min,
        rate_max: expert.rate_max,
        score: matchScoreMap.get(expertId) ?? 0,
        // TODO(DEC-41): cal_username → Google Calendar booking (E06S10/E06S11)
        booking_url: expert.cal_username
          ? `https://cal.com/${expert.cal_username}/intro-call`
          : null,
      };
    })
    .filter(Boolean);

  const emailDomain = email.split('@')[1] ?? 'unknown';
  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `prospect:${prospectId}`,
    event: 'prospect.identified',
    properties: { email_domain: emailDomain },
  }));

  return jsonResponse({ experts: expertProfiles });
}
