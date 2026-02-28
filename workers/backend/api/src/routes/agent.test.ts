import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleAgentExtract, handleAgentMatch, handleAgentRevealRequest, handleAgentRevealConfirm, handleAgentRevealRefuse, handleAgentRevealStatus } from './agent';
import type { Env } from '../types/env';
import type { AgentCtx } from './agent';

vi.mock('../lib/db', () => ({
  createSql: vi.fn(() =>
    Object.assign(vi.fn().mockResolvedValue([]) as unknown as ReturnType<typeof import('../lib/db').createSql>, {
      end: vi.fn().mockResolvedValue(undefined),
    }),
  ),
}));

vi.mock('../lib/extraction', () => ({
  performExtraction: vi.fn().mockResolvedValue({
    ok: true,
    data: {
      requirements: { challenge: 'test challenge' },
      confidence: { challenge: 0.9 },
      needs_confirmation: [],
      ready_to_match: true,
    },
    tokensUsed: 100,
    latencyMs: 500,
  }),
}));

vi.mock('../lib/inputValidation', () => ({
  validateFreetext: vi.fn().mockReturnValue({ valid: true }),
}));

vi.mock('./matches', () => ({
  handleMatchCompute: vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ computed: 2, top_matches: [{ id: 'match-1', score: 0.9 }, { id: 'match-2', score: 0.7 }] }), { status: 200 })
  ),
}));

const mockCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;

const mockSessions: Record<string, string> = {};
const mockEnv = {
  SESSIONS: {
    get: vi.fn(async (key: string) => mockSessions[key] ?? null),
    put: vi.fn(async (key: string, value: string) => { mockSessions[key] = value; }),
    delete: vi.fn(async (key: string) => { delete mockSessions[key]; }),
  } as unknown as KVNamespace,
  AGENT_API_KEY_SECRET: 'test-agent-secret-32-chars-padding!!',
  WORKER_BASE_URL: 'https://test.workers.dev',
  RESEND_API_KEY: 'test-resend-key',
  EMAIL_FROM_DOMAIN: 'test.io',
  EMAIL_REPLY_TO: 'support@test.io',
  POSTHOG_API_KEY: '',
  HYPERDRIVE: { connectionString: 'postgresql://test:test@localhost:5432/test' },
} as unknown as Env;

const mockAgent: AgentCtx = {
  prospect_id: 'prospect-uuid-abc',
  key_id: 'key-id-abc',
  key_hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
};

function makeRequest(body: unknown, rateLimitOverride?: string): Request {
  return new Request('https://test.workers.dev/api/agent/extract', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('handleAgentExtract', () => {
  beforeEach(() => {
    Object.keys(mockSessions).forEach(k => delete mockSessions[k]);
    vi.mocked(mockCtx.waitUntil).mockReset();
  });

  it('returns 422 for missing text', async () => {
    const request = makeRequest({});
    const response = await handleAgentExtract(request, mockEnv, mockCtx, mockAgent);
    expect(response.status).toBe(422);
  });

  it('returns 200 with extraction data on success', async () => {
    const request = makeRequest({ text: 'I need an n8n automation for lead scoring.' });
    const response = await handleAgentExtract(request, mockEnv, mockCtx, mockAgent);
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body['requirements']).toBeTruthy();
    expect(body['ready_to_match']).toBe(true);
  });

  it('returns 429 when rate limit is exceeded', async () => {
    // Pre-fill rate limit counter to the limit
    const windowIndex = Math.floor(Date.now() / 60000);
    mockSessions[`agent-rate:${mockAgent.key_hash}:extract:${windowIndex}`] = '10';

    const request = makeRequest({ text: 'I need automation help.' });
    const response = await handleAgentExtract(request, mockEnv, mockCtx, mockAgent);
    expect(response.status).toBe(429);
  });
});

describe('handleAgentMatch', () => {
  beforeEach(() => {
    Object.keys(mockSessions).forEach(k => delete mockSessions[k]);
  });

  it('returns 422 for missing requirements', async () => {
    const request = makeRequest({});
    const response = await handleAgentMatch(request, mockEnv, mockCtx, mockAgent);
    expect(response.status).toBe(422);
  });

  it('returns 200 with anonymized match results', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(
      vi.fn().mockResolvedValue([{ id: 'project-uuid-1' }]),
      { end: vi.fn().mockResolvedValue(undefined) },
    );
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const request = makeRequest({ requirements: { challenge: 'test' } });
    const response = await handleAgentMatch(request, mockEnv, mockCtx, mockAgent);
    expect(response.status).toBe(200);
    const body = await response.json() as { top_matches: unknown[]; project_id: string };
    expect(body.project_id).toBe('project-uuid-1');
    expect(Array.isArray(body.top_matches)).toBe(true);
    // expert_id must NOT be present
    const match = body.top_matches[0] as Record<string, unknown>;
    expect(match['expert_id']).toBeUndefined();
  });
});

