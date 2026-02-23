import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleProspectSubmit, handleProspectMatches, handleProspectIdentify } from './prospects';
import type { Env } from '../types/env';

// ── Mock Env ──────────────────────────────────────────────────────────────────

const baseMockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'test-anon-key',
  SUPABASE_SERVICE_KEY: 'test-service-key',
  OPENAI_API_KEY: 'test-openai-key',
  SESSIONS: {} as KVNamespace,
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) },
  FEATURE_FLAGS: {} as KVNamespace,
  EXPERT_POOL: {} as KVNamespace,
  PROSPECT_TOKEN_SECRET: 'test-secret-32-chars-long-padding!!',
  TURNSTILE_SECRET_KEY: '1x0000000000000000000000000000000AA',
  EMAIL_NOTIFICATIONS: { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
  LEAD_BILLING: { send: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
  SCORE_COMPUTATION: {} as unknown as Queue,
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
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
    });
    const response = await handleProspectSubmit(request, makeMockEnv());
    expect(response.status).toBe(422);
    const body = await response.json() as Record<string, unknown>;
    expect(body['error']).toBe('Validation failed');
    expect((body['details'] as Record<string, string>)['cf-turnstile-response']).toBe('required');
  });

  it('returns 422 when cf-turnstile-response is an empty string (AC4)', async () => {
    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': '',
    });
    const response = await handleProspectSubmit(request, makeMockEnv());
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

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'invalid-token',
    });
    const response = await handleProspectSubmit(request, makeMockEnv());
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

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'some-token',
    });
    const response = await handleProspectSubmit(request, makeMockEnv());
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

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': '1x0000000000000000000000000000000AA',
    });
    const response = await handleProspectSubmit(request, makeMockEnv());
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
    const response = await handleProspectSubmit(request, env);
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

    const request = makeSubmitRequest({
      satellite_id: 'sat-1',
      quiz_answers: {},
      'cf-turnstile-response': 'valid-token',
    });
    const response = await handleProspectSubmit(request, env);
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
    const response = await handleProspectMatches(request, env, 'prospect-1');
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
        body: JSON.stringify({ email: 'test@test.com', token: 'tok' }),
      }
    );
    const response = await handleProspectIdentify(request, env, 'prospect-1');
    expect(response.status).toBe(429);
  });
});
