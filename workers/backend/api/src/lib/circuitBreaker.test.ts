import { describe, it, expect, vi, beforeEach } from 'vitest';
import { isCircuitOpen, recordExtractionCost } from './circuitBreaker';
import type { Env } from '../types/env';

// ── circuitBreaker — unit tests (E06S40 AC8, AC12) ───────────────────────────

function makeMockEnv(kvData: Record<string, string> = {}, extractCostCents?: string): Env {
  const store = new Map<string, string>(Object.entries(kvData));
  return {
    SESSIONS: {
      get: vi.fn(async (key: string) => store.get(key) ?? null),
      put: vi.fn(async (key: string, value: string) => { store.set(key, value); }),
      delete: vi.fn(),
      list: vi.fn(),
      getWithMetadata: vi.fn(),
    },
    EXTRACT_COST_CENTS: extractCostCents,
  } as unknown as Env;
}

function hourKey(): string {
  return `extract-cost:${new Date().toISOString().slice(0, 13)}`;
}

describe('isCircuitOpen', () => {
  it('returns false when no KV data (fresh start)', async () => {
    const env = makeMockEnv();
    expect(await isCircuitOpen(env)).toBe(false);
  });

  it('returns false when cost is below threshold (999 cents < 1000)', async () => {
    const env = makeMockEnv({ [hourKey()]: '999' });
    expect(await isCircuitOpen(env)).toBe(false);
  });

  it('returns true when cost equals threshold (1000 cents = $10)', async () => {
    const env = makeMockEnv({ [hourKey()]: '1000' });
    expect(await isCircuitOpen(env)).toBe(true);
  });

  it('returns true when cost exceeds threshold (1500 cents)', async () => {
    const env = makeMockEnv({ [hourKey()]: '1500' });
    expect(await isCircuitOpen(env)).toBe(true);
  });

  it('fails open on KV error (returns false)', async () => {
    const env = {
      SESSIONS: {
        get: vi.fn().mockRejectedValue(new Error('KV unavailable')),
      },
    } as unknown as Env;
    expect(await isCircuitOpen(env)).toBe(false);
  });
});

describe('recordExtractionCost', () => {
  it('sets initial counter to default cost (0.4 cents) when no prior value', async () => {
    const env = makeMockEnv();
    await recordExtractionCost(env);
    expect(env.SESSIONS.put).toHaveBeenCalledWith(
      hourKey(),
      '0.4000',
      expect.objectContaining({ expirationTtl: 7200 }),
    );
  });

  it('adds default cost to existing counter', async () => {
    const env = makeMockEnv({ [hourKey()]: '5.0000' });
    await recordExtractionCost(env);
    expect(env.SESSIONS.put).toHaveBeenCalledWith(
      hourKey(),
      '5.4000',
      expect.anything(),
    );
  });

  it('uses EXTRACT_COST_CENTS env var when set', async () => {
    const env = makeMockEnv({}, '0.8');
    await recordExtractionCost(env);
    expect(env.SESSIONS.put).toHaveBeenCalledWith(
      hourKey(),
      '0.8000',
      expect.anything(),
    );
  });

  it('swallows KV errors silently (never throws)', async () => {
    const env = {
      SESSIONS: {
        get: vi.fn().mockRejectedValue(new Error('KV unavailable')),
        put: vi.fn().mockRejectedValue(new Error('KV unavailable')),
      },
      EXTRACT_COST_CENTS: undefined,
    } as unknown as Env;
    // Must not throw
    await expect(recordExtractionCost(env)).resolves.toBeUndefined();
  });
});
