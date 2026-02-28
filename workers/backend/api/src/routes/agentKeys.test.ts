import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleCreateAgentKey, handleRevokeAgentKey, handleListAgentKeys } from './agentKeys';
import type { Env } from '../types/env';
import { signProspectSessionToken } from '../lib/jwt';

vi.mock('../lib/db', () => ({
  createSql: vi.fn(() => {
    const sql = vi.fn() as unknown as ReturnType<typeof import('../lib/db').createSql>;
    sql.end = vi.fn().mockResolvedValue(undefined);
    return sql;
  }),
}));

const SESSION_SECRET = 'test-secret-32-chars-long-padding!!';
const PROSPECT_ID = 'prospect-uuid-abc';

const mockCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;

const baseMockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_SERVICE_KEY: 'test-service-key',
  PROSPECT_TOKEN_SECRET: SESSION_SECRET,
  POSTHOG_API_KEY: '',
  SESSIONS: {} as KVNamespace,
  HYPERDRIVE: { connectionString: 'postgresql://test:test@localhost:5432/test' },
  RESEND_API_KEY: '',
  EMAIL_FROM_DOMAIN: 'test.io',
  EMAIL_REPLY_TO: 'test@test.io',
} as unknown as Env;

async function makeSessionToken(prospectId: string): Promise<string> {
  return signProspectSessionToken(prospectId, 'test@example.com', SESSION_SECRET);
}

function makeRequest(method: string, body?: unknown, token?: string): Request {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  return new Request('https://test.workers.dev/api/prospects/test/agent-keys', init);
}

describe('handleListAgentKeys', () => {
  it('returns 401 if no session token', async () => {
    const request = makeRequest('GET');
    const response = await handleListAgentKeys(request, baseMockEnv, PROSPECT_ID);
    expect(response.status).toBe(401);
  });

  it('returns 401 if session token is for a different prospect', async () => {
    const token = await makeSessionToken('other-prospect');
    const request = makeRequest('GET', undefined, token);
    const response = await handleListAgentKeys(request, baseMockEnv, PROSPECT_ID);
    expect(response.status).toBe(401);
  });

  it('returns 200 with keys list for valid session', async () => {
    const { createSql } = await import('../lib/db');
    const mockRows = [
      { id: 'key-1', name: 'Test Key', created_at: '2026-02-28T00:00:00Z', last_used_at: null, revoked_at: null },
    ];
    const mockSql = Object.assign(vi.fn().mockResolvedValue(mockRows), {
      end: vi.fn().mockResolvedValue(undefined),
    });
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('GET', undefined, token);
    const response = await handleListAgentKeys(request, baseMockEnv, PROSPECT_ID);
    expect(response.status).toBe(200);
    const body = await response.json() as { keys: unknown[] };
    expect(Array.isArray(body.keys)).toBe(true);
  });
});

describe('handleCreateAgentKey', () => {
  it('returns 401 if no session token', async () => {
    const request = makeRequest('POST', { name: 'My Key' });
    const response = await handleCreateAgentKey(request, baseMockEnv, PROSPECT_ID, mockCtx);
    expect(response.status).toBe(401);
  });

  it('returns 422 if name is missing', async () => {
    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('POST', {}, token);
    const response = await handleCreateAgentKey(request, baseMockEnv, PROSPECT_ID, mockCtx);
    expect(response.status).toBe(422);
  });

  it('returns 422 if at limit (3 active keys)', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(vi.fn().mockResolvedValue([{ count: 3 }]), {
      end: vi.fn().mockResolvedValue(undefined),
    });
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('POST', { name: 'New Key' }, token);
    const response = await handleCreateAgentKey(request, baseMockEnv, PROSPECT_ID, mockCtx);
    expect(response.status).toBe(422);
    const body = await response.json() as { error: string };
    expect(body.error).toBe('max_keys_reached');
  });

  it('returns 201 with key on success', async () => {
    const { createSql } = await import('../lib/db');
    let callCount = 0;
    const mockSql = Object.assign(
      vi.fn(() => {
        callCount++;
        if (callCount === 1) return Promise.resolve([{ count: 0 }]);
        return Promise.resolve([{ id: 'new-key-id', created_at: '2026-02-28T00:00:00Z' }]);
      }),
      { end: vi.fn().mockResolvedValue(undefined) },
    );
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('POST', { name: 'My Key' }, token);
    const response = await handleCreateAgentKey(request, baseMockEnv, PROSPECT_ID, mockCtx);
    expect(response.status).toBe(201);
    const body = await response.json() as { id: string; key: string; name: string };
    expect(body.id).toBe('new-key-id');
    expect(typeof body.key).toBe('string');
    expect(body.key).toMatch(/^[0-9a-f]{64}$/);
    expect(body.name).toBe('My Key');
  });
});

describe('handleRevokeAgentKey', () => {
  it('returns 401 if no session token', async () => {
    const request = makeRequest('DELETE');
    const response = await handleRevokeAgentKey(request, baseMockEnv, PROSPECT_ID, 'key-id-1');
    expect(response.status).toBe(401);
  });

  it('returns 404 if key not found or already revoked', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(vi.fn().mockResolvedValue([]), {
      end: vi.fn().mockResolvedValue(undefined),
    });
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('DELETE', undefined, token);
    const response = await handleRevokeAgentKey(request, baseMockEnv, PROSPECT_ID, 'key-id-1');
    expect(response.status).toBe(404);
  });

  it('returns 200 on successful revocation', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(vi.fn().mockResolvedValue([{ id: 'key-id-1' }]), {
      end: vi.fn().mockResolvedValue(undefined),
    });
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const token = await makeSessionToken(PROSPECT_ID);
    const request = makeRequest('DELETE', undefined, token);
    const response = await handleRevokeAgentKey(request, baseMockEnv, PROSPECT_ID, 'key-id-1');
    expect(response.status).toBe(200);
    const body = await response.json() as { success: boolean };
    expect(body.success).toBe(true);
  });
});
