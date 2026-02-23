import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleVectorizeReindex } from './vectorize';
import type { Env } from '../../types/env';

const mockAi = { run: vi.fn() };
const mockVectorize = { upsert: vi.fn() };

const mockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key-secret',
  AI: mockAi,
  VECTORIZE: mockVectorize,
} as unknown as Env;

const mockCtx = {
  waitUntil: vi.fn((p: Promise<void>) => p),
} as unknown as ExecutionContext;

function postgrestList(data: object[]) {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Content-Range': `0-${Math.max(0, data.length - 1)}/${data.length}`,
    },
  });
}

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
  mockAi.run.mockReset();
  mockVectorize.upsert.mockReset();
  vi.mocked(mockCtx.waitUntil).mockReset();
  vi.mocked(mockCtx.waitUntil).mockImplementation((p: Promise<void>) => p);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('handleVectorizeReindex — POST /api/admin/vectorize/reindex', () => {
  it('returns 401 when Authorization header is absent', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
    });
    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(401);
  });

  it('returns 401 when Authorization header has wrong value', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer wrong-key' },
    });
    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(401);
  });

  it('returns 202 + queued count for correct auth with experts', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      postgrestList([
        { id: 'e1', profile: { skills: ['react'] }, rate_min: 100, rate_max: 200, availability: 'available' },
      ])
    );
    mockAi.run.mockResolvedValue({ data: [Array(768).fill(0.1)] });
    mockVectorize.upsert.mockResolvedValue(undefined);

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });

    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(202);
    const body = await res.json() as { queued: number };
    expect(body.queued).toBe(1);

    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await bgPromise;
    expect(mockVectorize.upsert).toHaveBeenCalledOnce();
  });

  it('returns 202 + queued: 0 when no active experts', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(postgrestList([]));

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });

    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(202);
    const body = await res.json() as { queued: number };
    expect(body.queued).toBe(0);
  });

  it('returns 500 when Supabase query fails', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ message: 'connection error' }), { status: 500 })
    );

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });

    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(500);
  });

  it('AI failure for one expert does not abort others', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      postgrestList([
        { id: 'e1', profile: {}, rate_min: null, rate_max: null, availability: 'available' },
        { id: 'e2', profile: {}, rate_min: null, rate_max: null, availability: 'available' },
      ])
    );
    mockAi.run
      .mockRejectedValueOnce(new Error('AI down'))
      .mockResolvedValueOnce({ data: [Array(768).fill(0.1)] });
    mockVectorize.upsert.mockResolvedValue(undefined);

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });

    const res = await handleVectorizeReindex(req, mockEnv, mockCtx);
    expect(res.status).toBe(202);

    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await bgPromise;

    // Only the second expert should have Vectorize.upsert called
    expect(mockVectorize.upsert).toHaveBeenCalledOnce();
  });
});
