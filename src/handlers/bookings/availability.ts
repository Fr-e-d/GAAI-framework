import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { getAccessToken, gcalFreebusy, GcalApiError } from '../../lib/gcalClient';
import { mergeRules, computeFreeSlots } from '../../lib/availability';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleGetAvailability(
  request: Request,
  env: Env,
  expertId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const tz = url.searchParams.get('tz') ?? 'UTC';

  const supabase = createServiceClient(env);
  const { data: expert, error } = await supabase
    .from('experts')
    .select('gcal_email, gcal_access_token, gcal_token_expiry_at, gcal_connected, availability_rules')
    .eq('id', expertId)
    .single();

  if (error || !expert) return json({ error: 'Not Found' }, 404);
  if (!expert.gcal_connected) return json({ error: 'gcal_not_connected' }, 422);
  if (!expert.gcal_email) return json({ error: 'gcal_not_connected' }, 422);

  const rules = mergeRules(expert.availability_rules as Record<string, unknown> | null);

  const now = new Date();
  const timeMin = now.toISOString();
  const timeMax = new Date(now.getTime() + rules.booking_window_days * 24 * 60 * 60 * 1000).toISOString();

  let accessToken: string;
  try {
    accessToken = await getAccessToken(expertId, env);
  } catch {
    return json({ error: 'gcal_token_error' }, 502);
  }

  let busyIntervals: Array<{ start: string; end: string }> = [];
  try {
    busyIntervals = await gcalFreebusy(accessToken, expert.gcal_email, timeMin, timeMax, expertId, env);
  } catch (err) {
    if (err instanceof GcalApiError) {
      return json({ error: 'gcal_error', status: err.gcalStatus, message: err.gcalMessage }, 502);
    }
    return json({ error: 'gcal_error' }, 502);
  }

  // Fetch held/confirmed bookings from DB
  const { data: heldBookings } = await supabase
    .from('bookings')
    .select('start_at, end_at')
    .eq('expert_id', expertId)
    .in('status', ['held', 'confirmed'])
    .lt('start_at', timeMax)
    .gt('end_at', timeMin);

  const slots = computeFreeSlots({
    busyIntervals,
    heldBookings: (heldBookings ?? []).filter(b => b.start_at && b.end_at) as Array<{ start_at: string; end_at: string }>,
    rules,
    now,
  });

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expertId}`,
    event: 'expert.availability_checked',
    properties: { expert_id: expertId, slots_available: slots.length },
  }));

  return json({
    slots,
    metadata: { tz, generated_at: now.toISOString() },
  });
}
