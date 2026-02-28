// Tests for E06S33: LemonSqueezy webhook handler (AC1–AC5, AC9, AC10, AC13)
import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { handleLsWebhook } from './lemonsqueezy';
import type { Env } from '../../types/env';

// ── Mocks ─────────────────────────────────────────────────────────────────────

vi.mock('../../lib/db', () => ({ createSql: vi.fn() }));

import { createSql } from '../../lib/db';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    LEMON_SQUEEZY_WEBHOOK_SECRET: 'test-secret',
    LEMON_SQUEEZY_API_KEY: 'test-ls-api-key',
    HYPERDRIVE: { connectionString: 'postgresql://test' } as unknown as Hyperdrive,
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_KEY: 'service-key',
    SESSIONS: {
      get: vi.fn().mockResolvedValue(null),
      put: vi.fn().mockResolvedValue(undefined),
    } as unknown as KVNamespace,
    EMAIL_NOTIFICATIONS: {
      send: vi.fn().mockResolvedValue(undefined),
    } as unknown as Queue,
    ...overrides,
  } as unknown as Env;
}

function makeLsEvent(eventName: string, overrides: Record<string, unknown> = {}) {
  return {
    meta: {
      event_name: eventName,
      custom_data: { expert_id: 'expert-uuid-1' },
    },
    data: {
      id: 'sub-123',
      attributes: {
        status: 'active',
        customer_email: 'expert@example.com',
      },
    },
    ...overrides,
  };
}

async function makeSignedRequest(body: unknown, secret: string, eventName: string): Promise<Request> {
  const bodyText = JSON.stringify(body);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(bodyText));
  const sigHex = Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');

  return new Request('https://api.callibrate.io/api/webhooks/lemonsqueezy', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Signature': sigHex,
    },
    body: bodyText,
  });
}

// ── AC1: Signature verification tests ─────────────────────────────────────────

describe('handleLsWebhook — signature verification (AC1)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('valid HMAC signature — returns 200', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_updated');
    const mockSql = vi.fn()
      .mockResolvedValueOnce([])   // L2: SELECT webhook_events → not found
      .mockResolvedValue([]);      // subsequent calls
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_updated');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('invalid HMAC signature — returns 401', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_updated');

    // Sign with wrong secret
    const req = await makeSignedRequest(event, 'wrong-secret', 'subscription_updated');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(401);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Unauthorized');
  });

  it('missing X-Signature header — returns 401', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_updated');

    const req = new Request('https://api.callibrate.io/api/webhooks/lemonsqueezy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(event),
    });
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(401);
  });
});

// ── AC5: Idempotency tests ─────────────────────────────────────────────────────

describe('handleLsWebhook — idempotency (AC5)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('duplicate event_id — returns 200 deduplicated without re-processing', async () => {
    const env = makeEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue('1'), // already processed
        put: vi.fn().mockResolvedValue(undefined),
      } as unknown as KVNamespace,
    });

    const event = makeLsEvent('subscription_updated');
    const req = await makeSignedRequest(event, 'test-secret', 'subscription_updated');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; deduplicated: boolean };
    expect(body.deduplicated).toBe(true);

    // createSql must NOT be called (no DB access for duplicate)
    expect(createSql).not.toHaveBeenCalled();
  });

  it('new event_id — marks processed in KV after handling', async () => {
    const env = makeEnv();
    const putSpy = env.SESSIONS.put as ReturnType<typeof vi.fn>;
    const event = makeLsEvent('subscription_updated');
    const mockSql = vi.fn()
      .mockResolvedValueOnce([])   // L2: SELECT webhook_events → not found
      .mockResolvedValue([]);      // subsequent calls (UPDATE experts, INSERT webhook_events)
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_updated');
    await handleLsWebhook(req, env);

    // KV.put must be called with idem key
    expect(putSpy).toHaveBeenCalledWith(
      expect.stringContaining('idem:ls-webhook:'),
      '1',
      { expirationTtl: 86400 }
    );
  });
});

// ── AC2 / AC11: subscription_created tests (E02S10: no welcome credit — milestone-based) ──

