// Tests for E06S42: gdprCron — GDPR data retention (purge abandoned funnels + OTP cleanup)
import { describe, it, expect, vi, afterEach, type Mock } from 'vitest';
import { purgeAbandonedFunnels, cleanupOtpKvKeys, handleGdprCron } from './gdprCron';
import type { Env } from '../types/env';

// ── Mocks ─────────────────────────────────────────────────────────────────────

vi.mock('../lib/db', () => ({ createSql: vi.fn() }));
vi.mock('../lib/posthog', () => ({ captureEvent: vi.fn().mockResolvedValue(undefined) }));

import { createSql } from '../lib/db';
import { captureEvent } from '../lib/posthog';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeEnv(overrides: Partial<Record<string, unknown>> = {}): Env {
  return {
    HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_KEY: 'service-key',
    POSTHOG_API_KEY: 'test-posthog-key',
    SESSIONS: {
      list: vi.fn(),
      delete: vi.fn().mockResolvedValue(undefined),
      get: vi.fn(),
      put: vi.fn(),
      getWithMetadata: vi.fn(),
    } as unknown as KVNamespace,
    ...overrides,
  } as unknown as Env;
}

// Returns a plain Mock (vi.fn) that also has .end and .array, cast as the sql client type
function makeMockSql(responses: unknown[]): Mock {
  return Object.assign(
    vi.fn().mockImplementation(() => Promise.resolve(responses.shift() ?? [])),
    {
      end: vi.fn().mockResolvedValue(undefined),
      array: vi.fn((arr: unknown[]) => arr),
    }
  ) as unknown as Mock;
}

// ── purgeAbandonedFunnels ────────────────────────────────────────────────────

