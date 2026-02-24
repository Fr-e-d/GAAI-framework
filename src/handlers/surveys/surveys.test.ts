// ── E06S17: Survey submission endpoints — unit tests ──────────────────────────
// Tests: AC1 (call-experience), AC2 (project-satisfaction), AC3 (lead evaluation)
// Covers: happy path, duplicate (409), invalid token (401), invalid input (422),
//         expert ownership violation (403).

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleCallExperienceSurvey } from './call-experience';
import { handleProjectSatisfactionSurvey } from './project-satisfaction';
import { handleLeadEvaluation } from '../evaluations/lead';
import type { Env } from '../../types/env';
import { signSurveyToken } from '../../lib/jwt';

// ── Mocks ─────────────────────────────────────────────────────────────────────

vi.mock('../../lib/supabase', () => ({
  createServiceClient: vi.fn(),
}));

vi.mock('../../middleware/auth', () => ({
  authenticate: vi.fn(),
}));

vi.mock('posthog-node', () => ({
  PostHog: vi.fn().mockImplementation(() => ({
    captureImmediate: vi.fn().mockResolvedValue(undefined),
  })),
}));

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

import { createServiceClient } from '../../lib/supabase';
import { authenticate } from '../../middleware/auth';

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEST_SECRET = 'test-survey-secret-32-bytes-long!!';
const TEST_BOOKING_ID = 'f47ac10b-58cc-4372-a567-0e02b2c3d001';
const TEST_PROSPECT_ID = 'f47ac10b-58cc-4372-a567-0e02b2c3d002';
const TEST_EXPERT_ID = 'f47ac10b-58cc-4372-a567-0e02b2c3d003';
const TEST_MATCH_ID = 'f47ac10b-58cc-4372-a567-0e02b2c3d004';
const TEST_LEAD_ID = 'f47ac10b-58cc-4372-a567-0e02b2c3d005';

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_KEY: 'service-key',
    SURVEY_TOKEN_SECRET: TEST_SECRET,
    PROSPECT_TOKEN_SECRET: 'prospect-secret',
    SCORE_COMPUTATION: { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
    ...overrides,
  } as unknown as Env;
}

function makeRequest(body: unknown, extraHeaders: Record<string, string> = {}): Request {
  return new Request('https://api.callibrate.io', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...extraHeaders },
    body: JSON.stringify(body),
  });
}

// ── Survey DB mock builder ──────────────────────────────────────────────────

function makeSurveyDbMock({
  insertResult = { data: { id: 'survey-1' }, error: null } as { data: { id: string } | null; error: null | { code: string; message: string } },
  bookingResult = { data: { match_id: TEST_MATCH_ID }, error: null } as { data: { match_id: string } | null; error: null | { code: string; message: string } },
  matchResult = { data: { expert_id: TEST_EXPERT_ID }, error: null } as { data: { expert_id: string } | null; error: null | { code: string; message: string } },
} = {}) {
  const insertSelectSingle = vi.fn().mockResolvedValue(insertResult);
  const insertSelect = vi.fn().mockReturnValue({ single: insertSelectSingle });
  const insert = vi.fn().mockReturnValue({ select: insertSelect });

  const bookingSelectSingle = vi.fn().mockResolvedValue(bookingResult);
  const bookingSelectEq = vi.fn().mockReturnValue({ single: bookingSelectSingle });
  const bookingSelect = vi.fn().mockReturnValue({ eq: bookingSelectEq });

  const matchSelectSingle = vi.fn().mockResolvedValue(matchResult);
  const matchSelectEq = vi.fn().mockReturnValue({ single: matchSelectSingle });
  const matchSelect = vi.fn().mockReturnValue({ eq: matchSelectEq });

  vi.mocked(createServiceClient).mockReturnValue({
    from: vi.fn().mockImplementation((table: string) => {
      if (table === 'call_experience_surveys' || table === 'project_satisfaction_surveys') {
        return { insert };
      }
      if (table === 'bookings') {
        return { select: bookingSelect };
      }
      if (table === 'matches') {
        return { select: matchSelect };
      }
      return {};
    }),
  } as unknown as ReturnType<typeof createServiceClient>);

  return { insert, insertSelect, insertSelectSingle };
}

// ── Lead evaluation DB mock builder ────────────────────────────────────────

