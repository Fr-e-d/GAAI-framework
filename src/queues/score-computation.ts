import { Env } from '../types/env';
import { ScoreComputationMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createServiceClient, TypedSupabaseClient } from '../lib/supabase';

export async function consumeScoreComputation(
  batch: MessageBatch<ScoreComputationMessage>,
  env: Env
): Promise<void> {
  for (const message of batch.messages) {
    try {
      if (await isAlreadyProcessed(env.SESSIONS, 'score-computation', message.id)) {
        message.ack();
        continue;
      }

      const body = message.body;

      switch (body.type) {
        case 'feedback.call_experience':
        case 'feedback.project_satisfaction':
        case 'feedback.lead_evaluation':
          await computeAndSaveCompositeScore(body.expert_id, env);
          break;
        default: {
          const exhaustiveCheck: never = body;
          console.warn('score-computation: unknown message type', (exhaustiveCheck as ScoreComputationMessage & { type: string }).type);
          message.ack();
          continue;
        }
      }

      await markProcessed(env.SESSIONS, 'score-computation', message.id);
      message.ack();
    } catch (err) {
      handleMessageFailure(message, err, 'score-computation');
    }
  }
}

async function computeAndSaveCompositeScore(expertId: string, env: Env): Promise<void> {
  const supabase = createServiceClient(env);

  // Fetch all match IDs for this expert (shared by call_exp, satisfaction, recency)
  const { data: matchRows, error: matchError } = await supabase
    .from('matches')
    .select('id')
    .eq('expert_id', expertId);

  if (matchError) {
    throw new Error(`Failed to fetch matches for expert ${expertId}: ${matchError.message}`);
  }

  const matchIds = (matchRows ?? []).map((m) => m.id);

  // If no matches yet, expert score remains 0 (initialized at registration)
  // Only compute when there is at least one match to avoid meaningless score writes
  if (matchIds.length === 0) {
    return;
  }

  // Fetch booking IDs for those matches (shared by call_exp and satisfaction)
  let bookingIds: string[] = [];
  const { data: bookingRows, error: bookingError } = await supabase
    .from('bookings')
    .select('id')
    .in('match_id', matchIds);

  if (bookingError) {
    throw new Error(`Failed to fetch bookings for expert ${expertId}: ${bookingError.message}`);
  }

  bookingIds = (bookingRows ?? []).map((b) => b.id);

  // Compute all 5 components in parallel
  const [callExperienceAvg, clientSatisfactionAvg, hireRate, recencyScore, trustScore] =
    await Promise.all([
      computeCallExperienceAvg(bookingIds, supabase),
      computeClientSatisfactionAvg(bookingIds, supabase),
      computeHireRate(expertId, supabase),
      computeRecencyScore(matchIds, supabase),
      computeTrustScore(expertId, supabase),
    ]);

  // Composite formula (AC2): weights sum to 1.0
  const compositeScore = Math.round(
    (callExperienceAvg * 0.35 +
      trustScore * 0.20 +
      clientSatisfactionAvg * 0.20 +
      hireRate * 0.10 +
      recencyScore * 0.15) *
      100
  ) / 100;

  // Write result atomically (AC2)
  const { error: updateError } = await supabase
    .from('experts')
    .update({
      composite_score: compositeScore,
      score_updated_at: new Date().toISOString(),
    })
    .eq('id', expertId);

  if (updateError) {
    throw new Error(`Failed to write composite_score for expert ${expertId}: ${updateError.message}`);
  }
}

// AC3: call_experience_avg — average of call_experience_surveys.score × 20 (1–5 → 0–100)
async function computeCallExperienceAvg(
  bookingIds: string[],
  supabase: TypedSupabaseClient
): Promise<number> {
  if (bookingIds.length === 0) return 0;

  const { data, error } = await supabase
    .from('call_experience_surveys')
    .select('score')
    .in('booking_id', bookingIds);

  if (error) {
    throw new Error(`computeCallExperienceAvg: ${error.message}`);
  }

  const scores = (data ?? [])
    .filter((r) => r.score !== null)
    .map((r) => r.score! * 20);

  return scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
}

