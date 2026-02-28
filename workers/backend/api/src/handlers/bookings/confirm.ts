import { z } from 'zod';
import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import type { BookingRow, ExpertRow, ProspectRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';
import { signBookingToken } from '../../lib/bookingToken';
import { sendEmail, buildConfirmationEmail } from '../../lib/email';

// AC3/AC4 (E08S04): Strict input validation for booking confirmation
const ConfirmBodySchema = z.object({
  prospect_name: z.string().min(1).max(255),
  prospect_email: z.string().email(),
  description: z.string().optional(),
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleConfirm(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const sql = createSql(env);
  try {
    // Fetch booking
    const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'start_at' | 'held_until' | 'status'>[]>`
      SELECT id, expert_id, prospect_id, start_at, held_until, status
      FROM bookings WHERE id = ${bookingId}`;

    if (!booking) return json({ error: 'Not Found' }, 404);
    if (booking.status !== 'held') return json({ error: 'Booking is not in held status' }, 409);
    if (!booking.held_until || new Date(booking.held_until) < new Date()) {
      return json({ error: 'Hold has expired' }, 410);
    }

    let rawBody: unknown;
    try {
      rawBody = await request.json();
    } catch {
      return json({ error: 'Invalid JSON' }, 400);
    }

    // AC3/AC4 (E08S04): Strict Zod validation — invalid email or name → 422
    const parseResult = ConfirmBodySchema.safeParse(rawBody);
    if (!parseResult.success) {
      return json({ error: 'Validation error', details: parseResult.error.issues }, 422);
    }
    const { prospect_name, prospect_email, description } = parseResult.data;

    // Fetch expert display_name
    const [expert] = await sql<Pick<ExpertRow, 'display_name'>[]>`
      SELECT display_name FROM experts WHERE id = ${booking.expert_id!}`;

    // Check prospect no-show count
    const [prospect] = await sql<Pick<ProspectRow, 'no_show_count'>[]>`
      SELECT no_show_count FROM prospects WHERE id = ${booking.prospect_id!}`;

    if ((prospect?.no_show_count ?? 0) >= 2) {
      return json({ error: 'prospect_blocked', reason: 'no_show_limit' }, 403);
    }

    // Generate confirmation and cancel tokens (30min TTL)
    const confirmToken = await signBookingToken(bookingId, 'confirm', env.BOOKING_CONFIRM_SECRET, 1800);
    const cancelToken = await signBookingToken(bookingId, 'cancel', env.BOOKING_CONFIRM_SECRET, 1800);

    const confirmUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/email-confirm?token=${confirmToken}`;
    const cancelUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/email-cancel?token=${cancelToken}`;

    // Update booking to pending_confirmation and store prospect data
    await sql`UPDATE bookings SET
      status = 'pending_confirmation',
      prospect_name = ${prospect_name},
      prospect_email = ${prospect_email},
      description = ${description ?? ''},
      confirmation_token = ${confirmToken}
      WHERE id = ${bookingId}`;

    // Send confirmation email
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
          to: prospect_email,
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

    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `prospect:${booking.prospect_id!}`,
      event: 'booking.confirmation_email_sent',
      properties: {
        booking_id: bookingId,
        expert_id: booking.expert_id!,
        prospect_id: booking.prospect_id!,
      },
    }));

    return json({ status: 'pending_confirmation', confirmation_sent_to: prospect_email, booking_id: bookingId });
  } finally {
    await sql.end();
  }
}
