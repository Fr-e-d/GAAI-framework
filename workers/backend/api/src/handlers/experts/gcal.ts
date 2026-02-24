import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import { encryptToken, decryptToken, GcalDecryptionError } from '../../lib/gcalCrypto';
import type { ExpertRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: { 'Content-Type': 'application/json' },
  });
}

function notFound(): Response {
  return new Response(JSON.stringify({ error: 'Not Found' }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function redirect(url: string): Response {
  return new Response(null, {
    status: 302,
    headers: { Location: url },
  });
}

// ── PKCE + CSRF state helpers ──────────────────────────────────────────────────

function generateStateToken(): string {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
}

function base64urlEncode(buffer: ArrayBuffer | Uint8Array): string {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let str = '';
  for (const byte of bytes) {
    str += String.fromCharCode(byte);
  }
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function generateCodeVerifier(): string {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return base64urlEncode(arr);
}

async function generateCodeChallenge(codeVerifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(codeVerifier);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return base64urlEncode(digest);
}

// ── AC1: GET /api/experts/:id/gcal/auth-url ──────────────────────────────────

export async function handleGcalAuthUrl(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);
  const [data] = await sql<Pick<ExpertRow, 'id'>[]>`SELECT id FROM experts WHERE id = ${expertId}`;

  if (!data) return notFound();

  // AC1: Generate cryptographically random CSRF state token (32 bytes, hex-encoded = 64 chars)
  const stateToken = generateStateToken();

  // AC2: Generate PKCE code_verifier and code_challenge
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);

  // AC1 + AC3: Store state token in SESSIONS KV with TTL 600s; value includes expert_id and code_verifier
  await env.SESSIONS.put(
    `oauth-state:${stateToken}`,
    JSON.stringify({ expert_id: expertId, code_verifier: codeVerifier }),
    { expirationTtl: 600 }
  );

  // AC6: state param is the random token, NOT expertId
  // AC2: code_challenge and code_challenge_method=S256 included in auth URL
  const params = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: `${env.WORKER_BASE_URL}/api/gcal/callback`,
    response_type: 'code',
    scope: 'openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly',
    access_type: 'offline',
    prompt: 'consent',
    state: stateToken,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
  });

  const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
  return json({ auth_url: authUrl });
}

// ── AC2 + AC3: GET /api/gcal/callback ────────────────────────────────────────
// UNAUTHENTICATED — Google redirects here after user grants permission.

