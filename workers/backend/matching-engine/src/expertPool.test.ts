import { describe, expect, it, vi, beforeEach } from 'vitest';
import type { ExpertPoolEntry } from './types';

// ── Mocks (declared before module import) ────────────────────────────────────

// Mock d1ExpertPool to avoid Cache API + D1 binding dependencies
vi.mock('./d1ExpertPool', () => ({
  getCachedPool: vi.fn(),
  writeCachePool: vi.fn().mockResolvedValue(undefined),
  loadFromD1: vi.fn(),
  upsertToD1: vi.fn().mockResolvedValue(undefined),
}));

// Mock db to avoid Hyperdrive/postgres dependency
vi.mock('./db', () => ({
  createSql: vi.fn(),
}));

import { loadExpertPool } from './expertPool';
import * as d1Module from './d1ExpertPool';
import * as dbModule from './db';
import type { MatchingEnv } from './env';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeEnv(overrides: Partial<MatchingEnv> = {}): MatchingEnv {
  return {
    HYPERDRIVE: {} as Hyperdrive,
    EXPERT_DB: undefined as unknown as D1Database,
    ...overrides,
  } as MatchingEnv;
}

/** Build a minimal sql mock that returns [] for any tagged template call and has a .end() method */
function makeSqlMock() {
  const sqlFn = vi.fn().mockResolvedValue([]);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (sqlFn as any).end = vi.fn().mockResolvedValue(undefined);
  return sqlFn as unknown as ReturnType<typeof dbModule.createSql>;
}

const samplePool: ExpertPoolEntry[] = [
  {
    id: 'expert-1',
    profile: { skills: ['n8n', 'python'], industries: ['fintech'] },
    preferences: { accepted_timelines: ['urgent'] },
    rate_min: 500,
    rate_max: 700,
    composite_score: 80,
    total_leads: 3,
  },
  {
    id: 'expert-2',
    profile: { skills: ['react', 'typescript'], industries: ['saas'] },
    preferences: null,
    rate_min: 400,
    rate_max: 600,
    composite_score: 65,
    total_leads: 7,
  },
];

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('loadExpertPool', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // Cache hit — L1 cache returns data
  it('returns cached pool when Cache API L1 has data', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(samplePool);

    const result = await loadExpertPool(makeEnv());

    expect(result).toEqual(samplePool);
    expect(d1Module.getCachedPool).toHaveBeenCalledOnce();
    expect(d1Module.loadFromD1).not.toHaveBeenCalled();
    expect(dbModule.createSql).not.toHaveBeenCalled();
  });

  // Cache miss + D1 hit
  it('falls through to D1 when cache is empty and EXPERT_DB binding present', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValue(samplePool);

    const fakeD1 = {} as D1Database;
    const result = await loadExpertPool(makeEnv({ EXPERT_DB: fakeD1 }));

    expect(d1Module.getCachedPool).toHaveBeenCalledOnce();
    expect(d1Module.loadFromD1).toHaveBeenCalledWith(fakeD1);
    expect(result).toEqual(samplePool);
  });

  // Cache miss + D1 hit → cache is populated
  it('writes to cache after D1 hit', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValue(samplePool);

    const fakeD1 = {} as D1Database;
    await loadExpertPool(makeEnv({ EXPERT_DB: fakeD1 }));

    expect(d1Module.writeCachePool).toHaveBeenCalledWith(samplePool);
  });

  // Cache miss + D1 empty → fallback to Hyperdrive
  it('falls through to Hyperdrive when D1 returns empty array', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(null);
    vi.mocked(d1Module.loadFromD1).mockResolvedValue([]);
    vi.mocked(dbModule.createSql).mockReturnValue(makeSqlMock());

    const fakeD1 = {} as D1Database;
    await loadExpertPool(makeEnv({ EXPERT_DB: fakeD1 }));

    expect(dbModule.createSql).toHaveBeenCalled();
  });

  // Cache miss + no D1 binding → skip to Hyperdrive
  it('skips D1 when EXPERT_DB binding is absent', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(null);
    vi.mocked(dbModule.createSql).mockReturnValue(makeSqlMock());

    await loadExpertPool(makeEnv({ EXPERT_DB: undefined as unknown as D1Database }));

    expect(d1Module.loadFromD1).not.toHaveBeenCalled();
    expect(dbModule.createSql).toHaveBeenCalled();
  });

  // Cache miss + D1 throws → fallback to Hyperdrive (non-blocking)
  it('falls through to Hyperdrive when D1 throws', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue(null);
    vi.mocked(d1Module.loadFromD1).mockRejectedValue(new Error('D1 unavailable'));
    vi.mocked(dbModule.createSql).mockReturnValue(makeSqlMock());

    const fakeD1 = {} as D1Database;
    // D1 failure is caught and falls through to Hyperdrive — should not throw
    await expect(loadExpertPool(makeEnv({ EXPERT_DB: fakeD1 }))).resolves.toBeDefined();
    expect(dbModule.createSql).toHaveBeenCalled();
  });

  // Cache empty array — treat as cache miss
  it('treats empty cache array as cache miss and proceeds to D1', async () => {
    vi.mocked(d1Module.getCachedPool).mockResolvedValue([]);
    vi.mocked(d1Module.loadFromD1).mockResolvedValue(samplePool);

    const fakeD1 = {} as D1Database;
    const result = await loadExpertPool(makeEnv({ EXPERT_DB: fakeD1 }));

    expect(d1Module.loadFromD1).toHaveBeenCalled();
    expect(result).toEqual(samplePool);
  });
});
