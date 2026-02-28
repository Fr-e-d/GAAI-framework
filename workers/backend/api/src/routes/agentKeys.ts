// E06S43: API key management routes for prospects
// POST /api/prospects/:id/agent-keys — create a new API key (max 3 active per prospect)
// DELETE /api/prospects/:id/agent-keys/:keyId — revoke an API key

import type { Env } from '../types/env';
import { verifyProspectSessionToken } from '../lib/jwt';
import { generateApiKey } from '../lib/agentKey';
import { createSql } from '../lib/db';
import { captureEvent } from '../lib/posthog';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

/**
 * POST /api/prospects/:id/agent-keys
 * Create a new API key for the authenticated prospect.
 * Requires: Authorization: Bearer {prospect_session_token} or Cookie: prospect_session=...
 * Body: { name: string }
 * Returns: { id, name, key, created_at } — key is shown only once
 */
export async function handleCreateAgentKey(
  request: Request,
  env: Env,
  prospectId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  // Authenticate via session token (cookie or Authorization header)
  const sessionToken = getSessionToken(request);
  if (!sessionToken) {
    return errorResponse('unauthorized', 401);
  }

  const claims = await verifyProspectSessionToken(sessionToken, env.PROSPECT_TOKEN_SECRET);
  if (!claims || claims.prospect_id !== prospectId) {
    return errorResponse('unauthorized', 401);
  }

  // Parse body
  let body: { name?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  if (typeof body.name !== 'string' || !body.name.trim()) {
    return errorResponse('Validation failed', 422, { name: 'required, non-empty string' });
  }

  if (body.name.length > 64) {
    return errorResponse('Validation failed', 422, { name: 'max 64 characters' });
  }

  const keyName = body.name.trim();
  const sql = createSql(env);

  try {
    // Check active key count
    const countRows = await sql<{ count: number }[]>`
      SELECT COUNT(*)::int AS count
      FROM prospect_api_keys
      WHERE prospect_id = ${prospectId} AND revoked_at IS NULL
    `;

    const activeCount = countRows[0]?.count ?? 0;
    if (activeCount >= 3) {
      return errorResponse('max_keys_reached', 422, {
        message: 'Maximum 3 active API keys per account. Revoke an existing key first.',
      });
    }

    // Generate new key
    const { key, hash } = await generateApiKey();

    // Insert into DB
    const insertRows = await sql<{ id: string; created_at: string }[]>`
      INSERT INTO prospect_api_keys (prospect_id, key_hash, name)
      VALUES (${prospectId}, ${hash}, ${keyName})
      RETURNING id, created_at
    `;

    const inserted = insertRows[0];
    if (!inserted) {
      return errorResponse('internal_error', 500);
    }

    // Analytics (fire-and-forget)
    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: prospectId,
      event: 'agent.api_key_created',
      properties: {
        key_id: inserted.id,
        key_name: keyName,
      },
    }));

    return jsonResponse({
      id: inserted.id,
      name: keyName,
      key,  // shown ONCE — client must store this
      created_at: inserted.created_at,
    }, 201);
  } finally {
    await sql.end().catch(() => {});
  }
}

/**
 * DELETE /api/prospects/:id/agent-keys/:keyId
 * Revoke an API key belonging to the authenticated prospect.
 */
export async function handleRevokeAgentKey(
  request: Request,
  env: Env,
  prospectId: string,
  keyId: string,
): Promise<Response> {
  // Authenticate via session token
  const sessionToken = getSessionToken(request);
  if (!sessionToken) {
    return errorResponse('unauthorized', 401);
  }

  const claims = await verifyProspectSessionToken(sessionToken, env.PROSPECT_TOKEN_SECRET);
  if (!claims || claims.prospect_id !== prospectId) {
    return errorResponse('unauthorized', 401);
  }

  const sql = createSql(env);

  try {
    const updateRows = await sql<{ id: string }[]>`
      UPDATE prospect_api_keys
      SET revoked_at = now()
      WHERE id = ${keyId}
        AND prospect_id = ${prospectId}
        AND revoked_at IS NULL
      RETURNING id
    `;

    if (updateRows.length === 0) {
      return errorResponse('not_found', 404);
    }

    return jsonResponse({ success: true });
  } finally {
    await sql.end().catch(() => {});
  }
}

/**
 * GET /api/prospects/:id/agent-keys
 * List API keys for the authenticated prospect (key_hash not returned).
 */
export async function handleListAgentKeys(
  request: Request,
  env: Env,
  prospectId: string,
): Promise<Response> {
  const sessionToken = getSessionToken(request);
  if (!sessionToken) {
    return errorResponse('unauthorized', 401);
  }

  const claims = await verifyProspectSessionToken(sessionToken, env.PROSPECT_TOKEN_SECRET);
  if (!claims || claims.prospect_id !== prospectId) {
    return errorResponse('unauthorized', 401);
  }

  const sql = createSql(env);

  try {
    const rows = await sql<{ id: string; name: string; created_at: string; last_used_at: string | null; revoked_at: string | null }[]>`
      SELECT id, name, created_at, last_used_at, revoked_at
      FROM prospect_api_keys
      WHERE prospect_id = ${prospectId}
      ORDER BY created_at DESC
    `;

    return jsonResponse({ keys: rows });
  } finally {
    await sql.end().catch(() => {});
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function getSessionToken(request: Request): string | null {
  // Check Authorization header first
  const authHeader = request.headers.get('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.slice(7);
  }

  // Fall back to Cookie
  const cookieHeader = request.headers.get('Cookie') ?? '';
  const match = cookieHeader.match(/(?:^|;\s*)prospect_session=([^;]+)/);
  return match?.[1] ?? null;
}
