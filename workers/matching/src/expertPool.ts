// Expert pool read chain (ported from core src/lib/expertPool.ts)
// Cache API L1 (60s TTL) → D1 → Hyperdrive fallback

import { createSql } from './db';
import { getCachedPool, writeCachePool, loadFromD1, upsertToD1 } from './d1ExpertPool';
import type { MatchingEnv } from './env';
import type { ExpertPoolEntry } from './types';

export type { ExpertPoolEntry };

export async function loadExpertPool(env: MatchingEnv): Promise<ExpertPoolEntry[]> {
  // 1. Cache API L1 (60s TTL, per-datacenter)
  const fromCache = await getCachedPool();
  if (fromCache !== null && fromCache.length > 0) {
    return fromCache;
  }

  // 2. D1 edge (optional binding)
  if (env.EXPERT_DB) {
    try {
      const fromD1 = await loadFromD1(env.EXPERT_DB);
      if (fromD1.length > 0) {
        await writeCachePool(fromD1);
        return fromD1;
      }
    } catch {
      // D1 failure — fall through to Hyperdrive
    }
  }

  // 3. Hyperdrive fallback
  return loadFromHyperdrive(env);
}

async function loadFromHyperdrive(env: MatchingEnv): Promise<ExpertPoolEntry[]> {
  const sql = createSql(env);

  const expertRows = await sql<
    Pick<ExpertPoolEntry, 'id' | 'profile' | 'preferences' | 'rate_min' | 'rate_max' | 'composite_score'>[]
  >`SELECT id, profile, preferences, rate_min, rate_max, composite_score
    FROM experts WHERE availability != 'unavailable'`;

  if (expertRows.length === 0) return [];

  const expertIds = expertRows.map((e) => e.id);
  const leadRows = await sql<{ expert_id: string }[]>`
    SELECT expert_id FROM leads WHERE expert_id = ANY(${expertIds})`;

  const leadCountMap = new Map<string, number>();
  for (const row of leadRows) {
    if (row.expert_id) {
      leadCountMap.set(row.expert_id, (leadCountMap.get(row.expert_id) ?? 0) + 1);
    }
  }

  const pool: ExpertPoolEntry[] = expertRows.map((e) => ({
    id: e.id,
    profile: e.profile,
    preferences: e.preferences,
    rate_min: e.rate_min,
    rate_max: e.rate_max,
    composite_score: e.composite_score,
    total_leads: leadCountMap.get(e.id) ?? 0,
  }));

  await writeCachePool(pool);
  if (env.EXPERT_DB) {
    try {
      await upsertToD1(env.EXPERT_DB, pool);
    } catch {
      // D1 write failure is non-blocking
    }
  }

  return pool;
}
