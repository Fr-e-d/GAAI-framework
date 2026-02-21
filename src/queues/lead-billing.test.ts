import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { consumeLeadBilling } from './lead-billing';
import type { Env } from '../types/env';
import type { LeadBillingMessage } from '../types/queues';

// ── Mock supabase ──────────────────────────────────────────────────────────────

vi.mock('../lib/supabase', () => ({
  createServiceClient: vi.fn(),
}));

import { createServiceClient } from '../lib/supabase';

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

// Build a mock Supabase client that handles the lead-billing query chain:
// insert → select('id') → single()   [leads insert]
// select('id') → eq() → single()     [leads fetch on conflict]
// select('gcal_email') → eq() → single()  [experts fetch]
// update() → eq()                    [leads update]
function buildMockSupabase(opts: {
  insertResult?: { data: { id: string } | null; error: { code?: string; message: string } | null };
  expertResult?: { data: { gcal_email: string } | null; error: { message: string } | null };
  updateResult?: { error: { message: string } | null };
}) {
  const {
    insertResult = { data: { id: 'lead-1' }, error: null },
    expertResult = { data: { gcal_email: 'expert@gcal.com' }, error: null },
    updateResult = { error: null },
  } = opts;

  // .update().eq() chain for leads
  const mockUpdateEq = vi.fn().mockResolvedValue(updateResult);
  const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });

  // .select('id').eq().single() chain for experts fetch
  let selectCallCount = 0;
  const mockSingle = vi.fn().mockImplementation(() => {
    selectCallCount++;
    if (selectCallCount === 1) return Promise.resolve(expertResult);
    return Promise.resolve({ data: null, error: { message: 'unexpected' } });
  });
  const mockSelectEq = vi.fn().mockReturnValue({ single: mockSingle });

  // .insert().select('id').single() chain for leads insert
  const mockInsertSingle = vi.fn().mockResolvedValue(insertResult);
  const mockInsertSelect = vi.fn().mockReturnValue({ single: mockInsertSingle });
  const mockInsert = vi.fn().mockReturnValue({ select: mockInsertSelect });

  const mockFrom = vi.fn().mockImplementation((table: string) => {
    if (table === 'leads') {
      return {
        insert: mockInsert,
        select: vi.fn().mockReturnValue({ eq: mockSelectEq }),
        update: mockUpdate,
      };
    }
    if (table === 'experts') {
      return {
        select: vi.fn().mockReturnValue({ eq: mockSelectEq }),
      };
    }
    return {};
  });

  return {
    from: mockFrom,
    _mocks: { mockInsert, mockUpdate, mockUpdateEq, mockSingle },
  };
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

    // Build mock supabase
    const mockInsertSingle = vi.fn().mockResolvedValue({ data: { id: 'lead-1' }, error: null });
    const mockInsertSelect = vi.fn().mockReturnValue({ single: mockInsertSingle });
    const mockInsert = vi.fn().mockReturnValue({ select: mockInsertSelect });

    const mockUpdateEq = vi.fn().mockResolvedValue({ error: null });
    const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });

    const expertSingle = vi.fn().mockResolvedValue({ data: { gcal_email: 'expert@gcal.com' }, error: null });
    const expertEq = vi.fn().mockReturnValue({ single: expertSingle });
    const expertSelect = vi.fn().mockReturnValue({ eq: expertEq });

    const mockFrom = vi.fn().mockImplementation((table: string) => {
      if (table === 'leads') {
        return { insert: mockInsert, update: mockUpdate };
      }
      if (table === 'experts') {
        return { select: expertSelect };
      }
      return {};
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

    // LS checkout API response
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ data: { id: 'ls-checkout-abc' } }), { status: 200 })
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
    expect(mockInsert).toHaveBeenCalledWith(expect.objectContaining({
      booking_id: 'booking-1',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
      status: 'pending',
    }));

    // LS API called
    expect(fetch).toHaveBeenCalledTimes(1);
    const [lsUrl] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(lsUrl).toBe('https://api.lemonsqueezy.com/v1/checkouts');

    // leads UPDATE to 'billed' with ls_checkout_id
    expect(mockUpdate).toHaveBeenCalledWith(expect.objectContaining({
      ls_checkout_id: 'ls-checkout-abc',
      status: 'billed',
    }));

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

    const mockInsertSingle = vi.fn().mockResolvedValue({ data: { id: 'lead-1' }, error: null });
    const mockInsertSelect = vi.fn().mockReturnValue({ single: mockInsertSingle });
    const mockInsert = vi.fn().mockReturnValue({ select: mockInsertSelect });

    const mockUpdate = vi.fn();

    const expertSingle = vi.fn().mockResolvedValue({ data: { gcal_email: 'expert@gcal.com' }, error: null });
    const expertEq = vi.fn().mockReturnValue({ single: expertSingle });
    const expertSelect = vi.fn().mockReturnValue({ eq: expertEq });

    const mockFrom = vi.fn().mockImplementation((table: string) => {
      if (table === 'leads') {
        return { insert: mockInsert, update: mockUpdate };
      }
      if (table === 'experts') {
        return { select: expertSelect };
      }
      return {};
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

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

    // UPDATE never called (LS failed before update step)
    expect(mockUpdate).not.toHaveBeenCalled();

    // KV NOT marked
    expect(kv.put).not.toHaveBeenCalled();
  });

  // ── Test 3: Idempotency — KV returns '1' → no Supabase, no fetch, acked ──

  it('idempotency — KV returns 1 → no Supabase calls, no fetch, message acked', async () => {
    const kv = makeKv('1'); // already processed
    const env = makeEnv(kv);

    const mockFrom = vi.fn();
    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-3',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeLeadBilling(batch, env);

    // No Supabase calls
    expect(mockFrom).not.toHaveBeenCalled();

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

    // Supabase insert fails
    const mockInsertSingle = vi.fn().mockResolvedValue({
      data: null,
      error: { code: '42P01', message: 'relation does not exist' },
    });
    const mockInsertSelect = vi.fn().mockReturnValue({ single: mockInsertSingle });
    const mockInsert = vi.fn().mockReturnValue({ select: mockInsertSelect });

    const mockFrom = vi.fn().mockImplementation(() => ({
      insert: mockInsert,
    }));

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

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