describe('purgeAbandonedFunnels', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('returns without SQL writes when no abandoned projects found', async () => {
    const env = makeEnv();
    // SELECT returns empty array
    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    // Only 1 SQL call — the SELECT; no UPDATE, DELETE, or INSERT
    expect(mockSql).toHaveBeenCalledTimes(1);
    const endFn = (mockSql as unknown as { end: Mock }).end;
    expect(endFn).toHaveBeenCalledTimes(1);
  });

  it('does not insert audit log when count is 0 (no abandoned projects)', async () => {
    const env = makeEnv();
    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    // Verify no INSERT into data_purge_log was made (only 1 call — the SELECT)
    expect(mockSql).toHaveBeenCalledTimes(1);
  });

  it('soft-purges freetext/requirements/extraction_confidence on abandoned projects', async () => {
    const env = makeEnv();
    const abandonedProjects = [{ id: 'proj-1' }, { id: 'proj-2' }];
    // SELECT → 2 projects, UPDATE → ok, DELETE → ok, INSERT → ok
    const mockSql = makeMockSql([abandonedProjects, [], [], []]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    // Should have 4 SQL calls: SELECT + UPDATE + DELETE + INSERT
    expect(mockSql).toHaveBeenCalledTimes(4);
    const endFn = (mockSql as unknown as { end: Mock }).end;
    expect(endFn).toHaveBeenCalledTimes(1);
  });

  it('deletes associated matches for abandoned projects', async () => {
    const env = makeEnv();
    const abandonedProjects = [{ id: 'proj-1' }];
    const mockSql = makeMockSql([abandonedProjects, [], [], []]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    // Verify DELETE FROM matches was called (3rd SQL call, index 2)
    expect(mockSql).toHaveBeenCalledTimes(4);
    const calls = mockSql.mock.calls as unknown[][];
    const deleteCall = calls[2]!;
    expect(deleteCall).toBeDefined();
    // The template string parts (first arg) should contain 'matches'
    const templateParts = deleteCall[0] as string[];
    expect(templateParts.some((s: string) => s.includes('matches'))).toBe(true);
  });

  it('inserts audit log row with correct count', async () => {
    const env = makeEnv();
    const abandonedProjects = [{ id: 'proj-1' }, { id: 'proj-2' }, { id: 'proj-3' }];
    const mockSql = makeMockSql([abandonedProjects, [], [], []]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    // 4th call (index 3) should be INSERT INTO data_purge_log with count=3
    const calls = mockSql.mock.calls as unknown[][];
    const insertCall = calls[3];
    expect(insertCall).toBeDefined();
    // count (3) should appear as an interpolated value in the call args
    expect(insertCall).toContain(3);
  });

  it('fires PostHog system.abandoned_funnel_purged event with count', async () => {
    const env = makeEnv();
    const abandonedProjects = [{ id: 'proj-1' }, { id: 'proj-2' }];
    const mockSql = makeMockSql([abandonedProjects, [], [], []]);
    (createSql as Mock).mockReturnValue(mockSql);

    await purgeAbandonedFunnels(env);

    expect(captureEvent).toHaveBeenCalledWith(
      'test-posthog-key',
      expect.objectContaining({
        distinctId: 'system',
        event: 'system.abandoned_funnel_purged',
        properties: { count: 2 },
      })
    );
  });

  it('calls sql.end() even when error is thrown mid-execution', async () => {
    const env = makeEnv();
    const endFn = vi.fn().mockResolvedValue(undefined);
    const mockSql = Object.assign(
      vi.fn().mockRejectedValueOnce(new Error('DB error')),
      {
        end: endFn,
        array: vi.fn((arr: unknown[]) => arr),
      }
    ) as unknown as Mock;
    (createSql as Mock).mockReturnValue(mockSql);

    await expect(purgeAbandonedFunnels(env)).rejects.toThrow('DB error');
    expect(endFn).toHaveBeenCalledTimes(1);
  });
});

// ── cleanupOtpKvKeys ─────────────────────────────────────────────────────────

describe('cleanupOtpKvKeys', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('deletes keys where expiration < now', async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const expiredKey = { name: 'otp:abc123', expiration: nowSec - 60 };
    const deleteFn = vi.fn().mockResolvedValue(undefined);
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: [expiredKey],
          list_complete: true,
        }),
        delete: deleteFn,
      } as unknown as KVNamespace,
    });

    // INSERT audit log
    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    expect(deleteFn).toHaveBeenCalledWith('otp:abc123');
    expect(mockSql).toHaveBeenCalledTimes(1);
  });

  it('does not delete keys where expiration > now', async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const activeKey = { name: 'otp:active', expiration: nowSec + 300 };
    const deleteFn = vi.fn().mockResolvedValue(undefined);
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: [activeKey],
          list_complete: true,
        }),
        delete: deleteFn,
      } as unknown as KVNamespace,
    });

    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    expect(deleteFn).not.toHaveBeenCalled();
  });

  it('does not delete keys without expiration set', async () => {
    const keyNoExpiry = { name: 'otp:no-expiry' }; // no expiration field
    const deleteFn = vi.fn().mockResolvedValue(undefined);
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: [keyNoExpiry],
          list_complete: true,
        }),
        delete: deleteFn,
      } as unknown as KVNamespace,
    });

    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    expect(deleteFn).not.toHaveBeenCalled();
  });

  it('logs warning when list_complete is false', async () => {
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: [],
          list_complete: false,
        }),
        delete: vi.fn().mockResolvedValue(undefined),
      } as unknown as KVNamespace,
    });

    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('list_complete=false'));
    consoleSpy.mockRestore();
  });

  it('inserts audit log row with count 0 when no keys expired', async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const activeKey = { name: 'otp:still-valid', expiration: nowSec + 600 };
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: [activeKey],
          list_complete: true,
        }),
        delete: vi.fn().mockResolvedValue(undefined),
      } as unknown as KVNamespace,
    });

    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    // Always inserts audit log — even when count is 0
    expect(mockSql).toHaveBeenCalledTimes(1);
    const calls = mockSql.mock.calls as unknown[][];
    // Audit log insert should include count 0
    expect(calls[0]).toContain(0);
  });

  it('inserts audit log row with correct count when keys deleted', async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const expiredKeys = [
      { name: 'otp:a', expiration: nowSec - 10 },
      { name: 'otp:b', expiration: nowSec - 20 },
    ];
    const deleteFn = vi.fn().mockResolvedValue(undefined);
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockResolvedValue({
          keys: expiredKeys,
          list_complete: true,
        }),
        delete: deleteFn,
      } as unknown as KVNamespace,
    });

    const mockSql = makeMockSql([[]]);
    (createSql as Mock).mockReturnValue(mockSql);

    await cleanupOtpKvKeys(env);

    // Deleted both keys
    expect(deleteFn).toHaveBeenCalledTimes(2);
    // Audit log with count=2
    const calls = mockSql.mock.calls as unknown[][];
    expect(calls[0]).toContain(2);
  });

  it('calls sql.end() even when error is thrown', async () => {
    const env = makeEnv({
      SESSIONS: {
        list: vi.fn().mockRejectedValue(new Error('KV list error')),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });

    const endFn = vi.fn().mockResolvedValue(undefined);
    const mockSql = Object.assign(
      vi.fn().mockResolvedValue([]),
      {
        end: endFn,
        array: vi.fn((arr: unknown[]) => arr),
      }
    ) as unknown as Mock;
    (createSql as Mock).mockReturnValue(mockSql);

    await expect(cleanupOtpKvKeys(env)).rejects.toThrow('KV list error');
    expect(endFn).toHaveBeenCalledTimes(1);
  });
});

