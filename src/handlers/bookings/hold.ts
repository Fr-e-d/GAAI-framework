import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import type { BookingRow } from '../../types/db';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleHold(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { expert_id, start_at, end_at, prospect_id } = body as Record<string, unknown>;

  if (!expert_id || !start_at || !end_at || !prospect_id) {
    return json({ error: 'Missing required fields: expert_id, start_at, end_at, prospect_id' }, 422);
  }

  if (typeof expert_id !== 'string' || typeof start_at !== 'string' || typeof end_at !== 'string' || typeof prospect_id !== 'string') {
    return json({ error: 'Invalid field types' }, 422);
  }

  const sql = createSql(env);

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

  return json({ booking_id: booking.id, held_until: booking.held_until });
}
