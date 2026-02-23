import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleHold(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const { expert_id, start_at, end_at, prospect_id } = body as Record<string, unknown>;

  if (!expert_id || !start_at || !end_at || !prospect_id) {
    return json({ error: 'Missing required fields: expert_id, start_at, end_at, prospect_id' }, 422);
  }

  if (typeof expert_id !== 'string' || typeof start_at !== 'string' || typeof end_at !== 'string' || typeof prospect_id !== 'string') {
    return json({ error: 'Invalid field types' }, 422);
  }

  const supabase = createServiceClient(env);

  // Conflict check: any held or confirmed booking overlapping this slot
  const { data: conflicts } = await supabase
    .from('bookings')
    .select('id')
    .eq('expert_id', expert_id)
    .in('status', ['held', 'confirmed'])
    .lt('start_at', end_at)
    .gt('end_at', start_at);

  if (conflicts && conflicts.length > 0) {
    return json({ error: 'slot_taken' }, 409);
  }

  // Lookup match_id (nullable)
  const { data: match } = await supabase
    .from('matches')
    .select('id')
    .eq('expert_id', expert_id)
    .eq('prospect_id', prospect_id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const heldUntil = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const prepToken = crypto.randomUUID();

  const { data: booking, error: insertError } = await supabase
    .from('bookings')
    .insert({
      expert_id,
      prospect_id,
      match_id: match?.id ?? null,
      start_at,
      end_at,
      scheduled_at: start_at,
      status: 'held',
      held_until: heldUntil,
      duration_min: 20,
      prep_token: prepToken,
    })
    .select('id, held_until')
    .single();

  if (insertError || !booking) {
    return json({ error: 'Failed to create hold', details: insertError?.message }, 500);
  }

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expert_id}`,
    event: 'booking.held',
    properties: { expert_id, duration_min: 20 },
  }));

  return json({ booking_id: booking.id, held_until: booking.held_until });
}