function makeLeadDbMock({
  leadResult = { data: { expert_id: TEST_EXPERT_ID }, error: null } as { data: { expert_id: string } | null; error: null | { code: string; message: string } },
  insertResult = { data: { id: 'eval-1' }, error: null } as { data: { id: string } | null; error: null | { code: string; message: string } },
} = {}) {
  const leadSelectSingle = vi.fn().mockResolvedValue(leadResult);
  const leadSelectEq = vi.fn().mockReturnValue({ single: leadSelectSingle });
  const leadSelect = vi.fn().mockReturnValue({ eq: leadSelectEq });

  const insertSelectSingle = vi.fn().mockResolvedValue(insertResult);
  const insertSelect = vi.fn().mockReturnValue({ single: insertSelectSingle });
  const insert = vi.fn().mockReturnValue({ select: insertSelect });

  vi.mocked(createServiceClient).mockReturnValue({
    from: vi.fn().mockImplementation((table: string) => {
      if (table === 'leads') return { select: leadSelect };
      if (table === 'lead_evaluations') return { insert };
      return {};
    }),
  } as unknown as ReturnType<typeof createServiceClient>);

  return { insert };
}

// ═══════════════════════════════════════════════════════════════════════════════
// AC1: POST /api/surveys/call-experience
// ═══════════════════════════════════════════════════════════════════════════════

