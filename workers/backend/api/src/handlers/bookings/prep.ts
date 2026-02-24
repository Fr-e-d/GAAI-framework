import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import type { Json } from '../../types/database';
import type { BookingRow, ProspectRow, ExpertRow, MatchRow } from '../../types/db';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function getCompositeScoreTier(score: number | null): 'rising' | 'established' | 'top' {
  if (!score || score < 50) return 'rising';
  if (score < 75) return 'established';
  return 'top';
}

function buildDirections(scoreBreakdown: Json | null): { expert: string; prospect: string } {
  if (!scoreBreakdown || !Array.isArray(scoreBreakdown)) {
    return {
      expert: 'Ce prospect correspond à vos critères de sélection.',
      prospect: 'Cet expert correspond à vos besoins.',
    };
  }

  const topCriteria = (scoreBreakdown as Array<{ criterion?: string; label?: string; score?: number }>)
    .filter(c => c.score != null && c.score > 50)
    .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
    .slice(0, 2)
    .map(c => c.label ?? c.criterion ?? '');

  const criteriaText = topCriteria.join(', ') || 'vos critères';

  return {
    expert: `Ce prospect présente un fort alignement sur : ${criteriaText}.`,
    prospect: `Cet expert est particulièrement adapté à votre projet sur : ${criteriaText}.`,
  };
}

export async function handleGetPrep(
  _request: Request,
  env: Env,
  prepToken: string
): Promise<Response> {
  const sql = createSql(env);

  // Fetch booking by prep_token
  const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'match_id' | 'start_at' | 'end_at' | 'meeting_url' | 'duration_min' | 'prep_token'>[]>`
    SELECT id, expert_id, prospect_id, match_id, start_at, end_at, meeting_url, duration_min, prep_token
    FROM bookings WHERE prep_token = ${prepToken}`;

  if (!booking) return json({ error: 'Not Found' }, 404);

  // Check token expiry: expires at start_at + 2h
  if (!booking.start_at) return json({ error: 'Not Found' }, 404);
  const expiresAt = new Date(new Date(booking.start_at).getTime() + 2 * 60 * 60 * 1000);
  if (new Date() > expiresAt) return json({ error: 'prep_token_expired' }, 404);

  // Fetch prospect
  const [prospect] = await sql<Pick<ProspectRow, 'requirements' | 'email'>[]>`
    SELECT requirements, email FROM prospects WHERE id = ${booking.prospect_id!}`;

  // Fetch expert
  const [expert] = await sql<Pick<ExpertRow, 'display_name' | 'bio' | 'profile' | 'composite_score'>[]>`
    SELECT display_name, bio, profile, composite_score FROM experts WHERE id = ${booking.expert_id!}`;

  // Fetch match (by match_id or query)
  let matchData: { score: number | null; score_breakdown: Json | null } | null = null;
  if (booking.match_id) {
    const [m] = await sql<Pick<MatchRow, 'score' | 'score_breakdown'>[]>`
      SELECT score, score_breakdown FROM matches WHERE id = ${booking.match_id}`;
    matchData = m ?? null;
  } else if (booking.expert_id && booking.prospect_id) {
    const [m] = await sql<Pick<MatchRow, 'score' | 'score_breakdown'>[]>`
      SELECT score, score_breakdown FROM matches WHERE expert_id = ${booking.expert_id}
      AND prospect_id = ${booking.prospect_id} ORDER BY created_at DESC LIMIT 1`;
    matchData = m ?? null;
  }

  const req = (prospect?.requirements ?? {}) as Record<string, unknown>;
  const profile = (expert?.profile ?? {}) as Record<string, unknown>;

  const directions = buildDirections(matchData?.score_breakdown ?? null);

  return json({
    booking: {
      start_at: booking.start_at,
      end_at: booking.end_at,
      meeting_url: booking.meeting_url,
      duration_min: booking.duration_min ?? 20,
    },
    prospect: {
      first_name: typeof req.first_name === 'string' ? req.first_name : 'Prospect',
      requirements_summary: typeof req.challenge === 'string' ? req.challenge : null,
      budget_range: req.budget_range ?? null,
      project_stage: req.project_stage ?? null,
      industry: req.industry ?? null,
      challenge: req.challenge ?? null,
    },
    expert: {
      first_name: typeof expert?.display_name === 'string'
        ? expert.display_name.split(' ')[0]
        : 'Expert',
      specialties: Array.isArray(profile.skills) ? profile.skills : [],
      bio_short: typeof expert?.bio === 'string'
        ? expert.bio.slice(0, 200)
        : (typeof profile.bio_short === 'string' ? profile.bio_short : null),
      composite_score_tier: getCompositeScoreTier(expert?.composite_score ?? null),
    },
    match: {
      score: matchData?.score ?? null,
      breakdown: Array.isArray(matchData?.score_breakdown) ? matchData.score_breakdown : [],
      direction_expert: directions.expert,
      direction_prospect: directions.prospect,
    },
  });
}
