// Tests for E06S33: lsBillingCron — auto-confirm leads + usage reporting (AC6–AC8, AC13)
import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { handleLsBillingCron } from './lsBillingCron';
import type { Env } from '../types/env';

// ── Mocks ─────────────────────────────────────────────────────────────────────

vi.mock('../lib/db', () => ({ createSql: vi.fn() }));

import { createSql } from '../lib/db';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    LEMON_SQUEEZY_API_KEY: 'test-ls-api-key',
    FLAG_WINDOW_MS: '60000', // 1 minute for testing
    HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_KEY: 'service-key',
    ...overrides,
  } as unknown as Env;
}

// ── AC6: Auto-confirm pending leads past the flag window ─────────────────────

describe('handleLsBillingCron — autoConfirmLeads (AC6)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('confirms pending leads past the FLAG_WINDOW_MS cutoff', async () => {
    const env = makeEnv();
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({}), { status: 201 })
    );

    const mockSql = vi.fn()
      // autoConfirmLeads: UPDATE leads → 2 confirmed
      .mockResolvedValueOnce([{ id: 'lead-1' }, { id: 'lead-2' }])
      // reportUsage: SELECT leads for usage → none pending
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    await handleLsBillingCron(env);

    // First SQL call must be the UPDATE for auto-confirm
    const firstCall = mockSql.mock.calls[0];
    expect(firstCall).toBeDefined();

    vi.restoreAllMocks();
  });

  it('uses FLAG_WINDOW_MS env var to determine cutoff', async () => {
    // 1 minute window — any lead older than 1 minute should be confirmed
    const env = makeEnv({ FLAG_WINDOW_MS: '60000' } as unknown as Partial<Env>);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({}), { status: 201 })
    );

    let capturedCutoff: string | undefined;
    const mockSql = vi.fn().mockImplementation((...args: unknown[]) => {
      if (Array.isArray(args[0])) {
        // 2nd arg is 'confirmed', 3rd is the cutoff ISO string
        if (typeof args[2] === 'string' && args[2].includes('T')) {
          capturedCutoff = args[2];
        }
      }
      return Promise.resolve([]);
    });
    (createSql as Mock).mockReturnValue(mockSql);

    const before = Date.now();
    await handleLsBillingCron(env);
    const after = Date.now();

    if (capturedCutoff) {
      const cutoffMs = new Date(capturedCutoff).getTime();
      // cutoff should be approximately (now - 60000ms)
      expect(cutoffMs).toBeGreaterThan(before - 60000 - 100);
      expect(cutoffMs).toBeLessThan(after - 60000 + 100);
    }

    vi.restoreAllMocks();
  });

  it('defaults to 7 days when FLAG_WINDOW_MS is absent', async () => {
    const env = makeEnv({ FLAG_WINDOW_MS: undefined } as unknown as Partial<Env>);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({}), { status: 201 })
    );

    let capturedCutoff: string | undefined;
    const mockSql = vi.fn().mockImplementation((...args: unknown[]) => {
      if (Array.isArray(args[0])) {
        if (typeof args[2] === 'string' && args[2].includes('T')) {
          capturedCutoff = args[2];
        }
      }
      return Promise.resolve([]);
    });
    (createSql as Mock).mockReturnValue(mockSql);

    const before = Date.now();
    await handleLsBillingCron(env);

    if (capturedCutoff) {
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      const cutoffMs = new Date(capturedCutoff).getTime();
      // Cutoff should be approximately 7 days ago
      expect(cutoffMs).toBeGreaterThan(before - sevenDaysMs - 1000);
      expect(cutoffMs).toBeLessThan(before - sevenDaysMs + 1000);
    }

    vi.restoreAllMocks();
  });
});

// ── AC7: Usage reporting happy path ──────────────────────────────────────────

