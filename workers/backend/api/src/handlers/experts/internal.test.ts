import { describe, it, expect, vi } from 'vitest';
import { handleGetInternalExpertBySlug } from './internal';
import { signDirectLinkToken } from '../../lib/directLinkToken';

const TEST_SECRET = 'test-secret-32bytes-padding-here';
const INTERNAL_KEY = 'test-internal-key';

const MOCK_EXPERT_ID = 'abcdef12-1234-5678-abcd-ef1234567890';
const MOCK_NONCE = 'test-nonce-abc';
const MOCK_SLUG = `exp-${MOCK_EXPERT_ID.substring(0, 8)}`;

function makeEnv(overrides: Record<string, unknown> = {}) {
  return {
    DIRECT_LINK_SECRET: TEST_SECRET,
    INTERNAL_API_KEY: INTERNAL_KEY,
    HYPERDRIVE: { connectionString: 'postgres://localhost/test' },
    ...overrides,
  } as unknown as import('../../types/env').Env;
}

function makeRequest(path: string, headers: Record<string, string> = {}, searchParams: Record<string, string> = {}) {
  const url = new URL(`https://api.callibrate.io${path}`);
  for (const [k, v] of Object.entries(searchParams)) {
    url.searchParams.set(k, v);
  }
  return new Request(url.toString(), { headers });
}

// Mock createSql to return our fixture
vi.mock('../../lib/db', () => ({
  createSql: () => {
    const mockSql = async () => [
      {
        id: MOCK_EXPERT_ID,
        display_name: 'Alice Expert',
        headline: 'AI Integration Expert',
        bio: 'I help companies integrate AI workflows.',
        profile: {
          skills: ['n8n', 'Python', 'Claude'],
          languages: ['English', 'French'],
          portfolio_links: ['https://example.com/portfolio'],
        },
        rate_min: 100,
        rate_max: 200,
        composite_score: 75,
        availability: 'available',
        direct_link_nonce: MOCK_NONCE,
        direct_submissions_this_month: 3,
      },
    ];
    mockSql.end = async () => {};
    return mockSql;
  },
}));

describe('handleGetInternalExpertBySlug', () => {
  it('returns 401 without auth header', async () => {
    const req = makeRequest(`/api/experts/internal/${MOCK_SLUG}`);
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), MOCK_SLUG);
    expect(res.status).toBe(401);
  });

  it('returns 401 with wrong key', async () => {
    const req = makeRequest(`/api/experts/internal/${MOCK_SLUG}`, {
      Authorization: 'Bearer wrong-key',
    });
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), MOCK_SLUG);
    expect(res.status).toBe(401);
  });

  it('returns 404 for invalid slug format', async () => {
    const req = makeRequest('/api/experts/internal/invalid', {
      Authorization: `Bearer ${INTERNAL_KEY}`,
    });
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), 'invalid');
    expect(res.status).toBe(404);
  });

  it('returns 200 with expert data and attribution=callibrate (no token)', async () => {
    const req = makeRequest(`/api/experts/internal/${MOCK_SLUG}`, {
      Authorization: `Bearer ${INTERNAL_KEY}`,
    });
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), MOCK_SLUG);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.id).toBe(MOCK_EXPERT_ID);
    expect(body.display_name).toBe('Alice Expert');
    expect(body.attribution).toBe('callibrate');
    expect(body.skills).toEqual(['n8n', 'Python', 'Claude']);
    expect(body.direct_submissions_this_month).toBe(3);
  });

  it('returns attribution=direct when valid token provided', async () => {
    const token = await signDirectLinkToken(MOCK_EXPERT_ID, MOCK_NONCE, TEST_SECRET);
    const req = makeRequest(
      `/api/experts/internal/${MOCK_SLUG}`,
      { Authorization: `Bearer ${INTERNAL_KEY}` },
      { t: token },
    );
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), MOCK_SLUG);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.attribution).toBe('direct');
  });

  it('returns attribution=callibrate when invalid token provided', async () => {
    const req = makeRequest(
      `/api/experts/internal/${MOCK_SLUG}`,
      { Authorization: `Bearer ${INTERNAL_KEY}` },
      { t: 'invalid-tampered-token' },
    );
    const res = await handleGetInternalExpertBySlug(req, makeEnv(), MOCK_SLUG);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.attribution).toBe('callibrate');
  });
});
