// ── CORS validation for satellite funnel routes ────────────────────────────────
// AC9: allow *.callibrate.io + app.callibrate.io + any satellite_configs.domain
// All other origins → 403. No Origin header → allowed (server-to-server calls).

import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';
import type { Env } from '../types/env';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

const CORS_METHODS = 'GET, POST, OPTIONS';
const CORS_HEADERS_ALLOWED = 'Content-Type, Authorization';
const CORS_MAX_AGE = '86400';

export function corsHeaders(origin: string): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': CORS_METHODS,
    'Access-Control-Allow-Headers': CORS_HEADERS_ALLOWED,
    'Access-Control-Max-Age': CORS_MAX_AGE,
  };
}

// Adds CORS headers to an existing Response when origin is known.
export function addCorsHeaders(response: Response, origin: string | null): Response {
  if (!origin) return response;
  const headers = new Headers(response.headers);
  Object.entries(corsHeaders(origin)).forEach(([k, v]) => headers.set(k, v));
  return new Response(response.body, { status: response.status, headers });
}

// Validates whether the given origin is in the allowlist.
// On DB failure, defaults to deny (safe default).
async function validateOrigin(origin: string, env: Env): Promise<boolean> {
  // Parse the origin to get just the host (strip protocol)
  let originUrl: URL;
  try {
    originUrl = new URL(origin);
  } catch {
    return false;
  }
  const host = originUrl.hostname.toLowerCase();

  // *.callibrate.io (covers app.callibrate.io, any-satellite.callibrate.io, etc.)
  if (host === 'callibrate.io' || host.endsWith('.callibrate.io')) {
    return true;
  }

  // Check satellite_configs.domain
  try {
    const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
      auth: { persistSession: false },
    });
    const { data } = await supabase
      .from('satellite_configs')
      .select('domain')
      .eq('domain', host)
      .maybeSingle();
    return data !== null;
  } catch {
    return false; // deny on DB error — safe default
  }
}

export interface CorsResult {
  allowed: boolean;
  origin: string | null;
  preflight: Response | null;
}

// Main CORS handler — call before processing any satellite/prospect route.
// Returns:
//   { allowed: true,  origin: null,      preflight: null }  — no Origin header (allow)
//   { allowed: true,  origin: "https://…", preflight: null }  — valid origin, proceed
//   { allowed: true,  origin: "https://…", preflight: Response } — valid OPTIONS preflight
//   { allowed: false, origin: "https://…", preflight: null }  — blocked origin
export async function handleCors(request: Request, env: Env): Promise<CorsResult> {
  const origin = request.headers.get('Origin');

  if (!origin) {
    // No Origin header — direct server-to-server call, allow without CORS headers
    return { allowed: true, origin: null, preflight: null };
  }

  const isAllowed = await validateOrigin(origin, env);

  if (!isAllowed) {
    return { allowed: false, origin, preflight: null };
  }

  // Valid origin — handle OPTIONS preflight
  if (request.method === 'OPTIONS') {
    const preflight = new Response(null, {
      status: 204,
      headers: corsHeaders(origin),
    });
    return { allowed: true, origin, preflight };
  }

  return { allowed: true, origin, preflight: null };
}

// Convenience: build a 403 forbidden response for blocked origins.
// Pass the blocked origin so the browser can read the response body (useful
// for satellite developers debugging a missing satellite_configs.domain entry).
export function corsForbidden(origin?: string | null): Response {
  const headers: Record<string, string> = { ...JSON_HEADERS };
  if (origin) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers,
  });
}
