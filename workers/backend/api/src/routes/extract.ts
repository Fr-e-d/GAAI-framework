import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';
import type { Env } from '../types/env';
import { captureEvent } from '../lib/posthog';
import type {
  ExtractionField,
  ExtractionQuestion,
  ExtractionResponse,
  FieldConfidence,
  ProspectRequirements,
} from '../types/matching';
import { validateFreetext } from '../lib/inputValidation';
import { isCircuitOpen, recordExtractionCost } from '../lib/circuitBreaker';
import { signFlowToken, isValidProspectToken } from '../lib/jwt';
import { checkRateLimit } from '../lib/rateLimit';

// ── Constants ─────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const KNOWN_VERTICALS = ['ai-consulting', 'automation', 'data-science', 'general'] as const;
const EXTRACTION_FIELDS: ExtractionField[] = [
  'challenge',
  'skills_needed',
  'industry',
  'budget_range',
  'timeline',
  'company_size',
  'languages',
];
const LOW_CONFIDENCE_THRESHOLD = 0.7;
const MAX_CONFIRMATION_QUESTIONS = 3;
const MODEL = 'gpt-4o-mini';
const OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions';
const MAX_OUTPUT_TOKENS = 500; // AC10: cap per-request LLM cost

// ── Helpers ───────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200, headers?: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...(headers ?? {}) },
  });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

// Fake success response for honeypot / timing rejections (AC3, AC4).
// Returns 200 with benign-looking empty extraction — bots cannot detect the defense.
function fakeSuccessResponse(): Response {
  const fakeBody: ExtractionResponse = {
    requirements: {} as ProspectRequirements,
    confidence: {} as FieldConfidence,
    needs_confirmation: [],
    ready_to_match: false,
  };
  return jsonResponse(fakeBody);
}

// ── Extract-specific tiered rate limiting (AC5) ───────────────────────────────
// KV-based per-IP rate limiting with three tiers:
//   Tier 1: >= 4 requests in current minute window → 429 (Retry-After: 60)
//   Tier 2: >= 10 requests in current 10-minute window → 429 (Retry-After: 600)
//   Tier 3: 24h block flag set when Tier 2 exceeded → 429 (Retry-After: 86400)

async function checkExtractRateLimit(
  env: Env,
  ip: string,
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const now = Date.now();
  const minuteWindow = Math.floor(now / 60000);
  const tenMinWindow = Math.floor(now / 600000);

  const minKey = `extract-rate-min:${ip}:${minuteWindow}`;
  const tenMinKey = `extract-rate-10m:${ip}:${tenMinWindow}`;
  const blockKey = `extract-block:${ip}`;

  try {
    // Check 24h block first
    const blocked = await env.SESSIONS.get(blockKey);
    if (blocked) {
      return { allowed: false, retryAfter: 86400 };
    }

    // Tier 1: > 4/min
    const minRaw = await env.SESSIONS.get(minKey);
    const minCount = minRaw ? parseInt(minRaw, 10) : 0;
    if (minCount >= 4) {
      return { allowed: false, retryAfter: 60 };
    }

    // Tier 2: > 10/10min
    const tenMinRaw = await env.SESSIONS.get(tenMinKey);
    const tenMinCount = tenMinRaw ? parseInt(tenMinRaw, 10) : 0;
    if (tenMinCount >= 10) {
      // Tier 2 exceeded → set 24h block
      await env.SESSIONS.put(blockKey, '1', { expirationTtl: 86400 });
      return { allowed: false, retryAfter: 86400 };
    }

    // Increment both counters
    await Promise.all([
      env.SESSIONS.put(minKey, String(minCount + 1), { expirationTtl: 120 }),
      env.SESSIONS.put(tenMinKey, String(tenMinCount + 1), { expirationTtl: 1200 }),
    ]);

    return { allowed: true };
  } catch {
    return { allowed: true }; // fail open — KV errors must not block legitimate users
  }
}

// ── Cookie helpers ────────────────────────────────────────────────────────────

function getExtractionCount(request: Request): number {
  const cookieHeader = request.headers.get('Cookie') ?? '';
  const match = cookieHeader.match(/(?:^|;\s*)_extract_count=(\d+)/);
  return match?.[1] ? parseInt(match[1], 10) : 0;
}

function buildExtractionCountCookie(): string {
  return '_extract_count=1; HttpOnly; SameSite=Lax; Max-Age=86400; Path=/';
}

// ── OpenAI tool schema ────────────────────────────────────────────────────────

