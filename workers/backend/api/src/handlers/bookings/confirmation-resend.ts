import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import type { BookingRow, ExpertRow } from '../../types/db';
import { signBookingToken } from '../../lib/bookingToken';
import { sendEmail, buildConfirmationEmail } from '../../lib/email';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}

const RESEND_KV_TTL = 3600; // 1 hour
const RESEND_MAX = 3;

export async function handleConfirmationResend(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  // Rate limit: max 3 resends per booking per hour
  const rateLimitKey = `confirm-resend-rate:${bookingId}`;
  const currentCount = parseInt((await env.SESSIONS.get(rateLimitKey)) ?? '0', 10);
  if (currentCount >= RESEND_MAX) {
    return json({ error: 'rate_limit_exceeded' }, 429);
  }

  const sql = createSql(env);
  try {
    const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'status' | 'start_at' | 'prospect_email'>[]>`
      SELECT id, expert_id, prospect_id, status, start_at, prospect_email FROM bookings WHERE id = ${bookingId}`;

    if (!booking) return json({ error: 'Not Found' }, 404);
    if (booking.status !== 'pending_confirmation') {
      return json({ error: 'Booking is not awaiting confirmation' }, 409);
    }
    if (!booking.prospect_email) return json({ error: 'No prospect email' }, 422);

    const [expert] = await sql<Pick<ExpertRow, 'display_name'>[]>`
      SELECT display_name FROM experts WHERE id = ${booking.expert_id!}`;

    // Generate fresh tokens (revokes previous via confirmation_token update)
    const confirmToken = await signBookingToken(bookingId, 'confirm', env.BOOKING_CONFIRM_SECRET, 1800);
    const cancelToken = await signBookingToken(bookingId, 'cancel', env.BOOKING_CONFIRM_SECRET, 1800);

    const confirmUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/email-confirm?token=${confirmToken}`;
    const cancelUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/email-cancel?token=${cancelToken}`;

    // Update stored token (revokes previous)
    await sql`UPDATE bookings SET confirmation_token = ${confirmToken} WHERE id = ${bookingId}`;

    const { html, text } = buildConfirmationEmail({
      expertName: expert?.display_name ?? 'l\'expert',
      confirmUrl,
      cancelUrl,
      startAt: booking.start_at!,
      expiryMinutes: 30,
    });

    try {
      await sendEmail(
        {
          to: booking.prospect_email,
          subject: `Confirmez votre appel avec ${expert?.display_name ?? 'l\'expert'}`,
          html,
          text,
        },
        {
          apiKey: env.RESEND_API_KEY,
          fromDomain: env.EMAIL_FROM_DOMAIN || 'callibrate.io',
          replyTo: env.EMAIL_REPLY_TO || 'support@callibrate.io',
        },
      );
    } catch {
      return json({ error: 'email_send_failed' }, 502);
    }

    // Increment rate limit counter
    await env.SESSIONS.put(rateLimitKey, String(currentCount + 1), { expirationTtl: RESEND_KV_TTL });

    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `prospect:${booking.prospect_id!}`,
      event: 'booking.confirmation_email_sent',
      properties: { booking_id: bookingId, resend: true },
    }));

    return json({ success: true });
  } finally {
    await sql.end();
  }
}
