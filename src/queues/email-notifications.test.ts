import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { consumeEmailNotifications } from './email-notifications';
import type { Env } from '../types/env';
import type { EmailNotificationMessage } from '../types/queues';

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
  queue = 'callibrate-core-queue-email-notifications-staging'
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
    EMAIL_FROM_DOMAIN: 'send.callibrate.io',
    EMAIL_REPLY_TO: 'support@callibrate.io',
    ...overrides,
  } as unknown as Env;
}

function okFetchResponse(body: unknown = {}): Response {
  return new Response(JSON.stringify(body), { status: 200 });
}

// ── Tests ──────────────────────────────────────────────────────────────────────

describe('consumeEmailNotifications', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  // ── Test 1: Happy path — expert.registered ────────────────────────────────

  it('expert.registered — calls Resend, marks KV, acks message', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    vi.mocked(fetch).mockResolvedValueOnce(okFetchResponse()); // Resend call

    const body: EmailNotificationMessage = {
      type: 'expert.registered',
      expert_id: 'expert-1',
      email: 'expert@example.com',
      name: 'Alice',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // Resend was called once
    expect(fetch).toHaveBeenCalledTimes(1);
    const [resendUrl, resendInit] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(resendUrl).toBe('https://api.resend.com/emails');
    const resendBody = JSON.parse(resendInit.body as string);
    expect(resendBody.to).toContain('expert@example.com');
    expect(resendBody.subject).toBe('Welcome to Callibrate');
    expect(resendBody.from).toBe('Callibrate <notifications@send.callibrate.io>');
    expect(resendBody.reply_to).toBe('support@callibrate.io');
    expect(resendBody.text).toBeTypeOf('string');
    expect(resendBody.text).toContain('Hi Alice');
    expect(resendBody.text).toContain('welcome to the Callibrate expert network');
    expect(resendBody.text).not.toContain('<p>');

    // KV marked
    expect(kv.put).toHaveBeenCalledWith('idem:email-notifications:msg-1', '1', { expirationTtl: 86400 });

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 2: Happy path — booking.confirmed ────────────────────────────────

  it('booking.confirmed — calls Resend twice + n8n webhook, acks message', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Mock sql: expert query returns expert data, prospect query returns prospect data
    const mockSql = vi.fn() as Mock;
    mockSql
      .mockResolvedValueOnce([{ gcal_email: 'expert@gcal.com', display_name: 'Alice' }])  // expert query
      .mockResolvedValueOnce([{ email: 'prospect@example.com' }]);                          // prospect query

    (createSql as Mock).mockReturnValue(mockSql);

    // fetch: Resend x2 + n8n x1
    vi.mocked(fetch)
      .mockResolvedValueOnce(okFetchResponse()) // Resend to expert
      .mockResolvedValueOnce(okFetchResponse()) // Resend to prospect
      .mockResolvedValueOnce(okFetchResponse()); // n8n webhook

    const body: EmailNotificationMessage = {
      type: 'booking.confirmed',
      booking_id: 'booking-1',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
      meeting_url: 'https://meet.example.com/abc',
      scheduled_at: '2026-03-01T10:00:00Z',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // fetch called 3 times: Resend x2 + n8n x1
    expect(fetch).toHaveBeenCalledTimes(3);

    const calls = (fetch as ReturnType<typeof vi.fn>).mock.calls as [string, RequestInit][];
    expect(calls[0]![0]).toBe('https://api.resend.com/emails');
    expect(calls[1]![0]).toBe('https://api.resend.com/emails');
    expect(calls[2]![0]).toBe('https://n8n.example.com/webhook/booking-confirmed');

    // Parse both Resend payloads
    const expertResendBody = JSON.parse(calls[0]![1].body as string);
    const prospectResendBody = JSON.parse(calls[1]![1].body as string);

    // Expert email assertions (E06S15)
    expect(expertResendBody.from).toBe('Callibrate <notifications@send.callibrate.io>');
    expect(expertResendBody.reply_to).toBe('support@callibrate.io');
    expect(expertResendBody.text).toBeTypeOf('string');
    expect(expertResendBody.text).toContain('Hi Alice');
    expect(expertResendBody.text).toContain('https://meet.example.com/abc');
    expect(expertResendBody.text).not.toContain('<p>');
    expect(expertResendBody.text).not.toContain('<a ');

    // Prospect email assertions (E06S15)
    expect(prospectResendBody.from).toBe('Callibrate <notifications@send.callibrate.io>');
    expect(prospectResendBody.reply_to).toBe('support@callibrate.io');
    expect(prospectResendBody.text).toBeTypeOf('string');
    expect(prospectResendBody.text).toContain('Your call has been confirmed');
    expect(prospectResendBody.text).toContain('https://meet.example.com/abc');
    expect(prospectResendBody.text).not.toContain('<p>');
    expect(prospectResendBody.text).not.toContain('<a ');

    // KV marked
    expect(kv.put).toHaveBeenCalledWith('idem:email-notifications:msg-1', '1', { expirationTtl: 86400 });

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 3: Happy path — booking.completed ────────────────────────────────

  it('booking.completed — calls only n8n webhook (no Resend), acks message', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    vi.mocked(fetch).mockResolvedValueOnce(okFetchResponse()); // n8n webhook

    const body: EmailNotificationMessage = {
      type: 'booking.completed',
      booking_id: 'booking-2',
      expert_id: 'expert-1',
      prospect_id: 'prospect-1',
      scheduled_at: '2026-03-01T10:00:00Z',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // Only the n8n webhook — no Resend call
    expect(fetch).toHaveBeenCalledTimes(1);
    const [url] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://n8n.example.com/webhook/booking-completed');

    // KV marked
    expect(kv.put).toHaveBeenCalledWith('idem:email-notifications:msg-1', '1', { expirationTtl: 86400 });

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 4: Retry on Resend failure (attempts=1) ──────────────────────────

  it('Resend failure (attempts=1) — retries with delaySeconds=1, KV NOT marked', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Resend returns error
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('Internal Server Error', { status: 500 })
    );

    const body: EmailNotificationMessage = {
      type: 'expert.registered',
      expert_id: 'expert-1',
      email: 'expert@example.com',
      name: 'Alice',
    };
    const message = makeMockMessage(body, { attempts: 1 });
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // retry called with delay 4^(1-1) = 1
    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 1 });
    expect(message.ack).not.toHaveBeenCalled();

    // KV NOT marked (failure before markProcessed)
    expect(kv.put).not.toHaveBeenCalled();
  });

  // ── Test 5: DLQ log on 3rd attempt failure (attempts=3) ──────────────────

  it('3rd attempt failure — logs structured JSON to console.error', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Resend returns error on the 3rd attempt
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('Service Unavailable', { status: 503 })
    );

    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const body: EmailNotificationMessage = {
      type: 'expert.registered',
      expert_id: 'expert-1',
      email: 'expert@example.com',
      name: 'Alice',
    };
    const message = makeMockMessage(body, { attempts: 3 });
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

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
    expect(logged.queue).toBe('email-notifications');
    expect(logged.message_id).toBe('msg-1');
    expect(logged.type).toBe('expert.registered');
    expect(typeof logged.error).toBe('string');
    expect(typeof logged.failed_at).toBe('string');

    consoleSpy.mockRestore();
  });

  // ── Test 6: Idempotency — KV returns '1' → no fetch, message acked ────────

  it('idempotency — KV returns 1 → fetch NOT called, message acked immediately', async () => {
    const kv = makeKv('1'); // already processed
    const env = makeEnv(kv);

    const body: EmailNotificationMessage = {
      type: 'expert.registered',
      expert_id: 'expert-1',
      email: 'expert@example.com',
      name: 'Alice',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // No fetch calls at all
    expect(fetch).not.toHaveBeenCalled();

    // KV put NOT called (no re-marking)
    expect(kv.put).not.toHaveBeenCalled();

    // Message acked (skip processed)
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });
});
