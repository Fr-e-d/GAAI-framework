import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { getAccessToken, gcalDeleteEvent, GcalApiError } from '../../lib/gcalClient';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleCancel(
  request: Request,
  env: Env,
  bookingId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const supabase = createServiceClient(env);

  const { data: booking, error } = await supabase
    .from('bookings')
    .select('id, expert_id, gcal_event_id, status')
    .eq('id', bookingId)
    .single();

  if (error || !booking) return json({ error: 'Not Found' }, 404);

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
  await supabase.from('bookings').update({ status: 'cancelled' }).eq('id', bookingId);

  // Push notification
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'booking.cancelled',
    booking_id: bookingId,
  });

  let cancelReason: string | null = null;
  try {
    const body = await request.clone().json() as Record<string, unknown>;
    if (typeof body['reason'] === 'string') cancelReason = body['reason'];
  } catch { /* Optional body */ }

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${booking.expert_id ?? 'unknown'}`,
    event: 'booking.cancelled',
    properties: { expert_id: booking.expert_id ?? null, reason: cancelReason },
  }));

  return json({ cancelled: true });
}
