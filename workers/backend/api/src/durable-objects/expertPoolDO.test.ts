// Tests for E06S25: ExpertPoolDO — write coordinator
// Covers: AC1 (fetch/alarm), AC2 (batching + 5s alarm), AC3 (D1 + Vectorize),
//         AC4 (singleton pattern via notifyExpertPoolDO), AC5 (non-blocking)
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ExpertPoolDO, notifyExpertPoolDO, type ProfileEvent } from './expertPoolDO';
import type { Env } from '../types/env';

// Mock cloudflare:workers — DurableObject base class
vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

// Mock d1ExpertPool — avoid real D1 calls
vi.mock('../lib/d1ExpertPool', () => ({
  upsertToD1: vi.fn(),
}));

import * as d1Module from '../lib/d1ExpertPool';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeStorage(alarmValue: number | null = null) {
  return {
    getAlarm: vi.fn().mockResolvedValue(alarmValue),
    setAlarm: vi.fn().mockResolvedValue(undefined),
  };
}

const fakeVector = Array(768).fill(0.1) as number[];

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    HYPERDRIVE: {} as Hyperdrive,
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_KEY: 'service-key',
    OPENAI_API_KEY: 'openai-key',
    SESSIONS: {} as KVNamespace,
    RATE_LIMITING: {} as KVNamespace,
    FEATURE_FLAGS: {} as KVNamespace,
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
    ...overrides,
  } as unknown as Env;
}

const sampleEvent: ProfileEvent = {
  id: 'expert-abc',
  profile: { skills: ['python', 'n8n'] },
  preferences: {},
  rate_min: 100,
  rate_max: 200,
  composite_score: null,
  total_leads: 0,
  availability: 'available',
};

function makeDoInstance(storageAlarm: number | null = null, envOverrides: Partial<Env> = {}) {
  const storage = makeStorage(storageAlarm);
  const ctx = { storage };
  const env = makeEnv(envOverrides);
  const doInstance = new ExpertPoolDO(ctx as unknown as DurableObjectState, env);
  return { doInstance, storage, env };
}

// ── fetch() tests ─────────────────────────────────────────────────────────────

describe('ExpertPoolDO.fetch — AC1', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns 405 for non-POST methods', async () => {
    const { doInstance } = makeDoInstance();
    const res = await doInstance.fetch(new Request('https://do.internal/event', { method: 'GET' }));
    expect(res.status).toBe(405);
  });

  it('returns 400 for invalid JSON body', async () => {
    const { doInstance } = makeDoInstance();
    const res = await doInstance.fetch(
      new Request('https://do.internal/event', { method: 'POST', body: 'not-json' }),
    );
    expect(res.status).toBe(400);
  });

  it('returns 400 when id is missing', async () => {
    const { doInstance } = makeDoInstance();
    const res = await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify({ profile: {} }),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    expect(res.status).toBe(400);
  });

  it('returns 202 and queues the event — AC2', async () => {
    const { doInstance, storage } = makeDoInstance();
    const res = await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    expect(res.status).toBe(202);
    expect(await res.text()).toBe('accepted');
    // Alarm should be set since none exists
    expect(storage.getAlarm).toHaveBeenCalledOnce();
    expect(storage.setAlarm).toHaveBeenCalledOnce();
    const [alarmTime] = storage.setAlarm.mock.calls[0] as [number];
    expect(alarmTime).toBeGreaterThan(Date.now());
  });

  it('does NOT re-set alarm when one is already scheduled — AC2', async () => {
    const futureAlarm = Date.now() + 3000;
    const { doInstance, storage } = makeDoInstance(futureAlarm);
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    expect(storage.getAlarm).toHaveBeenCalledOnce();
    expect(storage.setAlarm).not.toHaveBeenCalled();
  });

  it('last write wins for same expert id — AC2', async () => {
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);
    const { doInstance, storage } = makeDoInstance(null, { EXPERT_DB: {} as D1Database });
    const event1 = { ...sampleEvent, rate_min: 100 };
    const event2 = { ...sampleEvent, rate_min: 150 };
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(event1),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    // Second POST with same id — alarm already set, no re-schedule
    storage.getAlarm.mockResolvedValueOnce(Date.now() + 4000);
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(event2),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    // Trigger alarm — only 1 event (last write wins)
    await doInstance.alarm();
    expect(vi.mocked(d1Module.upsertToD1)).toHaveBeenCalledOnce();
    const [, entries] = vi.mocked(d1Module.upsertToD1).mock.calls[0] as [
      D1Database,
      { id: string; rate_min: number | null }[],
    ];
    expect(entries).toHaveLength(1);
    expect(entries[0]?.rate_min).toBe(150); // last write wins
  });
});

