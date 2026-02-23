import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { consumeLeadBilling } from './lead-billing';
import type { Env } from '../types/env';
import type { LeadBillingMessage } from '../types/queues';

// ── Mock db ────────────────────────────────────────────────────────────────────

vi.mock('../lib/db', () => ({
  createSql: vi.fn(),
}));

import { createSql } from '../lib/db';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeMockMessage<T>(
  body: T,
  opts: { id?: string; attempts?: number } = {}
): Message<T> & { ack: ReturnType<typeof vi.fn>; retry: ReturnType<typeof vi.fn> } {
  return {
    id: opts.id ?? 'msg-1',
    body,
    attempts: opts.attempts ?? 1,
    ack: vi.fn(),
    retry: vi.fn(),
    timestamp: new Date(),
  } as unknown as Message<T> & { ack: ReturnType<typeof vi.fn>; retry: ReturnType<typeof vi.fn> };
}

function makeBatch<T>(
  messages: Message<T>[],
  queue = 'callibrate-core-queue-lead-billing-staging'
): MessageBatch<T> {
  return {
    queue,
    messages,
    ackAll: vi.fn(),
  } as unknown as MessageBatch<T>;
}

function makeKv(existingKey: string | null = null): KVNamespace {
  return {
    get: vi.fn().mockResolvedValue(existingKey),
    put: vi.fn().mockResolvedValue(undefined),
  } as unknown as KVNamespace;
}

function makeEnv(kv: KVNamespace, overrides: Partial<Env> = {}): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'test-anon-key',
    SUPABASE_SERVICE_KEY: 'test-service-key',
    SESSIONS: kv,
    RESEND_API_KEY: 'test-resend-key',
    N8N_WEBHOOK_URL: 'https://n8n.example.com/webhook',
    LEMON_SQUEEZY_API_KEY: 'test-ls-key',
    ...overrides,
  } as unknown as Env;
}

function okFetchResponse(body: unknown = {}): Response {
  return new Response(JSON.stringify(body), { status: 200 });
}

// ── Tests ──────────────────────────────────────────────────────────────────────

describe('consumeLeadBilling', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  // ── Test 1: Happy path — booking.created ──────────────────────────────────

  it('booking.created — inserts lead, calls LS API, updates to billed, acks message', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mockSql = vi.fn() as Mock;
    // Call 1: INSERT INTO leads RETURNING id
    mockSql.mockResolvedValueOnce([{ id: 'lead-1' }]);
    // Call 2: SELECT gcal_email FROM experts
    mockSql.mockResolvedValueOnce([{ gcal_email: 'expert@gcal.com' }]);
    // Call 3: UPDATE leads SET ls_checkout_id ... (returns nothing meaningful)
    mockSql.mockResolvedValueOnce([]);

    (createSql as Mock).mockReturnValue(mockSql);

    // LS checkout API response
    vi.mocked(fetch).mockResolvedValueOnce(
      okFetchResponse({ data: { id: 'ls-checkout-abc' } })
    );

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-1',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeLeadBilling(batch, env);

    // leads INSERT called
    expect(mockSql).toHaveBeenCalledTimes(3);

    // LS API called once
    expect(fetch).toHaveBeenCalledTimes(1);
    const [lsUrl] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(lsUrl).toBe('https://api.lemonsqueezy.com/v1/checkouts');

    // The UPDATE call should reference ls_checkout_id 'ls-checkout-abc'
    // Find call that contains the checkout ID string
    const updateCall = mockSql.mock.calls.find((call) =>
      call.some((arg: unknown) => typeof arg === 'string' && arg === 'ls-checkout-abc')
    );
    expect(updateCall).toBeDefined();

    // KV marked
    expect(kv.put).toHaveBeenCalledWith('idem:lead-billing:msg-1', '1', { expirationTtl: 86400 });

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 2: Retry on LS failure (attempts=2) ──────────────────────────────

  it('LS failure (attempts=2) — retries with delaySeconds=4, lead NOT updated to billed', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mockSql = vi.fn() as Mock;
    // Call 1: INSERT INTO leads RETURNING id — succeeds
    mockSql.mockResolvedValueOnce([{ id: 'lead-1' }]);
    // Call 2: SELECT gcal_email FROM experts — succeeds
    mockSql.mockResolvedValueOnce([{ gcal_email: 'expert@gcal.com' }]);
    // UPDATE should NOT be reached (LS call fails before it)

    (createSql as Mock).mockReturnValue(mockSql);

    // LS API returns error
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('Bad Request', { status: 400 })
    );

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-2',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body, { attempts: 2 });
    const batch = makeBatch([message]);

    await consumeLeadBilling(batch, env);

    // retry with delay 4^(2-1) = 4
    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 4 });
    expect(message.ack).not.toHaveBeenCalled();

    // UPDATE never called (LS failed before update step) — only 2 sql calls
    expect(mockSql).toHaveBeenCalledTimes(2);

    // KV NOT marked
    expect(kv.put).not.toHaveBeenCalled();
  });

  // ── Test 3: Idempotency — KV returns '1' → no db calls, no fetch, acked ──

  it('idempotency — KV returns 1 → no db calls, no fetch, message acked', async () => {
    const kv = makeKv('1'); // already processed
    const env = makeEnv(kv);

    const mockSql = vi.fn() as Mock;
    (createSql as Mock).mockReturnValue(mockSql);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-3',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeLeadBilling(batch, env);

    // No sql calls (idempotency short-circuits before processLeadBilling)
    expect(mockSql).not.toHaveBeenCalled();

    // No fetch calls
    expect(fetch).not.toHaveBeenCalled();

    // KV put NOT called
    expect(kv.put).not.toHaveBeenCalled();

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 4: DLQ log on 3rd attempt failure (attempts=3) ──────────────────

  it('3rd attempt failure — logs structured JSON to console.error', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mockSql = vi.fn() as Mock;
    // INSERT INTO leads fails (throws)
    mockSql.mockRejectedValueOnce(new Error('relation does not exist'));

    (createSql as Mock).mockReturnValue(mockSql);

    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-4',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body, { attempts: 3 });
    const batch = makeBatch([message]);

    await consumeLeadBilling(batch, env);

    // retry still called (delaySeconds = 4^(3-1) = 16)
    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 16 });

    // console.error was called with structured JSON
    expect(consoleSpy).toHaveBeenCalledOnce();
    const logged = JSON.parse(consoleSpy.mock.calls[0]![0] as string) as {
      queue: string;
      message_id: string;
      type: string;
      payload: unknown;
      error: string;
      failed_at: string;
    };
    expect(logged.queue).toBe('lead-billing');
    expect(logged.message_id).toBe('msg-1');
    expect(logged.type).toBe('booking.created');
    expect(typeof logged.error).toBe('string');
    expect(typeof logged.failed_at).toBe('string');

    consoleSpy.mockRestore();
  });
});
