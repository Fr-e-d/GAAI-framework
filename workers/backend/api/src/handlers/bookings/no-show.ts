import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { AuthUser } from '../../middleware/auth';
import type { BookingRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}

export async function handleNoShow(
  request: Request,
  env: Env,
  user: AuthUser,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const sql = createSql(env);
  try {
    const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'status' | 'start_at'>[]>`
      SELECT id, expert_id, prospect_id, status, start_at FROM bookings WHERE id = ${bookingId}`;

    if (!booking) return json({ error: 'Not Found' }, 404);
    if (booking.expert_id !== user.id) return json({ error: 'Forbidden' }, 403);
    if (booking.status !== 'confirmed') return json({ error: 'Booking is not in confirmed status' }, 409);
    if (!booking.start_at || new Date(booking.start_at) > new Date()) {
      return json({ error: 'Cannot mark future booking as no-show' }, 409);
    }

    await sql`UPDATE bookings SET status = 'no_show' WHERE id = ${bookingId}`;

    // Increment prospect no_show_count
    const [updated] = await sql<{ no_show_count: number }[]>`
      UPDATE prospects SET no_show_count = no_show_count + 1
      WHERE id = ${booking.prospect_id!}
      RETURNING no_show_count`;

    const newCount = updated?.no_show_count ?? 1;

    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `expert:${user.id}`,
      event: 'booking.no_show_reported',
      properties: {
        booking_id: bookingId,
        expert_id: booking.expert_id!,
        prospect_id: booking.prospect_id!,
        prospect_no_show_count: newCount,
      },
    }));

    return json({ success: true, no_show_count: newCount });
  } finally {
    await sql.end();
  }
}
