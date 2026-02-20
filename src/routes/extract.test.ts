import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleExtract } from './extract';
import type { Env } from '../types/env';

// ── Mock Env ──────────────────────────────────────────────────────────────────

const mockEnv = {
  SUPABASE_URL: 'https://test.supabase.co',
  SUPABASE_ANON_KEY: 'test-anon-key',
  SUPABASE_SERVICE_KEY: 'test-service-key',
  ANTHROPIC_API_KEY: 'test-anthropic-key',
  CLOUDFLARE_AI_GATEWAY_URL: 'https://gateway.ai.cloudflare.com/v1/account/gateway/anthropic',
} as unknown as Env;

// ── Realistic 150-word freetext (AC10) ────────────────────────────────────────

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

// ── Mock Claude tool_use response (all 7 fields present, all confidence > 0.5) ─

const MOCK_HIGH_CONFIDENCE_RESPONSE = {
  id: 'msg_test',
  type: 'message',
  role: 'assistant',
  content: [
    {
      type: 'tool_use',
      id: 'toolu_test',
      name: 'extract_requirements',
      input: {
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
      },
    },
  ],
  model: 'claude-haiku-4-5-20251001',
  stop_reason: 'tool_use',
  usage: { input_tokens: 120, output_tokens: 200 },
};

// ── Mock Claude response with low-confidence fields ──────────────────────────

const MOCK_LOW_CONFIDENCE_RESPONSE = {
  id: 'msg_test2',
  type: 'message',
  role: 'assistant',
  content: [
    {
      type: 'tool_use',
      id: 'toolu_test2',
      name: 'extract_requirements',
      input: {
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
          skills_needed: 0.6,  // low
          industry: 0.5,       // low
          budget_range: 0.1,   // low
          timeline: 0.1,       // low
          company_size: 0.1,   // low
          languages: 0.4,      // low
        },
        confirmation_questions: [
          { field: 'budget_range', question: 'What is your budget range for this project (in EUR)?', options: ['< 5k€', '5–15k€', '15–50k€', '50k€+'] },
          { field: 'timeline', question: 'When do you need this project delivered?', options: ['< 1 month', '1–3 months', '3–6 months', 'Flexible'] },
          { field: 'company_size', question: 'How many employees does your company have?', options: ['1–10', '11–50', '51–200', '200+'] },
          { field: 'industry', question: 'What industry does your company operate in?' },
        ],
      },
    },
  ],
  model: 'claude-haiku-4-5-20251001',
  stop_reason: 'tool_use',
  usage: { input_tokens: 80, output_tokens: 150 },
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('handleExtract — POST /api/extract', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
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
    const res = await handleExtract(req, mockEnv);
    expect(res.status).toBe(400);
  });

  it('AC1 — returns 422 when text is missing', async () => {
    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ satellite_id: 'sat_123' }),
    });
    const res = await handleExtract(req, mockEnv);
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
    const res = await handleExtract(req, mockEnv);
    expect(res.status).toBe(422);
    const body = await res.json() as { error: string; details: Record<string, string> };
    expect(body.details.text).toMatch(/2000/);
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

    const res = await handleExtract(req, mockEnv);
    expect(res.status).toBe(200);

    const body = await res.json() as {
      requirements: Record<string, unknown>;
      confidence: Record<string, number>;
      needs_confirmation: string[];
      ready_to_match: boolean;
    };

    // AC4: All 7 fields present in requirements
    expect(body.requirements).toHaveProperty('challenge');
    expect(body.requirements).toHaveProperty('skills_needed');
    expect(body.requirements).toHaveProperty('industry');
    expect(body.requirements).toHaveProperty('budget_range');
    expect(body.requirements).toHaveProperty('timeline');
    expect(body.requirements).toHaveProperty('company_size');
    expect(body.requirements).toHaveProperty('languages');

    // AC10: At least 5 fields with confidence > 0.5
    const highConfidenceFields = Object.values(body.confidence).filter((c) => c > 0.5);
    expect(highConfidenceFields.length).toBeGreaterThanOrEqual(5);

    // AC3: Response shape
    expect(Array.isArray(body.needs_confirmation)).toBe(true);
    expect(typeof body.ready_to_match).toBe('boolean');
  });

  // ── AC3 + AC6: ready_to_match = true when all confidence ≥ 0.7 ─────────────

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

    const res = await handleExtract(req, mockEnv);
    const body = await res.json() as {
      ready_to_match: boolean;
      needs_confirmation: string[];
      confirmation_questions?: unknown[];
    };

    expect(body.ready_to_match).toBe(true);
    expect(body.needs_confirmation).toHaveLength(0);
    expect(body.confirmation_questions).toBeUndefined();
  });

  // ── AC3 + AC5: needs_confirmation + questions when confidence < 0.7 ─────────

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
      body: JSON.stringify({ text: 'I want to build a chatbot.' }),
    });

    const res = await handleExtract(req, mockEnv);
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
    // All questions target low-confidence fields
    const lowConfidenceSet = new Set(body.needs_confirmation);
    for (const q of body.confirmation_questions) {
      expect(lowConfidenceSet.has(q.field)).toBe(true);
    }
  });

  // ── AC8: Claude API errors propagate as 502 ──────────────────────────────────

  it('AC8 — returns 502 when Anthropic API returns non-200', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ error: { type: 'authentication_error' } }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'I want AI automation for my company.' }),
    });

    const res = await handleExtract(req, mockEnv);
    expect(res.status).toBe(502);
  });

  // ── AC2: tool_use not returned → 500 ────────────────────────────────────────

  it('AC2 — returns 500 when Anthropic returns no tool_use block', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ id: 'msg', type: 'message', content: [{ type: 'text', text: 'hello' }] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const req = new Request('https://api.callibrate.io/api/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: 'Build me an AI.' }),
    });

    const res = await handleExtract(req, mockEnv);
    expect(res.status).toBe(500);
  });
});
