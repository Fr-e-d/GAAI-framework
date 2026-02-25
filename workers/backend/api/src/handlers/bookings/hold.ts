import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import type { BookingRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';
import { verifyProspectToken } from '../../lib/jwt';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleHold(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  // AC2: Rate limiting — 5 holds per hour per IP (KV-based sliding window)
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const holdRateKey = `hold-rate:${ip}`;
  const holdCountStr = await env.SESSIONS.get(holdRateKey);
  const holdCount = holdCountStr ? parseInt(holdCountStr, 10) : 0;
  if (holdCount >= 5) {
    return json({ error: 'Too Many Requests' }, 429);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { expert_id, start_at, end_at, prospect_id, token } = body as Record<string, unknown>;

  if (!expert_id || !start_at || !end_at || !prospect_id) {
    return json({ error: 'Missing required fields: expert_id, start_at, end_at, prospect_id' }, 422);
  }

  if (typeof expert_id !== 'string' || typeof start_at !== 'string' || typeof end_at !== 'string' || typeof prospect_id !== 'string') {
    return json({ error: 'Invalid field types' }, 422);
  }

  // AC1: Prospect token verification
  if (!token || typeof token !== 'string') {
    return json({ error: 'Forbidden' }, 403);
  }
  const tokenValid = await verifyProspectToken(token, prospect_id, env.PROSPECT_TOKEN_SECRET, 'prospect:identify');
  if (!tokenValid) {
    return json({ error: 'Forbidden' }, 403);
  }

  // AC5: ISO-8601 datetime validation
  const startDate = new Date(start_at);
  const endDate = new Date(end_at);
  if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
    return json({ error: 'Invalid datetime format: start_at and end_at must be ISO-8601' }, 422);
  }
  if (startDate.getTime() <= Date.now()) {
    return json({ error: 'start_at must be in the future' }, 422);
  }
  if (endDate.getTime() <= startDate.getTime()) {
    return json({ error: 'end_at must be after start_at' }, 422);
  }

  const sql = createSql(env);

  // AC4: Validate expert_id exists
  const [expert] = await sql<{ id: string }[]>`
    SELECT id FROM experts WHERE id = ${expert_id}`;
  if (!expert) {
    return json({ error: 'expert_not_found' }, 404);
  }

  // AC3: Max 3 active holds per prospect
  const [activeHolds] = await sql<{ count: number }[]>`
    SELECT COUNT(*)::int AS count FROM bookings
    WHERE prospect_id = ${prospect_id} AND status = 'held'`;
  if (activeHolds && activeHolds.count >= 3) {
    return json({ error: 'max_holds_reached' }, 409);
  }

  // Conflict check: any held or confirmed booking overlapping this slot
  const conflicts = await sql<{ id: string }[]>`
    SELECT id FROM bookings WHERE expert_id = ${expert_id}
    AND status = ANY(ARRAY['held', 'confirmed'])
    AND start_at < ${end_at} AND end_at > ${start_at}`;

  if (conflicts.length > 0) {
    return json({ error: 'slot_taken' }, 409);
  }

  // Lookup match_id (nullable)
  const [match] = await sql<{ id: string }[]>`
    SELECT id FROM matches WHERE expert_id = ${expert_id} AND prospect_id = ${prospect_id}
    ORDER BY created_at DESC LIMIT 1`;

  const heldUntil = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const prepToken = crypto.randomUUID();

  const [booking] = await sql<Pick<BookingRow, 'id' | 'held_until'>[]>`
    INSERT INTO bookings (expert_id, prospect_id, match_id, start_at, end_at, scheduled_at, status, held_until, duration_min, prep_token)
    VALUES (${expert_id}, ${prospect_id}, ${match?.id ?? null}, ${start_at}, ${end_at}, ${start_at}, 'held', ${heldUntil}, 20, ${prepToken})
    RETURNING id, held_until`;

  if (!booking) {
    return json({ error: 'Failed to create hold' }, 500);
  }

  // Increment hold rate counter after successful hold (AC2)
  ctx.waitUntil(env.SESSIONS.put(holdRateKey, String(holdCount + 1), { expirationTtl: 3600 }));

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expert_id}`,
    event: 'booking.held',
    properties: { expert_id, duration_min: 20 },
  }));

  return json({ booking_id: booking.id, held_until: booking.held_until });
}
