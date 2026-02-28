// E06S43: Shared extraction logic — extracted from routes/extract.ts
// performExtraction() encapsulates the OpenAI API call + circuit breaker check.
// Called by both the public /api/extract endpoint and the agent /api/agent/extract endpoint.

import type { Env } from '../types/env';
import type {
  ExtractionField,
  ExtractionQuestion,
  ExtractionResponse,
  FieldConfidence,
  ProspectRequirements,
} from '../types/matching';
import { isCircuitOpen, recordExtractionCost } from './circuitBreaker';
import { captureEvent } from './posthog';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

// ── Constants ─────────────────────────────────────────────────────────────────

export const KNOWN_VERTICALS = ['ai-consulting', 'automation', 'data-science', 'general'] as const;
export const EXTRACTION_FIELDS: ExtractionField[] = [
  'challenge',
  'skills_needed',
  'industry',
  'budget_range',
  'timeline',
  'company_size',
  'languages',
];
export const LOW_CONFIDENCE_THRESHOLD = 0.7;
export const MAX_CONFIRMATION_QUESTIONS = 3;
const MODEL = 'gpt-4o-mini';
const OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions';
const MAX_OUTPUT_TOKENS = 500;

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

// ── Result type ───────────────────────────────────────────────────────────────

export type ExtractionResult =
  | { ok: true; data: ExtractionResponse; tokensUsed: number; latencyMs: number }
  | { ok: false; error: string; status: number; detail?: unknown };

/**
 * Perform AI extraction on freetext input.
 * Handles circuit breaker check, OpenAI call, and result parsing.
 * Does NOT handle rate limiting or abuse prevention — callers are responsible.
 *
 * @param freetext     The raw prospect input text
 * @param satelliteId  Optional satellite ID for vertical context
 * @param env          Worker environment (needs OPENAI_API_KEY, SUPABASE_URL, etc.)
 * @param ctx          Execution context for fire-and-forget side effects
 */
export async function performExtraction(
  freetext: string,
  satelliteId: string | null,
  env: Env,
  ctx: ExecutionContext,
): Promise<ExtractionResult> {
  // Circuit breaker check
  const circuitOpen = await isCircuitOpen(env);
  if (circuitOpen) {
    return {
      ok: false,
      error: 'service_overloaded',
      status: 503,
      detail: 'Service temporairement surchargé. Réessayez dans quelques minutes.',
    };
  }

  // Load satellite vertical context
  let verticalContext: string | null = null;
  if (satelliteId) {
    try {
      const supabase = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
        auth: { persistSession: false },
      });
      const { data: satConfig } = await supabase
        .from('satellite_configs')
        .select('vertical')
        .eq('id', satelliteId)
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

  // Build system prompt
  const systemPrompt = verticalContext
    ? `You extract structured AI project requirements from prospect descriptions. This extraction is for the "${verticalContext}" industry vertical — pay special attention to terminology and requirements specific to this domain. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "reduce manual errors"). Be precise with confidence scores.`
    : 'You extract structured AI project requirements from prospect descriptions. Also extract desired_outcomes: concrete results the prospect wants to achieve (e.g. "save time on invoicing", "automate lead qualification"). Be precise with confidence scores.';

  // Call OpenAI
  const openaiBody = {
    model: MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: freetext },
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
    return { ok: false, error: 'AI service unreachable', status: 502, detail: String(fetchErr) };
  }

  if (!openaiRes.ok) {
    const errText = await openaiRes.text().catch(() => 'unknown');
    return { ok: false, error: 'OpenAI API error', status: 502, detail: { status: openaiRes.status, body: errText } };
  }

  let openaiData: unknown;
  try {
    openaiData = await openaiRes.json();
  } catch {
    return { ok: false, error: 'Invalid response from OpenAI API', status: 500 };
  }

  const latencyMs = Date.now() - llmStart;
  const tokensUsed = (() => {
    if (typeof openaiData !== 'object' || openaiData === null) return 0;
    const usage = (openaiData as Record<string, unknown>)['usage'];
    if (typeof usage !== 'object' || usage === null) return 0;
    return Number((usage as Record<string, unknown>)['total_tokens'] ?? 0);
  })();

  const toolCallResult = extractOpenAIToolCall(openaiData);
  if (!toolCallResult) {
    return { ok: false, error: 'Unexpected response shape from OpenAI API', status: 500, detail: 'No tool_calls found in response' };
  }

  const { requirements, confidence, confirmation_questions: llmQuestions } = toolCallResult;

  // Compute needs_confirmation
  const needs_confirmation: string[] = EXTRACTION_FIELDS.filter((field) => {
    const score = (confidence as Record<string, number>)[field];
    return typeof score !== 'number' || score < LOW_CONFIDENCE_THRESHOLD;
  });

  const ready_to_match = needs_confirmation.length === 0;

  // Build confirmation questions
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

  // Fire-and-forget: increment circuit breaker cost counter
  ctx.waitUntil(recordExtractionCost(env));

  // Analytics
  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: 'system:extract',
    event: 'llm.extraction_completed',
    properties: {
      model: MODEL,
      tokens_used: tokensUsed,
      latency_ms: latencyMs,
      satellite_id: satelliteId,
    },
  }));

  const data: ExtractionResponse = {
    requirements: requirements as ProspectRequirements,
    confidence: confidence as FieldConfidence,
    needs_confirmation,
    ready_to_match,
    ...(filteredQuestions ? { confirmation_questions: filteredQuestions } : {}),
  };

  return { ok: true, data, tokensUsed, latencyMs };
}
