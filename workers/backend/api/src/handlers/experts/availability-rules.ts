// E02S11: CRUD handler for expert_availability_rules
// Routes:
//   GET    /api/experts/:id/availability/rules
//   POST   /api/experts/:id/availability/rules
//   PUT    /api/experts/:id/availability/rules/:ruleId
//   DELETE /api/experts/:id/availability/rules/:ruleId

import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import type { ExpertAvailabilityRuleRow } from '../../types/db';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

// ── Private helpers ─────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

function forbidden(): Response {
  return json({ error: 'forbidden' }, 403);
}

function notFound(): Response {
  return json({ error: 'not_found' }, 404);
}

/**
 * Validate that a time string is in HH:MM format with valid hour/minute values.
 * The API body must supply HH:MM (not HH:MM:SS).
 */
export function validateTimeFormat(t: string): boolean {
  if (!/^\d{2}:\d{2}$/.test(t)) return false;
  const [hStr, mStr] = t.split(':');
  const h = Number(hStr);
  const m = Number(mStr);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

/**
 * Returns true if two time intervals [s1, e1) and [s2, e2) overlap.
 * Assumes HH:MM string comparison is valid for same-day intervals (no midnight crossing).
 */
export function rulesOverlap(s1: string, e1: string, s2: string, e2: string): boolean {
  return s1 < e2 && e1 > s2;
}

/**
 * Normalise a postgres TIME column value ('HH:MM:SS' or 'HH:MM') to 'HH:MM'.
 */
function normalizeTime(t: string): string {
  return t.slice(0, 5);
}

function normalizeRule(row: ExpertAvailabilityRuleRow): ExpertAvailabilityRuleRow & { start_time: string; end_time: string } {
  return {
    ...row,
    start_time: normalizeTime(row.start_time),
    end_time: normalizeTime(row.end_time),
  };
}

// ── GET /api/experts/:id/availability/rules ──────────────────────────────────

export async function handleGetAvailabilityRules(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);

  const [expert] = await sql<{ timezone: string }[]>`
    SELECT timezone FROM experts WHERE id = ${expertId}
  `;

  const rules = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT id, expert_id, day_of_week, start_time, end_time, is_active, created_at, updated_at
    FROM expert_availability_rules
    WHERE expert_id = ${expertId} AND is_active = true
    ORDER BY day_of_week, start_time
  `;

  return json({
    rules: rules.map(normalizeRule),
    timezone: expert?.timezone ?? 'UTC',
  });
}

// ── POST /api/experts/:id/availability/rules ─────────────────────────────────

export async function handleCreateAvailabilityRule(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const { day_of_week, start_time, end_time } = body as Record<string, unknown>;

  // Validate day_of_week
  if (
    typeof day_of_week !== 'number' ||
    !Number.isInteger(day_of_week) ||
    day_of_week < 0 ||
    day_of_week > 6
  ) {
    return json(
      { error: 'Validation failed', details: { day_of_week: 'must be integer 0–6' } },
      422,
    );
  }

  // Validate time formats
  if (typeof start_time !== 'string' || !validateTimeFormat(start_time)) {
    return json(
      { error: 'Validation failed', details: { start_time: 'must be HH:MM format' } },
      422,
    );
  }
  if (typeof end_time !== 'string' || !validateTimeFormat(end_time)) {
    return json(
      { error: 'Validation failed', details: { end_time: 'must be HH:MM format' } },
      422,
    );
  }

  // end_time must be after start_time (string comparison valid for HH:MM same day)
  if (end_time <= start_time) {
    return json(
      { error: 'Validation failed', details: { end_time: 'must be after start_time' } },
      422,
    );
  }

  const sql = createSql(env);

  // Overlap check: query all active rules for this expert on this day
  const existing = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT start_time, end_time
    FROM expert_availability_rules
    WHERE expert_id = ${expertId}
      AND day_of_week = ${day_of_week}
      AND is_active = true
  `;

  for (const row of existing) {
    if (rulesOverlap(start_time, end_time, normalizeTime(row.start_time), normalizeTime(row.end_time))) {
      return json({ error: 'overlapping_rule' }, 409);
    }
  }

  const [created] = await sql<ExpertAvailabilityRuleRow[]>`
    INSERT INTO expert_availability_rules (expert_id, day_of_week, start_time, end_time)
    VALUES (${expertId}, ${day_of_week}, ${start_time}, ${end_time})
    RETURNING id, expert_id, day_of_week, start_time, end_time, is_active, created_at, updated_at
  `;

  return json(normalizeRule(created!), 201);
}

// ── PUT /api/experts/:id/availability/rules/:ruleId ──────────────────────────

export async function handleUpdateAvailabilityRule(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
  ruleId: string,
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);

  // Fetch existing rule — must belong to expert and be active
  const [existingRule] = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT id, expert_id, day_of_week, start_time, end_time, is_active
    FROM expert_availability_rules
    WHERE id = ${ruleId} AND expert_id = ${expertId} AND is_active = true
  `;

  if (!existingRule) return notFound();

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const { day_of_week, start_time, end_time } = body as Record<string, unknown>;

  // Validate day_of_week
  if (
    typeof day_of_week !== 'number' ||
    !Number.isInteger(day_of_week) ||
    day_of_week < 0 ||
    day_of_week > 6
  ) {
    return json(
      { error: 'Validation failed', details: { day_of_week: 'must be integer 0–6' } },
      422,
    );
  }

  // Validate time formats
  if (typeof start_time !== 'string' || !validateTimeFormat(start_time)) {
    return json(
      { error: 'Validation failed', details: { start_time: 'must be HH:MM format' } },
      422,
    );
  }
  if (typeof end_time !== 'string' || !validateTimeFormat(end_time)) {
    return json(
      { error: 'Validation failed', details: { end_time: 'must be HH:MM format' } },
      422,
    );
  }

  // end_time must be after start_time
  if (end_time <= start_time) {
    return json(
      { error: 'Validation failed', details: { end_time: 'must be after start_time' } },
      422,
    );
  }

  // Overlap check: exclude current rule from the check
  const otherRules = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT start_time, end_time
    FROM expert_availability_rules
    WHERE expert_id = ${expertId}
      AND day_of_week = ${day_of_week}
      AND is_active = true
      AND id != ${ruleId}
  `;

  for (const row of otherRules) {
    if (rulesOverlap(start_time, end_time, normalizeTime(row.start_time), normalizeTime(row.end_time))) {
      return json({ error: 'overlapping_rule' }, 409);
    }
  }

  const [updated] = await sql<ExpertAvailabilityRuleRow[]>`
    UPDATE expert_availability_rules
    SET day_of_week = ${day_of_week},
        start_time  = ${start_time},
        end_time    = ${end_time},
        updated_at  = NOW()
    WHERE id = ${ruleId} AND expert_id = ${expertId}
    RETURNING id, expert_id, day_of_week, start_time, end_time, is_active, created_at, updated_at
  `;

  return json(normalizeRule(updated!));
}

// ── DELETE /api/experts/:id/availability/rules/:ruleId ───────────────────────

export async function handleDeleteAvailabilityRule(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
  ruleId: string,
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);

  // Fetch rule — must belong to expert and be active
  const [existingRule] = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT id FROM expert_availability_rules
    WHERE id = ${ruleId} AND expert_id = ${expertId} AND is_active = true
  `;

  if (!existingRule) return notFound();

  // Soft delete
  await sql`
    UPDATE expert_availability_rules
    SET is_active = false, updated_at = NOW()
    WHERE id = ${ruleId} AND expert_id = ${expertId}
  `;

  return new Response(null, { status: 204 });
}