describe('handleCallExperienceSurvey', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  it('CE1: happy path — valid token + score=4 → 201 with id', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock();

    const req = makeRequest({ token, score: 4 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(201);
    const body = await res.json() as { id: string };
    expect(body.id).toBe('survey-1');
    expect(vi.mocked(env.SCORE_COMPUTATION.send)).toHaveBeenCalledWith({
      type: 'feedback.call_experience',
      expert_id: TEST_EXPERT_ID,
    });
  });

  it('CE2: happy path — with optional comment → 201', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock();

    const req = makeRequest({ token, score: 5, comment: 'Great call!' });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(201);
  });

  it('CE3: duplicate submission → 409', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock({
      insertResult: { data: null, error: { code: '23505', message: 'unique violation' } },
    });

    const req = makeRequest({ token, score: 3 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(409);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Already submitted');
  });

  it('CE4: invalid token (bad signature) → 401', async () => {
    const env = makeEnv();
    const req = makeRequest({ token: 'bad.token.here', score: 4 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(401);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('CE5: expired token → 401', async () => {
    // Create an expired token manually (exp in the past)
    const encoder = new TextEncoder();
    function toBase64Url(buf: ArrayBuffer): string {
      const bytes = new Uint8Array(buf);
      let b = '';
      for (const byte of bytes) b += String.fromCharCode(byte);
      return btoa(b).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    }
    const exp = Math.floor(Date.now() / 1000) - 1; // already expired
    const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).buffer as ArrayBuffer);
    const payload = toBase64Url(encoder.encode(JSON.stringify({ booking_id: TEST_BOOKING_ID, prospect_id: TEST_PROSPECT_ID, exp })).buffer as ArrayBuffer);
    const signingInput = `${header}.${payload}`;
    const key = await crypto.subtle.importKey('raw', encoder.encode(TEST_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const sig = toBase64Url(await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput)));
    const expiredToken = `${signingInput}.${sig}`;

    const env = makeEnv();
    const req = makeRequest({ token: expiredToken, score: 4 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(401);
  });

  it('CE6: score out of range (6 > max 5) → 422', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    const req = makeRequest({ token, score: 6 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(422);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('CE7: score out of range (0 < min 1) → 422', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    const req = makeRequest({ token, score: 0 });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(422);
  });

  it('CE8: missing score → 422', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    const req = makeRequest({ token });
    const res = await handleCallExperienceSurvey(req, env, mockCtx);

    expect(res.status).toBe(422);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// AC2: POST /api/surveys/project-satisfaction
// ═══════════════════════════════════════════════════════════════════════════════

describe('handleProjectSatisfactionSurvey', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  it('PS1: happy path — valid token + score=8 → 201 with id', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock();

    const req = makeRequest({ token, score: 8 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(201);
    const body = await res.json() as { id: string };
    expect(body.id).toBe('survey-1');
    expect(vi.mocked(env.SCORE_COMPUTATION.send)).toHaveBeenCalledWith({
      type: 'feedback.project_satisfaction',
      expert_id: TEST_EXPERT_ID,
    });
  });

  it('PS2: happy path — score=10 (max) → 201', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock();

    const req = makeRequest({ token, score: 10 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(201);
  });

  it('PS3: duplicate submission → 409', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    makeSurveyDbMock({
      insertResult: { data: null, error: { code: '23505', message: 'unique violation' } },
    });

    const req = makeRequest({ token, score: 7 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(409);
  });

  it('PS4: invalid token → 401', async () => {
    const env = makeEnv();
    const req = makeRequest({ token: 'invalid.token.here', score: 8 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(401);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('PS5: score 11 (> max 10) → 422', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    const req = makeRequest({ token, score: 11 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(422);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('PS6: score 0 (< min 1) → 422', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const env = makeEnv();
    const req = makeRequest({ token, score: 0 });
    const res = await handleProjectSatisfactionSurvey(req, env);

    expect(res.status).toBe(422);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// AC3/AC6: POST /api/evaluations/lead
// ═══════════════════════════════════════════════════════════════════════════════

describe('handleLeadEvaluation', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  function mockAuthenticateOk(expertId = TEST_EXPERT_ID) {
    vi.mocked(authenticate).mockResolvedValue({
      user: { id: expertId, email: 'expert@example.com' },
    });
  }

  function mockAuthenticateFail() {
    vi.mocked(authenticate).mockResolvedValue({
      response: new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 }),
    });
  }

  it('LE1: happy path — valid auth + lead ownership → 201', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    makeLeadDbMock();

    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 8 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(201);
    const body = await res.json() as { id: string };
    expect(body.id).toBe('eval-1');
    expect(vi.mocked(env.SCORE_COMPUTATION.send)).toHaveBeenCalledWith({
      type: 'feedback.lead_evaluation',
      expert_id: TEST_EXPERT_ID,
    });
  });

  it('LE2: happy path — with notes + conversion_declared → 201', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    makeLeadDbMock();

    const req = makeRequest({
      lead_id: TEST_LEAD_ID,
      score: 7,
      notes: 'Good project',
      conversion_declared: true,
    });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(201);
  });

  it('LE3: duplicate submission → 409', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    makeLeadDbMock({
      insertResult: { data: null, error: { code: '23505', message: 'unique violation' } },
    });

    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 8 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(409);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Already submitted');
  });

  it('LE4: no Authorization header → 401 from authenticate()', async () => {
    mockAuthenticateFail();
    const env = makeEnv();
    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 8 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(401);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('LE5: score 11 (> max 10) → 422', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 11 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(422);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('LE6: score 0 (< min 1) → 422', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 0 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(422);
  });

  it('LE7: invalid lead_id (not a UUID) → 422', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    const req = makeRequest({ lead_id: 'not-a-uuid', score: 8 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(422);
    expect(createServiceClient).not.toHaveBeenCalled();
  });

  it('LE8: expert ownership violation — lead belongs to other expert → 403', async () => {
    const otherExpertId = '00000000-0000-0000-0000-000000000099';
    mockAuthenticateOk(otherExpertId); // auth as otherExpert
    const env = makeEnv();
    makeLeadDbMock({
      // lead.expert_id is TEST_EXPERT_ID, not otherExpertId
      leadResult: { data: { expert_id: TEST_EXPERT_ID }, error: null },
    });

    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 7 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(403);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Forbidden');
  });

  it('LE9: lead not found → 404', async () => {
    mockAuthenticateOk();
    const env = makeEnv();
    makeLeadDbMock({
      leadResult: { data: null, error: { code: 'PGRST116', message: 'No rows' } },
    });

    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 8 });
    const res = await handleLeadEvaluation(req, env, mockCtx);

    expect(res.status).toBe(404);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Lead not found');
  });

  it('LE10: queue dispatch called with correct expert_id', async () => {
    mockAuthenticateOk(TEST_EXPERT_ID);
    const env = makeEnv();
    makeLeadDbMock();

    const req = makeRequest({ lead_id: TEST_LEAD_ID, score: 9 });
    await handleLeadEvaluation(req, env, mockCtx);

    expect(vi.mocked(env.SCORE_COMPUTATION.send)).toHaveBeenCalledWith({
      type: 'feedback.lead_evaluation',
      expert_id: TEST_EXPERT_ID,
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// verifySurveyToken unit tests (AC4)
// ═══════════════════════════════════════════════════════════════════════════════

import { verifySurveyToken } from '../../lib/jwt';

describe('verifySurveyToken', () => {
  it('VT1: valid token → returns claims', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const claims = await verifySurveyToken(token, TEST_SECRET);
    expect(claims).not.toBeNull();
    expect(claims?.booking_id).toBe(TEST_BOOKING_ID);
    expect(claims?.prospect_id).toBe(TEST_PROSPECT_ID);
  });

  it('VT2: wrong secret → null', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const claims = await verifySurveyToken(token, 'wrong-secret');
    expect(claims).toBeNull();
  });

  it('VT3: malformed token (2 parts) → null', async () => {
    const claims = await verifySurveyToken('a.b', TEST_SECRET);
    expect(claims).toBeNull();
  });

  it('VT4: tampered payload → null', async () => {
    const token = await signSurveyToken(TEST_BOOKING_ID, TEST_PROSPECT_ID, TEST_SECRET);
    const parts = token.split('.');
    // Replace the payload with tampered data (different prospect_id)
    const tampered = `${parts[0]}.${btoa(JSON.stringify({ booking_id: TEST_BOOKING_ID, prospect_id: 'tampered', exp: Math.floor(Date.now() / 1000) + 86400 }))}.${parts[2]}`;
    const claims = await verifySurveyToken(tampered, TEST_SECRET);
    expect(claims).toBeNull();
  });
});