// ── alarm() tests — AC3 ───────────────────────────────────────────────────────

describe('ExpertPoolDO.alarm — D1 upsert — AC3', () => {
  beforeEach(() => vi.clearAllMocks());

  it('does nothing when pendingEvents is empty', async () => {
    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
    });
    await doInstance.alarm();
    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
  });

  it('calls upsertToD1 with all pending events', async () => {
    vi.mocked(d1Module.upsertToD1).mockResolvedValueOnce(undefined);
    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
    });

    // Queue two events
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify({ ...sampleEvent, id: 'expert-xyz' }),
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    await doInstance.alarm();

    expect(d1Module.upsertToD1).toHaveBeenCalledOnce();
    const [, entries] = vi.mocked(d1Module.upsertToD1).mock.calls[0] as [
      D1Database,
      { id: string }[],
    ];
    expect(entries).toHaveLength(2);
    const ids = entries.map((e) => e.id).sort();
    expect(ids).toEqual(['expert-abc', 'expert-xyz']);
  });

  it('skips D1 upsert when EXPERT_DB is not bound', async () => {
    const { doInstance } = makeDoInstance(); // no EXPERT_DB
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await doInstance.alarm();
    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
  });

  it('D1 failure is non-fatal — logs error and continues', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.mocked(d1Module.upsertToD1).mockRejectedValueOnce(new Error('D1 down'));
    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
    });

    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await expect(doInstance.alarm()).resolves.toBeUndefined();
    expect(consoleSpy).toHaveBeenCalledWith(
      'ExpertPoolDO: D1 batch upsert failed',
      expect.any(Error),
    );
    consoleSpy.mockRestore();
  });
});

