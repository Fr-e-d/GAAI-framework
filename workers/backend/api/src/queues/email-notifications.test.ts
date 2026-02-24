import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { consumeEmailNotifications } from './email-notifications';
import type { Env } from '../types/env';
import type { EmailNotificationMessage } from '../types/queues';

// ── Mock db ────────────────────────────────────────────────────────────────────

vi.mock('../lib/db', () => ({
  createSql: vi.fn(),
}));

vi.mock('../lib/supabase', () => ({
  createServiceClient: vi.fn(),
}));

import { createSql } from '../lib/db';
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

function makeWorkflowBinding(): { create: ReturnType<typeof vi.fn> } {
  return {
    create: vi.fn().mockResolvedValue({ id: 'wf-instance-1' }),
  };
}

function makeEnv(kv: KVNamespace, overrides: Partial<Env> = {}): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'test-anon-key',
    SUPABASE_SERVICE_KEY: 'test-service-key',
    SESSIONS: kv,
    RESEND_API_KEY: 'test-resend-key',
    LEMON_SQUEEZY_API_KEY: 'test-ls-key',
    EMAIL_FROM_DOMAIN: 'send.callibrate.io',
    EMAIL_REPLY_TO: 'support@callibrate.io',
    WORKER_BASE_URL: 'https://callibrate-core-staging.workers.dev',
    PROSPECT_TOKEN_SECRET: 'test-secret-32-chars-long-padding',
    SURVEY_TOKEN_SECRET: 'test-survey-secret-32-chars-paddd',
    BOOKING_CONFIRMED_WORKFLOW: makeWorkflowBinding() as unknown as Workflow,
    BOOKING_COMPLETED_WORKFLOW: makeWorkflowBinding() as unknown as Workflow,
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

  it('booking.confirmed — calls Resend twice + dispatches BOOKING_CONFIRMED_WORKFLOW (no n8n)', async () => {
    const kv = makeKv(null);
    const confirmedWorkflow = makeWorkflowBinding();
    const env = makeEnv(kv, {
      BOOKING_CONFIRMED_WORKFLOW: confirmedWorkflow as unknown as Workflow,
    });

    // Mock sql: expert query returns expert data, prospect query returns prospect data
    const mockSql = vi.fn() as Mock;
    mockSql
      .mockResolvedValueOnce([{ gcal_email: 'expert@gcal.com', display_name: 'Alice' }])  // expert query
      .mockResolvedValueOnce([{ email: 'prospect@example.com' }]);                          // prospect query

    (createSql as Mock).mockReturnValue(mockSql);

    // fetch: Resend x2 (no n8n)
    vi.mocked(fetch)
      .mockResolvedValueOnce(okFetchResponse()) // Resend to expert
      .mockResolvedValueOnce(okFetchResponse()); // Resend to prospect

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

    // fetch called 2 times: Resend x2 only (n8n removed)
    expect(fetch).toHaveBeenCalledTimes(2);

    const calls = (fetch as ReturnType<typeof vi.fn>).mock.calls as [string, RequestInit][];
    expect(calls[0]![0]).toBe('https://api.resend.com/emails');
    expect(calls[1]![0]).toBe('https://api.resend.com/emails');

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

    // Workflow dispatch called once with booking params
    expect(confirmedWorkflow.create).toHaveBeenCalledOnce();
    expect(confirmedWorkflow.create).toHaveBeenCalledWith({
      params: expect.objectContaining({
        type: 'booking.confirmed',
        booking_id: 'booking-1',
        expert_id: 'expert-1',
        prospect_id: 'prospect-1',
        meeting_url: 'https://meet.example.com/abc',
        scheduled_at: '2026-03-01T10:00:00Z',
      }),
    });

    // KV marked
    expect(kv.put).toHaveBeenCalledWith('idem:email-notifications:msg-1', '1', { expirationTtl: 86400 });

    // Message acked
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 3: Happy path — booking.completed ────────────────────────────────

  it('booking.completed — dispatches BOOKING_COMPLETED_WORKFLOW only (no Resend, no n8n)', async () => {
    const kv = makeKv(null);
    const completedWorkflow = makeWorkflowBinding();
    const env = makeEnv(kv, {
      BOOKING_COMPLETED_WORKFLOW: completedWorkflow as unknown as Workflow,
    });

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

    // No fetch calls at all (no Resend, no n8n)
    expect(fetch).not.toHaveBeenCalled();

    // Workflow dispatch called once
    expect(completedWorkflow.create).toHaveBeenCalledOnce();
    expect(completedWorkflow.create).toHaveBeenCalledWith({
      params: expect.objectContaining({
        type: 'booking.completed',
        booking_id: 'booking-2',
        prospect_id: 'prospect-1',
      }),
    });

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

  // ── Test 7: booking.confirmed.enriched — enriched expert email ────────────

  it('booking.confirmed.enriched — sends enriched expert email with prospect context', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Mock supabase: different tables return different data
    const mockFrom = vi.fn().mockImplementation((table: string) => {
      const mockSelect = vi.fn();
      const mockEq = vi.fn();
      const mockSingle = vi.fn();

      mockEq.mockReturnValue({ single: mockSingle });
      mockSelect.mockReturnValue({ eq: mockEq });

      if (table === 'experts') {
        mockSingle.mockResolvedValue({
          data: { gcal_email: 'expert@gcal.com', display_name: 'Bob' },
          error: null,
        });
      } else if (table === 'bookings') {
        mockSingle.mockResolvedValue({
          data: { prospect_name: 'Prospect Corp' },
          error: null,
        });
      } else {
        // prospects
        mockSingle.mockResolvedValue({
          data: {
            requirements: {
              challenge: 'Scale data pipeline',
              skills_needed: ['Python', 'Spark'],
              industry: 'Fintech',
              timeline: '3 months',
            },
          },
          error: null,
        });
      }

      return { select: mockSelect };
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

    vi.mocked(fetch).mockResolvedValueOnce(okFetchResponse()); // Resend to expert

    const body: EmailNotificationMessage = {
      type: 'booking.confirmed.enriched',
      booking_id: 'booking-3',
      expert_id: 'expert-2',
      prospect_id: 'prospect-2',
      meeting_url: 'https://meet.example.com/xyz',
      scheduled_at: '2026-03-05T14:00:00Z',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // Only 1 Resend call (to expert only)
    expect(fetch).toHaveBeenCalledTimes(1);
    const [resendUrl, resendInit] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(resendUrl).toBe('https://api.resend.com/emails');
    const resendBody = JSON.parse(resendInit.body as string);

    // Sent to expert
    expect(resendBody.to).toContain('expert@gcal.com');
    // Contains prospect context
    expect(resendBody.text).toContain('Prospect Corp');
    expect(resendBody.text).toContain('Scale data pipeline');
    expect(resendBody.text).toContain('Python');
    expect(resendBody.text).toContain('https://meet.example.com/xyz');
    expect(resendBody.text).toContain('2026-03-05T14:00:00Z');
    // Plain text only
    expect(resendBody.text).not.toContain('<p>');

    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 8: survey.call_experience — survey email to prospect ─────────────

  it('survey.call_experience — sends survey email with token-gated call-experience URL', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Mock supabase: bookings query returns prospect_email
    const mockFrom = vi.fn();
    const mockSelect = vi.fn();
    const mockEq = vi.fn();
    const mockSingle = vi.fn();

    mockSingle.mockResolvedValue({
      data: { prospect_email: 'prospect@example.com' },
      error: null,
    });
    mockEq.mockReturnValue({ single: mockSingle });
    mockSelect.mockReturnValue({ eq: mockEq });
    mockFrom.mockReturnValue({ select: mockSelect });

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

    vi.mocked(fetch).mockResolvedValueOnce(okFetchResponse()); // Resend

    const body: EmailNotificationMessage = {
      type: 'survey.call_experience',
      booking_id: 'booking-4',
      prospect_id: 'prospect-3',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    // 1 Resend call
    expect(fetch).toHaveBeenCalledTimes(1);
    const [resendUrl, resendInit] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    expect(resendUrl).toBe('https://api.resend.com/emails');
    const resendBody = JSON.parse(resendInit.body as string);

    // Sent to prospect
    expect(resendBody.to).toContain('prospect@example.com');
    expect(resendBody.subject).toContain('call');
    // Text contains survey URL with call-experience path and JWT token
    expect(resendBody.text).toContain('/api/surveys/call-experience?token=');
    expect(resendBody.text).not.toContain('<p>');

    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Test 9: survey.project_satisfaction — correct URL path ────────────────

  it('survey.project_satisfaction — sends survey email with project-satisfaction URL path', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const mockFrom = vi.fn();
    const mockSelect = vi.fn();
    const mockEq = vi.fn();
    const mockSingle = vi.fn();

    mockSingle.mockResolvedValue({
      data: { prospect_email: 'prospect@example.com' },
      error: null,
    });
    mockEq.mockReturnValue({ single: mockSingle });
    mockSelect.mockReturnValue({ eq: mockEq });
    mockFrom.mockReturnValue({ select: mockSelect });

    vi.mocked(createServiceClient).mockReturnValue({ from: mockFrom } as unknown as ReturnType<typeof createServiceClient>);

    vi.mocked(fetch).mockResolvedValueOnce(okFetchResponse()); // Resend

    const body: EmailNotificationMessage = {
      type: 'survey.project_satisfaction',
      booking_id: 'booking-5',
      prospect_id: 'prospect-4',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeEmailNotifications(batch, env);

    const [, resendInit] = (fetch as ReturnType<typeof vi.fn>).mock.calls[0] as [string, RequestInit];
    const resendBody = JSON.parse(resendInit.body as string);

    expect(resendBody.text).toContain('/api/surveys/project-satisfaction?token=');
    expect(resendBody.text).not.toContain('call-experience');
    expect(resendBody.subject).toContain('project');

    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });
});
