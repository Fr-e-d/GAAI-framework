// ── POST /api/surveys/project-satisfaction ────────────────────────────────────
// AC2: Token-gated survey submission. Validates survey JWT, inserts into
// project_satisfaction_surveys, dispatches feedback.project_satisfaction to SCORE_COMPUTATION.
// Idempotent on (booking_id, prospect_id): returns 409 on duplicate.

import { z } from 'zod';
import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { verifySurveyToken } from '../../lib/jwt';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const ProjectSatisfactionSchema = z.object({
  token: z.string(),
  score: z.number().int().min(1).max(10),
  comment: z.string().optional(),
});

export async function handleProjectSatisfactionSurvey(
  request: Request,
  env: Env,
): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = ProjectSatisfactionSchema.safeParse(body);
  if (!parsed.success) {
    return json({ error: 'Validation failed', details: parsed.error.flatten().fieldErrors }, 422);
  }

  const { token, score, comment } = parsed.data;

  // Verify survey JWT (AC4)
  const claims = await verifySurveyToken(token, env.SURVEY_TOKEN_SECRET);
  if (!claims) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const { booking_id, prospect_id } = claims;

  const supabase = createServiceClient(env);

  // INSERT into project_satisfaction_surveys (AC2)
  const { data: survey, error: insertError } = await supabase
    .from('project_satisfaction_surveys')
    .insert({ booking_id, prospect_id, score, comment: comment ?? null })
    .select('id')
    .single();

  if (insertError) {
    if (insertError.code === '23505') {
      return json({ error: 'Already submitted' }, 409);
    }
    return json({ error: 'Failed to save survey', details: insertError.message }, 500);
  }

  // Resolve expert_id: booking.match_id → matches.expert_id (AC7)
  const expertId = await resolveExpertIdFromBooking(booking_id, supabase);
  if (!expertId) {
    return json({ error: 'Could not resolve expert for this booking' }, 500);
  }

  // Dispatch to SCORE_COMPUTATION queue (AC7)
  await env.SCORE_COMPUTATION.send({ type: 'feedback.project_satisfaction', expert_id: expertId });

  return json({ id: survey.id }, 201);
}

async function resolveExpertIdFromBooking(
  bookingId: string,
  supabase: ReturnType<typeof createServiceClient>,
): Promise<string | null> {
  const { data: booking, error: bookingError } = await supabase
    .from('bookings')
    .select('match_id')
    .eq('id', bookingId)
    .single();

  if (bookingError || !booking?.match_id) return null;

  const { data: match, error: matchError } = await supabase
    .from('matches')
    .select('expert_id')
    .eq('id', booking.match_id)
    .single();

  if (matchError || !match?.expert_id) return null;

  return match.expert_id;
}
