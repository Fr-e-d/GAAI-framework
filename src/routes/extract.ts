import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';
import type { Env } from '../types/env';
import type {
  ExtractionField,
  ExtractionQuestion,
  ExtractionResponse,
  FieldConfidence,
  ProspectRequirements,
} from '../types/matching';

// ── Constants ─────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };
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
const MODEL = 'claude-haiku-4-5-20251001';
const ANTHROPIC_VERSION = '2023-06-01';

// ── Helpers ───────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

// ── Anthropic tool schema ─────────────────────────────────────────────────────

const EXTRACT_TOOL = {
  name: 'extract_requirements',
  description:
    'Extract structured project requirements from a prospect description. For each field, assign a confidence score (0.0–1.0) reflecting how clearly the field is expressed in the text. Generate targeted confirmation questions for any field with confidence < 0.7.',
  input_schema: {
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
} as const;

// ── POST /api/extract ─────────────────────────────────────────────────────────
// AC1–AC9: Stateless freetext extraction service

export async function handleExtract(request: Request, env: Env): Promise<Response> {
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

  // ── Load satellite vertical context (AC9) ───────────────────────────────────
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
        verticalContext = satConfig.vertical;
      }
    } catch {
      // Non-blocking: proceed without vertical context
    }
  }

  // ── Build system prompt (AC9: inject vertical context when available) ────────
  const systemPrompt = verticalContext
    ? `You extract structured AI project requirements from prospect descriptions. This extraction is for the "${verticalContext}" industry vertical — pay special attention to terminology and requirements specific to this domain. Be precise with confidence scores.`
    : 'You extract structured AI project requirements from prospect descriptions. Be precise with confidence scores.';

  // ── Call Claude via Cloudflare AI Gateway (AC2, AC8) ─────────────────────────
  const apiUrl = `${env.CLOUDFLARE_AI_GATEWAY_URL}/v1/messages`;

  const anthropicBody = {
    model: MODEL,
    max_tokens: 1024,
    system: systemPrompt,
    tools: [EXTRACT_TOOL],
    tool_choice: { type: 'tool', name: 'extract_requirements' },
    messages: [
      {
        role: 'user',
        content: text,
      },
    ],
  };

  let anthropicRes: Response;
  try {
    anthropicRes = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify(anthropicBody),
    });
  } catch (fetchErr) {
    return errorResponse('AI Gateway unreachable', 502, { detail: String(fetchErr) });
  }

  if (!anthropicRes.ok) {
    const errText = await anthropicRes.text().catch(() => 'unknown');
    return errorResponse('Anthropic API error', 502, {
      status: anthropicRes.status,
      detail: errText,
    });
  }

  // ── Parse tool_use response (AC2) ────────────────────────────────────────────
  let anthropicData: unknown;
  try {
    anthropicData = await anthropicRes.json();
  } catch {
    return errorResponse('Invalid response from Anthropic API', 500);
  }

  const toolUseBlock = extractToolUseBlock(anthropicData);
  if (!toolUseBlock) {
    return errorResponse('Unexpected response shape from Anthropic API', 500, {
      detail: 'No tool_use block found in response',
    });
  }

  const { requirements, confidence, confirmation_questions: llmQuestions } = toolUseBlock;

  // ── Compute needs_confirmation (AC3) ─────────────────────────────────────────
  const needs_confirmation: string[] = EXTRACTION_FIELDS.filter((field) => {
    const score = (confidence as Record<string, number>)[field];
    return typeof score !== 'number' || score < LOW_CONFIDENCE_THRESHOLD;
  });

  const ready_to_match = needs_confirmation.length === 0;

  // ── Build confirmation questions (AC5, AC6) ──────────────────────────────────
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

  // ── Return structured response (AC3, AC7: stateless — no DB writes) ──────────
  const response: ExtractionResponse = {
    requirements: requirements as ProspectRequirements,
    confidence: confidence as FieldConfidence,
    needs_confirmation,
    ready_to_match,
    ...(filteredQuestions ? { confirmation_questions: filteredQuestions } : {}),
  };

  return jsonResponse(response);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

interface ToolUseInput {
  requirements: unknown;
  confidence: unknown;
  confirmation_questions?: unknown;
}

function extractToolUseBlock(data: unknown): ToolUseInput | null {
  if (typeof data !== 'object' || data === null) return null;

  const message = data as Record<string, unknown>;
  const content = message['content'];
  if (!Array.isArray(content)) return null;

  for (const block of content) {
    if (
      typeof block === 'object' &&
      block !== null &&
      (block as Record<string, unknown>)['type'] === 'tool_use' &&
      (block as Record<string, unknown>)['name'] === 'extract_requirements'
    ) {
      const input = (block as Record<string, unknown>)['input'];
      if (typeof input === 'object' && input !== null) {
        return input as ToolUseInput;
      }
    }
  }

  return null;
}
