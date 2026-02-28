import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { verifyBookingToken, signBookingToken } from '../../lib/bookingToken';
import { getAccessToken, gcalInsertEvent, GcalApiError } from '../../lib/gcalClient';
import type { BookingRow, ExpertRow, ProspectRow, SatelliteConfigRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';
import { sendEmail, buildExpertApprovalEmail } from '../../lib/email';

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

export async function handleEmailConfirm(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  const fallbackDomain = new URL(env.WORKER_BASE_URL).hostname;

  if (!token) return redirect(`https://${fallbackDomain}/booking-expired`);

  const tokenResult = await verifyBookingToken(token, bookingId, 'confirm', env.BOOKING_CONFIRM_SECRET);

  const sql = createSql(env);
  try {
    if (tokenResult === 'invalid') {
      return redirect(`https://${fallbackDomain}/booking-error`);
    }

    // Fetch booking
    const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'start_at' | 'end_at' | 'status' | 'confirmation_token' | 'prep_token' | 'match_id' | 'duration_min' | 'prospect_name' | 'prospect_email' | 'description'>[]>`
      SELECT id, expert_id, prospect_id, start_at, end_at, status, confirmation_token, prep_token, match_id, duration_min, prospect_name, prospect_email, description
      FROM bookings WHERE id = ${bookingId}`;

    if (!booking) return redirect(`https://${fallbackDomain}/booking-error`);

    const satelliteDomain = await getSatelliteDomain(sql, booking.prospect_id!, env.WORKER_BASE_URL);

    if (booking.status === 'confirmed') {
      return redirect(`https://${satelliteDomain}/booking-confirmed/${bookingId}?already=true`);
    }

    if (tokenResult === 'expired') {
      return redirect(`https://${satelliteDomain}/booking-expired`);
    }

    if (booking.status !== 'pending_confirmation') {
      return redirect(`https://${satelliteDomain}/booking-error`);
    }

    // Token revocation check (resend replaces token)
    if (booking.confirmation_token !== token) {
      return redirect(`https://${satelliteDomain}/booking-expired`);
    }

    // Fetch expert
    const [expert] = await sql<Pick<ExpertRow, 'gcal_email' | 'display_name' | 'booking_auto_confirm'>[]>`
      SELECT gcal_email, display_name, booking_auto_confirm FROM experts WHERE id = ${booking.expert_id!}`;

    if (!expert?.gcal_email) return redirect(`https://${satelliteDomain}/booking-error`);

    // Get GCal token
    let accessToken: string;
    try {
      accessToken = await getAccessToken(booking.expert_id!, env);
    } catch {
      return redirect(`https://${satelliteDomain}/booking-error`);
    }

    // Create GCal event (moved from confirm.ts)
    let gcalResult: { eventId: string; meetingUrl: string | null; htmlLink: string | null };
    try {
      gcalResult = await gcalInsertEvent(
        accessToken,
        expert.gcal_email,
        {
          summary: `Discovery Call — Callibrate`,
          description: booking.description ?? '',
          start: { dateTime: booking.start_at!, timeZone: 'UTC' },
          end: { dateTime: booking.end_at!, timeZone: 'UTC' },
          attendees: [
            { email: expert.gcal_email },
            { email: booking.prospect_email! },
          ],
          conferenceData: {
            createRequest: {
              requestId: bookingId,
              conferenceSolutionKey: { type: 'hangoutsMeet' },
            },
          },
        },
        booking.expert_id!,
        env,
      );
    } catch (err) {
      if (err instanceof GcalApiError) {
        console.error('email-confirm: gcal error', err.gcalStatus, err.gcalMessage);
      }
      return redirect(`https://${satelliteDomain}/booking-error`);
    }

    // Determine next status based on booking_auto_confirm (default true)
    const autoConfirm = expert.booking_auto_confirm !== false;

    if (autoConfirm) {
      // Immediately confirm
      await sql`UPDATE bookings SET
        status = 'confirmed',
        gcal_event_id = ${gcalResult.eventId},
        meeting_url = ${gcalResult.meetingUrl},
        confirmed_at = ${new Date().toISOString()},
        confirmation_token = NULL
        WHERE id = ${bookingId}`;

      // Fire queue messages
      await env.LEAD_BILLING.send({
        type: 'booking.created',
        booking_id: bookingId,
        expert_id: booking.expert_id!,
        prospect_id: booking.prospect_id!,
      });

      await env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.confirmed',
        booking_id: bookingId,
        expert_id: booking.expert_id!,
        prospect_id: booking.prospect_id!,
        meeting_url: gcalResult.meetingUrl ?? '',
        scheduled_at: booking.start_at!,
      });

      ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
        distinctId: `prospect:${booking.prospect_id!}`,
        event: 'booking.email_confirmed',
        properties: {
          booking_id: bookingId,
          expert_id: booking.expert_id!,
          prospect_id: booking.prospect_id!,
        },
      }));

      const prepToken = booking.prep_token ?? '';
      return redirect(`https://${satelliteDomain}/booking-confirmed/${bookingId}?token=${prepToken}`);
    } else {
      // Expert approval required
      await sql`UPDATE bookings SET
        status = 'pending_expert_approval',
        gcal_event_id = ${gcalResult.eventId},
        meeting_url = ${gcalResult.meetingUrl},
        confirmed_at = NULL,
        confirmation_token = NULL
        WHERE id = ${bookingId}`;

      // Generate approve/reject tokens (24h TTL)
      const approveToken = await signBookingToken(bookingId, 'expert-approve', env.BOOKING_CONFIRM_SECRET, 86400);
      const rejectToken = await signBookingToken(bookingId, 'expert-reject', env.BOOKING_CONFIRM_SECRET, 86400);
      const approveUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/expert-approve?token=${approveToken}`;
      const rejectUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/expert-reject?token=${rejectToken}`;

      // Send expert approval email
      const { html, text } = buildExpertApprovalEmail({
        expertName: expert.display_name ?? 'Expert',
        prospectName: booking.prospect_name ?? 'Un prospect',
        startAt: booking.start_at!,
        approveUrl,
        rejectUrl,
        expiryHours: 24,
      });

      try {
        await sendEmail(
          {
            to: expert.gcal_email,
            subject: `Nouvelle demande de réservation : ${booking.prospect_name ?? 'Un prospect'}`,
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
        // Non-blocking — booking is in pending_expert_approval, cron will auto-confirm in 24h
        console.error('email-confirm: failed to send expert approval email for booking', bookingId);
      }

      ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
        distinctId: `prospect:${booking.prospect_id!}`,
        event: 'booking.email_confirmed',
        properties: {
          booking_id: bookingId,
          expert_id: booking.expert_id!,
          prospect_id: booking.prospect_id!,
          requires_expert_approval: true,
        },
      }));

      // Redirect prospect to a "pending expert approval" page
      return redirect(`https://${satelliteDomain}/booking-pending-approval/${bookingId}`);
    }
  } finally {
    await sql.end();
  }
}
