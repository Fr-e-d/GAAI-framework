import { Env } from './types/env';
import { handleMatchCompute, handleMatchGet } from './routes/matches';
import { handleExtract } from './routes/extract';
import { authenticate } from './middleware/auth';
import { handleRegister } from './handlers/experts/register';
import { handleGetProfile, handlePatchProfile } from './handlers/experts/profile';
import { handleSatelliteConfig } from './routes/satellites';
import { handleProspectSubmit, handleProspectMatches, handleProspectIdentify } from './routes/prospects';
import { handleCors, addCorsHeaders, corsForbidden } from './lib/cors';

const QUEUES = ['email-notifications', 'lead-billing'] as const;

async function checkSupabase(env: Env): Promise<'connected' | 'error'> {
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/`, {
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
    });
    return res.ok ? 'connected' : 'error';
  } catch {
    return 'error';
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const { pathname, method } = { pathname: url.pathname, method: request.method };

    // ── Health ──────────────────────────────────────────────────────────────
    if (method === 'GET' && pathname === '/api/health') {
      const supabaseStatus = await checkSupabase(env);
      const body = { status: 'ok', supabase: supabaseStatus, queues: [...QUEUES] };
      const statusCode = supabaseStatus === 'connected' ? 200 : 503;
      return new Response(JSON.stringify(body), {
        status: statusCode,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // ── Matching ────────────────────────────────────────────────────────────
    // POST /api/matches/compute
    if (method === 'POST' && pathname === '/api/matches/compute') {
      return handleMatchCompute(request, env);
    }

    // GET /api/matches/:prospect_id
    const matchGetPattern = pathname.match(/^\/api\/matches\/([^/]+)$/);
    if (method === 'GET' && matchGetPattern && matchGetPattern[1]) {
      const prospectId = matchGetPattern[1];
      return handleMatchGet(request, env, prospectId);
    }

    // ── AI Extraction ────────────────────────────────────────────────────────
    // POST /api/extract
    if (method === 'POST' && pathname === '/api/extract') {
      return handleExtract(request, env);
    }

    // ── Satellite routes (AC9: CORS enforced) ───────────────────────────────
    if (pathname.startsWith('/api/satellites/')) {
      const corsResult = await handleCors(request, env);
      if (corsResult.preflight) return corsResult.preflight;
      if (!corsResult.allowed) return corsForbidden(corsResult.origin);

      // GET /api/satellites/:id/config
      const satConfigMatch = pathname.match(/^\/api\/satellites\/([^/]+)\/config$/);
      if (method === 'GET' && satConfigMatch && satConfigMatch[1]) {
        const response = await handleSatelliteConfig(request, env, satConfigMatch[1]);
        return addCorsHeaders(response, corsResult.origin);
      }

      return addCorsHeaders(
        new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
        corsResult.origin,
      );
    }

    // ── Prospect routes (AC9: CORS enforced) ────────────────────────────────
    if (pathname.startsWith('/api/prospects/')) {
      const corsResult = await handleCors(request, env);
      if (corsResult.preflight) return corsResult.preflight;
      if (!corsResult.allowed) return corsForbidden(corsResult.origin);

      // POST /api/prospects/submit
      if (method === 'POST' && pathname === '/api/prospects/submit') {
        const response = await handleProspectSubmit(request, env);
        return addCorsHeaders(response, corsResult.origin);
      }

      const prospectId = pathname.match(/^\/api\/prospects\/([^/]+)\//)?.[1];

      if (prospectId) {
        // GET /api/prospects/:id/matches?token=xxx
        if (method === 'GET' && pathname === `/api/prospects/${prospectId}/matches`) {
          const response = await handleProspectMatches(request, env, prospectId);
          return addCorsHeaders(response, corsResult.origin);
        }

        // POST /api/prospects/:id/identify
        if (method === 'POST' && pathname === `/api/prospects/${prospectId}/identify`) {
          const response = await handleProspectIdentify(request, env, prospectId);
          return addCorsHeaders(response, corsResult.origin);
        }
      }

      return addCorsHeaders(
        new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
        corsResult.origin,
      );
    }

    // ── Expert routes (authenticated) ───────────────────────────────────────
    if (pathname.startsWith('/api/experts/')) {
      const authResult = await authenticate(request, env);
      if (authResult.response) {
        return authResult.response;
      }
      const user = authResult.user;

      if (method === 'POST' && pathname === '/api/experts/register') {
        return handleRegister(request, env, user);
      }

      const profileMatch = pathname.match(/^\/api\/experts\/([^/]+)\/profile$/);
      if (profileMatch) {
        if (method === 'GET') {
          return handleGetProfile(request, env, user, profileMatch[1]!);
        }
        if (method === 'PATCH') {
          return handlePatchProfile(request, env, user, profileMatch[1]!);
        }
      }

      return new Response(JSON.stringify({ error: 'Not Found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  },

  // Queue consumer stub — E06S06 not yet implemented.
  // Acks all messages to prevent DLQ accumulation until real consumers are wired.
  async queue(batch: MessageBatch<unknown>, _env: Env): Promise<void> {
    batch.ackAll();
  },
} satisfies ExportedHandler<Env>;
