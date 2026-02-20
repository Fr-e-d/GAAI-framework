/**
 * Cal.com webhook handler
 *
 * AC5: Validate HMAC-SHA256 signature (X-Cal-Signature-256 header)
 * AC6: Handle booking.created — create bookings row, push to lead-billing + email-notifications
 * AC7: Handle booking.cancelled — update bookings.status to 'cancelled'
 * AC8: Idempotency — skip duplicate booking.created (same cal_booking_id)
 */

import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';

// ── Signature Validation ─────────────────────────────────────────────────────

/**
 * AC5: Validate Cal.com HMAC-SHA256 webhook signature.
 * Cal.com computes: HMAC-SHA256(secret, rawBody) and sends as hex in X-Cal-Signature-256.
 */
async function validateWebhookSignature(
  secret: string,
  rawBody: string,
  signatureHeader: string | null
): Promise<boolean> {
  if (!signatureHeader) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(rawBody));
  const expectedHex = Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  // Timing-safe comparison
  const provided = signatureHeader.toLowerCase().replace(/^sha256=/, '');
  if (provided.length !== expectedHex.length) return false;

  let mismatch = 0;
  for (let i = 0; i < expectedHex.length; i++) {
    mismatch |= expectedHex.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return mismatch === 0;
}

// ── Webhook Payload Types ─────────────────────────────────────────────────────

type CalAttendee = {
  email: string;
  name?: string;
};

type CalOrganizer = {
  username?: string;
  email?: string;
};

type CalVideoCallData = {
  url?: string;
};

type CalMetadata = {
  match_id?: string;
  prospect_id?: string;
  [key: string]: string | undefined;
};

type CalBookingPayload = {
  uid: string;
  title?: string;
  startTime?: string;
  endTime?: string;
  duration?: number;
  attendees?: CalAttendee[];
  organizer?: CalOrganizer;
  videoCallData?: CalVideoCallData;
  metadata?: CalMetadata;
};

type CalWebhookBody = {
  triggerEvent: string;
  payload?: CalBookingPayload;
};

// ── Main Handler ──────────────────────────────────────────────────────────────

export async function handleCalWebhook(
  request: Request,
  env: Env
): Promise<Response> {
  // Read raw body (needed for signature validation before JSON parsing)
  const rawBody = await request.text();

  // AC5: Validate HMAC-SHA256 signature
  const signatureHeader = request.headers.get('X-Cal-Signature-256');
  const isValid = await validateWebhookSignature(env.CAL_WEBHOOK_SECRET, rawBody, signatureHeader);

  if (!isValid) {
    return new Response(JSON.stringify({ error: 'Invalid signature' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: CalWebhookBody;
  try {
    body = JSON.parse(rawBody) as CalWebhookBody;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { triggerEvent, payload } = body;

  if (triggerEvent === 'BOOKING_CREATED' && payload) {
    return handleBookingCreated(env, payload);
  }

  if (triggerEvent === 'BOOKING_CANCELLED' && payload) {
    return handleBookingCancelled(env, payload);
  }

  // Unhandled event type — acknowledge receipt
  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ── booking.created ───────────────────────────────────────────────────────────

async function handleBookingCreated(env: Env, payload: CalBookingPayload): Promise<Response> {
  const supabase = createServiceClient(env);
  const calBookingId = payload.uid;

  // AC8: Idempotency — skip if booking already exists
  const { data: existing } = await supabase
    .from('bookings')
    .select('id')
    .eq('cal_booking_id', calBookingId)
    .single();

  if (existing) {
    // Duplicate event — acknowledge without side effects
    return new Response(JSON.stringify({ received: true, duplicate: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Resolve expert_id + prospect_id + match_id from metadata or organizer
  const matchId = payload.metadata?.match_id ?? null;
  let expertId: string | null = null;
  let prospectId: string | null = payload.metadata?.prospect_id ?? null;

  if (matchId) {
    // Preferred path: match_id carried via Cal.com booking metadata
    const { data: match } = await supabase
      .from('matches')
      .select('expert_id, prospect_id')
      .eq('id', matchId)
      .single();

    if (match) {
      expertId = match.expert_id;
      prospectId = match.prospect_id ?? prospectId;
    }
  } else if (payload.organizer?.username) {
    // Fallback: look up expert by cal_username
    const { data: expert } = await supabase
      .from('experts')
      .select('id')
      .eq('cal_username', payload.organizer.username)
      .single();

    if (expert) expertId = expert.id;
  }

  // AC6: Create bookings row
  const { data: booking, error: insertError } = await supabase
    .from('bookings')
    .insert({
      match_id: matchId,
      cal_booking_id: calBookingId,
      cal_meeting_url: payload.videoCallData?.url ?? null,
      scheduled_at: payload.startTime ?? null,
      duration_min: payload.duration ?? 20,
      status: 'confirmed',
    })
    .select('id')
    .single();

  if (insertError || !booking) {
    console.error('[E06S04] Failed to insert booking:', insertError);
    return new Response(JSON.stringify({ error: 'Failed to create booking' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Update prospect email if captured from attendee list
  const attendeeEmail = payload.attendees?.[0]?.email;
  if (attendeeEmail && prospectId) {
    await supabase
      .from('prospects')
      .update({ email: attendeeEmail })
      .eq('id', prospectId);
  }

  // AC6: Push to lead-billing queue
  await env.LEAD_BILLING.send({
    type: 'booking.created',
    booking_id: booking.id,
    expert_id: expertId,
    prospect_id: prospectId,
  });

  // AC6: Push to email-notifications queue
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'booking.confirmed',
    booking_id: booking.id,
  });

  return new Response(JSON.stringify({ received: true, booking_id: booking.id }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ── booking.cancelled ─────────────────────────────────────────────────────────

async function handleBookingCancelled(env: Env, payload: CalBookingPayload): Promise<Response> {
  const supabase = createServiceClient(env);

  // AC7: Update bookings.status to 'cancelled'
  const { error } = await supabase
    .from('bookings')
    .update({ status: 'cancelled' })
    .eq('cal_booking_id', payload.uid);

  if (error) {
    console.error('[E06S04] Failed to cancel booking:', error);
    return new Response(JSON.stringify({ error: 'Failed to update booking status' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
