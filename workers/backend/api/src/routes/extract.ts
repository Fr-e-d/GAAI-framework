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

// ── Helpers ───────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
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
              description: 'Concrete outcomes the prospect wants to achieve (e.g. ["save time on invoicing", "reduce manual data entry", "automate lead qualification"]). Extract from phrases like "I need to...", "I want to...", "so that...", "in order to...". Maximum 5 items.',
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
// AC1–AC8: Stateless freetext extraction service

export async function handleExtract(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  // ── Parse and validate request body (AC1) ───────────────────────────────────
  let body: { text?: unknown; satellite_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { text, satellite_id } = body;

  if (typeof text !== 'string' || !text.trim()) {
    return errorResponse('Validation failed', 422, { text: 'must be a non-empty string' });
  }

  if (text.length > 2000) {
    return errorResponse('Validation failed', 422, {
      text: `must be at most 2000 characters (got ${text.length})`,
    });
  }

  // ── Load satellite vertical context (AC6) ───────────────────────────────────
  // Non-blocking: errors or missing satellite_id → proceed without context
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

  // ── Build system prompt (AC6: inject vertical context when available) ─────────
  const systemPrompt = verticalContext
    ? `You extract structured AI project requirements from prospect descriptions. This extraction is for the "${verticalContext}" industry vertical — pay special attention to terminology and requirements specific to this domain. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "reduce manual errors"). Be precise with confidence scores.`
    : 'You extract structured AI project requirements from prospect descriptions. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "automate lead qualification"). Be precise with confidence scores.';

  // ── Call OpenAI Chat Completions API (AC2) ────────────────────────────────────
  const openaiBody = {
    model: MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: text },
    ],
    tools: [EXTRACT_TOOL],
    tool_choice: { type: 'function', function: { name: 'extract_requirements' } },
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

  // ── Parse tool_calls response (AC3) ──────────────────────────────────────────
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
  // Only included when ready_to_match is false, capped at MAX_CONFIRMATION_QUESTIONS
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

  // ── Return structured response (AC1: stateless — no DB writes) ───────────────
  const response: ExtractionResponse = {
    requirements: requirements as ProspectRequirements,
    confidence: confidence as FieldConfidence,
    needs_confirmation,
    ready_to_match,
    ...(filteredQuestions ? { confirmation_questions: filteredQuestions } : {}),
  };

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

  return jsonResponse(response);
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
