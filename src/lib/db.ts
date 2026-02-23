import postgres from 'postgres';
import type { Env } from '../types/env';

export function createSql(env: Env) {
  return postgres(env.HYPERDRIVE.connectionString, { prepare: true });
}

export type SqlClient = ReturnType<typeof createSql>;
