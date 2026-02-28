import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { getAccessToken, gcalFreebusy, GcalApiError } from '../../lib/gcalClient';
import { mergeRules, computeFreeSlots, expandRulesToWorkingHours } from '../../lib/availability';
import type { ExpertRow, BookingRow, ExpertAvailabilityRuleRow } from '../../types/db';
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
  const requestedTz = url.searchParams.get('tz') ?? 'UTC';

  const sql = createSql(env);
  const [expert] = await sql<Pick<ExpertRow, 'gcal_email' | 'gcal_access_token' | 'gcal_token_expiry_at' | 'gcal_connected' | 'availability_rules' | 'timezone'>[]>`
    SELECT gcal_email, gcal_access_token, gcal_token_expiry_at, gcal_connected, availability_rules, timezone
    FROM experts WHERE id = ${expertId}`;

  if (!expert) return json({ error: 'Not Found' }, 404);

  // E02S11: Load DB-based availability rules
  const dbRules = await sql<ExpertAvailabilityRuleRow[]>`
    SELECT id, expert_id, day_of_week, start_time, end_time, is_active, created_at, updated_at
    FROM expert_availability_rules
    WHERE expert_id = ${expertId} AND is_active = true
    ORDER BY day_of_week, start_time
  `;

  // Determine working hours source: DB rules take precedence over legacy JSONB rules
  let rules: ReturnType<typeof mergeRules>;

  if (dbRules.length > 0) {
    // E02S11 path: convert DB rules (local time) → UTC working_hours → mergeRules
    const workingHours = expandRulesToWorkingHours(dbRules, expert.timezone ?? 'UTC');
    rules = mergeRules({ ...((expert.availability_rules as Record<string, unknown>) ?? {}), working_hours: workingHours });
  } else if (expert.availability_rules) {
    // Legacy path: JSONB availability_rules on experts table
    rules = mergeRules(expert.availability_rules as Record<string, unknown> | null);
  } else {
    // Not configured — return empty slots with status indicator
    return json({
      slots: [],
      availability_status: 'not_configured',
      metadata: { tz: requestedTz, generated_at: new Date().toISOString() },
    });
  }

  const now = new Date();
  const timeMin = now.toISOString();
  const timeMax = new Date(now.getTime() + rules.booking_window_days * 24 * 60 * 60 * 1000).toISOString();

  // E02S11: GCal is optional — only fetch FreeBusy if expert has GCal connected
  let busyIntervals: Array<{ start: string; end: string }> = [];

  if (expert.gcal_connected && expert.gcal_email) {
    try {
      const accessToken = await getAccessToken(expertId, env);
      busyIntervals = await gcalFreebusy(accessToken, expert.gcal_email, timeMin, timeMax, expertId, env);
    } catch (err) {
      if (err instanceof GcalApiError) {
        // GCal error is non-fatal when DB rules are configured — log and continue
        console.error('GCal freebusy error (non-fatal):', err.gcalStatus, err.gcalMessage);
      } else {
        console.error('GCal access token error (non-fatal):', err);
      }
      // Proceed without GCal conflict filtering
    }
  }

  // Fetch held/confirmed bookings from DB
  const heldBookings = await sql<Pick<BookingRow, 'start_at' | 'end_at'>[]>`
    SELECT start_at, end_at FROM bookings
    WHERE expert_id = ${expertId} AND status = ANY(ARRAY['held', 'confirmed'])
    AND start_at < ${timeMax} AND end_at > ${timeMin}`;

  const slots = computeFreeSlots({
    busyIntervals,
    heldBookings: heldBookings.filter(b => b.start_at && b.end_at) as Array<{ start_at: string; end_at: string }>,
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
    availability_status: 'configured',
    metadata: { tz: requestedTz, generated_at: now.toISOString() },
  });
}
