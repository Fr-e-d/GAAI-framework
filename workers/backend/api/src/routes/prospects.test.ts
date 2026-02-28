import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleProspectSubmit, handleProspectMatches, handleProspectIdentify, handleOtpSend, handleOtpVerify, handleProspectRequirements, handleProspectProjects } from './prospects';
import type { Env } from '../types/env';

vi.mock('../lib/db', () => ({
  createSql: vi.fn(() => Object.assign((() => []) as unknown as ReturnType<typeof import('../lib/db').createSql>, { begin: vi.fn(), end: vi.fn().mockResolvedValue(undefined) })),
}));

// Mock matches module so handleProspectRequirements doesn't trigger real compute
vi.mock('./matches', () => ({
  handleMatchCompute: vi.fn().mockResolvedValue(new Response(JSON.stringify({ computed: 0 }), { status: 200 })),
  handleMatchGet: vi.fn(),
}));

const mockCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;

// ── Mock Env ──────────────────────────────────────────────────────────────────

const baseMockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'test-anon-key',
  SUPABASE_SERVICE_KEY: 'test-service-key',
  OPENAI_API_KEY: 'test-openai-key',
  SESSIONS: {} as KVNamespace,
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) },
  FEATURE_FLAGS: {} as KVNamespace,
  PROSPECT_TOKEN_SECRET: 'test-secret-32-chars-long-padding!!',
  TURNSTILE_SECRET_KEY: '1x0000000000000000000000000000000AA',
  EMAIL_NOTIFICATIONS: { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
  LEAD_BILLING: { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
  SCORE_COMPUTATION: {} as unknown as Queue,
  HYPERDRIVE: { connectionString: 'postgresql://test:test@localhost:5432/test' },
  GOOGLE_CLIENT_ID: '',
  GOOGLE_CLIENT_SECRET: '',
  GCAL_TOKEN_ENCRYPTION_KEY: '',
  WORKER_BASE_URL: 'https://test.workers.dev',
  RESEND_API_KEY: '',
  LEMON_SQUEEZY_API_KEY: '',
  N8N_WEBHOOK_URL: '',
  EMAIL_FROM_DOMAIN: 'send.test.io',
  EMAIL_REPLY_TO: 'support@test.io',
};

function makeMockEnv(overrides?: Partial<typeof baseMockEnv>): Env {
  return { ...baseMockEnv, ...overrides } as unknown as Env;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeSubmitRequest(body: Record<string, unknown>, ip = '1.2.3.4'): Request {
  return new Request('https://test.workers.dev/api/prospects/submit', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'CF-Connecting-IP': ip,
    },
    body: JSON.stringify(body),
  });
}

function postgrestResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Content-Range': '0-0/*' },
  });
}

// ── Tests: handleProspectSubmit — Turnstile validation ────────────────────────

describe('handleProspectSubmit — Turnstile validation', () => {
  beforeEach(() => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : (input as Request).url;
      if (url.includes('siteverify')) {
        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return postgrestResponse({ quiz_schema: { fields: [] }, matching_weights: null });
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 422 when cf-turnstile-response is absent from body (AC4)', async () => {
    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-001', 'test-secret-32-chars-long-padding!!');
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      flow_token,
    });
    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Validation failed');
    expect((body['details'] as Record<string, string>)['cf-turnstile-response']).toBe('required');
  });

  it('returns 422 when cf-turnstile-response is an empty string (AC4)', async () => {
    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-002', 'test-secret-32-chars-long-padding!!');
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': '',
      flow_token,
    });
    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Validation failed');
  });

  it('returns 422 with "Bot verification failed" when siteverify returns success: false (AC7)', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : (input as Request).url;
      if (url.includes('siteverify')) {
        return new Response(JSON.stringify({ success: false }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return postgrestResponse({});
    });

    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-003', 'test-secret-32-chars-long-padding!!');
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'invalid-token',
      flow_token,
    });
    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Bot verification failed');
  });

  it('returns 422 with "Bot verification failed" when siteverify fetch throws (AC7)', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : (input as Request).url;
      if (url.includes('siteverify')) {
        throw new Error('Network error');
      }
      return postgrestResponse({});
    });

    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-004', 'test-secret-32-chars-long-padding!!');
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'some-token',
      flow_token,
    });
    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Bot verification failed');
  });

  it('passes Turnstile check and proceeds past bot protection when token is valid (AC5, AC6)', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : (input as Request).url;
      if (url.includes('siteverify')) {
        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return postgrestResponse(null, 200);
    });

    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-abc', 'test-secret-32-chars-long-padding!!');

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': '1x0000000000000000000000000000000AA',
      flow_token,
    });
    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    // Must NOT be a Turnstile 422
    if (response.status === 422) {
      const body = await response.json() as Record<string, unknown>;
      expect(body['error']).not.toBe('Bot verification failed');
    }
    // Accept 404 (satellite not found) or 500 (DB error in test) — proves Turnstile passed
    expect([404, 500, 422]).toContain(response.status);
  });
});

// ── Tests: handleProspectSubmit — Rate Limiting ───────────────────────────────

describe('handleProspectSubmit — Rate Limiting', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 429 when RATE_LIMITER.limit() returns success: false (AC3)', async () => {
    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) },
    });

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'some-token',
    });
    const response = await handleProspectSubmit(request, env, mockCtx);
    expect(response.status).toBe(429);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Too Many Requests');
  });

  it('passes rate limit check when RATE_LIMITER.limit() returns success: true (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : (input as Request).url;
      if (url.includes('siteverify')) {
        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return postgrestResponse(null, 200);
    });

    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) },
    });

    const { signFlowToken } = await import('../lib/jwt');
    const flow_token = await signFlowToken('extraction-xyz', env.PROSPECT_TOKEN_SECRET);

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'valid-token',
      flow_token,
    });
    const response = await handleProspectSubmit(request, env, mockCtx);
    expect(response.status).not.toBe(429);
  });
});

// ── Tests: handleProspectMatches — Rate Limiting ──────────────────────────────

describe('handleProspectMatches — Rate Limiting', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 429 when rate limited (AC3)', async () => {
    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) },
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/matches?token=sometoken',
      { headers: { 'CF-Connecting-IP': '1.2.3.4' } }
    );
    const response = await handleProspectMatches(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
  });
});

// ── Tests: handleProspectIdentify — Rate Limiting ─────────────────────────────

describe('handleProspectIdentify — Rate Limiting', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 429 when rate limited (AC3)', async () => {
    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) },
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/identify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ token: 'tok' }),
      }
    );
    const response = await handleProspectIdentify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
  });
});

// ── E06S39: handleProspectIdentify — OTP guard ────────────────────────────────

describe('handleProspectIdentify — OTP verification guard (E06S39 AC7)', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 403 "OTP verification required" when no verified KV record exists (AC7)', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });

    // We need a valid prospect token — build a real one
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/identify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ token }),
      }
    );
    const response = await handleProspectIdentify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(403);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('OTP verification required');
  });

  it('returns 403 when prospect token is missing (AC7)', async () => {
    const env = makeMockEnv({
      SESSIONS: { get: vi.fn().mockResolvedValue(null) } as unknown as KVNamespace,
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/identify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({}),
      }
    );
    const response = await handleProspectIdentify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(403);
  });
});

// ── E06S39: handleOtpSend — Rate Limiting ─────────────────────────────────────

describe('handleOtpSend — Rate Limiting (E06S39 AC5)', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 429 when global rate limiter blocks the request (AC5)', async () => {
    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) },
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/send',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ email: 'test@example.com', token: 'tok' }),
      }
    );
    const response = await handleOtpSend(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
  });

  it('returns 403 when prospect token is missing (AC5)', async () => {
    const env = makeMockEnv();

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/send',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ email: 'test@example.com' }),
      }
    );
    const response = await handleOtpSend(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(403);
  });

  it('returns 422 when email is missing (AC5)', async () => {
    const env = makeMockEnv();
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/send',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ token }),
      }
    );
    const response = await handleOtpSend(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Validation failed');
  });

  it('returns 422 for invalid email syntax after pre-check (AC4, AC5)', async () => {
    const env = makeMockEnv();
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/send',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ email: 'notanemail', token }),
      }
    );
    const response = await handleOtpSend(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toContain('Invalid email address');
  });

  it('returns 422 for disposable email domain (AC4, AC5)', async () => {
    const env = makeMockEnv();
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    // Mock MX check to pass for mailinator.com so it reaches the disposable check
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ Status: 0, Answer: [{ type: 15, data: '10 mx.mailinator.com.' }] }), {
        status: 200, headers: { 'Content-Type': 'application/json' }
      })
    );

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/send',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ email: 'user@mailinator.com', token }),
      }
    );
    const response = await handleOtpSend(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toContain('Disposable');
  });
});

// ── E06S39: handleOtpVerify — Core flow ──────────────────────────────────────

describe('handleOtpVerify — Core flow (E06S39 AC6)', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns 429 when global rate limiter blocks the request (AC6)', async () => {
    const env = makeMockEnv({
      RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) },
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code: '123456', token: 'tok' }),
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
  });

  it('returns 403 when prospect token is missing (AC6)', async () => {
    const env = makeMockEnv({
      SESSIONS: { get: vi.fn().mockResolvedValue(null) } as unknown as KVNamespace,
    });

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code: '123456' }),
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(403);
  });

  it('returns 410 when no OTP record found in KV (AC6)', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code: '123456', token }),
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(410);
    const body = await response.json() as Record<string, unknown>;
    expect((body['error'] as string).toLowerCase()).toContain('expired');
  });

  it('returns verified=false with remaining_attempts when code is wrong (AC6)', async () => {
    const { hashOtp } = await import('../lib/otp');
    const storedHash = await hashOtp('000000');
    const otpRecord = JSON.stringify({ hash: storedHash, email: 'test@example.com', attempts: 0 });

    const mockSessions = {
      get: vi.fn().mockResolvedValue(otpRecord),
      put: vi.fn().mockResolvedValue(undefined),
      delete: vi.fn().mockResolvedValue(undefined),
    };
    const env = makeMockEnv({
      SESSIONS: mockSessions as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code: '999999', token }), // wrong code
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body['verified']).toBe(false);
    expect(typeof body['remaining_attempts']).toBe('number');
  });

  it('returns verified=true with email when correct code submitted (AC6)', async () => {
    const { generateOtp } = await import('../lib/otp');
    const { code, hash } = await generateOtp();
    const otpRecord = JSON.stringify({ hash, email: 'user@example.com', attempts: 0 });

    const mockSessions = {
      get: vi.fn().mockResolvedValue(otpRecord),
      put: vi.fn().mockResolvedValue(undefined),
      delete: vi.fn().mockResolvedValue(undefined),
    };
    const env = makeMockEnv({
      SESSIONS: mockSessions as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code, token }),
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body['verified']).toBe(true);
    expect(body['email']).toBe('user@example.com');
    // verified KV token should be stored
    expect(mockSessions.put).toHaveBeenCalledWith(
      `verified:prospect-1`,
      expect.stringContaining('user@example.com'),
      expect.objectContaining({ expirationTtl: 300 })
    );
    // OTP record should be deleted
    expect(mockSessions.delete).toHaveBeenCalledWith('otp:prospect-1');
  });

  it('blocks after 5 failed attempts and deletes OTP record (AC6)', async () => {
    const { hashOtp } = await import('../lib/otp');
    const storedHash = await hashOtp('000000');
    // 5 attempts already made
    const otpRecord = JSON.stringify({ hash: storedHash, email: 'test@example.com', attempts: 5 });

    const mockSessions = {
      get: vi.fn().mockResolvedValue(otpRecord),
      put: vi.fn(),
      delete: vi.fn().mockResolvedValue(undefined),
    };
    const env = makeMockEnv({
      SESSIONS: mockSessions as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = new Request(
      'https://test.workers.dev/api/prospects/prospect-1/otp/verify',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '1.2.3.4' },
        body: JSON.stringify({ code: '111111', token }),
      }
    );
    const response = await handleOtpVerify(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
    expect(mockSessions.delete).toHaveBeenCalledWith('otp:prospect-1');
  });
});

// ── handleProspectRequirements — POST /api/prospects/:id/requirements ──────────
// E03S08 (AC5): Update prospect requirements + async re-match

describe('handleProspectRequirements — POST /api/prospects/:id/requirements', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  function makeRequirementsRequest(
    body: Record<string, unknown>,
    ip = '1.2.3.4'
  ): Request {
    return new Request(
      'https://test.workers.dev/api/prospects/prospect-1/requirements',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'CF-Connecting-IP': ip,
        },
        body: JSON.stringify(body),
      }
    );
  }

  it('returns 403 when token is invalid', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const request = makeRequirementsRequest({
      requirements: { skills_needed: ['n8n'] },
      token: 'invalid-token',
    });
    const response = await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(403);
  });

  it('returns 400 when body is missing requirements', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({ token });
    const response = await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Validation failed');
  });

  it('returns 422 when requirements is not an object', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({ requirements: 'not-an-object', token });
    const response = await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(422);
  });

  it('returns 429 when rate limit exceeded (rematch count > 5)', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        // Return count > 5 for rematch-count key
        get: vi.fn().mockResolvedValue('6'),
        put: vi.fn(),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({
      requirements: { skills_needed: ['n8n'] },
      token,
    });
    const response = await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(429);
  });

  it('returns 202 with { status: "recomputing" } on success', async () => {
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue('0'), // rematch count = 0
        put: vi.fn().mockResolvedValue(undefined),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({
      requirements: { skills_needed: ['n8n'], industry: 'E-commerce' },
      token,
    });
    const response = await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(response.status).toBe(202);
    const body = await response.json() as Record<string, unknown>;
    expect(body['status']).toBe('recomputing');
  });

  it('increments rematch counter in KV on success', async () => {
    const mockPut = vi.fn().mockResolvedValue(undefined);
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue('2'), // existing count
        put: mockPut,
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({
      requirements: { industry: 'SaaS' },
      token,
    });
    await handleProspectRequirements(request, env, 'prospect-1', mockCtx);
    expect(mockPut).toHaveBeenCalledWith(
      'rematch-count:prospect-1',
      '3',
      expect.objectContaining({ expirationTtl: 86400 })
    );
  });

  it('triggers async match recompute via ctx.waitUntil', async () => {
    const waitUntilMock = vi.fn();
    const ctx = { waitUntil: waitUntilMock, passThroughOnException: vi.fn() } as unknown as ExecutionContext;
    const env = makeMockEnv({
      SESSIONS: {
        get: vi.fn().mockResolvedValue('0'),
        put: vi.fn().mockResolvedValue(undefined),
        delete: vi.fn(),
      } as unknown as KVNamespace,
    });
    const { signProspectToken } = await import('../lib/jwt');
    const { token } = await signProspectToken('prospect-1', env.PROSPECT_TOKEN_SECRET, 'prospect:submit');

    const request = makeRequirementsRequest({
      requirements: { skills_needed: ['Make'] },
      token,
    });
    await handleProspectRequirements(request, env, 'prospect-1', ctx);
    expect(waitUntilMock).toHaveBeenCalled();
  });
});

// ── Tests: E06S41 — identified fast-track (project 2+) ────────────────────────

describe('handleProspectSubmit — identified fast-track (E06S41 AC5/AC9)', () => {
  it('routes to fast-track when Authorization carries valid prospect:submit JWT', async () => {
    // This test verifies the routing decision — mock sql returns [] for all queries
    // so the fast-track will return 404 ("Prospect not found") which proves we entered
    // the identified path (the anonymous path would reject with invalid_flow_token first)
    const { signProspectToken } = await import('../lib/jwt');
    const prospectId = '00000000-0000-0000-0000-000000000001';
    const { token } = await signProspectToken(prospectId, 'test-secret-32-chars-long-padding!!', 'prospect:submit');

    const request = new Request('https://test.workers.dev/api/prospects/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '1.2.3.4',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({
        satellite_id: 'sat-1',
        quiz_answers: { challenge: 'test', skills_needed: ['python'] },
      }),
    });

    const response = await handleProspectSubmit(request, makeMockEnv(), mockCtx);
    // With mocked DB (returns []), prospect not found → 404 from fast-track
    expect(response.status).toBe(404);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Prospect not found');
  });
});

// ── Tests: E06S41 — handleProspectProjects ────────────────────────────────────

describe('handleProspectProjects (E06S41 AC8)', () => {
  it('returns 403 without Authorization header', async () => {
    const request = new Request('https://test.workers.dev/api/prospects/test-id/projects', {
      method: 'GET',
      headers: { 'CF-Connecting-IP': '1.2.3.4' },
    });

    const response = await handleProspectProjects(request, makeMockEnv(), 'test-id', mockCtx);
    expect(response.status).toBe(403);
  });

  it('returns 403 with invalid token', async () => {
    const request = new Request('https://test.workers.dev/api/prospects/test-id/projects', {
      method: 'GET',
      headers: {
        'CF-Connecting-IP': '1.2.3.4',
        'Authorization': 'Bearer invalid-token',
      },
    });

    const response = await handleProspectProjects(request, makeMockEnv(), 'test-id', mockCtx);
    expect(response.status).toBe(403);
  });

  it('returns empty projects list with valid token and mocked DB', async () => {
    const { signProspectToken } = await import('../lib/jwt');
    const prospectId = '00000000-0000-0000-0000-000000000002';
    const { token } = await signProspectToken(prospectId, 'test-secret-32-chars-long-padding!!', 'prospect:submit');

    const request = new Request(`https://test.workers.dev/api/prospects/${prospectId}/projects`, {
      method: 'GET',
      headers: {
        'CF-Connecting-IP': '1.2.3.4',
        'Authorization': `Bearer ${token}`,
      },
    });

    const response = await handleProspectProjects(request, makeMockEnv(), prospectId, mockCtx);
    expect(response.status).toBe(200);
    const body = await response.json() as { projects: unknown[] };
    expect(Array.isArray(body.projects)).toBe(true);
    expect(body.projects).toHaveLength(0);
  });
});

// ── Tests: E06S41 — Anti-abuse (AC10/AC11) ───────────────────────────────────

describe('handleProspectSubmit — anti-abuse max projects (E06S41 AC10)', () => {
  it('returns 429 max_projects_exceeded when 5 active projects exist', async () => {
    const { signProspectToken } = await import('../lib/jwt');
    const prospectId = '00000000-0000-0000-0000-000000000003';
    const { token } = await signProspectToken(prospectId, 'test-secret-32-chars-long-padding!!', 'prospect:submit');

    // Mock DB: prospect found + has email + count returns 5
    const { createSql } = await import('../lib/db');
    let callCount = 0;
    (createSql as ReturnType<typeof vi.fn>).mockImplementation(() => {
      const mockSql = Object.assign(
        (async () => {
          callCount++;
          if (callCount === 1) return [{ id: prospectId, email: 'user@test.com' }]; // prospect
          if (callCount === 2) return [{ count: '5' }]; // active project count
          return [];
        }) as unknown as ReturnType<typeof import('../lib/db').createSql>,
        { begin: vi.fn(), end: vi.fn().mockResolvedValue(undefined) },
      );
      return mockSql;
    });

    const mockEnvSessions = {
      ...baseMockEnv,
      SESSIONS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined),
        delete: vi.fn().mockResolvedValue(undefined),
      },
    };

    const request = new Request('https://test.workers.dev/api/prospects/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '1.2.3.4',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({
        satellite_id: 'sat-1',
        quiz_answers: { challenge: 'test', skills_needed: ['python'] },
      }),
    });

    const response = await handleProspectSubmit(request, makeMockEnv(mockEnvSessions as any), mockCtx);
    expect(response.status).toBe(429);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('max_projects_exceeded');

    // Restore default mock
    (createSql as ReturnType<typeof vi.fn>).mockImplementation(() =>
      Object.assign((() => []) as unknown as ReturnType<typeof import('../lib/db').createSql>, {
        begin: vi.fn(),
        end: vi.fn().mockResolvedValue(undefined),
      }),
    );
  });
});