const EXTRACT_TOOL = {
  type: 'function',
  function: {
    name: 'extract_requirements',
    description:
      'Extract structured project requirements from a prospect description. For each field, assign a confidence score (0.0–1.0) reflecting how clearly the field is expressed in the text. Generate targeted confirmation questions for any field with confidence < 0.7.',
    parameters: {
      type: 'object',
      properties: {
        requirements: {
          type: 'object',
          description: 'Extracted project requirements',
          properties: {
            challenge: {
              type: 'string',
              description: 'Short summary of the core problem or challenge the prospect wants to solve',
            },
            skills_needed: {
              type: 'array',
              items: { type: 'string' },
              description: 'List of technical skills or expertise required (e.g. ["n8n", "Python", "Claude API"])',
            },
            industry: {
              type: 'string',
              description: 'Industry or sector of the prospect (e.g. "healthcare", "e-commerce", "finance")',
            },
            budget_range: {
              type: 'object',
              description: 'Project budget range in EUR',
              properties: {
                min: { type: 'number', description: 'Minimum budget in EUR' },
                max: { type: 'number', description: 'Maximum budget in EUR' },
              },
            },
            timeline: {
              type: 'string',
              description: 'Expected project timeline or urgency (e.g. "4 weeks", "ASAP", "3 months")',
            },
            company_size: {
              type: 'string',
              description: 'Size of the prospect company (e.g. "1-10", "50-200", "500+")',
            },
            languages: {
              type: 'array',
              items: { type: 'string' },
              description: 'Working languages for the project (e.g. ["French", "English"])',
            },
            desired_outcomes: {
              type: 'array',
              items: { type: 'string' },
              description: 'Concrete outcomes the prospect wants to achieve (e.g. "save time on invoicing", "reduce manual data entry", "automate lead qualification"). Extract from phrases like "I need to...", "I want to...", "so that...", "in order to...". Maximum 5 items.',
            },
          },
        },
        confidence: {
          type: 'object',
          description: 'Confidence score (0.0–1.0) for each extracted field',
          properties: {
            challenge: { type: 'number' },
            skills_needed: { type: 'number' },
            industry: { type: 'number' },
            budget_range: { type: 'number' },
            timeline: { type: 'number' },
            company_size: { type: 'number' },
            languages: { type: 'number' },
          },
          required: ['challenge', 'skills_needed', 'industry', 'budget_range', 'timeline', 'company_size', 'languages'],
        },
        confirmation_questions: {
          type: 'array',
          description: 'Questions to ask the prospect to clarify low-confidence fields (confidence < 0.7). Maximum 3 questions.',
          items: {
            type: 'object',
            properties: {
              field: { type: 'string', description: 'The field key this question targets' },
              question: { type: 'string', description: 'The question to ask the prospect in natural language' },
              options: {
                type: 'array',
                items: { type: 'string' },
                description: 'Optional multiple-choice answers if applicable',
              },
            },
            required: ['field', 'question'],
          },
        },
      },
      required: ['requirements', 'confidence'],
    },
  },
} as const;

// ── POST /api/extract ─────────────────────────────────────────────────────────
// 6-layer defense (E06S40 DEC-120) + abuse prevention (DEC-122).
// Layers ordered cheapest-first: reject garbage before it costs anything.

