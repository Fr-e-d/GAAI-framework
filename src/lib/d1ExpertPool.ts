// D1 + Cache API L1 helpers for expert pool (E06S23)
// Handles: Cache API L1 (60s TTL, per-datacenter) + D1 read/write + sync_meta

import type { Json } from '../types/database';
import type { ExpertPoolEntry } from './expertPool';

// ── Constants ─────────────────────────────────────────────────────────────────

// AC9: synthetic cache URL — Cache API works on custom domains (api.callibrate.io / staging custom domain)
const CACHE_KEY_URL = 'https://cache.internal/expert-pool';
const CACHE_TTL_SECONDS = 60; // AC9
const SYNC_META_KEY = 'last_sync_at'; // AC3

// ── D1 row type ───────────────────────────────────────────────────────────────

interface D1ExpertRow {
  id: string;
  profile: string;      // JSON string
  preferences: string;  // JSON string
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number;
}

// ── Cache API L1 ──────────────────────────────────────────────────────────────

// AC8/AC9: try Cache API — returns null on any failure (workers.dev, cold start)
export async function getCachedPool(): Promise<ExpertPoolEntry[] | null> {
  try {
    const cache = caches.default;
    const cached = await cache.match(new Request(CACHE_KEY_URL));
    if (!cached) return null;
    const data = await cached.json() as unknown;
    if (Array.isArray(data)) return data as ExpertPoolEntry[];
    return null;
  } catch {
    // Cache API unavailable (workers.dev domain) — not a failure, D1 handles it
    return null;
  }
}

// AC9/AC10: write pool to Cache API with 60s TTL — non-blocking on failure
export async function writeCachePool(pool: ExpertPoolEntry[]): Promise<void> {
  try {
    const cache = caches.default;
    const response = new Response(JSON.stringify(pool), {
      headers: { 'Cache-Control': `max-age=${CACHE_TTL_SECONDS}` },
    });
    await cache.put(new Request(CACHE_KEY_URL), response);
  } catch {
    // Cache write failure is non-blocking — D1 serves as reliable fallback
  }
}

// ── D1 read ───────────────────────────────────────────────────────────────────

// AC8: load all expert pool entries from D1
export async function loadFromD1(db: D1Database): Promise<ExpertPoolEntry[]> {
  const { results } = await db
    .prepare('SELECT id, profile, preferences, rate_min, rate_max, composite_score, total_leads FROM expert_pool')
    .all<D1ExpertRow>();
  return (results ?? []).map(rowToEntry);
}

// ── D1 write ─────────────────────────────────────────────────────────────────

// AC5/AC6/AC7: upsert expert pool entries into D1 (INSERT OR REPLACE)
export async function upsertToD1(db: D1Database, experts: ExpertPoolEntry[]): Promise<void> {
  if (experts.length === 0) return;

  const now = new Date().toISOString();

  // Batch all upserts in a single D1 batch call
  const stmts = experts.map((e) =>
    db
      .prepare(
        `INSERT INTO expert_pool (id, profile, preferences, rate_min, rate_max, composite_score, total_leads, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         ON CONFLICT (id) DO UPDATE SET
           profile = excluded.profile,
           preferences = excluded.preferences,
           rate_min = excluded.rate_min,
           rate_max = excluded.rate_max,
           composite_score = excluded.composite_score,
           total_leads = excluded.total_leads,
           updated_at = excluded.updated_at`,
      )
      .bind(
        e.id,
        JSON.stringify(e.profile ?? {}),
        JSON.stringify(e.preferences ?? {}),
        e.rate_min,
        e.rate_max,
        e.composite_score,
        e.total_leads,
        now,
      ),
  );

  await db.batch(stmts);
}

// ── Sync metadata ─────────────────────────────────────────────────────────────

// AC3/AC6: get last_sync_at — returns null if not set or on D1 error
export async function getLastSyncAt(db: D1Database): Promise<string | null> {
  try {
    const row = await db
      .prepare('SELECT value FROM _sync_meta WHERE key = ?1')
      .bind(SYNC_META_KEY)
      .first<{ value: string }>();
    return row?.value ?? null;
  } catch {
    // D1 error — treat as no prior sync (full load)
    return null;
  }
}

// AC3: set last_sync_at after successful sync
export async function setLastSyncAt(db: D1Database, ts: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO _sync_meta (key, value)
       VALUES (?1, ?2)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value`,
    )
    .bind(SYNC_META_KEY, ts)
    .run();
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function rowToEntry(row: D1ExpertRow): ExpertPoolEntry {
  let profile: Json | null = null;
  let preferences: Json | null = null;
  try {
    profile = JSON.parse(row.profile) as Json;
  } catch {
    /* keep null */
  }
  try {
    preferences = JSON.parse(row.preferences) as Json;
  } catch {
    /* keep null */
  }
  return {
    id: row.id,
    profile,
    preferences,
    rate_min: row.rate_min,
    rate_max: row.rate_max,
    composite_score: row.composite_score,
    total_leads: row.total_leads,
  };
}
