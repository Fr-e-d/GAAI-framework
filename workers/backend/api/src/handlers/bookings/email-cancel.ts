import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { verifyBookingToken } from '../../lib/bookingToken';
import type { BookingRow, ProspectRow, SatelliteConfigRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

function redirect(url: string): Response {
  return Response.redirect(url, 302);
}

async function getSatelliteDomain(sql: ReturnType<typeof createSql>, prospectId: string, fallback: string): Promise<string> {
  try {
    const [prospect] = await sql<Pick<ProspectRow, 'satellite_id'>[]>`
      SELECT satellite_id FROM prospects WHERE id = ${prospectId}`;
    if (prospect?.satellite_id) {
      const [sat] = await sql<Pick<SatelliteConfigRow, 'domain'>[]>`
        SELECT domain FROM satellite_configs WHERE id = ${prospect.satellite_id}`;
      if (sat?.domain) return sat.domain;
    }
  } catch { /* ignore */ }
  return new URL(fallback).hostname;
}

export async function handleEmailCancel(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  const fallbackDomain = new URL(env.WORKER_BASE_URL).hostname;

  if (!token) return redirect(`https://${fallbackDomain}/booking-error`);

  const tokenResult = await verifyBookingToken(token, bookingId, 'cancel', env.BOOKING_CONFIRM_SECRET);
  if (tokenResult === 'invalid') return redirect(`https://${fallbackDomain}/booking-error`);

  const sql = createSql(env);
  try {
    const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'status'>[]>`
      SELECT id, expert_id, prospect_id, status FROM bookings WHERE id = ${bookingId}`;

    if (!booking) return redirect(`https://${fallbackDomain}/booking-error`);

    const satelliteDomain = await getSatelliteDomain(sql, booking.prospect_id!, env.WORKER_BASE_URL);

    if (tokenResult === 'expired') {
      return redirect(`https://${satelliteDomain}/booking-expired`);
    }

    // Only cancel if still pending_confirmation (idempotent)
    if (booking.status === 'pending_confirmation') {
      await sql`UPDATE bookings SET status = 'cancelled_by_prospect' WHERE id = ${bookingId}`;

      ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
        distinctId: `prospect:${booking.prospect_id!}`,
        event: 'booking.email_cancelled',
        properties: {
          booking_id: bookingId,
          expert_id: booking.expert_id!,
          prospect_id: booking.prospect_id!,
        },
      }));
    }

    return redirect(`https://${satelliteDomain}/booking-cancelled`);
  } finally {
    await sql.end();
  }
}
