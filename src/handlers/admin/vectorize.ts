// AC6 (E06S24): Admin reindex proxied to callibrate-matching via Service Binding.
// Auth is enforced here (Core); the Matching Worker executes the actual reindex.

import { Env } from '../../types/env';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export async function handleVectorizeReindex(
  request: Request,
  env: Env,
  _ctx: ExecutionContext
): Promise<Response> {
  // Service-key auth
  const authHeader = request.headers.get('Authorization');
  if (authHeader !== `Bearer ${env.SUPABASE_SERVICE_KEY}`) {
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
