// Tests for handleVectorizeReindex — updated for E08S04 (ADMIN_API_KEY) + E06S24 (Service Binding proxy).
// AC7 (E08S04): wrong key → 401; correct ADMIN_API_KEY → proxied.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleVectorizeReindex } from './vectorize';
import type { Env } from '../../types/env';

const ADMIN_KEY = 'admin-api-key-secret';

const mockMatchingService = {
  fetch: vi.fn(),
};

const mockEnvWithService = {
  ADMIN_API_KEY: ADMIN_KEY,
  MATCHING_SERVICE: mockMatchingService,
} as unknown as Env;

const mockEnvNoService = {
  ADMIN_API_KEY: ADMIN_KEY,
} as unknown as Env;

const mockCtx = {
  waitUntil: vi.fn((p: Promise<void>) => p),
} as unknown as ExecutionContext;

beforeEach(() => {
  mockMatchingService.fetch.mockReset();
  vi.mocked(mockCtx.waitUntil).mockReset();
});

describe('handleVectorizeReindex — POST /api/admin/vectorize/reindex', () => {
  it('returns 401 when Authorization header is absent (AC7a)', async () => {
    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
    });
    const res = await handleVectorizeReindex(req, mockEnvWithService, mockCtx);
    expect(res.status).toBe(401);
    expect(mockMatchingService.fetch).not.toHaveBeenCalled();
  });

  it('returns 401 when Authorization header has wrong key (AC7a)', async () => {
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
      headers: { Authorization: `Bearer ${ADMIN_KEY}` },
    });
    const res = await handleVectorizeReindex(req, mockEnvNoService, mockCtx);
    expect(res.status).toBe(503);
  });

  it('proxies to MATCHING_SERVICE /admin/reindex when correct ADMIN_API_KEY (AC7b)', async () => {
    mockMatchingService.fetch.mockResolvedValue(
      new Response(JSON.stringify({ queued: 5 }), {
        status: 202,
        headers: { 'Content-Type': 'application/json' },
      })
    );

    const req = new Request('https://api.callibrate.io/api/admin/vectorize/reindex', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ADMIN_KEY}` },
    });

    const res = await handleVectorizeReindex(req, mockEnvWithService, mockCtx);
    expect(res.status).toBe(202);
    const body = await res.json() as { queued: number };
    expect(body.queued).toBe(5);
    expect(mockMatchingService.fetch).toHaveBeenCalledOnce();
  });
});