// ── handleGdprCron ────────────────────────────────────────────────────────────

describe('handleGdprCron', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('calls purgeAbandonedFunnels and cleanupOtpKvKeys', async () => {
    const env = makeEnv();
    // Two sql instances: one for purgeAbandonedFunnels (SELECT → empty), one for cleanupOtpKvKeys (INSERT → ok)
    const mockSqlPurge = makeMockSql([[]]);
    const mockSqlOtp = makeMockSql([[]]);
    (createSql as Mock)
      .mockReturnValueOnce(mockSqlPurge)
      .mockReturnValueOnce(mockSqlOtp);

    (env.SESSIONS.list as Mock).mockResolvedValue({
      keys: [],
      list_complete: true,
    });

    await handleGdprCron(env);

    // createSql called twice (once per sub-function)
    expect(createSql).toHaveBeenCalledTimes(2);
    const endPurge = (mockSqlPurge as unknown as { end: Mock }).end;
    const endOtp = (mockSqlOtp as unknown as { end: Mock }).end;
    expect(endPurge).toHaveBeenCalledTimes(1);
    expect(endOtp).toHaveBeenCalledTimes(1);
  });

  it('continues when purgeAbandonedFunnels throws', async () => {
    const env = makeEnv();
    const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    // purgeAbandonedFunnels SQL throws
    const endPurgeFn = vi.fn().mockResolvedValue(undefined);
    const mockSqlPurge = Object.assign(
      vi.fn().mockRejectedValue(new Error('Purge DB error')),
      {
        end: endPurgeFn,
        array: vi.fn((arr: unknown[]) => arr),
      }
    ) as unknown as Mock;

    const mockSqlOtp = makeMockSql([[]]);
    (createSql as Mock)
      .mockReturnValueOnce(mockSqlPurge)
      .mockReturnValueOnce(mockSqlOtp);

    (env.SESSIONS.list as Mock).mockResolvedValue({
      keys: [],
      list_complete: true,
    });

    // Should NOT throw — handleGdprCron catches errors per sub-function
    await expect(handleGdprCron(env)).resolves.toBeUndefined();

    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining('purgeAbandonedFunnels'),
      expect.any(Error)
    );

    // cleanupOtpKvKeys still ran
    const endOtp = (mockSqlOtp as unknown as { end: Mock }).end;
    expect(endOtp).toHaveBeenCalledTimes(1);

    consoleErrorSpy.mockRestore();
  });

  it('continues when cleanupOtpKvKeys throws', async () => {
    const env = makeEnv();
    const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    // purgeAbandonedFunnels succeeds (empty SELECT)
    const mockSqlPurge = makeMockSql([[]]);

    // cleanupOtpKvKeys: SESSIONS.list throws
    (env.SESSIONS.list as Mock).mockRejectedValue(new Error('KV error'));

    const endOtpFn = vi.fn().mockResolvedValue(undefined);
    const mockSqlOtp = Object.assign(
      vi.fn().mockResolvedValue([]),
      {
        end: endOtpFn,
        array: vi.fn((arr: unknown[]) => arr),
      }
    ) as unknown as Mock;

    (createSql as Mock)
      .mockReturnValueOnce(mockSqlPurge)
      .mockReturnValueOnce(mockSqlOtp);

    // Should NOT throw
    await expect(handleGdprCron(env)).resolves.toBeUndefined();

    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining('cleanupOtpKvKeys'),
      expect.any(Error)
    );

    consoleErrorSpy.mockRestore();
  });
});
