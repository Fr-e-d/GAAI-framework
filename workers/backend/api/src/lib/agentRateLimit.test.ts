import { describe, it, expect, vi } from 'vitest';
import { checkAgentRateLimit } from './agentRateLimit';

// Build a simple in-memory KV mock
function makeKv(initial: Record<string, string> = {}): KVNamespace {
  const store: Record<string, string> = { ...initial };
  return {
    get: vi.fn(async (key: string) => store[key] ?? null),
    put: vi.fn(async (key: string, value: string) => { store[key] = value; }),
    delete: vi.fn(async (key: string) => { delete store[key]; }),
    list: vi.fn(async () => ({ keys: [], list_complete: true, cursor: '' })),
    getWithMetadata: vi.fn(async (key: string) => ({ value: store[key] ?? null, metadata: null })),
  } as unknown as KVNamespace;
}

describe('checkAgentRateLimit', () => {
  it('allows the first request', async () => {
    const kv = makeKv();
    const result = await checkAgentRateLimit(kv, 'key-hash-abc', 'extract');
    expect(result.allowed).toBe(true);
  });

  it('blocks after the limit is reached for extract (10/min)', async () => {
    // Pre-fill store to simulate 10 existing requests in the window
    const windowIndex = Math.floor(Date.now() / 60000);
    const kvKey = `agent-rate:key-hash-xyz:extract:${windowIndex}`;
    const kv = makeKv({ [kvKey]: '10' }); // count is already at limit

    const result = await checkAgentRateLimit(kv, 'key-hash-xyz', 'extract');
    expect(result.allowed).toBe(false);
    expect(result.retryAfter).toBeGreaterThan(0);
  });

  it('blocks after the limit is reached for reveal (3/hour)', async () => {
    const windowIndex = Math.floor(Date.now() / 3600000);
    const kvKey = `agent-rate:key-hash-xyz:reveal:${windowIndex}`;
    const kv = makeKv({ [kvKey]: '3' });

    const result = await checkAgentRateLimit(kv, 'key-hash-xyz', 'reveal');
    expect(result.allowed).toBe(false);
    expect(result.retryAfter).toBeGreaterThan(0);
  });

  it('fails open on KV error', async () => {
    const kv = {
      get: vi.fn(async () => { throw new Error('KV unavailable'); }),
      put: vi.fn(async () => { throw new Error('KV unavailable'); }),
    } as unknown as KVNamespace;

    const result = await checkAgentRateLimit(kv, 'key-hash-abc', 'match');
    expect(result.allowed).toBe(true);
  });

  it('increments counter on each allowed request', async () => {
    const kv = makeKv();
    await checkAgentRateLimit(kv, 'key-hash-abc', 'extract');
    await checkAgentRateLimit(kv, 'key-hash-abc', 'extract');
    await checkAgentRateLimit(kv, 'key-hash-abc', 'extract');

    // Count should be 3 now
    const windowIndex = Math.floor(Date.now() / 60000);
    const kvKey = `agent-rate:key-hash-abc:extract:${windowIndex}`;
    const stored = await kv.get(kvKey);
    expect(stored).toBe('3');
  });
});
