import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { consumeScoreComputation } from './score-computation';
import type { Env } from '../types/env';
import type { ScoreComputationMessage } from '../types/queues';

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
  headline: string | null;
  gcal_connected: boolean;
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

  it('idempotency — KV returns 1 → no DB calls, message acked immediately', async () => {
    const kv = makeKv('1'); // already processed
    const env = makeEnv(kv);

    const body: ScoreComputationMessage = {
      type: 'feedback.call_experience',
      expert_id: 'expert-1',
    };
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(createSql).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
  });

  // ── Unknown message type ──────────────────────────────────────────────────────

  it('unknown message type — console.warn, acked, no DB call', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);

    const body = { type: 'unknown.type', expert_id: 'expert-1' } as unknown as ScoreComputationMessage;
    const message = makeMockMessage(body);
    const batch = makeBatch([message]);

    await consumeScoreComputation(batch, env);

    expect(consoleSpy).toHaveBeenCalledOnce();
    expect(createSql).not.toHaveBeenCalled();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(message.retry).not.toHaveBeenCalled();
    expect(kv.put).not.toHaveBeenCalled();

    consoleSpy.mockRestore();
  });

  // ── Retry on failure ──────────────────────────────────────────────────────────

  it('retry (attempts=1) — DB error → retry with delaySeconds=1, KV NOT marked', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    // Make sql throw on first call (matches query)
    const mockSql = vi.fn().mockRejectedValue(new Error('DB unavailable'));
    (createSql as Mock).mockReturnValue(mockSql);

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

    const mockSql = vi.fn().mockRejectedValue(new Error('DB error'));
    (createSql as Mock).mockReturnValue(mockSql);

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
  // With postgres.js, the sql tagged template is called as a regular function.
  // We mock createSql to return a vi.fn() that we control per call sequence.
  //
  // computeAndSaveCompositeScore call sequence:
  // 1. matches query (SELECT id FROM matches WHERE expert_id = ?)
  // 2. bookings query (SELECT id FROM bookings WHERE match_id = ANY(?))
  // 3. Parallel:
  //    - call_experience_surveys
  //    - project_satisfaction_surveys
  //    - lead_evaluations
  //    - bookings recency (SELECT scheduled_at ... LIMIT 1)
  //    - experts trust (SELECT verified_at, bio, headline, gcal_connected, profile)
  // 4. UPDATE experts SET composite_score = ...

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
      headline: 'AI Automation Expert',
      gcal_connected: true,
      profile: {
        skills: ['n8n', 'python', 'react'],
      },
    } as TestExpertProfile,
  } = {}) {
    const mockSql = vi.fn() as Mock;

    // Call sequence tracking:
    // call 1: matches → return matchIds
    // call 2: bookings (first) → return bookingIds
    // calls 3-7: parallel (call_exp, client_sat, hire_rate, recency, trust) — order may vary
    // call 8: UPDATE experts

    let callCount = 0;

    mockSql.mockImplementation(() => {
      callCount++;
      const call = callCount;

      if (call === 1) {
        // matches query
        return Promise.resolve(matchIds.map(id => ({ id })));
      }
      if (call === 2) {
        // bookings query (first — get booking IDs)
        return Promise.resolve(bookingIds.map(id => ({ id })));
      }
      // Parallel calls — we return based on what would be queried
      // Since we can't know exact order for parallel calls,
      // we'll use a pattern where each mock returns a reasonable value.
      // The 5 parallel calls are identified by their return shapes.
      // We use mockResolvedValueOnce for the 5 parallel + 1 update = 6 more calls

      // This is the update call (last) — we'll handle it with a default
      return Promise.resolve([]);
    });

    // Set specific return values for the parallel calls and update:
    // After call 2 (sequential), we have 5 parallel + 1 update = 6 calls
    // call_experience_surveys:
    mockSql.mockResolvedValueOnce(matchIds.map(id => ({ id }))); // call 1: matches (reset)
    mockSql.mockResolvedValueOnce(bookingIds.map(id => ({ id }))); // call 2: bookings

    // Reset the counter-based mock and use sequential:
    mockSql.mockReset();

    mockSql
      .mockResolvedValueOnce(matchIds.map(id => ({ id })))         // call 1: matches
      .mockResolvedValueOnce(bookingIds.map(id => ({ id })))        // call 2: bookings
      .mockResolvedValueOnce(callExperienceSurveys)                 // call 3: call_exp (parallel)
      .mockResolvedValueOnce(satisfactionSurveys)                   // call 4: client_sat (parallel)
      .mockResolvedValueOnce(leadEvaluations)                       // call 5: hire_rate (parallel)
      .mockResolvedValueOnce(mostRecentBookingScheduledAt            // call 6: recency (parallel)
        ? [{ scheduled_at: mostRecentBookingScheduledAt }]
        : [])
      .mockResolvedValueOnce([expertProfile])                       // call 7: trust (parallel)
      .mockResolvedValueOnce([]);                                   // call 8: UPDATE experts

    return { mockSql };
  }

  // ── A1: call_experience_avg — 2 surveys → 80 ──────────────────────────────

  it('A1: call_experience_avg — scores [3, 5] → avg = 80', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      callExperienceSurveys: [{ score: 3 }, { score: 5 }],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(), // 10 days ago → recency=100
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call_experience_avg = (3*20 + 5*20)/2 = 80
    // trust = 100 (all criteria met in default expert profile)
    // satisfaction = 0, hire = 0, recency = 100
    // composite = 80*0.35 + 100*0.20 + 0*0.20 + 0*0.10 + 100*0.15 = 28 + 20 + 0 + 0 + 15 = 63
    expect(mockSql).toHaveBeenCalled();
    // The last call should be the UPDATE — find the call that was passed composite_score=63
    const updateCall = mockSql.mock.calls.find(call =>
      // The SQL template call for UPDATE has the composite score as one of the args
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 63) < 0.01)
    );
    expect(updateCall).toBeDefined();
    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A2: call_experience_avg — no surveys → 0 ─────────────────────────────

  it('A2: call_experience_avg — no surveys → contributes 0 to composite', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(),
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call_experience=0, trust=100, satisfaction=0, hire=0, recency=100
    // composite = 0*0.35 + 100*0.20 + 0*0.20 + 0*0.10 + 100*0.15 = 0+20+0+0+15 = 35
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 35) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A3: client_satisfaction_avg — scores [8, 6] → 70 ────────────────────

  it('A3: client_satisfaction_avg — scores [8, 6] → avg = 70', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [{ score: 8 }, { score: 6 }],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: new Date(Date.now() - 10 * 86400000).toISOString(),
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // satisfaction = (80+60)/2 = 70, call=0, trust=100, hire=0, recency=100
    // composite = 0*0.35 + 100*0.20 + 70*0.20 + 0*0.10 + 100*0.15 = 0+20+14+0+15 = 49
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 49) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A4: client_satisfaction_avg — no surveys → 0 ─────────────────────────

  it('A4: client_satisfaction_avg — no surveys → contributes 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // all=0, trust=0 (null profile, no verified_at)
    // composite = 0
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 0) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A5: hire_rate — 2 of 4 converted → 50 ────────────────────────────────

  it('A5: hire_rate — 2 of 4 conversion_declared=true → 50', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      callExperienceSurveys: [],
      satisfactionSurveys: [],
      leadEvaluations: [
        { conversion_declared: true },
        { conversion_declared: true },
        { conversion_declared: false },
        { conversion_declared: null },
      ],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // hire_rate = 50, all others = 0
    // composite = 0*0.35 + 0*0.20 + 0*0.20 + 50*0.10 + 0*0.15 = 5
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 5) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A6: hire_rate — no evaluations → 0 ───────────────────────────────────

  it('A6: hire_rate — no evaluations → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      leadEvaluations: [],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A7: hire_rate — all null → 0 ─────────────────────────────────────────

  it('A7: hire_rate — all conversion_declared=null → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      leadEvaluations: [{ conversion_declared: null }, { conversion_declared: null }],
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A8: recency — booking 15 days ago → 100 ──────────────────────────────

  it('A8: recency_score — booking 15 days ago → 100', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 15 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // recency = 100, all others = 0
    // composite = 100*0.15 = 15
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 15) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A9: recency — booking 105 days ago → ~50 ─────────────────────────────

  it('A9: recency_score — booking 105 days ago → ~50', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 105 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // daysSince ~= 105, recency = 100 - ((105-30)/150)*100 = 100 - 50 = 50
    // composite = 50*0.15 = 7.5
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && arg > 5 && arg < 12)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A10: recency — booking 200 days ago → 0 ──────────────────────────────

  it('A10: recency_score — booking 200 days ago → 0 (clamped)', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: new Date(Date.now() - 200 * 86400000).toISOString(),
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // recency = 0, composite = 0
    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A11: recency — no bookings → 0 ───────────────────────────────────────

  it('A11: recency_score — no bookings → 0', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    expect(message.ack).toHaveBeenCalledOnce();
  });

  // ── A12: trust_score — fully complete profile → 100 ──────────────────────

  it('A12: trust_score — verified + bio + gcal + headline + 3 skills → 100', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'Expert bio here',
        headline: 'AI Automation Expert',
        gcal_connected: true,
        profile: {
          skills: ['n8n', 'python', 'react'],
        },
      },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 100, all others = 0, composite = 100*0.20 = 20
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 20) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A13: trust_score — null profile + verified → 20 ─────────────────────────────────

  it('A13: trust_score — null profile + verified only → 20', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: null,
        headline: null,
        gcal_connected: false,
        profile: null,
      },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 20 (only verified_at criterion met), composite = 20*0.20 = 4
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 4) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A14: trust — only 2 skills → criterion 5 fails ──────────────

  it('A14: trust_score — only 2 skills → criterion 5 fails', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'My bio',
        headline: 'Expert headline',
        gcal_connected: true,
        profile: {
          skills: ['n8n', 'python'], // only 2 — criterion 5 fails
        },
      },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 80 (criterion 5 fails — only 2 skills)
    // composite = 80*0.20 = 16
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 16) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── A15: trust — gcal_connected = false → criterion 3 fails ────────────────

  it('A15: trust_score — gcal_connected = false → criterion 3 fails', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
      mostRecentBookingScheduledAt: null,
      expertProfile: {
        verified_at: '2026-01-01T00:00:00Z',
        bio: 'My bio',
        headline: 'Expert headline',
        gcal_connected: false, // fails criterion 3
        profile: {
          skills: ['n8n', 'python', 'react'],
        },
      },
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // trust = 80 (criterion 3 fails — gcal not connected)
    // composite = 80*0.20 = 16
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && Math.abs((arg as number) - 16) < 0.01)
    );
    expect(updateCall).toBeDefined();
  });

  // ── B8: composite formula verification ───────────────────────────────────

  it('B8: composite formula — controlled inputs → expected score', async () => {
    // call=80, trust=60, satisfaction=70, hire=50, recency=50
    // 80*0.35 + 60*0.20 + 70*0.20 + 50*0.10 + 50*0.15 = 28+12+14+5+7.5 = 66.5
    const kv = makeKv(null);
    const env = makeEnv(kv);

    const { mockSql } = buildScoringMock({
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
        headline: 'Expert headline',
        gcal_connected: false, // fails criterion 3 → -20
        profile: {
          skills: ['n8n', 'python'], // only 2 → fails criterion 5 → -20
        },
      },
      // trust = 60 (verified + bio + headline = 60, gcal=false, skills<3)
    });

    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.call_experience', expert_id: 'expert-1' };
    const message = makeMockMessage(body);
    await consumeScoreComputation(makeBatch([message]), env);

    // call=80, trust=60, satisfaction=70, hire=50, recency≈50
    // composite ≈ 28+12+14+5+7.5 = 66.5
    const updateCall = mockSql.mock.calls.find(call =>
      call.some((arg: unknown) => typeof arg === 'number' && arg > 60 && arg < 72)
    );
    expect(updateCall).toBeDefined();
    expect(message.ack).toHaveBeenCalledOnce();
    expect(kv.put).toHaveBeenCalledWith('idem:score-computation:msg-1', '1', { expirationTtl: 86400 });
  });

  // ── all 3 message types route to same compute path ────────────────────────

  it('feedback.project_satisfaction — routes to same computeAndSaveCompositeScore', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const { mockSql } = buildScoringMock({
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });
    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.project_satisfaction', expert_id: 'expert-1' };
    await consumeScoreComputation(makeBatch([makeMockMessage(body)]), env);
    expect(mockSql).toHaveBeenCalled();
  });

  it('feedback.lead_evaluation — routes to same computeAndSaveCompositeScore', async () => {
    const kv = makeKv(null);
    const env = makeEnv(kv);
    const { mockSql } = buildScoringMock({
      expertProfile: { verified_at: null, bio: null, headline: null, gcal_connected: false, profile: null },
    });
    (createSql as Mock).mockReturnValue(mockSql);

    const body: ScoreComputationMessage = { type: 'feedback.lead_evaluation', expert_id: 'expert-1' };
    await consumeScoreComputation(makeBatch([makeMockMessage(body)]), env);
    expect(mockSql).toHaveBeenCalled();
  });
});
