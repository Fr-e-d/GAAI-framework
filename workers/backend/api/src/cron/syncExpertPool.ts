// Expert pool sync: Supabase (via Hyperdrive) → D1 (E06S23)
// AC4: triggered by cron */5 * * * * via handleScheduled
// AC5: reads from Supabase via Hyperdrive (postgres.js)
// AC6: incremental — WHERE updated_at > last_sync_at
// AC7: first sync = full load (no last_sync_at)
// AC12: sync failure is non-fatal — read path falls back to Hyperdrive

import { createSql } from '../lib/db';
import { upsertToD1, getLastSyncAt, setLastSyncAt } from '../lib/d1ExpertPool';
import type { Env } from '../types/env';
import type { ExpertRow } from '../types/db';

export async function syncExpertPoolToD1(env: Env): Promise<void> {
  // AC13: dispatched from scheduled() handler in cron.ts
  if (!env.EXPERT_DB) {
    console.warn('syncExpertPoolToD1: EXPERT_DB binding not available — skipping sync');
    return;
  }

  // AC3: read last sync timestamp (returns null on first run or D1 error)
  const lastSyncAt = await getLastSyncAt(env.EXPERT_DB);
  const syncStartedAt = new Date().toISOString();
  const sql = createSql(env);

  try {
    let expertRows: Pick<
      ExpertRow,
      'id' | 'profile' | 'preferences' | 'rate_min' | 'rate_max' | 'composite_score'
    >[];

    if (lastSyncAt === null) {
      // AC7: first sync — load all available experts
      expertRows = await sql<typeof expertRows>`
        SELECT id, profile, preferences, rate_min, rate_max, composite_score
        FROM experts WHERE availability != 'unavailable'`;
    } else {
      // AC6: incremental — only experts updated since last sync
      expertRows = await sql<typeof expertRows>`
        SELECT id, profile, preferences, rate_min, rate_max, composite_score
        FROM experts WHERE availability != 'unavailable' AND updated_at > ${lastSyncAt}`;
    }

    if (expertRows.length === 0) {
      // AC6: nothing changed — still update last_sync_at
      await setLastSyncAt(env.EXPERT_DB, syncStartedAt);
      console.log(`syncExpertPoolToD1: no changes since ${lastSyncAt ?? 'epoch'}`);
      return;
    }

    // AC6: aggregate lead counts during sync (avoids per-request count queries)
    const expertIds = expertRows.map((e) => e.id);
    const leadRows = await sql<{ expert_id: string; lead_count: string }[]>`
      SELECT expert_id, COUNT(*)::text AS lead_count
      FROM leads WHERE expert_id = ANY(${expertIds})
      GROUP BY expert_id`;

    const leadCountMap = new Map<string, number>();
    for (const row of leadRows) {
      leadCountMap.set(row.expert_id, parseInt(row.lead_count, 10));
    }

    const pool = expertRows.map((e) => ({
      id: e.id,
      profile: e.profile,
      preferences: e.preferences,
      rate_min: e.rate_min,
      rate_max: e.rate_max,
      composite_score: e.composite_score,
      total_leads: leadCountMap.get(e.id) ?? 0,
    }));

    // AC5: upsert to D1 via batched writes
    await upsertToD1(env.EXPERT_DB, pool);
    await setLastSyncAt(env.EXPERT_DB, syncStartedAt);

    console.log(
      `syncExpertPoolToD1: synced ${pool.length} experts (incremental=${lastSyncAt !== null})`,
    );
  } catch (err) {
    // AC12: sync failure is non-fatal — read path falls back to Hyperdrive automatically
    console.error('syncExpertPoolToD1 error:', err);
  }
}
