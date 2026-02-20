// ── Satellite funnel — prospect routes ────────────────────────────────────────
// AC2/AC3: POST /api/prospects/submit
// AC4/AC5/AC6: GET /api/prospects/:id/matches?token=xxx
// AC7/AC8: POST /api/prospects/:id/identify
// AC10: consistent error shape { error: string, details?: object }

import { createClient } from '@supabase/supabase-js';
import type { Json, Database } from '../types/database';
import type { Env } from '../types/env';
import {
  DEFAULT_WEIGHTS,
  type ExpertPreferences,
  type ExpertProfile,
  type MatchingWeights,
  type ProspectRequirements,
  type ScoreBreakdown,
} from '../types/matching';
import { scoreMatch } from '../matching/score';
import { signProspectToken, verifyProspectToken } from '../lib/jwt';
import { loadExpertPool } from '../lib/expertPool';

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

// Extract required field keys from quiz_schema JSONB.
// Expected schema format: Record<string, { required?: boolean, ... }>
// Also supports { questions: Array<{ key: string, required?: boolean }> }
function extractRequiredKeys(quizSchema: Json): string[] {
  if (!quizSchema || typeof quizSchema !== 'object' || Array.isArray(quizSchema)) return [];

  const schema = quizSchema as Record<string, Json>;

  // Format A: { questions: [{ key, required }, ...] }
  if (Array.isArray(schema['questions'])) {
    return (schema['questions'] as Json[])
      .filter((q): q is Record<string, Json> => typeof q === 'object' && q !== null && !Array.isArray(q))
      .filter((q) => q['required'] === true)
      .map((q) => String(q['key'] ?? ''))
      .filter(Boolean);
  }

  // Format B: { field_key: { required: boolean, ... }, ... }
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

export async function handleProspectSubmit(request: Request, env: Env): Promise<Response> {
  let body: { satellite_id?: unknown; quiz_answers?: unknown; utm_source?: unknown; utm_campaign?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
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

  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // Load satellite config
  const { data: satellite, error: satErr } = await supabase
    .from('satellite_configs')
    .select('quiz_schema, matching_weights')
    .eq('id', satellite_id)
    .maybeSingle();

  if (satErr) return errorResponse('Database error', 500);
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
  const { data: prospect, error: prospectErr } = await supabase
    .from('prospects')
    .insert({
      satellite_id,
      quiz_answers: answers as unknown as Json,
      requirements: requirements as unknown as Json,
      status: 'anonymous',
      utm_source: typeof utm_source === 'string' ? utm_source : null,
      utm_campaign: typeof utm_campaign === 'string' ? utm_campaign : null,
    })
    .select('id')
    .single();

  if (prospectErr || !prospect) return errorResponse('Database error', 500);

  // AC3: load expert pool from KV (with DB fallback)
  const experts = await loadExpertPool(env);

  // Resolve matching weights from satellite config or fall back to defaults
  let weights: MatchingWeights = DEFAULT_WEIGHTS;
  if (satellite.matching_weights && typeof satellite.matching_weights === 'object' && !Array.isArray(satellite.matching_weights)) {
    weights = satellite.matching_weights as unknown as MatchingWeights;
  }

  // AC3: scoreMatch() synchronously for each expert
  if (experts.length > 0) {
    const matchRows: Database['public']['Tables']['matches']['Insert'][] = experts.map((expert) => {
      const profile: ExpertProfile = {
        ...((expert.profile ?? {}) as ExpertProfile),
        rate_min: expert.rate_min,
        rate_max: expert.rate_max,
      };
      const prefs = (expert.preferences ?? {}) as ExpertPreferences;
      const { score, breakdown } = scoreMatch(profile, prefs, requirements, weights);

      return {
        prospect_id: prospect.id,
        expert_id: expert.id,
        score,
        score_breakdown: breakdown as unknown as Json,
        status: 'active',
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      };
    });

    // AC3: INSERT all scored results (best-effort — AC6 guard covers insert failures)
    await supabase.from('matches').insert(matchRows);
  }

  // AC3: sign JWT token (24h TTL)
  const { token, expiresAt } = await signProspectToken(prospect.id, env.PROSPECT_TOKEN_SECRET);

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
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  // AC4: token required
  if (!token) {
    return errorResponse('Forbidden', 403);
  }

  // AC4: validate token
  const tokenValid = await verifyProspectToken(token, prospectId, env.PROSPECT_TOKEN_SECRET);
  if (!tokenValid) {
    return errorResponse('Forbidden', 403);
  }

  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // AC5: load all matches for prospect, ordered by score DESC
  const { data: matches, error: matchErr } = await supabase
    .from('matches')
    .select('id, expert_id, score, score_breakdown')
    .eq('prospect_id', prospectId)
    .neq('status', 'expired')
    .order('score', { ascending: false });

  if (matchErr) return errorResponse('Database error', 500);

  // AC6: defensive guard — empty matches table
  if (!matches || matches.length === 0) {
    return jsonResponse({ status: 'computing', estimated_seconds: 5 }, 202);
  }

  // Load expert profiles for anonymized fields
  const expertIds = matches.map((m) => m.expert_id).filter((id): id is string => Boolean(id));
  const { data: experts, error: expertErr } = await supabase
    .from('experts')
    .select('id, composite_score, profile, rate_min, rate_max')
    .in('id', expertIds);

  if (expertErr) return errorResponse('Database error', 500);

  const expertMap = new Map((experts ?? []).map((e) => [e.id, e]));

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

  return jsonResponse({ matches: anonymizedMatches });
}

// ── POST /api/prospects/:id/identify ──────────────────────────────────────────

export async function handleProspectIdentify(
  request: Request,
  env: Env,
  prospectId: string,
): Promise<Response> {
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

  const tokenValid = await verifyProspectToken(token, prospectId, env.PROSPECT_TOKEN_SECRET);
  if (!tokenValid) {
    return errorResponse('Forbidden', 403);
  }

  // AC7: validate email format
  if (typeof email !== 'string' || !email || !isValidEmail(email)) {
    return errorResponse('Validation failed', 422, { email: 'must be a valid email address' });
  }

  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // AC8: check if prospect already identified
  const { data: prospect, error: fetchErr } = await supabase
    .from('prospects')
    .select('id, email')
    .eq('id', prospectId)
    .maybeSingle();

  if (fetchErr) return errorResponse('Database error', 500);
  if (!prospect) return errorResponse('Prospect not found', 404);

  if (prospect.email !== null) {
    return errorResponse('Prospect already identified', 409);
  }

  // AC7: update prospect with email + status
  const { error: updateErr } = await supabase
    .from('prospects')
    .update({ email, status: 'identified' })
    .eq('id', prospectId);

  if (updateErr) return errorResponse('Database error', 500);

  // Load matches to get expert_ids, sorted by score DESC
  const { data: matches, error: matchErr } = await supabase
    .from('matches')
    .select('expert_id, score')
    .eq('prospect_id', prospectId)
    .neq('status', 'expired')
    .order('score', { ascending: false });

  if (matchErr) return errorResponse('Database error', 500);

  const expertIds = (matches ?? [])
    .map((m) => m.expert_id)
    .filter((id): id is string => Boolean(id));

  if (expertIds.length === 0) {
    return jsonResponse({ experts: [] });
  }

  // AC7: load full expert profiles
  const { data: expertRows, error: expertErr } = await supabase
    .from('experts')
    .select('id, display_name, headline, bio, profile, rate_min, rate_max, cal_username')
    .in('id', expertIds);

  if (expertErr) return errorResponse('Database error', 500);

  const expertMap = new Map((expertRows ?? []).map((e) => [e.id, e]));
  const matchScoreMap = new Map((matches ?? []).map((m) => [m.expert_id ?? '', m.score ?? 0]));

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
        booking_url: expert.cal_username
          ? `https://cal.com/${expert.cal_username}/intro-call`
          : null,
      };
    })
    .filter(Boolean);

  return jsonResponse({ experts: expertProfiles });
}