describe('handleAgentRevealConfirm', () => {
  it('returns 400 for missing token', async () => {
    const request = new Request('https://test.workers.dev/api/agent/reveal/confirm');
    const response = await handleAgentRevealConfirm(request, mockEnv, mockCtx);
    expect(response.status).toBe(400);
    const text = await response.text();
    expect(text).toContain('invalide');
  });

  it('returns 400 for invalid token', async () => {
    const request = new Request('https://test.workers.dev/api/agent/reveal/confirm?token=invalid-token');
    const response = await handleAgentRevealConfirm(request, mockEnv, mockCtx);
    expect(response.status).toBe(400);
  });

  it('returns HTML response for valid token + KV state', async () => {
    const { signRevealConfirmToken } = await import('../lib/jwt');
    const token = await signRevealConfirmToken('match-1', 'prospect-1', mockEnv.AGENT_API_KEY_SECRET);

    // Pre-populate KV with pending reveal state
    mockSessions['agent-reveal:match-1'] = JSON.stringify({
      match_id: 'match-1',
      prospect_id: 'prospect-1',
      expert_id: 'expert-1',
      status: 'pending',
    });

    const request = new Request(`https://test.workers.dev/api/agent/reveal/confirm?token=${encodeURIComponent(token)}`);
    const response = await handleAgentRevealConfirm(request, mockEnv, mockCtx);
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).toContain('confirmé');
  });
});

describe('handleAgentRevealRefuse', () => {
  it('returns 400 for missing token', async () => {
    const request = new Request('https://test.workers.dev/api/agent/reveal/refuse');
    const response = await handleAgentRevealRefuse(request, mockEnv, mockCtx);
    expect(response.status).toBe(400);
  });
});

describe('handleAgentRevealStatus', () => {
  it('returns not_requested when no KV entry exists', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(
      vi.fn().mockResolvedValue([{ id: 'match-99' }]),
      { end: vi.fn().mockResolvedValue(undefined) },
    );
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const request = new Request('https://test.workers.dev/api/agent/reveal/match-99/status');
    const response = await handleAgentRevealStatus(request, mockEnv, mockAgent, 'match-99');
    expect(response.status).toBe(200);
    const body = await response.json() as { status: string };
    expect(body.status).toBe('not_requested');
  });

  it('returns current status from KV', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(
      vi.fn().mockResolvedValue([{ id: 'match-5' }]),
      { end: vi.fn().mockResolvedValue(undefined) },
    );
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    mockSessions['agent-reveal:match-5'] = JSON.stringify({ status: 'confirmed', confirmed_at: '2026-02-28T10:00:00Z' });

    const request = new Request('https://test.workers.dev/api/agent/reveal/match-5/status');
    const response = await handleAgentRevealStatus(request, mockEnv, mockAgent, 'match-5');
    expect(response.status).toBe(200);
    const body = await response.json() as { status: string; confirmed_at: string };
    expect(body.status).toBe('confirmed');
    expect(body.confirmed_at).toBe('2026-02-28T10:00:00Z');
  });

  it('returns 404 if match does not belong to prospect', async () => {
    const { createSql } = await import('../lib/db');
    const mockSql = Object.assign(
      vi.fn().mockResolvedValue([]), // empty = not found
      { end: vi.fn().mockResolvedValue(undefined) },
    );
    vi.mocked(createSql).mockReturnValue(mockSql as unknown as ReturnType<typeof createSql>);

    const request = new Request('https://test.workers.dev/api/agent/reveal/not-my-match/status');
    const response = await handleAgentRevealStatus(request, mockEnv, mockAgent, 'not-my-match');
    expect(response.status).toBe(404);
  });
});
