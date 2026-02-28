import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleExtract } from './extract';
import type { Env } from '../types/env';

vi.mock('posthog-node', () => ({
  PostHog: vi.fn().mockImplementation(() => ({
    captureImmediate: vi.fn().mockResolvedValue(undefined),
  })),
}));

const mockCtx = {
  waitUntil: vi.fn(),
  passThroughOnException: vi.fn(),
} as unknown as ExecutionContext;

// ── Mock KV (in-memory, test-isolated) ────────────────────────────────────────

function makeMockKv(initial: Record<string, string> = {}): KVNamespace {
  const store = new Map<string, string>(Object.entries(initial));
  return {
    get: vi.fn(async (key: string) => store.get(key) ?? null),
    put: vi.fn(async (key: string, value: string) => { store.set(key, value); }),
    delete: vi.fn(async (key: string) => { store.delete(key); }),
    list: vi.fn(),
    getWithMetadata: vi.fn(),
  } as unknown as KVNamespace;
}

// ── Mock Rate Limiter (always allows by default) ───────────────────────────────

function makeMockRateLimiter(allow = true): RateLimit {
  return {
    limit: vi.fn().mockResolvedValue({ success: allow }),
  } as unknown as RateLimit;
}

// ── Mock Env ──────────────────────────────────────────────────────────────────

function makeMockEnv(overrides: Partial<Env> = {}): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'test-anon-key',
    SUPABASE_SERVICE_KEY: 'test-service-key',
    OPENAI_API_KEY: 'test-openai-key',
    PROSPECT_TOKEN_SECRET: 'test-secret-32-chars-minimum-len',
    SESSIONS: makeMockKv(),
    RATE_LIMITER: makeMockRateLimiter(),
    ...overrides,
  } as unknown as Env;
}

// Fresh mockEnv per test — checkExtractRateLimit writes to SESSIONS KV on every call,
// so a shared env would cause counter overflow across tests.
let mockEnv: Env = makeMockEnv();

// ── Realistic 150-word freetext ────────────────────────────────────────────────

const REALISTIC_FREETEXT = `
We are a mid-size e-commerce company with around 80 employees based in France. We're struggling with
our customer support operations — we get over 500 tickets per week and our team of 6 agents can barely
keep up. We want to automate first-level responses using AI, integrating with our existing Zendesk setup.
Ideally the AI should handle order status inquiries, returns, and FAQs automatically.

We've heard about Claude and GPT-4 and think one of them would be good for this. We'd also need
someone who knows Zendesk API and can build n8n workflows.

Our budget is between 5,000 and 15,000 euros for the initial implementation. We'd like to launch
before our busy season in 3 months. We work primarily in French but the system should handle English
customers too.
`.trim();

// ── Mock OpenAI responses ─────────────────────────────────────────────────────

const MOCK_HIGH_CONFIDENCE_RESPONSE = {
  id: 'chatcmpl-test',
  object: 'chat.completion',
  choices: [
    {
      index: 0,
      message: {
        role: 'assistant',
        content: null,
        tool_calls: [
          {
            id: 'call_test',
            type: 'function',
            function: {
              name: 'extract_requirements',
              arguments: JSON.stringify({
                requirements: {
                  challenge:
                    'Automate customer support first-level responses to handle 500+ weekly tickets with AI, integrated with Zendesk',
                  skills_needed: ['Claude API', 'GPT-4', 'Zendesk API', 'n8n', 'AI automation'],
                  industry: 'e-commerce',
                  budget_range: { min: 5000, max: 15000 },
                  timeline: '3 months',
                  company_size: '50-200',
                  languages: ['French', 'English'],
                },
                confidence: {
                  challenge: 0.95,
                  skills_needed: 0.85,
                  industry: 0.9,
                  budget_range: 0.9,
                  timeline: 0.85,
                  company_size: 0.8,
                  languages: 0.9,
                },
                confirmation_questions: [],
              }),
            },
          },
        ],
      },
      finish_reason: 'tool_calls',
    },
  ],
  model: 'gpt-4o-mini',
  usage: { prompt_tokens: 120, completion_tokens: 200, total_tokens: 320 },
};

