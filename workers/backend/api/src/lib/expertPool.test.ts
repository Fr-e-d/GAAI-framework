// Tests for E06S23: three-tier read chain (Cache API L1 → D1 → Hyperdrive fallback)
import { describe, it, expect, vi, beforeEach, type Mock } from 'vitest';
import { loadExpertPool, type ExpertPoolEntry } from './expertPool';
import * as d1Module from './d1ExpertPool';
import type { Env } from '../types/env';

vi.mock('./d1ExpertPool');
vi.mock('./db', () => ({ createSql: vi.fn() }));

import { createSql } from './db';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const expert1: ExpertPoolEntry = {
  id: 'expert-uuid-001',
  profile: { skills: ['Python', 'n8n'], bio: 'AI automation expert' },
  preferences: { min_budget: 5000 },
  rate_min: 100,
  rate_max: 200,
  composite_score: 75,
  total_leads: 3,
};

const expert2: ExpertPoolEntry = {
  id: 'expert-uuid-002',
  profile: null,
  preferences: null,
  rate_min: null,
  rate_max: null,
  composite_score: null,
  total_leads: 0,
};

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

describe('loadExpertPool — Cache API L1 hit (AC8/AC9)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns cached pool without querying D1 or Hyperdrive', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce([expert1]);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toEqual([expert1]);
    expect(d1Module.loadFromD1).not.toHaveBeenCalled();
    expect(createSql).not.toHaveBeenCalled();
  });

  it('does not fall through when cache returns non-empty array', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce([expert1, expert2]);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toHaveLength(2);
    expect(d1Module.loadFromD1).not.toHaveBeenCalled();
  });
});

describe('loadExpertPool — Cache miss + D1 hit (AC8/AC10)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns D1 pool and writes back to Cache API', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValueOnce([expert1]);
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toEqual([expert1]);
    // AC10: write-back on D1 hit
    expect(d1Module.writeCachePool).toHaveBeenCalledWith([expert1]);
    expect(createSql).not.toHaveBeenCalled();
  });

  it('falls through to Hyperdrive when D1 returns empty (not yet synced)', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValueOnce([]);
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([expert2])  // expert query
      .mockResolvedValueOnce([]);         // lead count query
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toHaveLength(1);
    expect(result[0]?.id).toBe(expert2.id);
    expect(createSql).toHaveBeenCalledOnce();
  });
});

describe('loadExpertPool — D1 error falls through to Hyperdrive (AC12)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('falls through to Hyperdrive on D1 exception', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockRejectedValueOnce(new Error('D1 unavailable'));
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([expert1])
      .mockResolvedValueOnce([{ expert_id: expert1.id }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toHaveLength(1);
    expect(result[0]?.id).toBe(expert1.id);
    expect(result[0]?.total_leads).toBe(1);
    expect(createSql).toHaveBeenCalledOnce();
  });
});

describe('loadExpertPool — Hyperdrive fallback (AC11)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads from Hyperdrive, writes to Cache API and D1', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValueOnce([]);
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([expert1, expert2])
      .mockResolvedValueOnce([{ expert_id: expert1.id }, { expert_id: expert1.id }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toHaveLength(2);
    expect(result[0]?.total_leads).toBe(2);
    expect(result[1]?.total_leads).toBe(0);
    // AC11: both write-backs called
    expect(d1Module.writeCachePool).toHaveBeenCalledWith(result);
    expect(d1Module.upsertToD1).toHaveBeenCalledWith(expect.anything(), result);
  });

  it('returns empty array when Hyperdrive finds no experts', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValueOnce([]);

    const mockSql = vi.fn().mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toEqual([]);
    // writeCachePool not called when pool is empty (no point caching zero experts)
    expect(d1Module.writeCachePool).not.toHaveBeenCalled();
  });

  it('still returns pool if D1 write-back fails (non-blocking)', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValueOnce([]);
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);
    vi.mocked(d1Module.upsertToD1).mockRejectedValueOnce(new Error('D1 write error'));

    const mockSql = vi.fn()
      .mockResolvedValueOnce([expert1])
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvWithDb);

    expect(result).toHaveLength(1);
  });
});

describe('loadExpertPool — EXPERT_DB not provisioned (graceful degradation)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('skips D1 and goes directly to Hyperdrive when EXPERT_DB is undefined', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValueOnce(null);
    vi.mocked(d1Module.writeCachePool).mockResolvedValueOnce(undefined);

    const mockSql = vi.fn()
      .mockResolvedValueOnce([expert1])
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    const result = await loadExpertPool(mockEnvNoDb);

    expect(result).toHaveLength(1);
    expect(d1Module.loadFromD1).not.toHaveBeenCalled();
    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
  });
});
