// Tests for E06S23: syncExpertPoolToD1 (AC4–AC7, AC12)
import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest';
import { syncExpertPoolToD1 } from './syncExpertPool';
import * as d1Module from '../lib/d1ExpertPool';
import type { Env } from '../types/env';

vi.mock('../lib/d1ExpertPool');
vi.mock('../lib/db', () => ({ createSql: vi.fn() }));

import { createSql } from '../lib/db';

// ── Helpers ───────────────────────────────────────────────────────────────────

const baseEnv = {
  HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  OPENAI_API_KEY: 'openai-key',
  SESSIONS: {} as KVNamespace,
  RATE_LIMITING: {} as KVNamespace,
  FEATURE_FLAGS: {} as KVNamespace,
  EXPERT_POOL: {} as KVNamespace,
  PROSPECT_TOKEN_SECRET: 'secret',
  EMAIL_NOTIFICATIONS: {} as Queue,
  LEAD_BILLING: {} as Queue,
  SCORE_COMPUTATION: {} as Queue,
  GOOGLE_CLIENT_ID: 'gcid',
  GOOGLE_CLIENT_SECRET: 'gcsecret',
  GCAL_TOKEN_ENCRYPTION_KEY: 'enc-key',
  WORKER_BASE_URL: 'https://test.workers.dev',
  RESEND_API_KEY: 'resend',
  LEMON_SQUEEZY_API_KEY: 'ls',
  N8N_WEBHOOK_URL: 'https://n8n.example.com',
  EMAIL_FROM_DOMAIN: 'send.callibrate.io',
  EMAIL_REPLY_TO: 'support@callibrate.io',
};

const mockEnvWithDb = { ...baseEnv, EXPERT_DB: {} as D1Database } as unknown as Env;
const mockEnvNoDb = { ...baseEnv } as unknown as Env;

// ── Test suite ────────────────────────────────────────────────────────────────

describe('syncExpertPoolToD1 — EXPERT_DB not available', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns early without any DB calls when EXPERT_DB is undefined', async () => {
    await syncExpertPoolToD1(mockEnvNoDb);

    expect(d1Module.getLastSyncAt).not.toHaveBeenCalled();
    expect(createSql).not.toHaveBeenCalled();
  });
});

describe('syncExpertPoolToD1 — Full load (AC7: no lastSyncAt)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads all experts when no prior sync exists', async () => {
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce(null);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.setLastSyncAt).mockResolvedValueOnce(undefined);

    const expertRows = [
      { id: 'e1', profile: { skills: ['Python'] }, preferences: {}, rate_min: 100, rate_max: 200, composite_score: 60 },
    ];
    const mockSql = vi.fn()
      .mockResolvedValueOnce(expertRows)                                       // full expert load
      .mockResolvedValueOnce([{ expert_id: 'e1', lead_count: '3' }]);          // lead counts
    (createSql as Mock).mockReturnValue(mockSql);

    await syncExpertPoolToD1(mockEnvWithDb);

    expect(d1Module.upsertToD1).toHaveBeenCalledOnce();
    const [, pool] = vi.mocked(d1Module.upsertToD1).mock.calls[0]!;
    expect(pool).toHaveLength(1);
    expect(pool[0]?.id).toBe('e1');
    expect(pool[0]?.total_leads).toBe(3);
    expect(d1Module.setLastSyncAt).toHaveBeenCalledOnce();
  });

  it('handles experts with no leads (total_leads = 0)', async () => {
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce(null);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.setLastSyncAt).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([{ id: 'e2', profile: null, preferences: null, rate_min: null, rate_max: null, composite_score: null }])
      .mockResolvedValueOnce([]); // no leads
    (createSql as Mock).mockReturnValue(mockSql);

    await syncExpertPoolToD1(mockEnvWithDb);

    const [, pool] = vi.mocked(d1Module.upsertToD1).mock.calls[0]!;
    expect(pool[0]?.total_leads).toBe(0);
  });
});

describe('syncExpertPoolToD1 — Incremental load (AC6)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('syncs only changed experts when lastSyncAt is set', async () => {
    const lastSync = '2026-02-23T10:00:00.000Z';
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce(lastSync);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.setLastSyncAt).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([{ id: 'e1', profile: null, preferences: null, rate_min: 50, rate_max: 100, composite_score: 30 }])
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    await syncExpertPoolToD1(mockEnvWithDb);

    expect(d1Module.upsertToD1).toHaveBeenCalledOnce();
    expect(d1Module.setLastSyncAt).toHaveBeenCalledOnce();
  });

  it('skips upsert but updates last_sync_at when no experts changed', async () => {
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce('2026-02-23T10:00:00.000Z');
    vi.mocked(d1Module.setLastSyncAt).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn().mockResolvedValueOnce([]); // incremental — no changes
    (createSql as Mock).mockReturnValue(mockSql);

    await syncExpertPoolToD1(mockEnvWithDb);

    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
    expect(d1Module.setLastSyncAt).toHaveBeenCalledOnce();
  });
});

describe('syncExpertPoolToD1 — Sync failure (AC12)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('does not throw when SQL query fails', async () => {
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce(null);
    const mockSql = vi.fn().mockRejectedValueOnce(new Error('Hyperdrive connection error'));
    (createSql as Mock).mockReturnValue(mockSql);

    // AC12: sync failure must not propagate
    await expect(syncExpertPoolToD1(mockEnvWithDb)).resolves.toBeUndefined();
    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
  });

  it('does not throw when upsertToD1 fails', async () => {
    vi.mocked(d1Module.getLastSyncAt).mockResolvedValueOnce(null);
    vi.mocked(d1Module.upsertToD1).mockRejectedValueOnce(new Error('D1 batch failed'));

    const mockSql = vi.fn()
      .mockResolvedValueOnce([{ id: 'e1', profile: null, preferences: null, rate_min: null, rate_max: null, composite_score: null }])
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    await expect(syncExpertPoolToD1(mockEnvWithDb)).resolves.toBeUndefined();
  });
});