export async function handleGcalCallback(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');

  if (!state) return redirect('/onboarding/gcal-error?reason=invalid_state');
  if (!code) return redirect('/onboarding/gcal-error?reason=no_code');

  // AC4: Look up state token in SESSIONS KV
  const kvValue = await env.SESSIONS.get(`oauth-state:${state}`);
  if (!kvValue) return redirect('/onboarding/gcal-error?reason=invalid_state');

  // AC4: Delete immediately (one-time use)
  await env.SESSIONS.delete(`oauth-state:${state}`);

  const { expert_id: expertId, code_verifier: codeVerifier } = JSON.parse(kvValue) as { expert_id: string; code_verifier: string };

  const sql = createSql(env);
  const [expert] = await sql<Pick<ExpertRow, 'id'>[]>`SELECT id FROM experts WHERE id = ${expertId}`;

  if (!expert) {
    return redirect('/onboarding/gcal-error?reason=expert_not_found');
  }

  // AC5: Exchange code for tokens — includes code_verifier for PKCE
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: `${env.WORKER_BASE_URL}/api/gcal/callback`,
      grant_type: 'authorization_code',
      code_verifier: codeVerifier,
    }).toString(),
  });

  if (!tokenResponse.ok) {
    return redirect('/onboarding/gcal-error?reason=token_exchange_failed');
  }

  const tokens = await tokenResponse.json() as {
    access_token: string;
    refresh_token?: string | null;
    expires_in?: number;
  };

  const { access_token, refresh_token, expires_in } = tokens;

  const encryptedAccessToken = await encryptToken(access_token, env.GCAL_TOKEN_ENCRYPTION_KEY);
  const expiryAt = expires_in ? new Date(Date.now() + expires_in * 1000).toISOString() : null;

  // AC3: Only encrypt+store refresh token if present and non-null
  let encryptedRefreshToken: string | undefined;
  if (refresh_token) {
    encryptedRefreshToken = await encryptToken(refresh_token, env.GCAL_TOKEN_ENCRYPTION_KEY);
  }

  // Fetch Google account email (non-blocking)
  let gcalEmail: string | null = null;
  try {
    const userinfoResponse = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${access_token}` },
    });
    if (userinfoResponse.ok) {
      const userinfo = await userinfoResponse.json() as { email?: string };
      gcalEmail = userinfo.email ?? null;
    }
  } catch {
    // Non-blocking — proceed without email
  }

  const now = new Date().toISOString();

  // Build update SQL conditionally (AC3: do NOT include gcal_refresh_token if not present)
  // AC4: gcal_connected = true only when a refresh token is present
  try {
    if (encryptedRefreshToken !== undefined && gcalEmail !== null) {
      await sql`UPDATE experts SET gcal_access_token = ${encryptedAccessToken}, gcal_token_expiry_at = ${expiryAt}, gcal_connected = ${encryptedRefreshToken !== undefined}, gcal_connected_at = ${now}, gcal_refresh_token = ${encryptedRefreshToken}, gcal_email = ${gcalEmail} WHERE id = ${expertId}`;
    } else if (encryptedRefreshToken !== undefined) {
      await sql`UPDATE experts SET gcal_access_token = ${encryptedAccessToken}, gcal_token_expiry_at = ${expiryAt}, gcal_connected = ${encryptedRefreshToken !== undefined}, gcal_connected_at = ${now}, gcal_refresh_token = ${encryptedRefreshToken} WHERE id = ${expertId}`;
    } else if (gcalEmail !== null) {
      await sql`UPDATE experts SET gcal_access_token = ${encryptedAccessToken}, gcal_token_expiry_at = ${expiryAt}, gcal_connected = false, gcal_connected_at = ${now}, gcal_email = ${gcalEmail} WHERE id = ${expertId}`;
    } else {
      await sql`UPDATE experts SET gcal_access_token = ${encryptedAccessToken}, gcal_token_expiry_at = ${expiryAt}, gcal_connected = false, gcal_connected_at = ${now} WHERE id = ${expertId}`;
    }
  } catch {
    return redirect('/onboarding/gcal-error?reason=db_error');
  }

  if (encryptedRefreshToken !== undefined) {
    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `expert:${expertId}`,
      event: 'expert.gcal_connected',
      properties: { expert_id: expertId },
    }));
  }

  return redirect('/onboarding/gcal-connected');
}

// ── AC4: GET /api/experts/:id/gcal/status ────────────────────────────────────

export async function handleGcalStatus(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);
  // AC4: connected: true only if non-null refresh token exists — select gcal_refresh_token to derive it
  const [data] = await sql<Pick<ExpertRow, 'gcal_refresh_token' | 'gcal_email' | 'gcal_connected_at'>[]>`
    SELECT gcal_refresh_token, gcal_email, gcal_connected_at FROM experts WHERE id = ${expertId}`;

  if (!data) return notFound();

  return json({
    connected: data.gcal_refresh_token != null,
    google_email: data.gcal_email ?? null,
    connected_at: data.gcal_connected_at ?? null,
  });
}

// ── AC7: DELETE /api/experts/:id/gcal/disconnect ─────────────────────────────

export async function handleGcalDisconnect(
  _request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  if (user.id !== expertId) return forbidden();

  const sql = createSql(env);
  const [data] = await sql<Pick<ExpertRow, 'gcal_refresh_token'>[]>`
    SELECT gcal_refresh_token FROM experts WHERE id = ${expertId}`;

  if (!data) return notFound();

  // Attempt Google token revocation (non-blocking)
  if (data.gcal_refresh_token) {
    try {
      const decryptedToken = await decryptToken(data.gcal_refresh_token, env.GCAL_TOKEN_ENCRYPTION_KEY);
      await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(decryptedToken)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      });
      // Ignore revocation response — proceed to DB cleanup regardless
    } catch (e) {
      if (!(e instanceof GcalDecryptionError)) {
        // Unexpected error — log but proceed
      }
    }
  }

  try {
    await sql`UPDATE experts SET gcal_connected = false, gcal_access_token = null, gcal_refresh_token = null, gcal_token_expiry_at = null, gcal_email = null, gcal_connected_at = null WHERE id = ${expertId}`;
  } catch {
    return json({ error: 'Internal Server Error' }, 500);
  }

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expertId}`,
    event: 'expert.gcal_disconnected',
    properties: { expert_id: expertId },
  }));

  return json({ disconnected: true });
}