describe('handleLsWebhook — subscription_created (AC2/AC11)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('AC11: expert found via custom_data.expert_id — only subscription fields updated, NO credit awarded', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_created');

    // Mock fetch for LS subscription items API (still needed for ls_subscription_item_id)
    const globalFetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ data: [{ id: 'si-456' }] }), { status: 200 })
    );

    // AC11: sql calls = L2 check (1), SELECT expert by id (2), UPDATE experts subscription fields (3), INSERT webhook_events (4)
    // NO INSERT credit_transactions — credits are milestone-based now
    const mockSql = vi.fn()
      .mockResolvedValueOnce([])                             // L2: SELECT webhook_events → not found
      .mockResolvedValueOnce([{ id: 'expert-uuid-1' }])     // SELECT id FROM experts WHERE id
      .mockResolvedValueOnce([])                             // UPDATE experts (subscription fields only)
      .mockResolvedValueOnce([]);                            // INSERT webhook_events
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_created');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);

    // LS subscription items API still called (to get subscription item ID)
    expect(globalFetchSpy).toHaveBeenCalledWith(
      expect.stringContaining('subscription-items?filter[subscription_id]=sub-123'),
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer test-ls-api-key' }) })
    );

    // SQL called 4 times (AC11: no credit_transactions INSERT)
    expect(mockSql).toHaveBeenCalledTimes(4);

    // Verify no credit amount in any SQL call (no +10000)
    const allCalls = mockSql.mock.calls.map((c: unknown[]) => JSON.stringify(c));
    const hasCreditCall = allCalls.some((call: string) => call.includes('10000') || call.includes('welcome_credit'));
    expect(hasCreditCall).toBe(false);

    globalFetchSpy.mockRestore();
  });

  it('fallback to gcal_email when custom_data.expert_id returns no expert — no credit awarded', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_created');

    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ data: [{ id: 'si-789' }] }), { status: 200 })
    );

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])                              // L2: SELECT webhook_events → not found
      .mockResolvedValueOnce([])                              // SELECT id WHERE id → not found
      .mockResolvedValueOnce([{ id: 'expert-uuid-2' }])      // SELECT id WHERE gcal_email → found
      .mockResolvedValueOnce([])                              // UPDATE experts (subscription fields only)
      .mockResolvedValueOnce([]);                             // INSERT webhook_events
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_created');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);
    expect(mockSql).toHaveBeenCalledTimes(5);

    vi.restoreAllMocks();
  });

  it('expert not found — logs warning, returns 200 (silent failure)', async () => {
    const env = makeEnv();
    const event = makeLsEvent('subscription_created', {
      meta: { event_name: 'subscription_created', custom_data: {} },
    });

    vi.spyOn(console, 'warn').mockImplementation(() => {});

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])   // L2: SELECT webhook_events → not found
      .mockResolvedValueOnce([])   // gcal_email fallback → not found
      .mockResolvedValueOnce([]);  // INSERT webhook_events (after switch handles the no-expert path)
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_created');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);

    vi.restoreAllMocks();
  });
});

// ── AC4: subscription_payment_failed tests ────────────────────────────────────

describe('handleLsWebhook — subscription_payment_failed (AC4)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('sets ls_subscription_status to past_due and queues payment_failed notification', async () => {
    const env = makeEnv();
    const sendSpy = env.EMAIL_NOTIFICATIONS.send as ReturnType<typeof vi.fn>;
    const event = makeLsEvent('subscription_payment_failed');

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])                           // L2: SELECT webhook_events → not found
      .mockResolvedValueOnce([{ id: 'expert-uuid-1' }])   // UPDATE experts RETURNING id
      .mockResolvedValueOnce([]);                          // INSERT webhook_events
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_payment_failed');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);

    // UPDATE called — check SQL calls: L2 check + UPDATE + INSERT webhook_events = 3
    expect(mockSql).toHaveBeenCalledTimes(3);

    // EMAIL_NOTIFICATIONS.send called with payment_failed type
    expect(sendSpy).toHaveBeenCalledWith({
      type: 'expert.billing.payment_failed',
      expert_id: 'expert-uuid-1',
    });
  });

  it('no expert found for subscription — logs warning, no notification sent', async () => {
    const env = makeEnv();
    const sendSpy = env.EMAIL_NOTIFICATIONS.send as ReturnType<typeof vi.fn>;
    vi.spyOn(console, 'warn').mockImplementation(() => {});

    const event = makeLsEvent('subscription_payment_failed');

    const mockSql = vi.fn()
      .mockResolvedValueOnce([])   // L2: SELECT webhook_events → not found
      .mockResolvedValueOnce([])   // UPDATE experts → no rows (subscription not found)
      .mockResolvedValueOnce([]);  // INSERT webhook_events
    (createSql as Mock).mockReturnValue(mockSql);

    const req = await makeSignedRequest(event, 'test-secret', 'subscription_payment_failed');
    const res = await handleLsWebhook(req, env);

    expect(res.status).toBe(200);
    expect(sendSpy).not.toHaveBeenCalled();

    vi.restoreAllMocks();
  });
});

// ── AC3: subscription_updated status mapping tests ────────────────────────────

describe('handleLsWebhook — subscription_updated (AC3)', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  const statusMappings = [
    { lsStatus: 'active', expected: 'active' },
    { lsStatus: 'past_due', expected: 'past_due' },
    { lsStatus: 'cancelled', expected: 'cancelled' },
    { lsStatus: 'canceled', expected: 'cancelled' },
    { lsStatus: 'unpaid', expected: 'unpaid' },
  ];

  for (const { lsStatus, expected } of statusMappings) {
    it(`maps LS status '${lsStatus}' → '${expected}'`, async () => {
      const env = makeEnv();
      const event = makeLsEvent('subscription_updated', {
        data: {
          id: 'sub-123',
          attributes: { status: lsStatus },
        },
      });

      // Capture the SQL template tag arguments — skip first call (L2 webhook_events check)
      let capturedStatus: unknown;
      let callCount = 0;
      const mockSql = vi.fn().mockImplementation((...args: unknown[]) => {
        callCount++;
        // Second call is UPDATE experts SET ls_subscription_status = ${mappedStatus}
        if (callCount === 2 && Array.isArray(args[0])) {
          capturedStatus = args[1]; // second arg = first interpolation = mappedStatus
        }
        return Promise.resolve([]);
      });
      (createSql as Mock).mockReturnValue(mockSql);

      const req = await makeSignedRequest(event, 'test-secret', 'subscription_updated');
      const res = await handleLsWebhook(req, env);

      expect(res.status).toBe(200);
      expect(capturedStatus).toBe(expected);
    });
  }
});
