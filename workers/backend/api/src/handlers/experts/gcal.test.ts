import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from 'vitest';
import { handleGcalAuthUrl, handleGcalStatus, handleGcalCallback, handleGcalDisconnect } from './gcal';

// ── Mock db ────────────────────────────────────────────────────────────────────

vi.mock('../../lib/db', () => ({
  createSql: vi.fn(),
}));

import { createSql } from '../../lib/db';

vi.mock('posthog-node', () => ({
  PostHog: vi.fn().mockImplementation(() => ({
    captureImmediate: vi.fn().mockResolvedValue(undefined),
  })),
}));

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

// ── SESSIONS KV mock ──────────────────────────────────────────────────────────

let mockSessionsStore: Map<string, string>;
const mockSessions = {
  put: vi.fn(),
  get: vi.fn(),
  delete: vi.fn(),
  list: vi.fn(),
  getWithMetadata: vi.fn(),
};

// ── Minimal mock Env ──────────────────────────────────────────────────────────

const mockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_KEY: 'service-key',
  GOOGLE_CLIENT_ID: 'test-client-id',
  GOOGLE_CLIENT_SECRET: 'test-client-secret',
  // Valid AES-256 key: 32 bytes base64-encoded
  GCAL_TOKEN_ENCRYPTION_KEY: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  WORKER_BASE_URL: 'https://callibrate-core-staging.test.workers.dev',
  ANTHROPIC_API_KEY: '',
  CLOUDFLARE_AI_GATEWAY_URL: '',
  PROSPECT_TOKEN_SECRET: '',
  SESSIONS: mockSessions as unknown as KVNamespace,
  RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: true }) } as unknown as RateLimit,
  FEATURE_FLAGS: {} as KVNamespace,
  EMAIL_NOTIFICATIONS: {} as Queue,
  LEAD_BILLING: {} as Queue,
};

const mockUser = { id: 'expert-uuid-123', email: 'expert@example.com' };
const expertId = 'expert-uuid-123';

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
  vi.clearAllMocks();

  // Reset KV store and configure mock implementations
  mockSessionsStore = new Map();
  mockSessions.put.mockImplementation(async (key: string, value: string) => {
    mockSessionsStore.set(key, value);
  });
  mockSessions.get.mockImplementation(async (key: string) => {
    return mockSessionsStore.get(key) ?? null;
  });
  mockSessions.delete.mockImplementation(async (key: string) => {
    mockSessionsStore.delete(key);
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

// ── Test 1: Auth URL generation ───────────────────────────────────────────────

describe('handleGcalAuthUrl', () => {
  it('returns 200 with correct auth URL params including PKCE and random state (AC1, AC2, AC3, AC6)', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts WHERE id = ... → expert found
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/auth-url`);
    const response = await handleGcalAuthUrl(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as { auth_url: string };
    expect(body.auth_url).toContain('accounts.google.com/o/oauth2/v2/auth');
    expect(body.auth_url).toContain('calendar.events');
    expect(body.auth_url).toContain('calendar.readonly');
    expect(body.auth_url).toContain('access_type=offline');
    expect(body.auth_url).toContain('prompt=consent');

    // AC6: state should be a hex string (64 chars), NOT the expertId
    const stateMatch = body.auth_url.match(/[?&]state=([^&]+)/);
    expect(stateMatch).not.toBeNull();
    const stateParam = stateMatch![1];
    expect(stateParam).toMatch(/^[0-9a-f]{64}$/);
    expect(stateParam).not.toBe(expertId);

    // AC2: code_challenge and code_challenge_method=S256 are present
    expect(body.auth_url).toContain('code_challenge=');
    expect(body.auth_url).toContain('code_challenge_method=S256');

    // AC1 + AC3: KV was called with the correct key format and value includes expertId
    expect(mockSessions.put).toHaveBeenCalledWith(
      expect.stringMatching(/^oauth-state:[0-9a-f]{64}$/),
      expect.stringContaining(expertId),
      { expirationTtl: 600 }
    );

    // AC3: KV value also contains code_verifier
    const putCall = mockSessions.put.mock.calls[0]!;
    const storedValue = JSON.parse(putCall[1] as string) as { expert_id: string; code_verifier: string };
    expect(storedValue.expert_id).toBe(expertId);
    expect(typeof storedValue.code_verifier).toBe('string');
    expect(storedValue.code_verifier.length).toBeGreaterThanOrEqual(43);
  });

  it('returns 403 when caller is not the expert', async () => {
    const differentUser = { id: 'different-user-uuid', email: 'other@example.com' };
    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/auth-url`);
    // 403 short-circuits before any DB call
    const response = await handleGcalAuthUrl(request, mockEnv as any, differentUser, expertId);
    expect(response.status).toBe(403);
  });
});

// ── Test 2: Callback token storage ───────────────────────────────────────────

