import postgres from 'postgres';
import type { MatchingEnv } from './env';

export function createSql(env: MatchingEnv) {
  return postgres(env.HYPERDRIVE.connectionString, { prepare: true });
}

export type SqlClient = ReturnType<typeof createSql>;
