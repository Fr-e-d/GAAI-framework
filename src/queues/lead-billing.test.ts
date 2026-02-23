import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { consumeLeadBilling } from './lead-billing';
import type { Env } from '../types/env';
import type { LeadBillingMessage } from '../types/queues';

// ── Mock supabase ──────────────────────────────────────────────────────────────

vi.mock('../lib/supabase', () => ({
  createServiceClient: vi.fn(),
}));

import { createServiceClient } from '../lib/supabase';

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

function makeEmailQueue(): Queue {
  return { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue;
}

function makeEnv(kv: KVNamespace, overrides: Partial<Env> = {}): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'test-anon-key',
    SUPABASE_SERVICE_KEY: 'test-service-key',
    SESSIONS: kv,
    EMAIL_NOTIFICATIONS: makeEmailQueue(),
    ...overrides,
  } as unknown as Env;
}

function okFetchResponse(body: unknown = {}): Response {
  return new Response(JSON.stringify(body), { status: 200 });
}

// ── Supabase mock builder ──────────────────────────────────────────────────────

function buildMockSupabase(opts: {
  prospectResult?: { data: { requirements: Record<string, unknown> | null } | null; error: { message: string } | null };
  rpcResult?: { data: Record<string, unknown> | null; error: { message: string } | null };
}) {
  const {
    prospectResult = {
      data: { requirements: { budget_range: { max: 15000 }, timeline: '2-4 weeks', skills_needed: ['n8n', 'python'] } },
      error: null,
    },
    rpcResult = { data: { success: true, lead_id: 'lead-1', balance_after: 85100 }, error: null },
  } = opts;

  const mockProspectSingle = vi.fn().mockResolvedValue(prospectResult);
  const mockProspectEq = vi.fn().mockReturnValue({ single: mockProspectSingle });
  const mockProspectSelect = vi.fn().mockReturnValue({ eq: mockProspectEq });

  const mockRpc = vi.fn().mockResolvedValue(rpcResult);

  const mockFrom = vi.fn().mockImplementation((table: string) => {
    if (table === 'prospects') {
      return { select: mockProspectSelect };
    }
    return {};
  });

  return {
    from: mockFrom,
    rpc: mockRpc,
    _mocks: { mockFrom, mockRpc, mockProspectSingle },
  };
}

// ── Tests ──────────────────────────────────────────────────────────────────────

