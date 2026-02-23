import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { getAccessToken, gcalFreebusy, gcalInsertEvent, GcalApiError } from '../../lib/gcalClient';
import type { BookingRow, ExpertRow, ProspectRow, SatelliteConfigRow } from '../../types/db';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleConfirm(
  request: Request,
  env: Env,
  bookingId: string
): Promise<Response> {
  const sql = createSql(env);

  // Fetch booking
  const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'prospect_id' | 'start_at' | 'end_at' | 'status' | 'held_until' | 'prep_token' | 'match_id'>[]>`
    SELECT id, expert_id, prospect_id, start_at, end_at, status, held_until, prep_token, match_id
    FROM bookings WHERE id = ${bookingId}`;

  if (!booking) return json({ error: 'Not Found' }, 404);
  if (booking.status !== 'held') return json({ error: 'Booking is not in held status' }, 409);
  if (!booking.held_until || new Date(booking.held_until) < new Date()) {
    return json({ error: 'Hold has expired' }, 410);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { prospect_name, prospect_email, description } = body as Record<string, unknown>;
  if (!prospect_name || !prospect_email) {
    return json({ error: 'Missing required fields: prospect_name, prospect_email' }, 422);
  }

  // Fetch expert
  const [expert] = await sql<Pick<ExpertRow, 'gcal_email' | 'gcal_access_token' | 'gcal_token_expiry_at' | 'display_name'>[]>`
    SELECT gcal_email, gcal_access_token, gcal_token_expiry_at, display_name FROM experts WHERE id = ${booking.expert_id!}`;

  if (!expert?.gcal_email) return json({ error: 'Expert not found or GCal not connected' }, 422);

  let accessToken: string;
  try {
    accessToken = await getAccessToken(booking.expert_id!, env);
  } catch {
    return json({ error: 'gcal_token_error' }, 502);
  }

  // AC6: Freebusy race condition guard
  let busyCheck: Array<{ start: string; end: string }>;
  try {
    busyCheck = await gcalFreebusy(accessToken, expert.gcal_email, booking.start_at!, booking.end_at!, booking.expert_id!, env);
  } catch (err) {
    if (err instanceof GcalApiError) {
      return json({ error: 'gcal_error', status: err.gcalStatus, message: err.gcalMessage }, 502);
    }
    return json({ error: 'gcal_error' }, 502);
  }

  const slotStart = new Date(booking.start_at!);
  const slotEnd = new Date(booking.end_at!);
  const slotTaken = busyCheck.some(b => new Date(b.start) < slotEnd && new Date(b.end) > slotStart);

  if (slotTaken) {
    // AC6: Delete the hold and return 409
    await sql`DELETE FROM bookings WHERE id = ${bookingId}`;
    return json({ error: 'slot_taken' }, 409);
  }

  // Fetch prospect requirements for event description
  let eventDescription = typeof description === 'string' ? description : '';
  let prepUrl = `${env.WORKER_BASE_URL}/prep/${booking.prep_token}`;

  try {
    const [prospect] = await sql<Pick<ProspectRow, 'requirements' | 'satellite_id'>[]>`
      SELECT requirements, satellite_id FROM prospects WHERE id = ${booking.prospect_id!}`;

    if (prospect?.requirements) {
      const req = prospect.requirements as Record<string, unknown>;
      const parts: string[] = [];
      if (req.challenge) parts.push(`Contexte : ${req.challenge}`);
      if (req.budget_range) parts.push(`Budget : ${req.budget_range}`);
      if (req.project_stage) parts.push(`Stade de projet : ${req.project_stage}`);
      if (req.industry) parts.push(`Secteur : ${req.industry}`);

      // Try to get satellite domain for prep URL
      if (prospect.satellite_id) {
        const [satellite] = await sql<Pick<SatelliteConfigRow, 'domain'>[]>`
          SELECT domain FROM satellite_configs WHERE id = ${prospect.satellite_id}`;
        if (satellite?.domain) {
          prepUrl = `https://${satellite.domain}/prep/${booking.prep_token}`;
        }
      }

      parts.push(`\n→ Fiche de préparation : ${prepUrl}`);
      eventDescription = parts.join('\n');
    }
  } catch {
    // Non-blocking — use default description
  }

  // Create GCal event
  let gcalResult: { eventId: string; meetingUrl: string | null; htmlLink: string | null };
  try {
    gcalResult = await gcalInsertEvent(
      accessToken,
      expert.gcal_email,
      {
        summary: `Discovery Call — Callibrate`,
        description: eventDescription,
        start: { dateTime: booking.start_at!, timeZone: 'UTC' },
        end: { dateTime: booking.end_at!, timeZone: 'UTC' },
        attendees: [
          { email: expert.gcal_email },
          { email: prospect_email as string },
        ],
        conferenceData: {
          createRequest: {
            requestId: bookingId, // unique per booking — ensures fresh Meet link
            conferenceSolutionKey: { type: 'hangoutsMeet' },
          },
        },
      },
      booking.expert_id!,
      env
    );
  } catch (err) {
    if (err instanceof GcalApiError) {
      return json({ error: 'gcal_error', status: err.gcalStatus, message: err.gcalMessage }, 502);
    }
    return json({ error: 'gcal_error' }, 502);
  }

  // Update booking
  await sql`UPDATE bookings SET status = 'confirmed', gcal_event_id = ${gcalResult.eventId},
    meeting_url = ${gcalResult.meetingUrl}, prospect_name = ${prospect_name as string},
    prospect_email = ${prospect_email as string}, description = ${eventDescription},
    confirmed_at = ${new Date().toISOString()} WHERE id = ${bookingId}`;

  // AC5: Push queue messages
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

  return json({
    booking_id: bookingId,
    meeting_url: gcalResult.meetingUrl,
    start_at: booking.start_at,
    end_at: booking.end_at,
    expert_gcal_event_id: gcalResult.eventId,
  });
}
