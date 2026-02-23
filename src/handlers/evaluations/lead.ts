// ── POST /api/evaluations/lead ────────────────────────────────────────────────
// AC3: JWT-authenticated (expert session). Validates lead ownership, inserts into
// lead_evaluations, dispatches feedback.lead_evaluation to SCORE_COMPUTATION.
// Idempotent on lead_id: returns 409 on duplicate.

import { z } from 'zod';
import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { authenticate } from '../../middleware/auth';
import { captureEvent } from '../../lib/posthog';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const LeadEvaluationSchema = z.object({
  lead_id: z.string().uuid(),
  score: z.number().int().min(1).max(10),
  notes: z.string().optional(),
  conversion_declared: z.boolean().optional(),
});

export async function handleLeadEvaluation(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  // JWT auth (AC3 — expert session)
  const authResult = await authenticate(request, env);
  if (authResult.response) {
    return authResult.response;
  }
  const expertId = authResult.user.id;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const parsed = LeadEvaluationSchema.safeParse(body);
  if (!parsed.success) {
    return json({ error: 'Validation failed', details: parsed.error.flatten().fieldErrors }, 422);
  }

  const { lead_id, score, notes, conversion_declared } = parsed.data;

  const supabase = createServiceClient(env);

  // Fetch lead to verify existence and ownership (AC6)
  const { data: lead, error: leadError } = await supabase
    .from('leads')
    .select('expert_id')
    .eq('id', lead_id)
    .single();

  if (leadError) {
    if (leadError.code === 'PGRST116') {
      return json({ error: 'Lead not found' }, 404);
    }
    return json({ error: 'Failed to fetch lead', details: leadError.message }, 500);
  }

  // Ownership check (AC6)
  if (lead.expert_id !== expertId) {
    return json({ error: 'Forbidden' }, 403);
  }

  // INSERT into lead_evaluations (AC3)
  const { data: evaluation, error: insertError } = await supabase
    .from('lead_evaluations')
    .insert({
      lead_id,
      expert_id: expertId,
      lead_quality_score: score,
      notes: notes ?? null,
      conversion_declared: conversion_declared ?? false,
    })
    .select('id')
    .single();

  if (insertError) {
    if (insertError.code === '23505') {
      return json({ error: 'Already submitted' }, 409);
    }
    return json({ error: 'Failed to save evaluation', details: insertError.message }, 500);
  }

  // Dispatch to SCORE_COMPUTATION queue (AC7)
  await env.SCORE_COMPUTATION.send({ type: 'feedback.lead_evaluation', expert_id: expertId });

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expertId}`,
    event: 'survey.lead_evaluation_submitted',
    properties: {
      lead_quality_score: score,
      conversion_declared: conversion_declared ?? false,
    },
  }));

  return json({ id: evaluation.id }, 201);
}
