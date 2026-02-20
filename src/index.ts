import { Env } from './types/env';
import { handleMatchCompute, handleMatchGet } from './routes/matches';

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

    return new Response('Not Found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;