describe('handleGcalCallback', () => {
  it('stores encrypted tokens and redirects to gcal-connected on success (AC4, AC5)', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts WHERE id = ... → expert found
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    // UPDATE experts SET ... → success
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    // Google token exchange
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ access_token: 'at_plain', refresh_token: 'rt_plain', expires_in: 3600 }),
      { status: 200 }
    ));
    // Google userinfo
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ email: 'expert@gmail.com' }),
      { status: 200 }
    ));

    // AC4: Pre-populate KV with a valid state entry
    const validState = 'a'.repeat(64); // 64-char hex state token
    const validCodeVerifier = 'valid-code-verifier-for-test';
    mockSessionsStore.set(`oauth-state:${validState}`, JSON.stringify({ expert_id: expertId, code_verifier: validCodeVerifier }));

    const request = new Request(
      `https://example.com/api/gcal/callback?code=authcode&state=${validState}`
    );
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);

    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('/onboarding/gcal-connected');

    // AC4: KV entry was deleted after use (one-time use)
    expect(mockSessions.delete).toHaveBeenCalledWith(`oauth-state:${validState}`);

    // AC5: code_verifier was sent in the token exchange body
    const fetchCall = vi.mocked(fetch).mock.calls[0]!;
    const tokenBody = fetchCall[1]?.body as string;
    expect(tokenBody).toContain('code_verifier=valid-code-verifier-for-test');
  });

  it('does NOT include gcal_refresh_token in update when absent from token exchange (AC3)', async () => {
    const mockSql = vi.fn() as Mock;
    // SELECT id FROM experts
    mockSql.mockResolvedValueOnce([{ id: expertId }]);
    // UPDATE experts (capture call args to inspect)
    mockSql.mockResolvedValueOnce([]);
    (createSql as Mock).mockReturnValue(mockSql);

    // Token exchange WITHOUT refresh_token
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ access_token: 'at_plain' }), // no refresh_token
      { status: 200 }
    ));
    // userinfo
    vi.mocked(fetch).mockResolvedValueOnce(new Response(
      JSON.stringify({ email: 'expert@gmail.com' }),
      { status: 200 }
    ));

    // Pre-populate KV
    const validState2 = 'c'.repeat(64);
    mockSessionsStore.set(`oauth-state:${validState2}`, JSON.stringify({ expert_id: expertId, code_verifier: 'test-verifier' }));

    const request = new Request(
      `https://example.com/api/gcal/callback?code=authcode&state=${validState2}`
    );
    await handleGcalCallback(request, mockEnv as any, mockCtx);

    // The UPDATE call (second sql call) should not contain 'gcal_refresh_token' as a literal
    // Since postgres.js uses tagged templates, we inspect the raw template strings array
    // The second call is the UPDATE — check it was called (the template doesn't include refresh_token column)
    expect(mockSql).toHaveBeenCalledTimes(2);

    // Inspect template strings of the UPDATE call: raw strings array is the first argument
    const updateCallArgs = mockSql.mock.calls[1]!;
    const templateStrings = updateCallArgs[0] as TemplateStringsArray;
    // Join all template string parts and verify gcal_refresh_token is absent
    const sqlText = Array.from(templateStrings).join('');
    expect(sqlText).not.toContain('gcal_refresh_token');
  });

  it('redirects to gcal-error when state is missing (AC4)', async () => {
    const request = new Request('https://example.com/api/gcal/callback?code=authcode');
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);
    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('/onboarding/gcal-error?reason=invalid_state');
  });

  it('redirects to gcal-error when state is not found in KV (invalid/expired) (AC4)', async () => {
    // KV returns null (no entry for this state) — don't pre-populate the store
    const request = new Request(
      'https://example.com/api/gcal/callback?code=authcode&state=deadbeef' + '0'.repeat(56)
    );
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);
    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('/onboarding/gcal-error?reason=invalid_state');
  });

  it('redirects to gcal-error when state is reused (already deleted from KV) (AC4)', async () => {
    // Simulate a state that was already consumed (deleted) by a previous callback
    // KV store is empty for this key — simulates already-deleted
    const usedState = 'b'.repeat(64);
    // Don't add to store

    const request = new Request(
      `https://example.com/api/gcal/callback?code=authcode&state=${usedState}`
    );
    const response = await handleGcalCallback(request, mockEnv as any, mockCtx);
    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('/onboarding/gcal-error?reason=invalid_state');
  });
});

// ── Test 3: Status endpoint ───────────────────────────────────────────────────

describe('handleGcalStatus', () => {
  it('returns connected: true when gcal_refresh_token is non-null (AC4)', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([{
      gcal_refresh_token: 'encrypted-refresh-token',
      gcal_email: 'expert@gmail.com',
      gcal_connected_at: '2026-02-20T10:00:00Z',
    }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as any;
    expect(body.connected).toBe(true);
    expect(body.google_email).toBe('expert@gmail.com');
    expect(body.connected_at).toBe('2026-02-20T10:00:00Z');
  });

  it('returns connected: false when gcal_refresh_token is null (AC4)', async () => {
    const mockSql = vi.fn() as Mock;
    mockSql.mockResolvedValueOnce([{
      gcal_refresh_token: null,
      gcal_email: null,
      gcal_connected_at: null,
    }]);
    (createSql as Mock).mockReturnValue(mockSql);

    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, mockUser, expertId);

    expect(response.status).toBe(200);
    const body = await response.json() as any;
    expect(body.connected).toBe(false);
    expect(body.google_email).toBeNull();
    expect(body.connected_at).toBeNull();
  });

  it('returns 403 when user.id !== expertId', async () => {
    const differentUser = { id: 'other-user', email: 'other@example.com' };
    const request = new Request(`https://example.com/api/experts/${expertId}/gcal/status`);
    const response = await handleGcalStatus(request, mockEnv as any, differentUser, expertId);
    expect(response.status).toBe(403);
  });
});
