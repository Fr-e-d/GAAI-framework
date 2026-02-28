// E06S43: Agent API key authentication middleware

import type { Env } from '../types/env';
import { hashApiKey } from '../lib/agentKey';
import { createSql } from '../lib/db';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function agentUnauthorized(error: string): Response {
  return new Response(JSON.stringify({ error }), { status: 401, headers: JSON_HEADERS });
}

export type AgentAuthResult =
  | { prospect_id: string; key_id: string; key_hash: string; response?: never }
  | { prospect_id?: never; key_id?: never; key_hash?: never; response: Response };

/**
 * Authenticate an agent request via API key.
 * Expects: Authorization: Bearer {64-hex-char-api-key}
 */
export async function agentAuth(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<AgentAuthResult> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { response: agentUnauthorized('missing_api_key') };
  }

  const rawKey = authHeader.slice(7);
  if (!/^[0-9a-f]{64}$/.test(rawKey)) {
    return { response: agentUnauthorized('invalid_api_key') };
  }

  const keyHash = await hashApiKey(rawKey);
  const sql = createSql(env);

  try {
    const rows = await sql<{ id: string; prospect_id: string; revoked_at: string | null }[]>`
      SELECT id, prospect_id, revoked_at
      FROM prospect_api_keys
      WHERE key_hash = ${keyHash}
      LIMIT 1
    `;

    if (rows.length === 0) {
      return { response: agentUnauthorized('invalid_api_key') };
    }

    const row = rows[0]!;
    if (row.revoked_at !== null) {
      return { response: agentUnauthorized('api_key_revoked') };
    }

    // Update last_used_at asynchronously — do not block the response
    ctx.waitUntil(
      sql`UPDATE prospect_api_keys SET last_used_at = now() WHERE id = ${row.id}`.then(() => sql.end()),
    );

    return { prospect_id: row.prospect_id, key_id: row.id, key_hash: keyHash };
  } catch (err) {
    await sql.end().catch(() => {});
    throw err;
  }
}
