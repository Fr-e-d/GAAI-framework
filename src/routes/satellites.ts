// ── GET /api/satellites/:id/config ────────────────────────────────────────────
// AC1: returns { id, label, domain, vertical, quiz_schema, matching_weights }
// AC1: 404 if satellite not found
// AC10: consistent error shape { error: string, details?: object }

import { createSql } from '../lib/db';
import type { Env } from '../types/env';
import type { SatelliteConfigRow } from '../types/db';

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
  const sql = createSql(env);

  const [data] = await sql<Pick<SatelliteConfigRow, 'id' | 'label' | 'domain' | 'vertical' | 'quiz_schema' | 'matching_weights'>[]>`
    SELECT id, label, domain, vertical, quiz_schema, matching_weights
    FROM satellite_configs WHERE id = ${satelliteId}`;

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
