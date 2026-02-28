import postgres from 'postgres';
import type { Env } from '../types/env';

// max: 1 — one connection per Worker isolate, prevents Hyperdrive pool exhaustion
// across concurrent invocations. Handlers SHOULD call sql.end() in a finally block,
// but cleanupPendingSql() provides a safety net at the router level.
// prepare: false — required for Supabase PgBouncer pooler (port 6543, transaction mode).
// PgBouncer transaction mode does not support named prepared statements.

let _pendingCleanup: (() => Promise<void>)[] = [];

export function createSql(env: Env) {
  const sql = postgres(env.HYPERDRIVE.connectionString, { max: 1, prepare: false, connect_timeout: 10, idle_timeout: 5 });
  _pendingCleanup.push(() => sql.end());
  return sql;
}

/** Call in the fetch handler's finally block to close all SQL connections created during the request. */
export function cleanupPendingSql(ctx: ExecutionContext) {
  const fns = _pendingCleanup;
  _pendingCleanup = [];
  for (const fn of fns) {
    ctx.waitUntil(fn().catch(() => {}));
  }
}

export type SqlClient = ReturnType<typeof createSql>;
