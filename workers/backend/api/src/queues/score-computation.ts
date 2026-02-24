import { Env } from '../types/env';
import { ScoreComputationMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createSql } from '../lib/db';
import type { SqlClient } from '../lib/db';
import type { ExpertRow, MatchRow, BookingRow, CallExperienceSurveyRow, ProjectSatisfactionSurveyRow, LeadEvaluationRow } from '../types/db';

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
  const sql = createSql(env);

  // Fetch all match IDs for this expert (shared by call_exp, satisfaction, recency)
  const matchRows = await sql<Pick<MatchRow, 'id'>[]>`
    SELECT id FROM matches WHERE expert_id = ${expertId}`;

  const matchIds = matchRows.map((m) => m.id);

  // If no matches yet, expert score remains 0 (initialized at registration)
  // Only compute when there is at least one match to avoid meaningless score writes
  if (matchIds.length === 0) {
    return;
  }

  // Fetch booking IDs for those matches (shared by call_exp and satisfaction)
  const bookingRows = await sql<Pick<BookingRow, 'id'>[]>`
    SELECT id FROM bookings WHERE match_id = ANY(${matchIds})`;

  const bookingIds = bookingRows.map((b) => b.id);

  // Compute all 5 components in parallel
  const [callExperienceAvg, clientSatisfactionAvg, hireRate, recencyScore, trustScore] =
    await Promise.all([
      computeCallExperienceAvg(bookingIds, sql),
      computeClientSatisfactionAvg(bookingIds, sql),
      computeHireRate(expertId, sql),
      computeRecencyScore(matchIds, sql),
      computeTrustScore(expertId, sql),
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
  await sql`UPDATE experts SET composite_score = ${compositeScore}, score_updated_at = ${new Date().toISOString()} WHERE id = ${expertId}`;
}

// AC3: call_experience_avg — average of call_experience_surveys.score × 20 (1–5 → 0–100)
async function computeCallExperienceAvg(
  bookingIds: string[],
  sql: SqlClient
): Promise<number> {
  if (bookingIds.length === 0) return 0;

  const data = await sql<Pick<CallExperienceSurveyRow, 'score'>[]>`
    SELECT score FROM call_experience_surveys WHERE booking_id = ANY(${bookingIds})`;

  const scores = data
    .filter((r) => r.score !== null)
    .map((r) => r.score! * 20);

  return scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
}

// AC4: client_satisfaction_avg — average of project_satisfaction_surveys.score × 10 (1–10 → 0–100)
async function computeClientSatisfactionAvg(
  bookingIds: string[],
  sql: SqlClient
): Promise<number> {
  if (bookingIds.length === 0) return 0;

  const data = await sql<Pick<ProjectSatisfactionSurveyRow, 'score'>[]>`
    SELECT score FROM project_satisfaction_surveys WHERE booking_id = ANY(${bookingIds})`;

  const scores = data
    .filter((r) => r.score !== null)
    .map((r) => r.score! * 10);

  return scores.length > 0 ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;
}

// AC5: hire_rate — (conversion_declared = true count) / total × 100
async function computeHireRate(expertId: string, sql: SqlClient): Promise<number> {
  const data = await sql<Pick<LeadEvaluationRow, 'conversion_declared'>[]>`
    SELECT conversion_declared FROM lead_evaluations WHERE expert_id = ${expertId}`;

  if (data.length === 0) return 0;

  const converted = data.filter((r) => r.conversion_declared === true).length;
  return (converted / data.length) * 100;
}

// AC6: recency_score — 100 if last booking < 30 days, linear decrease to 0 at 180 days
async function computeRecencyScore(
  matchIds: string[],
  sql: SqlClient
): Promise<number> {
  if (matchIds.length === 0) return 0;

  const [latest] = await sql<Pick<BookingRow, 'scheduled_at'>[]>`
    SELECT scheduled_at FROM bookings WHERE match_id = ANY(${matchIds})
    AND scheduled_at IS NOT NULL ORDER BY scheduled_at DESC LIMIT 1`;

  if (!latest?.scheduled_at) return 0;

  const daysSince =
    (Date.now() - new Date(latest.scheduled_at).getTime()) / (1000 * 60 * 60 * 24);

  if (daysSince < 30) return 100;
  if (daysSince >= 180) return 0;

  // Linear interpolation: 100 at 30 days, 0 at 180 days
  return Math.min(100, Math.max(0, Math.round(100 - ((daysSince - 30) / 150) * 100)));
}

// AC7: trust_score — static profile completeness (5 criteria × 20pts each)
// Criteria use only MVP-collected data (post-delivery correction 2026-02-22)
async function computeTrustScore(expertId: string, sql: SqlClient): Promise<number> {
  const [data] = await sql<Pick<ExpertRow, 'verified_at' | 'bio' | 'headline' | 'gcal_connected' | 'profile'>[]>`
    SELECT verified_at, bio, headline, gcal_connected, profile FROM experts WHERE id = ${expertId}`;

  if (!data) throw new Error(`computeTrustScore: expert ${expertId} not found`);

  let score = 0;
  const p = data.profile as Record<string, unknown> | null;

  // Criterion 1: verified email (20pts) — verified_at is non-null
  if (data.verified_at !== null) score += 20;

  // Criterion 2: bio non-empty (20pts) — collected via E06S03 register form
  if (data.bio !== null && (data.bio as string).trim().length > 0) score += 20;

  // Criterion 3: Google Calendar connected (20pts) — collected via E06S10 OAuth
  if (data.gcal_connected === true) score += 20;

  // Criterion 4: headline non-empty (20pts) — collected via E06S03 register form
  if (data.headline !== null && (data.headline as string).trim().length > 0) score += 20;

  // Criterion 5: ≥3 skills in profile JSONB (20pts) — collected via E06S03 PATCH profile
  const skills = p?.skills;
  if (Array.isArray(skills) && skills.length >= 3) score += 20;

  return score;
}
