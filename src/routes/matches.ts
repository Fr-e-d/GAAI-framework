import { createClient } from '@supabase/supabase-js';
import type { Database, Json } from '../types/database';
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
import { scoreMatch } from '../matching/score';

// ── Helpers ───────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

function deriveQualityTier(compositeScore: number | null): QualityTier {
  if (!compositeScore || compositeScore === 0) return 'new';
  if (compositeScore <= 25) return 'rising';
  if (compositeScore <= 60) return 'established';
  return 'top';
}

// ── POST /api/matches/compute ─────────────────────────────────────────────────
// AC7: loads prospect + available experts, scores, stores top-20, returns results

export async function handleMatchCompute(request: Request, env: Env): Promise<Response> {
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

  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // Load prospect requirements
  const { data: prospect, error: prospectErr } = await supabase
    .from('prospects')
    .select('id, requirements, satellite_id')
    .eq('id', prospect_id)
    .maybeSingle();

  if (prospectErr) return errorResponse('Database error', 500);
  if (!prospect) return errorResponse('Prospect not found', 404);

  // Resolve matching weights (satellite override or default)
  const effectiveSatelliteId = satellite_id ?? prospect.satellite_id;
  let weights: MatchingWeights = DEFAULT_WEIGHTS;

  if (typeof effectiveSatelliteId === 'string' && effectiveSatelliteId) {
    const { data: satConfig } = await supabase
      .from('satellite_configs')
      .select('matching_weights')
      .eq('id', effectiveSatelliteId)
      .maybeSingle();

    if (satConfig?.matching_weights && typeof satConfig.matching_weights === 'object') {
      weights = satConfig.matching_weights as unknown as MatchingWeights;
    }
  }

  // Load all available experts
  const { data: experts, error: expertsErr } = await supabase
    .from('experts')
    .select('id, profile, preferences, rate_min, rate_max, composite_score')
    .neq('availability', 'unavailable');

  if (expertsErr) return errorResponse('Database error', 500);
  if (!experts || experts.length === 0) {
    return jsonResponse({ computed: 0, top_matches: [] });
  }

  // Score each expert
  const requirements = (prospect.requirements ?? {}) as ProspectRequirements;

  const scored = experts.map((expert) => {
    // Merge DB-column rates into the profile for the pure scoring function (AC1)
    const profile: ExpertProfile = {
      ...((expert.profile ?? {}) as ExpertProfile),
      rate_min: expert.rate_min,
      rate_max: expert.rate_max,
    };
    const prefs = (expert.preferences ?? {}) as ExpertPreferences;
    const matchScore = scoreMatch(profile, prefs, requirements, weights);

    return { expert, matchScore };
  });

  // Sort by score DESC, take top 20
  scored.sort((a, b) => b.matchScore.score - a.matchScore.score);
  const top20 = scored.slice(0, 20);

  // Upsert into matches table: delete existing, then insert fresh
  if (top20.length > 0) {
    await supabase.from('matches').delete().eq('prospect_id', prospect_id);

    const matchRows: Database['public']['Tables']['matches']['Insert'][] = top20.map(({ expert, matchScore }) => ({
      prospect_id,
      expert_id: expert.id,
      score: matchScore.score,
      score_breakdown: matchScore.breakdown as unknown as Json,
      status: 'active',
      expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(), // 7-day TTL
    }));

    await supabase.from('matches').insert(matchRows);
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
    };
  });

  return jsonResponse({ computed: top20.length, top_matches: topMatches });
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

  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // Fetch matches (excluding expired), sorted by score DESC, paginated
  const { data: matches, error: matchErr } = await supabase
    .from('matches')
    .select('id, expert_id, score, score_breakdown')
    .eq('prospect_id', prospectId)
    .neq('status', 'expired')
    .order('score', { ascending: false })
    .range(offset, offset + pageSize - 1);

  if (matchErr) return errorResponse('Database error', 500);
  if (!matches || matches.length === 0) {
    return jsonResponse({ results: [], page, page_size: pageSize, total: 0 });
  }

  // Fetch expert composite_score and profile for tiebreaker and anonymized fields
  const expertIds = matches.map((m) => m.expert_id).filter(Boolean) as string[];
  const { data: experts, error: expertErr } = await supabase
    .from('experts')
    .select('id, composite_score, profile')
    .in('id', expertIds);

  if (expertErr) return errorResponse('Database error', 500);

  const expertMap = new Map((experts ?? []).map((e) => [e.id, e]));

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
