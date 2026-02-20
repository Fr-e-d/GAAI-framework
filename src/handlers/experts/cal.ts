/**
 * Cal.com expert handlers
 *
 * AC2: GET /api/experts/:id/cal/auth-url  — return Google Calendar OAuth URL
 * AC3: GET /api/experts/:id/cal/callback  — handle OAuth callback, trigger event type creation
 * AC4: (called from callback) auto-create "20-min Intro Call" event type
 * AC10: GET /api/experts/:id/cal/status   — return cal connection state
 */

import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createServiceClient } from '../../lib/supabase';
import { getGoogleCalendarAuthUrl, createIntroCallEventType } from '../../lib/cal';

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: { 'Content-Type': 'application/json' },
  });
}

function notFound(msg: string): Response {
  return new Response(JSON.stringify({ error: msg }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * AC2: GET /api/experts/:id/cal/auth-url
 * Returns the Google Calendar OAuth URL scoped to the Cal.com managed user.
 * The expert onboarding UI opens this URL to trigger Google Calendar connection.
 */
export async function handleCalAuthUrl(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const supabase = createServiceClient(env);
  const { data: expert, error } = await supabase
    .from('experts')
    .select('cal_access_token, cal_username')
    .eq('id', expertId)
    .single();

  if (error || !expert) return notFound('Expert not found');

  if (!expert.cal_access_token) {
    return json({ error: 'Cal.com account not yet provisioned for this expert' }, 409);
  }

  // Build callback URL pointing to our handler (AC3)
  const callbackUrl = new URL(request.url);
  callbackUrl.pathname = `/api/experts/${expertId}/cal/callback`;
  callbackUrl.search = '';

  try {
    const authUrl = await getGoogleCalendarAuthUrl(
      expert.cal_access_token,
      callbackUrl.toString()
    );
    return json({ auth_url: authUrl });
  } catch (err) {
    console.error('[E06S04] Failed to get Google Calendar auth URL:', err);
    return json({ error: 'Failed to generate Google Calendar authorization URL' }, 502);
  }
}

/**
 * AC3: GET /api/experts/:id/cal/callback
 * Handles the OAuth callback after expert grants Google Calendar access.
 * Cal.com processes the OAuth with Google and redirects the expert here.
 * We mark the expert's Google Calendar as connected and auto-create the event type (AC4).
 */
export async function handleCalCallback(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const supabase = createServiceClient(env);
  const { data: expert, error } = await supabase
    .from('experts')
    .select('cal_access_token, cal_event_type_id, cal_google_calendar_connected')
    .eq('id', expertId)
    .single();

  if (error || !expert) return notFound('Expert not found');

  if (!expert.cal_access_token) {
    return json({ error: 'Cal.com account not yet provisioned for this expert' }, 409);
  }

  // Mark Google Calendar as connected
  const updatePayload: Record<string, unknown> = {
    cal_google_calendar_connected: true,
  };

  // AC4: Auto-create "20-min Intro Call" event type if not already created
  if (!expert.cal_event_type_id) {
    try {
      const eventTypeId = await createIntroCallEventType(expert.cal_access_token);
      updatePayload.cal_event_type_id = eventTypeId;
    } catch (err) {
      console.error('[E06S04] Failed to create intro-call event type:', err);
      // Non-fatal: mark calendar as connected, event type creation can be retried
    }
  }

  const { error: updateError } = await supabase
    .from('experts')
    .update(updatePayload)
    .eq('id', expertId);

  if (updateError) {
    console.error('[E06S04] Failed to update expert cal state:', updateError);
    return json({ error: 'Failed to save Calendar connection state' }, 500);
  }

  return json({ connected: true, event_type_configured: !!updatePayload.cal_event_type_id });
}

/**
 * AC10: GET /api/experts/:id/cal/status
 * Returns the expert's Cal.com connection state.
 * Used by onboarding UI to show connection progress.
 */
export async function handleCalStatus(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const supabase = createServiceClient(env);
  const { data: expert, error } = await supabase
    .from('experts')
    .select('cal_username, cal_google_calendar_connected, cal_event_type_id')
    .eq('id', expertId)
    .single();

  if (error || !expert) return notFound('Expert not found');

  return json({
    connected: expert.cal_google_calendar_connected,
    cal_username: expert.cal_username,
    event_type_configured: expert.cal_event_type_id !== null,
  });
}
