import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { getAccessToken, gcalDeleteEvent, GcalApiError } from '../../lib/gcalClient';
import type { BookingRow } from '../../types/db';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleCancel(
  _request: Request,
  env: Env,
  bookingId: string
): Promise<Response> {
  const sql = createSql(env);

  const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'gcal_event_id' | 'status'>[]>`
    SELECT id, expert_id, gcal_event_id, status FROM bookings WHERE id = ${bookingId}`;

  if (!booking) return json({ error: 'Not Found' }, 404);

  // Delete GCal event if present
  if (booking.gcal_event_id && booking.expert_id) {
    try {
      const accessToken = await getAccessToken(booking.expert_id, env);
      await gcalDeleteEvent(accessToken, 'primary', booking.gcal_event_id, booking.expert_id, env);
    } catch (err) {
      if (err instanceof GcalApiError) {
        // Log but don't fail — DB update still proceeds
        console.error('gcalDeleteEvent error:', err.gcalStatus, err.gcalMessage);
      }
    }
  }

  // Update status
  await sql`UPDATE bookings SET status = 'cancelled' WHERE id = ${bookingId}`;

  // Push notification
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'booking.cancelled',
    booking_id: bookingId,
  });

  return json({ cancelled: true });
}
