// AC1/AC2 (E08S04): Admin reindex uses ADMIN_API_KEY with HMAC-based timing-safe comparison.
// AC6 (E06S24): Admin reindex proxied to callibrate-matching via Service Binding.
// Auth is enforced here (Core); the Matching Worker executes the actual reindex.

import { Env } from '../../types/env';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

/**
 * Timing-safe string comparison via HMAC.
 * crypto.subtle.timingSafeEqual is not available in CF Workers as of 2026-02 (SEC-06).
 * AC2: If lengths differ → reject immediately (length is not secret).
 */
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  if (a.length !== b.length) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.generateKey(
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  ) as CryptoKey;
  const [hmacA, hmacB] = await Promise.all([
    crypto.subtle.sign('HMAC', key, enc.encode(a)),
    crypto.subtle.sign('HMAC', key, enc.encode(b)),
  ]);
  const aBytes = new Uint8Array(hmacA);
  const bBytes = new Uint8Array(hmacB);
  return aBytes.every((byte, i) => byte === bBytes[i]);
}

export async function handleVectorizeReindex(
  request: Request,
  env: Env,
  _ctx: ExecutionContext
): Promise<Response> {
  // AC1: Use dedicated ADMIN_API_KEY (not SUPABASE_SERVICE_KEY)
  const authHeader = request.headers.get('Authorization');
  const provided = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : '';

  // AC2: Timing-safe comparison via HMAC polyfill
  const authorized = await timingSafeEqual(provided, env.ADMIN_API_KEY);
  if (!authorized) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  if (!env.MATCHING_SERVICE) {
    return new Response(
      JSON.stringify({ error: 'Matching service not configured' }),
      { status: 503, headers: JSON_HEADERS }
    );
  }

  // Forward to Matching Worker — no auth header needed (internal Service Binding, AC4)
  return env.MATCHING_SERVICE.fetch(
    new Request('https://matching/admin/reindex', { method: 'POST' })
  );
}