export async function handleExtract(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  // ── Parse request body ───────────────────────────────────────────────────────
  let body: {
    text?: unknown;
    satellite_id?: unknown;
    _hp?: unknown;   // AC3: honeypot (hidden field — bots fill it, humans don't)
    _ts?: unknown;   // AC4: page-load timestamp (ms since epoch)
  };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { text, satellite_id, _hp, _ts } = body;

  // ── Layer 2a: Honeypot check (AC3) ───────────────────────────────────────────
  // Hidden CSS field rendered by satellite frontend. Bots fill it; real users never see it.
  // Silent rejection: return fake 200 — do not reveal detection to the bot.
  if (typeof _hp === 'string' && _hp.length > 0) {
    return fakeSuccessResponse();
  }

  // ── Layer 2b: Timing check (AC4) ─────────────────────────────────────────────
  // _ts = page load timestamp set by satellite JS on DOMContentLoaded.
  // < 3 seconds from page load to submit = bot. Fake 200.
  // Missing or unparseable _ts → proceed (backwards compat with older clients).
  if (typeof _ts === 'number' || typeof _ts === 'string') {
    const tsNum = typeof _ts === 'number' ? _ts : parseInt(String(_ts), 10);
    if (!isNaN(tsNum) && Date.now() - tsNum < 3000) {
      return fakeSuccessResponse();
    }
  }

  // ── Layer 3: Rate limiting (AC5) ─────────────────────────────────────────────
  // Global limit (30/min all public endpoints via CF Rate Limiter)
  const globalRateCheck = await checkRateLimit(request, env);
  if (!globalRateCheck.allowed) {
    return errorResponse('Too Many Requests', 429);
  }

  // Extract-specific tiered limits: 4/min → 429, 10/10min → 429 + 24h block
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const extractRateCheck = await checkExtractRateLimit(env, ip);
  if (!extractRateCheck.allowed) {
    const retryAfter = extractRateCheck.retryAfter ?? 60;
    return new Response(
      JSON.stringify({ error: 'Too Many Requests' }),
      {
        status: 429,
        headers: { 'Content-Type': 'application/json', 'Retry-After': String(retryAfter) },
      },
    );
  }

  // ── Layer 1: Input pre-validation (AC1, AC2) ──────────────────────────────────
  // Pure CPU, ~0ms. Reject gibberish before any I/O or LLM cost.
  if (typeof text !== 'string' || !text.trim()) {
    return errorResponse('Validation failed', 422, { text: 'must be a non-empty string' });
  }

  if (text.length > 2000) {
    return errorResponse('Validation failed', 422, {
      text: `must be at most 2000 characters (got ${text.length})`,
    });
  }

  const freetextValidation = validateFreetext(text);
  if (!freetextValidation.valid) {
    return errorResponse('invalid_input', 422, {
      message: freetextValidation.reason,
    });
  }

  // ── Layer 6: Circuit breaker (AC8) ───────────────────────────────────────────
  // Check hourly cost accumulator. If > $10/hour → 503 until next hour resets key.
  const circuitOpen = await isCircuitOpen(env);
  if (circuitOpen) {
    return jsonResponse(
      {
        error: 'service_overloaded',
        message: 'Service temporairement surchargé. Réessayez dans quelques minutes.',
        retry_after: 300,
      },
      503,
    );
  }

  // ── Abuse prevention: extraction count (AC9) ──────────────────────────────────
  // After 1 extraction, unidentified users must identify before extracting again.
  // Identified users (hold a valid prospect JWT in Authorization header) are exempt.
  const authHeader = request.headers.get('Authorization');
  const bearerToken = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  const isIdentified = bearerToken
    ? await isValidProspectToken(bearerToken, env.PROSPECT_TOKEN_SECRET)
    : false;

  if (!isIdentified) {
    // Cookie-based primary control
    const cookieCount = getExtractionCount(request);
    if (cookieCount >= 1) {
      return errorResponse('identification_required', 403, {
        message: 'Identifiez-vous pour continuer.',
      });
    }

    // IP-based fallback: max 3/24h per IP (handles users who clear cookies)
    const ipKey = `extract-ip:${ip}`;
    try {
      const ipRaw = await env.SESSIONS.get(ipKey);
      const ipCount = ipRaw ? parseInt(ipRaw, 10) : 0;
      if (ipCount >= 3) {
        return errorResponse('identification_required', 403, {
          message: 'Identifiez-vous pour continuer.',
        });
      }
    } catch { /* fail open */ }
  }

  // ── Load satellite vertical context ──────────────────────────────────────────
  let verticalContext: string | null = null;

  if (typeof satellite_id === 'string' && satellite_id) {
    try {
      const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
        auth: { persistSession: false },
      });

      const { data: satConfig } = await supabase
        .from('satellite_configs')
        .select('vertical')
        .eq('id', satellite_id)
        .maybeSingle();

      if (satConfig?.vertical && typeof satConfig.vertical === 'string') {
        if ((KNOWN_VERTICALS as readonly string[]).includes(satConfig.vertical)) {
          verticalContext = satConfig.vertical;
        }
      }
    } catch {
      // Non-blocking: proceed without vertical context
    }
  }

  // ── Build system prompt ───────────────────────────────────────────────────────
  const systemPrompt = verticalContext
    ? `You extract structured AI project requirements from prospect descriptions. This extraction is for the "${verticalContext}" industry vertical — pay special attention to terminology and requirements specific to this domain. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "reduce manual errors"). Be precise with confidence scores.`
    : 'You extract structured AI project requirements from prospect descriptions. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "automate lead qualification"). Be precise with confidence scores.';

  // ── Call OpenAI (AC10: max_tokens: 500) ──────────────────────────────────────
  const openaiBody = {
    model: MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: text },
    ],
    tools: [EXTRACT_TOOL],
    tool_choice: { type: 'function', function: { name: 'extract_requirements' } },
    max_tokens: MAX_OUTPUT_TOKENS,
  };

  const llmStart = Date.now();

  let openaiRes: Response;
  try {
    openaiRes = await fetch(OPENAI_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(openaiBody),
    });
  } catch (fetchErr) {
    return errorResponse('AI service unreachable', 502, { detail: String(fetchErr) });
  }

  if (!openaiRes.ok) {
    const errText = await openaiRes.text().catch(() => 'unknown');
    return errorResponse('OpenAI API error', 502, {
      status: openaiRes.status,
      detail: errText,
    });
  }

  // ── Parse tool_calls response ─────────────────────────────────────────────────
  let openaiData: unknown;
  try {
    openaiData = await openaiRes.json();
  } catch {
    return errorResponse('Invalid response from OpenAI API', 500);
  }

  const llmLatencyMs = Date.now() - llmStart;
  const openaiUsage = (() => {
    if (typeof openaiData !== 'object' || openaiData === null) return 0;
    const usage = (openaiData as Record<string, unknown>)['usage'];
    if (typeof usage !== 'object' || usage === null) return 0;
    return (usage as Record<string, unknown>)['total_tokens'] ?? 0;
  })();

  const toolCallResult = extractOpenAIToolCall(openaiData);
  if (!toolCallResult) {
    return errorResponse('Unexpected response shape from OpenAI API', 500, {
      detail: 'No tool_calls found in response',
    });
  }

  const { requirements, confidence, confirmation_questions: llmQuestions } = toolCallResult;

  // ── Compute needs_confirmation ────────────────────────────────────────────────
  const needs_confirmation: string[] = EXTRACTION_FIELDS.filter((field) => {
    const score = (confidence as Record<string, number>)[field];
    return typeof score !== 'number' || score < LOW_CONFIDENCE_THRESHOLD;
  });

  const ready_to_match = needs_confirmation.length === 0;

  // ── Build confirmation questions ──────────────────────────────────────────────
  let filteredQuestions: ExtractionQuestion[] | undefined;
  if (!ready_to_match && Array.isArray(llmQuestions) && llmQuestions.length > 0) {
    const lowConfidenceSet = new Set(needs_confirmation);
    filteredQuestions = (llmQuestions as ExtractionQuestion[])
      .filter((q) => typeof q.field === 'string' && lowConfidenceSet.has(q.field))
      .slice(0, MAX_CONFIRMATION_QUESTIONS);

    if (filteredQuestions.length === 0) {
      filteredQuestions = undefined;
    }
  }

  // ── Post-LLM side effects (fire-and-forget) ────────────────────────────────────

  // AC8: increment circuit breaker cost counter
  ctx.waitUntil(recordExtractionCost(env));

  // AC9: update IP extraction counter (non-identified users only)
  if (!isIdentified) {
    const ipKey = `extract-ip:${ip}`;
    ctx.waitUntil(
      (async () => {
        try {
          const ipRaw = await env.SESSIONS.get(ipKey);
          const ipCount = ipRaw ? parseInt(ipRaw, 10) : 0;
          await env.SESSIONS.put(ipKey, String(ipCount + 1), { expirationTtl: 86400 });
        } catch { /* non-critical */ }
      })(),
    );
  }

  // AC11: generate signed flow token (proves legitimate extraction → confirmation → submit path)
  const extractionId = crypto.randomUUID();
  const flowToken = await signFlowToken(extractionId, env.PROSPECT_TOKEN_SECRET);

  // AC9: set extraction count cookie (non-identified users only)
  const responseHeaders: Record<string, string> = {};
  if (!isIdentified) {
    responseHeaders['Set-Cookie'] = buildExtractionCountCookie();
  }

  // Analytics
  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: 'system:extract',
    event: 'llm.extraction_completed',
    properties: {
      model: MODEL,
      tokens_used: openaiUsage,
      latency_ms: llmLatencyMs,
      satellite_id: typeof satellite_id === 'string' ? satellite_id : null,
    },
  }));

  // ── Return structured response ────────────────────────────────────────────────
  const response: ExtractionResponse & { flow_token: string } = {
    requirements: requirements as ProspectRequirements,
    confidence: confidence as FieldConfidence,
    needs_confirmation,
    ready_to_match,
    flow_token: flowToken, // AC11: client must include in Authorization header or flow_token body field on /api/prospects/submit
    ...(filteredQuestions ? { confirmation_questions: filteredQuestions } : {}),
  };

  return jsonResponse(response, 200, responseHeaders);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

interface ToolUseInput {
  requirements: unknown;
  confidence: unknown;
  confirmation_questions?: unknown;
}

function extractOpenAIToolCall(data: unknown): ToolUseInput | null {
  if (typeof data !== 'object' || data === null) return null;
  const msg = data as Record<string, unknown>;
  const choices = msg['choices'];
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const message = (choices[0] as Record<string, unknown>)['message'];
  if (typeof message !== 'object' || message === null) return null;
  const toolCalls = (message as Record<string, unknown>)['tool_calls'];
  if (!Array.isArray(toolCalls) || toolCalls.length === 0) return null;
  const fn = (toolCalls[0] as Record<string, unknown>)['function'];
  if (typeof fn !== 'object' || fn === null) return null;
  const args = (fn as Record<string, unknown>)['arguments'];
  if (typeof args !== 'string') return null;
  try {
    const parsed = JSON.parse(args);
    if (typeof parsed !== 'object' || parsed === null) return null;
    return parsed as ToolUseInput;
  } catch {
    return null;
  }
}