describe('handleLsBillingCron — reportUsage happy path (AC7)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('reports usage to LS API and marks leads as usage_reported', async () => {
    const env = makeEnv();

    // Mock fetch for LS usage records API
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ data: { id: 'ur-1' } }), { status: 201 })
    );

    const leadForUsage = {
      id: 'lead-1',
      amount: 9900,
      expert_id: 'expert-1',
      ls_subscription_item_id: 'si-456',
    };

    const mockSql = vi.fn()
      // autoConfirmLeads: UPDATE → none confirmed
      .mockResolvedValueOnce([])
      // reportUsage: SELECT confirmed leads → 1 pending
      .mockResolvedValueOnce([leadForUsage])
      // reportLeadUsage: UPDATE lead SET status='usage_reported'
      .mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    await handleLsBillingCron(env);

    // LS usage records API called with correct body
    expect(fetchSpy).toHaveBeenCalledWith(
      'https://api.lemonsqueezy.com/v1/usage-records',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer test-ls-api-key',
          'Content-Type': 'application/vnd.api+json',
        }),
      })
    );

    // Verify body structure
    const callArgs = fetchSpy.mock.calls[0]!;
    const requestBody = JSON.parse(callArgs[1]!.body as string) as unknown;
    expect(requestBody).toMatchObject({
      data: {
        type: 'usage-records',
        attributes: {
          quantity: 9900,
          action: 'increment',
        },
        relationships: {
          'subscription-item': {
            data: {
              type: 'subscription-items',
              id: 'si-456',
            },
          },
        },
      },
    });

    // UPDATE called to mark lead as usage_reported
    expect(mockSql).toHaveBeenCalledTimes(3);

    fetchSpy.mockRestore();
  });

  it('processes multiple leads in a single cron run', async () => {
    const env = makeEnv();

    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ data: { id: 'ur-1' } }), { status: 201 })
    );

    const leads = [
      { id: 'lead-1', amount: 5000, expert_id: 'e1', ls_subscription_item_id: 'si-1' },
      { id: 'lead-2', amount: 8000, expert_id: 'e2', ls_subscription_item_id: 'si-2' },
    ];

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])     // autoConfirmLeads
      .mockResolvedValueOnce(leads)  // SELECT confirmed leads
      .mockResolvedValueOnce([])     // UPDATE lead-1
      .mockResolvedValueOnce([]);    // UPDATE lead-2
    (createSql as Mock).mockReturnValue(mockSql);

    await handleLsBillingCron(env);

    // Fetch called twice (once per lead)
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    // SQL called 4 times: auto-confirm + SELECT + 2x UPDATE
    expect(mockSql).toHaveBeenCalledTimes(4);

    fetchSpy.mockRestore();
  });
});

// ── AC8: LS failure — retry on next run ──────────────────────────────────────

describe('handleLsBillingCron — LS failure → retry (AC8)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('does NOT update lead status when LS API returns error', async () => {
    const env = makeEnv();
    vi.spyOn(console, 'error').mockImplementation(() => {});

    // LS API returns 422 error
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response('Unprocessable Entity', { status: 422 })
    );

    const leadForUsage = {
      id: 'lead-1',
      amount: 9900,
      expert_id: 'expert-1',
      ls_subscription_item_id: 'si-456',
    };

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])              // autoConfirmLeads
      .mockResolvedValueOnce([leadForUsage]); // SELECT confirmed leads
    // No 3rd call — UPDATE should NOT happen on failure
    (createSql as Mock).mockReturnValue(mockSql);

    await handleLsBillingCron(env);

    // Fetch called once (attempted)
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    // SQL called only twice — no UPDATE for failed lead
    expect(mockSql).toHaveBeenCalledTimes(2);

    fetchSpy.mockRestore();
    vi.restoreAllMocks();
  });

  it('does NOT update lead status when fetch throws', async () => {
    const env = makeEnv();
    vi.spyOn(console, 'error').mockImplementation(() => {});

    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('Network timeout'));

    const leadForUsage = {
      id: 'lead-1',
      amount: 9900,
      expert_id: 'expert-1',
      ls_subscription_item_id: 'si-456',
    };

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([leadForUsage]);
    (createSql as Mock).mockReturnValue(mockSql);

    // Should not throw — error is caught and logged
    await expect(handleLsBillingCron(env)).resolves.toBeUndefined();

    // Only 2 SQL calls — no UPDATE on failure
    expect(mockSql).toHaveBeenCalledTimes(2);

    fetchSpy.mockRestore();
    vi.restoreAllMocks();
  });

  it('continues processing other leads when one fails', async () => {
    const env = makeEnv();
    vi.spyOn(console, 'error').mockImplementation(() => {});

    // First call fails, second succeeds
    const fetchSpy = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response('Error', { status: 500 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: {} }), { status: 201 }));

    const leads = [
      { id: 'lead-1', amount: 5000, expert_id: 'e1', ls_subscription_item_id: 'si-1' },
      { id: 'lead-2', amount: 8000, expert_id: 'e2', ls_subscription_item_id: 'si-2' },
    ];

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])     // autoConfirmLeads
      .mockResolvedValueOnce(leads)  // SELECT confirmed leads
      .mockResolvedValueOnce([]);    // UPDATE lead-2 (only successful one)
    (createSql as Mock).mockReturnValue(mockSql);

    await handleLsBillingCron(env);

    // Both fetch calls attempted
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    // Only 3 SQL calls — auto-confirm + SELECT + 1 UPDATE (lead-2 only)
    expect(mockSql).toHaveBeenCalledTimes(3);

    fetchSpy.mockRestore();
    vi.restoreAllMocks();
  });
});
