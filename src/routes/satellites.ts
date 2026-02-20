// ── GET /api/satellites/:id/config ────────────────────────────────────────────
// AC1: returns { id, label, domain, vertical, quiz_schema, matching_weights }
// AC1: 404 if satellite not found
// AC10: consistent error shape { error: string, details?: object }

import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';
import type { Env } from '../types/env';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

export async function handleSatelliteConfig(
  _request: Request,
  env: Env,
  satelliteId: string,
): Promise<Response> {
  const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase
    .from('satellite_configs')
    .select('id, label, domain, vertical, quiz_schema, matching_weights')
    .eq('id', satelliteId)
    .maybeSingle();

  if (error) return errorResponse('Database error', 500);
  if (!data) return errorResponse('Satellite not found', 404);

  return jsonResponse({
    id: data.id,
    label: data.label,
    domain: data.domain,
    vertical: data.vertical,
    quiz_schema: data.quiz_schema,
    matching_weights: data.matching_weights,
  });
}
