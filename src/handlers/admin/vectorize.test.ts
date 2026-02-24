// Tests for handleVectorizeReindex — updated for E06S24 Service Binding proxy architecture.
// The handler now proxies to MATCHING_SERVICE instead of directly calling AI/Vectorize.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleVectorizeReindex } from './vectorize';
import type { Env } from '../../types/env';

const mockMatchingService = {
  fetch: vi.fn(),
};

const mockEnvWithService = {
  SUPABASE_SERVICE_KEY: 'service-key-secret',
  MATCHING_SERVICE: mockMatchingService,
} as unknown as Env;

const mockEnvNoService = {
  SUPABASE_SERVICE_KEY: 'service-key-secret',
} as unknown as Env;

const mockCtx = {
  waitUntil: vi.fn((p: Promise<void>) => p),
} as unknown as ExecutionContext;

beforeEach(() => {
  mockMatchingService.fetch.mockReset();
  vi.mocked(mockCtx.waitUntil).mockReset();
});

describe('handleVectorizeReindex — POST /api/admin/vectorize/reindex', () => {
  it('returns 401 when Authorization header is absent', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
    });
    const res = await handleVectorizeReindex(req, mockEnvWithService, mockCtx);
    expect(res.status).toBe(401);
    expect(mockMatchingService.fetch).not.toHaveBeenCalled();
  });

  it('returns 401 when Authorization header has wrong value', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer wrong-key' },
    });
    const res = await handleVectorizeReindex(req, mockEnvWithService, mockCtx);
    expect(res.status).toBe(401);
    expect(mockMatchingService.fetch).not.toHaveBeenCalled();
  });

  it('returns 503 when MATCHING_SERVICE is not bound', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });
    const res = await handleVectorizeReindex(req, mockEnvNoService, mockCtx);
    expect(res.status).toBe(503);
  });

  it('proxies to MATCHING_SERVICE /admin/reindex and returns its response', async () => {
    mockMatchingService.fetch.mockResolvedValue(
      new Response(JSON.stringify({ queued: 5 }), {
        status: 202,
        headers: { 'Content-Type': 'application/json' },
      })
    );

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: 'Bearer service-key-secret' },
    });

    const res = await handleVectorizeReindex(req, mockEnvWithService, mockCtx);
    expect(res.status).toBe(202);
    const body = await res.json() as { queued: number };
    expect(body.queued).toBe(5);
    expect(mockMatchingService.fetch).toHaveBeenCalledOnce();
  });
});
