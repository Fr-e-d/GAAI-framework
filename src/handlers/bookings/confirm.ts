import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { getAccessToken, gcalFreebusy, gcalInsertEvent, GcalApiError } from '../../lib/gcalClient';
import { captureEvent } from '../../lib/posthog';

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
  const supabase = createServiceClient(env);

  // Fetch booking
  const { data: booking, error: bookingError } = await supabase
    .from('bookings')
    .select('id, expert_id, prospect_id, start_at, end_at, status, held_until, prep_token, match_id, duration_min')
    .eq('id', bookingId)
    .single();

  if (bookingError || !booking) return json({ error: 'Not Found' }, 404);
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
  const { data: expert, error: expertError } = await supabase
    .from('experts')
    .select('gcal_email, gcal_access_token, gcal_token_expiry_at, display_name')
    .eq('id', booking.expert_id!)
    .single();

  if (expertError || !expert?.gcal_email) return json({ error: 'Expert not found or GCal not connected' }, 422);

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
    await supabase.from('bookings').delete().eq('id', bookingId);
    return json({ error: 'slot_taken' }, 409);
  }

  // Fetch prospect requirements for event description
  let eventDescription = typeof description === 'string' ? description : '';
  let prepUrl = `${env.WORKER_BASE_URL}/prep/${booking.prep_token}`;

  try {
    const { data: prospect } = await supabase
      .from('prospects')
      .select('requirements, satellite_id')
      .eq('id', booking.prospect_id!)
      .single();

    if (prospect?.requirements) {
      const req = prospect.requirements as Record<string, unknown>;
      const parts: string[] = [];
      if (req.challenge) parts.push(`Contexte : ${req.challenge}`);
      if (req.budget_range) parts.push(`Budget : ${req.budget_range}`);
      if (req.project_stage) parts.push(`Stade de projet : ${req.project_stage}`);
      if (req.industry) parts.push(`Secteur : ${req.industry}`);

      // Try to get satellite domain for prep URL
      if (prospect.satellite_id) {
        const { data: satellite } = await supabase
          .from('satellite_configs')
          .select('domain')
          .eq('id', prospect.satellite_id)
          .single();
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
  const { error: updateError } = await supabase
    .from('bookings')
    .update({
      status: 'confirmed',
      gcal_event_id: gcalResult.eventId,
      meeting_url: gcalResult.meetingUrl,
      prospect_name: prospect_name as string,
      prospect_email: prospect_email as string,
      description: eventDescription,
      confirmed_at: new Date().toISOString(),
    })
    .eq('id', bookingId);

  if (updateError) {
    return json({ error: 'Failed to update booking', details: updateError.message }, 500);
  }

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

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${booking.expert_id!}`,
    event: 'booking.confirmed',
    properties: {
      expert_id: booking.expert_id!,
      prospect_id: booking.prospect_id!,
      duration_min: booking.duration_min ?? 20,
    },
  }));

  return json({
    booking_id: bookingId,
    meeting_url: gcalResult.meetingUrl,
    start_at: booking.start_at,
    end_at: booking.end_at,
    expert_gcal_event_id: gcalResult.eventId,
  });
}
