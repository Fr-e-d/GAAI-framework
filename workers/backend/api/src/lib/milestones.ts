// ── lib/milestones.ts — E02S10: Expert credit milestone logic (DEC-116/DEC-117) ──
//
// Milestone 1 "Matchable"   → 40EUR (4000 centimes) — display_name + bio 50+ + 3+ skill tags
// Milestone 2 "Bookable"    → 40EUR (4000 centimes) — ≥1 active availability rule (E02S11)
// Milestone 3 "Trustworthy" → 20EUR (2000 centimes) — photo OR portfolio/external link
//
// Anti-gaming: 72h available_at delay on milestone credit transactions (AC6).
// Idempotency: milestone_X_at IS NULL check — once set, never re-triggered.

import type { ExpertRow } from '../types/db';
import type { SqlClient } from './db';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface MilestoneResult {
  matchable: boolean;
  bookable: boolean;
  trust: boolean;
}

const MILESTONE_CREDITS = {
  matchable: { amount: 4000, type: 'milestone_matchable', description: 'Profil matchable - 40EUR offerts' },
  bookable:  { amount: 4000, type: 'milestone_bookable',  description: 'Profil reservable - 40EUR offerts' },
  trust:     { amount: 2000, type: 'milestone_trust',     description: 'Profil de confiance - 20EUR offerts' },
} as const;

// ── checkMilestones ───────────────────────────────────────────────────────────
// Evaluates the 3 milestone conditions synchronously from the expert record.
// "Bookable" condition requires an async DB check — use checkBookable() separately.

export function checkMilestones(expert: ExpertRow): Omit<MilestoneResult, 'bookable'> {
  // Milestone 1 — Matchable: display_name (≥2 chars) + bio (≥50 chars) + 3+ skill tags
  const matchable = !!(
    expert.display_name && expert.display_name.length >= 2 &&
    expert.bio && expert.bio.length >= 50 &&
    expert.outcome_tags && expert.outcome_tags.length >= 3
  );

  // Milestone 3 — Trustworthy: avatar_url OR portfolio_url/external link in profile JSONB
  const profileData = expert.profile as Record<string, unknown> | null;
  const trust = !!(
    expert.avatar_url ||
    profileData?.portfolio_url ||
    profileData?.linkedin_url ||
    profileData?.github_url ||
    profileData?.website_url
  );

  return { matchable, trust };
}

// ── checkBookable ─────────────────────────────────────────────────────────────
// Checks if the expert has ≥1 active availability rule (requires expert_availability_rules
// table, delivered in E02S11). Returns false gracefully if table doesn't exist yet.

export async function checkBookable(expertId: string, sql: SqlClient): Promise<boolean> {
  try {
    const rows = await sql<{ exists: boolean }[]>`
      SELECT EXISTS(
        SELECT 1 FROM expert_availability_rules
        WHERE expert_id = ${expertId} AND is_active = true
      ) AS exists
    `;
    return rows[0]?.exists ?? false;
  } catch {
    // Table doesn't exist yet (E02S11 not yet delivered) — Milestone 2 permanently locked
    return false;
  }
}

// ── processMilestoneCredits ───────────────────────────────────────────────────
// For each newly unlocked milestone: atomic UPDATE expert + INSERT credit_transaction.
// Each milestone is an independent transaction (idempotent — IF milestone_X_at IS NULL).
// Credits have available_at = NOW() + 72h (anti-gaming delay, AC6).
// Returns the list of newly unlocked milestone names.

export async function processMilestoneCredits(
  expertId: string,
  milestoneConditions: MilestoneResult,
  sql: SqlClient,
): Promise<Array<keyof MilestoneResult>> {
  const unlocked: Array<keyof MilestoneResult> = [];

  const milestoneChecks: Array<{
    key: keyof MilestoneResult;
    condition: boolean;
    column: 'milestone_matchable_at' | 'milestone_bookable_at' | 'milestone_trust_at';
  }> = [
    { key: 'matchable', condition: milestoneConditions.matchable, column: 'milestone_matchable_at' },
    { key: 'bookable',  condition: milestoneConditions.bookable,  column: 'milestone_bookable_at' },
    { key: 'trust',     condition: milestoneConditions.trust,     column: 'milestone_trust_at' },
  ];

  for (const { key, condition, column } of milestoneChecks) {
    if (!condition) continue;

    const { amount, type, description } = MILESTONE_CREDITS[key];

    // Atomic transaction: SET milestone_X_at IF NULL, award credit with 72h delay
    // Uses CTE to ensure idempotency: only proceeds if column IS NULL
    const result = await sql<{ balance_after: number; unlocked: boolean }[]>`
      WITH lock AS (
        UPDATE experts
        SET
          ${sql(column)} = NOW(),
          credit_balance = credit_balance + ${amount}
        WHERE id = ${expertId}
          AND ${sql(column)} IS NULL
        RETURNING id, credit_balance
      ),
      credit AS (
        INSERT INTO credit_transactions (expert_id, type, amount, balance_after, description, available_at)
        SELECT
          ${expertId},
          ${type},
          ${amount},
          lock.credit_balance,
          ${description},
          NOW() + INTERVAL '72 hours'
        FROM lock
        RETURNING balance_after
      )
      SELECT
        COALESCE((SELECT balance_after FROM credit), 0) AS balance_after,
        EXISTS(SELECT 1 FROM lock) AS unlocked
    `;

    if (result[0]?.unlocked) {
      unlocked.push(key);
    }
  }

  return unlocked;
}