const MOCK_LOW_CONFIDENCE_RESPONSE = {
  id: 'chatcmpl-test2',
  object: 'chat.completion',
  choices: [
    {
      index: 0,
      message: {
        role: 'assistant',
        content: null,
        tool_calls: [
          {
            id: 'call_test2',
            type: 'function',
            function: {
              name: 'extract_requirements',
              arguments: JSON.stringify({
                requirements: {
                  challenge: 'Build an AI chatbot for customer service',
                  skills_needed: ['AI', 'chatbot'],
                  industry: 'retail',
                  budget_range: { min: 0, max: 0 },
                  timeline: '',
                  company_size: '',
                  languages: [],
                },
                confidence: {
                  challenge: 0.8,
                  skills_needed: 0.6,
                  industry: 0.5,
                  budget_range: 0.1,
                  timeline: 0.1,
                  company_size: 0.1,
                  languages: 0.4,
                },
                confirmation_questions: [
                  { field: 'budget_range', question: 'What is your budget range for this project (in EUR)?', options: ['< 5k€', '5–15k€', '15–50k€', '50k€+'] },
                  { field: 'timeline', question: 'When do you need this project delivered?', options: ['< 1 month', '1–3 months', '3–6 months', 'Flexible'] },
                  { field: 'company_size', question: 'How many employees does your company have?', options: ['1–10', '11–50', '51–200', '200+'] },
                  { field: 'industry', question: 'What industry does your company operate in?' },
                ],
              }),
            },
          },
        ],
      },
      finish_reason: 'tool_calls',
    },
  ],
  model: 'gpt-4o-mini',
  usage: { prompt_tokens: 80, completion_tokens: 150, total_tokens: 230 },
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('handleExtract — POST /api/extract', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
    mockEnv = makeMockEnv(); // Reset KV state between tests
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  // ── AC1: Input validation ───────────────────────────────────────────────────

  it('AC1 — returns 400 on invalid JSON body', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: 'not-json',
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(400);
  });

  it('AC1 — returns 422 when text is missing', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ satellite_id: 'sat_123' }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string; details: Record<string, string> };
    expect(body.details.text).toBeDefined();
  });

  it('AC1 — returns 422 when text exceeds 2000 characters', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'a'.repeat(2001) }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string; details: Record<string, string> };
    expect(body.details.text).toMatch(/2000/);
  });

  it('AC2 — returns 422 with invalid_input when text is keyboard mashing', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa help me please now here' }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('invalid_input');
  });

  it('AC2 — returns 422 with invalid_input when text is lorem ipsum', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod.' }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('invalid_input');
  });

  // ── AC3: Honeypot ──────────────────────────────────────────────────────────

  it('AC3 — returns 200 fake response when honeypot _hp field is non-empty (bot silencing)', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: REALISTIC_FREETEXT,
        _hp: 'bot-filled-this',
      }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    const body = await res.json() as { ready_to_match: boolean; needs_confirmation: string[] };
    expect(body.ready_to_match).toBe(false);
    expect(body.needs_confirmation).toHaveLength(0);
    // Fake response — fetch should NOT have been called (no LLM cost)
    expect(vi.mocked(fetch)).not.toHaveBeenCalled();
  });

  it('AC3 — allows request when _hp is empty string (real user)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT, _hp: '' }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    expect(vi.mocked(fetch)).toHaveBeenCalledTimes(1);
  });

  // ── AC4: Timing check ──────────────────────────────────────────────────────

  it('AC4 — returns 200 fake response when _ts is < 3000ms ago (bot silencing)', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: REALISTIC_FREETEXT,
        _ts: Date.now() - 500, // 0.5s — way too fast
      }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    expect(vi.mocked(fetch)).not.toHaveBeenCalled();
  });

  it('AC4 — allows request when _ts is > 3000ms ago (normal human timing)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT, _ts: Date.now() - 5000 }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    expect(vi.mocked(fetch)).toHaveBeenCalledTimes(1);
  });

  it('AC4 — allows request when _ts is missing (backwards compat)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
  });

  // ── AC8: Circuit breaker ────────────────────────────────────────────────────

  it('AC8 — returns 503 when hourly cost exceeds $10 (1000 cents)', async () => {
    const hourKey = `extract-cost:${new Date().toISOString().slice(0, 13)}`;
    const env = makeMockEnv({ SESSIONS: makeMockKv({ [hourKey]: '1000' }) });

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, env, mockCtx);
    expect(res.status).toBe(503);
    const body = await res.json() as { error: string; retry_after: number };
    expect(body.error).toBe('service_overloaded');
    expect(body.retry_after).toBe(300);
    expect(vi.mocked(fetch)).not.toHaveBeenCalled();
  });

  it('AC8 — allows request when hourly cost is below threshold (999 cents)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const hourKey = `extract-cost:${new Date().toISOString().slice(0, 13)}`;
    const env = makeMockEnv({ SESSIONS: makeMockKv({ [hourKey]: '999' }) });

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, env, mockCtx);
    expect(res.status).toBe(200);
  });

  // ── AC9: Extraction count (cookie-based) ───────────────────────────────────

  it('AC9 — returns 403 identification_required when extraction count cookie >= 1', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Cookie': '_extract_count=1',
      },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(403);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('identification_required');
    expect(vi.mocked(fetch)).not.toHaveBeenCalled();
  });

  it('AC9 — allows first extraction and sets _extract_count cookie', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    const setCookie = res.headers.get('Set-Cookie');
    expect(setCookie).toContain('_extract_count=1');
    expect(setCookie).toContain('HttpOnly');
    expect(setCookie).toContain('SameSite=Lax');
  });

  it('AC9 — IP fallback: returns 403 when IP has >= 3 extractions without identification', async () => {
    const env = makeMockEnv({
      SESSIONS: makeMockKv({ 'extract-ip:1.2.3.4': '3' }),
    });
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '1.2.3.4',
      },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, env, mockCtx);
    expect(res.status).toBe(403);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('identification_required');
  });

  // ── AC11: Flow token included in successful extraction response ─────────────

  it('AC11 — successful extraction includes flow_token in response', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), { status: 200, headers: { 'Content-Type': 'application/json' } }),
    );
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });
    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    const body = await res.json() as { flow_token: string; requirements: unknown };
    expect(typeof body.flow_token).toBe('string');
    // JWT format: 3 base64url segments separated by dots
    expect(body.flow_token.split('.').length).toBe(3);
  });

  // ── AC10: Integration test — realistic 150-word description ────────────────

  it('AC10 — extracts all 7 fields with ≥5 having confidence > 0.5', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);

    const body = await res.json() as {
      requirements: Record<string, unknown>;
      confidence: Record<string, number>;
      needs_confirmation: string[];
      ready_to_match: boolean;
    };

    expect(body.requirements).toHaveProperty('challenge');
    expect(body.requirements).toHaveProperty('skills_needed');
    expect(body.requirements).toHaveProperty('industry');
    expect(body.requirements).toHaveProperty('budget_range');
    expect(body.requirements).toHaveProperty('timeline');
    expect(body.requirements).toHaveProperty('company_size');
    expect(body.requirements).toHaveProperty('languages');

    const highConfidenceFields = Object.values(body.confidence).filter((c) => c > 0.5);
    expect(highConfidenceFields.length).toBeGreaterThanOrEqual(5);

    expect(Array.isArray(body.needs_confirmation)).toBe(true);
    expect(typeof body.ready_to_match).toBe('boolean');
  });

  // ── AC6: ready_to_match + confirmation_questions ────────────────────────────

  it('AC6 — ready_to_match is true and no confirmation_questions when all confidence ≥ 0.7', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    const body = await res.json() as {
      ready_to_match: boolean;
      needs_confirmation: string[];
      confirmation_questions?: unknown[];
    };

    expect(body.ready_to_match).toBe(true);
    expect(body.needs_confirmation).toHaveLength(0);
    expect(body.confirmation_questions).toBeUndefined();
  });

  it('AC5 — includes confirmation_questions (max 3) for low-confidence fields', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_LOW_CONFIDENCE_RESPONSE), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'I want to build a chatbot for my company to handle orders.' }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);
    const body = await res.json() as {
      ready_to_match: boolean;
      needs_confirmation: string[];
      confirmation_questions: Array<{ field: string; question: string }>;
    };

    expect(body.ready_to_match).toBe(false);
    expect(body.needs_confirmation.length).toBeGreaterThan(0);
    expect(body.confirmation_questions).toBeDefined();
    expect(body.confirmation_questions.length).toBeLessThanOrEqual(3);
    const lowConfidenceSet = new Set(body.needs_confirmation);
    for (const q of body.confirmation_questions) {
      expect(lowConfidenceSet.has(q.field)).toBe(true);
    }
  });

  it('AC8 (OpenAI error) — returns 502 when OpenAI API returns non-200', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ error: { message: 'Invalid API key' } }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'I want AI automation for my company processes and workflows.' }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(502);
  });

  it('AC2 — returns 500 when OpenAI returns no tool_calls', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          id: 'chatcmpl-test',
          choices: [{ message: { role: 'assistant', content: 'hello', tool_calls: [] } }],
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'Build me an AI automation system for my business now.' }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(500);
  });

  it('AC5 (E06S37) — extracts desired_outcomes when present in LLM response', async () => {
    const responseWithOutcomes = {
      ...MOCK_HIGH_CONFIDENCE_RESPONSE,
      choices: [
        {
          ...MOCK_HIGH_CONFIDENCE_RESPONSE.choices[0],
          message: {
            ...MOCK_HIGH_CONFIDENCE_RESPONSE.choices[0]!.message,
            tool_calls: [
              {
                ...MOCK_HIGH_CONFIDENCE_RESPONSE.choices[0]!.message.tool_calls[0],
                function: {
                  name: 'extract_requirements',
                  arguments: JSON.stringify({
                    requirements: {
                      ...JSON.parse(MOCK_HIGH_CONFIDENCE_RESPONSE.choices[0]!.message.tool_calls[0]!.function.arguments).requirements,
                      desired_outcomes: ['save time on customer support', 'reduce ticket handling to < 2min'],
                    },
                    confidence: JSON.parse(MOCK_HIGH_CONFIDENCE_RESPONSE.choices[0]!.message.tool_calls[0]!.function.arguments).confidence,
                    confirmation_questions: [],
                  }),
                },
              },
            ],
          },
        },
      ],
    };

    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(responseWithOutcomes), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);

    const body = await res.json() as {
      requirements: { desired_outcomes?: string[] };
      ready_to_match: boolean;
    };

    expect(Array.isArray(body.requirements.desired_outcomes)).toBe(true);
    expect(body.requirements.desired_outcomes).toHaveLength(2);
    expect(body.requirements.desired_outcomes![0]).toBe('save time on customer support');
  });

  it('AC7 (E06S37) — backward compat: extractions without desired_outcomes remain valid', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(MOCK_HIGH_CONFIDENCE_RESPONSE), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: REALISTIC_FREETEXT }),
    });

    const res = await handleExtract(req, mockEnv, mockCtx);
    expect(res.status).toBe(200);

    const body = await res.json() as {
      requirements: { desired_outcomes?: string[] };
      ready_to_match: boolean;
    };

    expect(body.requirements.desired_outcomes).toBeUndefined();
    expect(typeof body.ready_to_match).toBe('boolean');
  });
});
