// E02S12 AC16: GET /api/bookings/:id/direct-email-confirm?token=...
// Magic link email confirmation handler for direct bookings.
// Called from the confirmation link in the prospect email.
// Validates JWT → updates booking status to 'pending_slot_selection' → redirect.
// On click → will later trigger GCal event + expert prep email (AC17, future Story).

import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { verifyBookingToken } from '../../lib/bookingToken';
import type { BookingRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

function redirectTo(url: string): Response {
  return Response.redirect(url, 302);
}

export async function handleDirectBookingEmailConfirm(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');
  const callibrateFrontend = 'https://callibrate.io';

  if (!token) {
    return redirectTo(`${callibrateFrontend}/booking-expired`);
  }

  // Validate token against DIRECT_BOOKING_SECRET (24h TTL magic link)
  const tokenResult = await verifyBookingToken(
    token,
    bookingId,
    'confirm',
    env.DIRECT_BOOKING_SECRET,
  );

  if (tokenResult === 'invalid') {
    return redirectTo(`${callibrateFrontend}/booking-error`);
  }

  if (tokenResult === 'expired') {
    return redirectTo(`${callibrateFrontend}/booking-expired`);
  }

  const sql = createSql(env);
  try {
    const [booking] = await sql<Pick<BookingRow, 'id' | 'status' | 'expert_id' | 'lead_source'>[]>`
      SELECT id, status, expert_id, lead_source
      FROM bookings
      WHERE id = ${bookingId}
    `;

    if (!booking) {
      return redirectTo(`${callibrateFrontend}/booking-error`);
    }

    // Only process direct bookings via this endpoint
    if (booking.lead_source !== 'direct') {
      return redirectTo(`${callibrateFrontend}/booking-error`);
    }

    // Idempotent: if already confirmed or past pending_confirmation, redirect to success
    if (booking.status === 'pending_slot_selection') {
      return redirectTo(`${callibrateFrontend}/booking-direct-confirmed/${bookingId}`);
    }

    if (booking.status !== 'pending_confirmation') {
      return redirectTo(`${callibrateFrontend}/booking-error`);
    }

    // Transition: pending_confirmation → pending_slot_selection
    // AC16: prospect has confirmed email; next step is slot selection (future AC17 integration)
    await sql`
      UPDATE bookings
      SET status = 'pending_slot_selection', confirmed_at = ${new Date().toISOString()}
      WHERE id = ${bookingId}
    `;

    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `system`,
      event: 'booking.direct_email_confirmed',
      properties: {
        booking_id: bookingId,
        expert_id: booking.expert_id,
        lead_source: 'direct',
      },
    }));

    // Redirect to slot selection page (landing Worker serves this in future)
    return redirectTo(`${callibrateFrontend}/booking-direct-confirmed/${bookingId}`);

  } finally {
    await sql.end();
  }
}
