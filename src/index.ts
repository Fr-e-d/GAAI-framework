import { Env } from './types/env';
import { handleMatchCompute, handleMatchGet } from './routes/matches';
import { handleExtract } from './routes/extract';
import { authenticate } from './middleware/auth';
import { handleRegister } from './handlers/experts/register';
import { handleGetProfile, handlePatchProfile } from './handlers/experts/profile';
import { handleCalAuthUrl, handleCalCallback, handleCalStatus } from './handlers/experts/cal';
import { handleCalWebhook } from './handlers/webhooks/cal';

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

    // ── Cal.com webhooks (unauthenticated — signature validated inside handler)
    if (method === 'POST' && pathname === '/webhooks/cal') {
      return handleCalWebhook(request, env);
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

      // ── Cal.com expert sub-routes ─────────────────────────────────────────
      const calAuthUrlMatch = pathname.match(/^\/api\/experts\/([^/]+)\/cal\/auth-url$/);
      if (method === 'GET' && calAuthUrlMatch && calAuthUrlMatch[1]) {
        return handleCalAuthUrl(request, env, user, calAuthUrlMatch[1]);
      }

      const calCallbackMatch = pathname.match(/^\/api\/experts\/([^/]+)\/cal\/callback$/);
      if (method === 'GET' && calCallbackMatch && calCallbackMatch[1]) {
        return handleCalCallback(request, env, user, calCallbackMatch[1]);
      }

      const calStatusMatch = pathname.match(/^\/api\/experts\/([^/]+)\/cal\/status$/);
      if (method === 'GET' && calStatusMatch && calStatusMatch[1]) {
        return handleCalStatus(request, env, user, calStatusMatch[1]);
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
} satisfies ExportedHandler<Env>;