describe('consumeLeadBilling', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  // ── Test 1: Happy path — booking.created, sufficient balance ─────────────

  it('booking.created — fetches prospect, calls RPC debit, acks message', async () => {
    const kv = makeKv(null);
    const emailQueue = makeEmailQueue();
    const env = makeEnv(kv, { EMAIL_NOTIFICATIONS: emailQueue });

    const mock = buildMockSupabase({});
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-1',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);

    await consumeLeadBilling(makeBatch([message]), env);

    // Prospect fetched
    expect(mock.from).toHaveBeenCalledWith('prospects');

    // RPC called with correct ids
    expect(mock.rpc).toHaveBeenCalledWith('debit_lead_credit', expect.objectContaining({
      p_expert_id:   'expert-1',
      p_booking_id:  'booking-1',
      p_prospect_id: 'prospect-1',
    }));

    // No email notification (balance sufficient)
    expect(emailQueue.send).not.toHaveBeenCalled();

    // KV marked as processed (AC7)
    expect(kv.put).toHaveBeenCalledWith('idem:lead-billing:msg-1', '1', { expirationTtl: 86400 });

    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 2: Insufficient balance — email notification queued (AC2) ───────

  it('insufficient balance — email notification queued, message acked', async () => {
    const kv = makeKv(null);
    const emailQueue = makeEmailQueue();
    const env = makeEnv(kv, { EMAIL_NOTIFICATIONS: emailQueue });

    const mock = buildMockSupabase({
      rpcResult: { data: { success: false, reason: 'insufficient_balance', lead_id: 'lead-2' }, error: null },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-2',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);
    await consumeLeadBilling(makeBatch([message]), env);

    // Email notification queued for expert (AC2)
    expect(emailQueue.send).toHaveBeenCalledWith(expect.objectContaining({
      type: 'expert.billing.insufficient_balance',
      expert_id: 'expert-1',
    }));

    // Processing succeeded — KV marked, message acked
    expect(kv.put).toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 3: Idempotency — KV hit → skip all processing (AC7) ────────────

  it('idempotency — KV returns 1 → no Supabase calls, message acked', async () => {
    const kv = makeKv('1');
    const env = makeEnv(kv);

    const mockFrom = vi.fn();
    const mockRpc = vi.fn();
    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom, rpc: mockRpc } as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-3',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body);
    await consumeLeadBilling(makeBatch([message]), env);

    expect(mockFrom).not.toHaveBeenCalled();
    expect(mockRpc).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── Test 4: RPC failure → retry (attempts=2) (AC8) ───────────────────────

  it('RPC failure (attempts=2) — retries with delaySeconds=4', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mock = buildMockSupabase({
      rpcResult: { data: null, error: { message: 'connection timeout' } },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-4',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body, { attempts: 2 });
    await consumeLeadBilling(makeBatch([message]), env);

    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 4 });
    expect(message.ack).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();
  });

  // ── Test 5: Prospect fetch failure → 3rd attempt → DLQ log (AC8) ────────

  it('3rd attempt failure — logs structured JSON to console.error', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mockProspectSingle = vi.fn().mockResolvedValue({
      data: null,
      error: { message: 'relation does not exist' },
    });
    const mockFrom = vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({ single: mockProspectSingle }),
      }),
    });
    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom, rpc: vi.fn() } as unknown as ReturnType<typeof createServiceClient>);

    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-5',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    const message = makeMockMessage(body, { attempts: 3 });
    await consumeLeadBilling(makeBatch([message]), env);

    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 16 });

    expect(consoleSpy).toHaveBeenCalledOnce();
    const logged = JSON.parse(consoleSpy.mock.calls[0]![0] as string) as {
      queue: string;
      message_id: string;
      type: string;
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

  // ── Test 6: Unknown message type — ack and skip ──────────────────────────

  it('unknown message type — acks without processing', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const mockRpc = vi.fn();
    vi.mocked(createServiceClient).mockReturnValue({ from: vi.fn(), rpc: mockRpc } as unknown as ReturnType<typeof createServiceClient>);

    const message = makeMockMessage({ type: 'unknown.event' } as unknown as LeadBillingMessage);
    await consumeLeadBilling(makeBatch([message]), env);

    expect(mockRpc).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── Test 7: Null requirements → micro tier price (4900) ─────────────────

  it('null prospect requirements — passes p_amount=4900 (micro tier) to RPC', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mock = buildMockSupabase({
      prospectResult: { data: { requirements: null }, error: null },
      rpcResult: { data: { success: true, lead_id: 'lead-7', balance_after: 95100 }, error: null },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-7',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    await consumeLeadBilling(makeBatch([makeMockMessage(body)]), env);

    // null budget → micro tier = 4900 centimes (AC1, DEC-67)
    expect(mock.rpc).toHaveBeenCalledWith('debit_lead_credit', expect.objectContaining({
      p_amount: 4900,
    }));
  });

  // ── Test 8: Premium tier — budget + timeline + skills ────────────────────

  it('premium qualification (budget + timeline + skills) — premium tier price passed to RPC', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mock = buildMockSupabase({
      prospectResult: {
        data: {
          requirements: {
            budget_range: { max: 25000 },
            timeline: '4-6 weeks',
            skills_needed: ['react', 'node'],
          },
        },
        error: null,
      },
      rpcResult: { data: { success: true, lead_id: 'lead-8', balance_after: 82900 }, error: null },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const body: LeadBillingMessage = {
      type: 'booking.created',
      booking_id: 'booking-8',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
    };
    await consumeLeadBilling(makeBatch([makeMockMessage(body)]), env);

    // budget=25000 (medium tier), premium: 17100 centimes
    expect(mock.rpc).toHaveBeenCalledWith('debit_lead_credit', expect.objectContaining({
      p_amount: 17100,
    }));
  });
});