describe('ExpertPoolDO.alarm — Vectorize embed/upsert — AC3', () => {
  beforeEach(() => vi.clearAllMocks());

  it('calls AI.run and VECTORIZE.upsert for each event', async () => {
    const mockAi = { run: vi.fn().mockResolvedValue({ data: [fakeVector] }) };
    const mockVectorize = { upsert: vi.fn().mockResolvedValue(undefined) };
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);

    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
      AI: mockAi as unknown as Ai,
      VECTORIZE: mockVectorize as unknown as VectorizeIndex,
    });

    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    await doInstance.alarm();

    expect(mockAi.run).toHaveBeenCalledOnce();
    expect(mockAi.run).toHaveBeenCalledWith('@cf/baai/bge-base-en-v1.5', {
      text: [expect.stringContaining('python')],
    });

    expect(mockVectorize.upsert).toHaveBeenCalledOnce();
    const [vectors] = mockVectorize.upsert.mock.calls[0] as [
      { id: string; values: number[]; metadata: Record<string, unknown> }[],
    ];
    expect(vectors[0]?.id).toBe('expert-abc');
    expect(vectors[0]?.values).toEqual(fakeVector);
    expect(vectors[0]?.metadata['expert_id']).toBe('expert-abc');
    expect(vectors[0]?.metadata['rate_min']).toBe(100);
    expect(vectors[0]?.metadata['availability']).toBe('available');
  });

  it('skips Vectorize when AI/VECTORIZE bindings are missing', async () => {
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);
    const { doInstance } = makeDoInstance(null, { EXPERT_DB: {} as D1Database });

    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await expect(doInstance.alarm()).resolves.toBeUndefined();
  });

  it('AI returns empty vector — Vectorize.upsert not called, continues', async () => {
    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const mockAi = { run: vi.fn().mockResolvedValue({ data: [[]] }) };
    const mockVectorize = { upsert: vi.fn() };
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);

    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
      AI: mockAi as unknown as Ai,
      VECTORIZE: mockVectorize as unknown as VectorizeIndex,
    });

    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await doInstance.alarm();

    expect(mockVectorize.upsert).not.toHaveBeenCalled();
    expect(consoleSpy).toHaveBeenCalledWith(
      'ExpertPoolDO: empty embedding for expert',
      'expert-abc',
    );
    consoleSpy.mockRestore();
  });

  it('Vectorize failure for one expert is non-fatal — continues to next', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const mockAi = { run: vi.fn().mockResolvedValue({ data: [fakeVector] }) };
    const mockVectorize = {
      upsert: vi
        .fn()
        .mockRejectedValueOnce(new Error('Vectorize down'))
        .mockResolvedValueOnce(undefined),
    };
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);

    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
      AI: mockAi as unknown as Ai,
      VECTORIZE: mockVectorize as unknown as VectorizeIndex,
    });

    // Queue two events — first fails, second should succeed
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify({ ...sampleEvent, id: 'expert-xyz' }),
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    await expect(doInstance.alarm()).resolves.toBeUndefined();
    expect(mockVectorize.upsert).toHaveBeenCalledTimes(2);
    expect(consoleSpy).toHaveBeenCalledWith(
      'ExpertPoolDO: Vectorize upsert failed for expert',
      expect.stringMatching(/expert-abc|expert-xyz/),
      expect.any(Error),
    );
    consoleSpy.mockRestore();
  });

  it('clears pendingEvents after alarm fires', async () => {
    const mockAi = { run: vi.fn().mockResolvedValue({ data: [fakeVector] }) };
    const mockVectorize = { upsert: vi.fn().mockResolvedValue(undefined) };
    vi.mocked(d1Module.upsertToD1).mockResolvedValue(undefined);

    const { doInstance } = makeDoInstance(null, {
      EXPERT_DB: {} as D1Database,
      AI: mockAi as unknown as Ai,
      VECTORIZE: mockVectorize as unknown as VectorizeIndex,
    });

    await doInstance.fetch(
      new Request('https://do.internal/event', {
        method: 'POST',
        body: JSON.stringify(sampleEvent),
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    await doInstance.alarm();
    vi.clearAllMocks();

    // Second alarm with no pending events — no calls
    await doInstance.alarm();
    expect(d1Module.upsertToD1).not.toHaveBeenCalled();
    expect(mockVectorize.upsert).not.toHaveBeenCalled();
  });
});

// ── notifyExpertPoolDO helper — AC4, AC5 ─────────────────────────────────────

describe('notifyExpertPoolDO — AC4/AC5', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns void immediately without awaiting — AC5 non-blocking', () => {
    const mockCtx = {
      waitUntil: vi.fn(),
    } as unknown as ExecutionContext;
    const env = makeEnv({
      EXPERT_POOL_DO: {
        idFromName: vi.fn().mockReturnValue({ toString: () => 'do-id' }),
        get: vi.fn().mockReturnValue({
          fetch: vi.fn().mockResolvedValue(new Response('accepted', { status: 202 })),
        }),
      } as unknown as DurableObjectNamespace,
    });

    const result = notifyExpertPoolDO(env, mockCtx, sampleEvent);
    expect(result).toBeUndefined();
    expect(mockCtx.waitUntil).toHaveBeenCalledOnce();
  });

  it('uses idFromName("expert-pool-coordinator") — AC4 singleton', async () => {
    const mockFetch = vi.fn().mockResolvedValue(new Response('accepted', { status: 202 }));
    const mockStub = { fetch: mockFetch };
    const idFromName = vi.fn().mockReturnValue({ id: 'singleton' });
    const get = vi.fn().mockReturnValue(mockStub);
    const env = makeEnv({
      EXPERT_POOL_DO: { idFromName, get } as unknown as DurableObjectNamespace,
    });
    const mockCtx = {
      waitUntil: vi.fn((p: Promise<void>) => p),
    } as unknown as ExecutionContext;

    notifyExpertPoolDO(env, mockCtx, sampleEvent);
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await bgPromise;

    expect(idFromName).toHaveBeenCalledWith('expert-pool-coordinator');
    expect(get).toHaveBeenCalledOnce();
    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, opts] = mockFetch.mock.calls[0] as [string, { method: string; body: string }];
    expect(url).toBe('https://do.internal/event');
    expect(opts.method).toBe('POST');
    const body = JSON.parse(opts.body) as ProfileEvent;
    expect(body.id).toBe('expert-abc');
  });

  it('is a no-op when EXPERT_POOL_DO binding is absent — AC5 graceful degradation', () => {
    const mockCtx = { waitUntil: vi.fn() } as unknown as ExecutionContext;
    const env = makeEnv(); // no EXPERT_POOL_DO
    notifyExpertPoolDO(env, mockCtx, sampleEvent);
    expect(mockCtx.waitUntil).not.toHaveBeenCalled();
  });

  it('DO fetch failure is non-fatal — no error propagated — AC5', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const mockStub = { fetch: vi.fn().mockRejectedValue(new Error('DO unreachable')) };
    const env = makeEnv({
      EXPERT_POOL_DO: {
        idFromName: vi.fn().mockReturnValue({}),
        get: vi.fn().mockReturnValue(mockStub),
      } as unknown as DurableObjectNamespace,
    });
    const mockCtx = {
      waitUntil: vi.fn((p: Promise<void>) => p),
    } as unknown as ExecutionContext;

    notifyExpertPoolDO(env, mockCtx, sampleEvent);
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await expect(bgPromise).resolves.toBeUndefined();
    expect(consoleSpy).toHaveBeenCalledWith(
      'ExpertPoolDO: notification failed',
      expect.any(Error),
    );
    consoleSpy.mockRestore();
  });
});
