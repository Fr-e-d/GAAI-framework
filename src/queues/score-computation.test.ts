import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { consumeScoreComputation } from './score-computation';
import type { Env } from '../types/env';
import type { ScoreComputationMessage } from '../types/queues';

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
  queue = 'callibrate-core-queue-score-computation-staging'
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
    ...overrides,
  } as unknown as Env;
}

// ── Expert profile type for test helpers ─────────────────────────────────────

interface TestExpertProfile {
  verified_at: string | null;
  bio: string | null;
  profile: Record<string, unknown> | null;
}

// ── Tests ──────────────────────────────────────────────────────────────────────

describe('consumeScoreComputation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ── Idempotency ───────────────────────────────────────────────────────────────

  it('idempotency — KV returns 1 → no Supabase calls, message acked immediately', async () => {
    const kv = makeKv('1'); // already processed
    const env = makeEnv(kv);

    const body: ScoreComputationMessage = {
      type: 'feedback.call_experience',
      expert_id: 'expert-1',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(createServiceClient).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Unknown message type ──────────────────────────────────────────────────────

  it('unknown message type — console.warn, acked, no Supabase call', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    const body = { type: 'unknown.type', expert_id: 'expert-1' } as unknown as ScoreComputationMessage;
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(consoleSpy).toHaveBeenCalledOnce();
    expect(createServiceClient).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();

    consoleSpy.mockRestore();
  });

  // ── Retry on failure ──────────────────────────────────────────────────────────

  it('retry (attempts=1) — Supabase error → retry with delaySeconds=1, KV NOT marked', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Make Supabase throw on matches query
    vi.mocked(createServiceClient).mockReturnValue({
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockResolvedValue({ data: null, error: { message: 'DB unavailable' } }),
        }),
      }),
    } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body, { attempts: 1 });
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 1 });
    expect(message.ack).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();
  });

  it('DLQ log (attempts=3) — console.error with structured JSON, retry with delaySeconds=16', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    vi.mocked(createServiceClient).mockReturnValue({
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockResolvedValue({ data: null, error: { message: 'DB error' } }),
        }),
      }),
    } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body, { attempts: 3 });
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(message.retry).toHaveBeenCalledWith({ delaySeconds: 16 });
    expect(consoleSpy).toHaveBeenCalledOnce();
    const logged = JSON.parse(consoleSpy.mock.calls[0]![0] as string) as {
      queue: string;
      message_id: string;
      type: string;
      error: string;
      failed_at: string;
    };
    expect(logged.queue).toBe('score-computation');
    expect(logged.message_id).toBe('msg-1');
    expect(logged.type).toBe('feedback.lead_evaluation');
    expect(typeof logged.error).toBe('string');
    expect(typeof logged.failed_at).toBe('string');

    consoleSpy.mockRestore();
  });

  // ── Score component unit tests (AC11) ─────────────────────────────────────────
  // We test components by controlling what Supabase returns for each table query.
  // The consumer runs computeAndSaveCompositeScore which:
  // 1. Queries matches → returns matchIds
  // 2. Queries bookings → returns bookingIds  (first .from('bookings') call)
  // 3. Parallel:
  //    - call_experience_surveys (.from().select().in())
  //    - project_satisfaction_surveys (.from().select().in())
  //    - lead_evaluations (.from().select().eq())
  //    - bookings (second .from('bookings') call) for recency: .select().in().not().order().limit()
  //    - experts (.from().select().eq().single()) for trust score
  // 4. Writes to experts .update()

  /**
   * buildScoringMock — constructs a fully controlled Supabase mock.
   *
   * IMPORTANT: `bookings` is called twice across the execution:
   *   call 1 (sequential): .from('bookings').select('id').in('match_id', matchIds)
   *   call 2 (in Promise.all): .from('bookings').select('scheduled_at').in(...).not().order().limit(1)
   *
   * We track this with a bookingsCallCount variable that is shared across all
   * .from('bookings') calls (hoisted above the mockImplementation closure).
   */
  function buildScoringMock({
    matchIds = ['match-1'],
    bookingIds = ['booking-1'],
    callExperienceSurveys = [] as Array<{ score: number | null }>,
    satisfactionSurveys = [] as Array<{ score: number | null }>,
    leadEvaluations = [] as Array<{ conversion_declared: boolean | null }>,
    mostRecentBookingScheduledAt = null as string | null,
    expertProfile = {
      verified_at: '2026-01-01T00:00:00Z',
      bio: 'Expert bio here',
      profile: {
        portfolio_items: [{}, {}, {}],
        linkedin_url: 'https://linkedin.com/in/expert',
        years_experience: 5,
        certifications: [{ name: 'AWS' }],
      },
    } as TestExpertProfile,
    updateResult = { error: null } as { error: null | { message: string } },
  } = {}) {
    const updateFn = vi.fn().mockReturnValue({ eq: vi.fn().mockResolvedValue(updateResult) });

    // Hoisted counter: tracks how many times .from('bookings') has been called
    // so the first call returns bookingIds and the second returns recency data.
    let bookingsFromCallCount = 0;

    const fromMock = vi.fn().mockImplementation((table: string) => {
      if (table === 'matches') {
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockResolvedValue({
              data: matchIds.map((id) => ({ id })),
              error: null,
            }),
          }),
        };
      }

      if (table === 'bookings') {
        bookingsFromCallCount++;
        const currentCall = bookingsFromCallCount;

        return {
          select: vi.fn().mockReturnValue({
            in: vi.fn().mockImplementation(() => {
              if (currentCall === 1) {
                // First bookings call: fetch booking IDs — returns immediately (awaited)
                return Promise.resolve({
                  data: bookingIds.map((id) => ({ id })),
                  error: null,
                });
              }
              // Second bookings call: recency chain — .in().not().order().limit()
              const recencyData = mostRecentBookingScheduledAt
                ? [{ scheduled_at: mostRecentBookingScheduledAt }]
                : [];
              const recencyResult = Promise.resolve({ data: recencyData, error: null });
              return {
                not: vi.fn().mockReturnValue({
                  order: vi.fn().mockReturnValue({
                    limit: vi.fn().mockReturnValue(recencyResult),
                  }),
                }),
              };
            }),
          }),
          update: updateFn,
        };
      }

      if (table === 'call_experience_surveys') {
        return {
          select: vi.fn().mockReturnValue({
            in: vi.fn().mockResolvedValue({
              data: callExperienceSurveys,
              error: null,
            }),
          }),
        };
      }

      if (table === 'project_satisfaction_surveys') {
        return {
          select: vi.fn().mockReturnValue({
            in: vi.fn().mockResolvedValue({
              data: satisfactionSurveys,
              error: null,
            }),
          }),
        };
      }

      if (table === 'lead_evaluations') {
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockResolvedValue({
              data: leadEvaluations,
              error: null,
            }),
          }),
        };
      }

      if (table === 'experts') {
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockReturnValue({
              single: vi.fn().mockResolvedValue({
                data: expertProfile,
                error: null,
              }),
            }),
          }),
          update: updateFn,
        };
      }

      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockResolvedValue({ data: [], error: null }),
        }),
      };
    });

    return { fromMock, updateFn };
  }

  // ── A1: call_experience_avg — 2 surveys → 80 ──────────────────────────────

  it('A1: call_experience_avg — scores [3, 5] → avg = 80', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [{ score: 3 }, { score: 5 }],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(), // 10 days ago → recency=100
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call_experience_avg = (3*20 + 5*20)/2 = 80
    // trust = 100 (all criteria met in default expert profile)
    // satisfaction = 0, hire = 0, recency = 100
    // composite = 80*0.35 + 100*0.20 + 0*0.20 + 0*0.10 + 100*0.15 = 28 + 20 + 0 + 0 + 15 = 63
    expect(updateFn).toHaveBeenCalled();
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number; score_updated_at: string };
    expect(updateArgs.composite_score).toBe(63);
    expect(typeof updateArgs.score_updated_at).toBe('string');
    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A2: call_experience_avg — no surveys → 0 ─────────────────────────────

  it('A2: call_experience_avg — no surveys → contributes 0 to composite', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(),
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call_experience=0, trust=100, satisfaction=0, hire=0, recency=100
    // composite = 0*0.35 + 100*0.20 + 0*0.20 + 0*0.10 + 100*0.15 = 0+20+0+0+15 = 35
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(35);
  });

  // ── A3: client_satisfaction_avg — scores [8, 6] → 70 ────────────────────

  it('A3: client_satisfaction_avg — scores [8, 6] → avg = 70', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [{ score: 8 }, { score: 6 }],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(),
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // satisfaction = (80+60)/2 = 70, call=0, trust=100, hire=0, recency=100
    // composite = 0*0.35 + 100*0.20 + 70*0.20 + 0*0.10 + 100*0.15 = 0+20+14+0+15 = 49
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(49);
  });

  // ── A4: client_satisfaction_avg — no surveys → 0 ─────────────────────────

  it('A4: client_satisfaction_avg — no surveys → contributes 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // all=0, trust=0 (null profile, no verified_at)
    // composite = 0
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(0);
  });

  // ── A5: hire_rate — 2 of 4 converted → 50 ────────────────────────────────

  it('A5: hire_rate — 2 of 4 conversion_declared=true → 50', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [
        { conversion_declared: true },
        { conversion_declared: true },
        { conversion_declared: false },
        { conversion_declared: null },
      ],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // hire_rate = 50, all others = 0
    // composite = 0*0.35 + 0*0.20 + 0*0.20 + 50*0.10 + 0*0.15 = 5
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(5);
  });

  // ── A6: hire_rate — no evaluations → 0 ───────────────────────────────────

  it('A6: hire_rate — no evaluations → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      leadEvaluations: [],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(0);
  });

  // ── A7: hire_rate — all null → 0 ─────────────────────────────────────────

  it('A7: hire_rate — all conversion_declared=null → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      leadEvaluations: [{ conversion_declared: null }, { conversion_declared: null }],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(0);
  });

  // ── A8: recency — booking 15 days ago → 100 ──────────────────────────────

  it('A8: recency_score — booking 15 days ago → 100', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 15 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // recency = 100, all others = 0
    // composite = 100*0.15 = 15
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(15);
  });

  // ── A9: recency — booking 105 days ago → ~50 ─────────────────────────────

  it('A9: recency_score — booking 105 days ago → ~50', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 105 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // daysSince ~= 105, recency = 100 - ((105-30)/150)*100 = 100 - 50 = 50
    // composite = 50*0.15 = 7.5
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBeCloseTo(7.5, 0);
  });

  // ── A10: recency — booking 200 days ago → 0 ──────────────────────────────

  it('A10: recency_score — booking 200 days ago → 0 (clamped)', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 200 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // recency = 0, composite = 0
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(0);
  });

  // ── A11: recency — no bookings → 0 ───────────────────────────────────────

  it('A11: recency_score — no bookings → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, profile: null },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(0);
  });

  // ── A12: trust_score — fully complete profile → 100 ──────────────────────

  it('A12: trust_score — fully complete profile → 100', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'Expert bio here',
        profile: {
          portfolio_items: [{ title: 'P1' }, { title: 'P2' }, { title: 'P3' }],
          linkedin_url: 'https://linkedin.com/in/expert',
          years_experience: 5,
          certifications: [{ name: 'AWS Certified' }],
        },
      },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 100, all others = 0, composite = 100*0.20 = 20
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(20);
  });

  // ── A13: trust_score — null profile → 20 ─────────────────────────────────

  it('A13: trust_score — null profile + verified → 20', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: null,
        profile: null,
      },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 20 (only verified_at criterion met), composite = 20*0.20 = 4
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(4);
  });

  // ── A14: trust — only 2 portfolio items → criterion 2 fails ──────────────

  it('A14: trust_score — bio present but only 2 portfolio items → criterion 2 fails', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'My bio',
        profile: {
          portfolio_items: [{ title: 'P1' }, { title: 'P2' }], // only 2
          linkedin_url: 'https://linkedin.com/in/expert',
          years_experience: 5,
          certifications: [{ name: 'AWS' }],
        },
      },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 80 (criterion 2 fails — only 2 portfolio items)
    // composite = 80*0.20 = 16
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(16);
  });

  // ── A15: trust — years_experience = 2 → criterion 4 fails ────────────────

  it('A15: trust_score — years_experience = 2 → criterion 4 fails', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'My bio',
        profile: {
          portfolio_items: [{ title: 'P1' }, { title: 'P2' }, { title: 'P3' }],
          linkedin_url: 'https://linkedin.com/in/expert',
          years_experience: 2, // fails criterion 4
          certifications: [{ name: 'AWS' }],
        },
      },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 80 (criterion 4 fails)
    // composite = 80*0.20 = 16
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBe(16);
  });

  // ── B8: composite formula verification ───────────────────────────────────

  it('B8: composite formula — controlled inputs → expected score', async () => {
    // call=80, trust=60, satisfaction=70, hire=50, recency=50
    // 80*0.35 + 60*0.20 + 70*0.20 + 50*0.10 + 50*0.15 = 28+12+14+5+7.5 = 66.5
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { fromMock, updateFn } = buildScoringMock({
      callExperienceSurveys: [{ score: 4 }], // 4*20=80
      satisfactionSurveys: [{ score: 7 }],   // 7*10=70
      leadEvaluations: [
        { conversion_declared: true },
        { conversion_declared: false },
      ], // hire_rate = 50
      mostRecentBookingScheduledAt: new Date(Date.now() - 105 * 86400000).toISOString(), // recency ~50
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'My bio',
        profile: {
          portfolio_items: [{ title: 'P1' }, { title: 'P2' }, { title: 'P3' }],
          linkedin_url: 'https://linkedin.com/in/expert',
          years_experience: 2, // fails criterion 4 → trust = 80
          certifications: [], // empty → fails criterion 5 → trust = 60
        },
      },
    });

    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call=80, trust=60, satisfaction=70, hire=50, recency≈50
    // composite ≈ 28+12+14+5+7.5 = 66.5
    const updateArgs = updateFn.mock.calls[0]![0] as { composite_score: number };
    expect(updateArgs.composite_score).toBeCloseTo(66.5, 0);
    expect(message.ack).toHaveBeenCalledOnce();
    expect(kv.put).toHaveBeenCalledWith('idem:score-computation:msg-1', '1', { expirationTtl: 86400 });
  });

  // ── all 3 message types route to same compute path ────────────────────────

  it('feedback.project_satisfaction — routes to same computeAndSaveCompositeScore', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const { fromMock, updateFn } = buildScoringMock({
      expertProfile: { verified_at: null, bio: null, profile: null },
    });
    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    await consumeScoreComputation(makeBatch([makeMockMessage(body)]), env);
    expect(updateFn).toHaveBeenCalled();
  });

  it('feedback.lead_evaluation — routes to same computeAndSaveCompositeScore', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const { fromMock, updateFn } = buildScoringMock({
      expertProfile: { verified_at: null, bio: null, profile: null },
    });
    vi.mocked(createServiceClient).mockReturnValue({ from: fromMock } as unknown as ReturnType<typeof createServiceClient>);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    await consumeScoreComputation(makeBatch([makeMockMessage(body)]), env);
    expect(updateFn).toHaveBeenCalled();
  });
});