// AC4: client_satisfaction_avg — average of project_satisfaction_surveys.score × 10 (1–10 → 0–100)
async function computeClientSatisfactionAvg(
  bookingIds: string[],
  supabase: TypedSupabaseClient
): Promise<number> {
  if (bookingIds.length === 0) return 0;

  const { data, error } = await supabase
    .from('project_satisfaction_surveys')
    .select('score')
    .in('booking_id', bookingIds);

  if (error) {
    throw new Error(`computeClientSatisfactionAvg: ${error.message}`);
  }

  const scores = (data ?? [])
    .filter((r) => r.score !== null)
    .map((r) => r.score! * 10);

  return scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
}

// AC5: hire_rate — (conversion_declared = true count) / total × 100
async function computeHireRate(expertId: string, supabase: TypedSupabaseClient): Promise<number> {
  const { data, error } = await supabase
    .from('lead_evaluations')
    .select('conversion_declared')
    .eq('expert_id', expertId);

  if (error) {
    throw new Error(`computeHireRate: ${error.message}`);
  }

  if (!data || data.length === 0) return 0;

  const converted = data.filter((r) => r.conversion_declared === true).length;
  return (converted / data.length) * 100;
}

// AC6: recency_score — 100 if last booking < 30 days, linear decrease to 0 at 180 days
async function computeRecencyScore(
  matchIds: string[],
  supabase: TypedSupabaseClient
): Promise<number> {
  if (matchIds.length === 0) return 0;

  const { data, error } = await supabase
    .from('bookings')
    .select('scheduled_at')
    .in('match_id', matchIds)
    .not('scheduled_at', 'is', null)
    .order('scheduled_at', { ascending: false })
    .limit(1);

  if (error) {
    throw new Error(`computeRecencyScore: ${error.message}`);
  }

  if (!data || data.length === 0 || !data[0]?.scheduled_at) return 0;

  const daysSince =
    (Date.now() - new Date(data[0].scheduled_at).getTime()) / (1000 * 60 * 60 * 24);

  if (daysSince < 30) return 100;
  if (daysSince >= 180) return 0;

  // Linear interpolation: 100 at 30 days, 0 at 180 days
  return Math.min(100, Math.max(0, Math.round(100 - ((daysSince - 30) / 150) * 100)));
}

// AC7: trust_score — static profile completeness (5 criteria × 20pts each)
async function computeTrustScore(expertId: string, supabase: TypedSupabaseClient): Promise<number> {
  const { data, error } = await supabase
    .from('experts')
    .select('verified_at, bio, profile')
    .eq('id', expertId)
    .single();

  if (error) {
    throw new Error(`computeTrustScore: ${error.message}`);
  }

  let score = 0;
  const p = data.profile as Record<string, unknown> | null;

  // Criterion 1: verified email (20pts) — verified_at is non-null
  if (data.verified_at !== null) score += 20;

  // Criterion 2: bio (non-empty) AND ≥3 portfolio items (20pts) — both required
  const portfolioItems = p?.portfolio_items;
  if (
    data.bio !== null &&
    data.bio.trim().length > 0 &&
    Array.isArray(portfolioItems) &&
    portfolioItems.length >= 3
  ) {
    score += 20;
  }

  // Criterion 3: LinkedIn URL present (20pts)
  const linkedinUrl = p?.linkedin_url;
  if (typeof linkedinUrl === 'string' && linkedinUrl.trim().length > 0) score += 20;

  // Criterion 4: years_experience declared ≥ 3 (20pts)
  const yearsExp = p?.years_experience;
  if (typeof yearsExp === 'number' && yearsExp >= 3) score += 20;

  // Criterion 5: ≥1 certification/credential in profile JSONB (20pts)
  const certifications = p?.certifications;
  if (Array.isArray(certifications) && certifications.length >= 1) score += 20;

  return score;
}
