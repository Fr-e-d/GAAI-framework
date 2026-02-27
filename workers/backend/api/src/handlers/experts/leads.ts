// E06S38: GET /api/experts/:id/leads — paginated lead list for expert dashboard
// E06S38: POST /api/leads/:id/evaluate — expert lead evaluation

import { z } from 'zod';
import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createSql } from '../../lib/db';
import { captureEvent } from '../../lib/posthog';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

const VALID_STATUSES = ['new', 'confirmed', 'flagged', 'all'] as const;
type LeadStatus = (typeof VALID_STATUSES)[number];

function forbidden(): Response {
  return new Response(JSON.stringify({ error: 'Forbidden' }), {
    status: 403,
    headers: JSON_HEADERS,
  });
}

// ── GET /api/experts/:id/leads ────────────────────────────────────────────────

export async function handleGetLeads(
  request: Request,
  env: Env,
  user: AuthUser,
  expertId: string,
): Promise<Response> {
  // Ownership check
  if (user.id !== expertId) {
    return forbidden();
  }

  const url = new URL(request.url);
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10) || 1);
  const perPage = Math.min(Math.max(1, parseInt(url.searchParams.get('per_page') ?? '20', 10) || 20), 50);
  const statusParam = url.searchParams.get('status') ?? 'all';

  // Validate status param
  if (!VALID_STATUSES.includes(statusParam as LeadStatus)) {
    return new Response(
      JSON.stringify({ error: 'Validation failed', details: { status: 'must be one of: new, confirmed, flagged, all' } }),
      { status: 422, headers: JSON_HEADERS },
    );
  }

  const status = statusParam as LeadStatus;
  const offset = (page - 1) * perPage;

  const sql = createSql(env);

  // Count query
  const countRows = await sql<{ count: string }[]>`
    SELECT COUNT(*) AS count
    FROM leads l
    WHERE l.expert_id = ${expertId}
      AND (${status} = 'all' OR l.status = ${status})
  `;
  const total = parseInt(countRows[0]?.count ?? '0', 10);

  // Main query with JOINs
  const rows = await sql<{
    id: string;
    status: string | null;
    price_cents: number | null;
    created_at: string | null;
    confirmed_at: string | null;
    flagged_at: string | null;
    flag_reason: string | null;
    flag_window_expires_at: string | null;
    evaluation_score: number | null;
    evaluation_notes: string | null;
    conversion_declared: boolean;
    evaluated_at: string | null;
    prospect_id: string | null;
    prospect_email: string | null;
    prospect_requirements: unknown;
    match_score: number | null;
    booking_id: string | null;
    booking_starts_at: string | null;
    booking_status: string | null;
  }[]>`
    SELECT
      l.id,
      l.status,
      l.amount AS price_cents,
      l.created_at,
      l.confirmed_at,
      l.flagged_at,
      l.flag_reason,
      (l.created_at + interval '7 days') AS flag_window_expires_at,
      l.evaluation_score,
      l.evaluation_notes,
      l.conversion_declared,
      l.evaluated_at,
      p.id AS prospect_id,
      p.email AS prospect_email,
      p.requirements AS prospect_requirements,
      m.score AS match_score,
      b.id AS booking_id,
      b.start_at AS booking_starts_at,
      b.status AS booking_status
    FROM leads l
    LEFT JOIN prospects p ON p.id = l.prospect_id
    LEFT JOIN LATERAL (
      SELECT score FROM matches
      WHERE expert_id = l.expert_id AND prospect_id = l.prospect_id
      ORDER BY created_at DESC LIMIT 1
    ) m ON true
    LEFT JOIN bookings b ON b.id = l.booking_id
    WHERE l.expert_id = ${expertId}
      AND (${status} = 'all' OR l.status = ${status})
    ORDER BY l.created_at DESC
    LIMIT ${perPage} OFFSET ${offset}
  `;

  const leads = rows.map((r) => ({
    id: r.id,
    status: r.status,
    price_cents: r.price_cents,
    created_at: r.created_at,
    confirmed_at: r.confirmed_at,
    flagged_at: r.flagged_at,
    flag_reason: r.flag_reason,
    flag_window_expires_at: r.flag_window_expires_at,
    evaluation_score: r.evaluation_score,
    evaluation_notes: r.evaluation_notes,
    conversion_declared: r.conversion_declared,
    evaluated_at: r.evaluated_at,
    prospect: r.prospect_id
      ? { id: r.prospect_id, email: r.prospect_email, requirements: r.prospect_requirements }
      : null,
    match_score: r.match_score,
    booking: r.booking_id
      ? { id: r.booking_id, starts_at: r.booking_starts_at, status: r.booking_status }
      : null,
  }));

  return new Response(
    JSON.stringify({ leads, total, page, per_page: perPage }),
    { status: 200, headers: JSON_HEADERS },
  );
}

// ── POST /api/leads/:id/evaluate ──────────────────────────────────────────────

const EvaluateLeadSchema = z.object({
  score: z.number().int().min(1).max(10),
  notes: z.string().max(500).optional(),
  conversion_declared: z.boolean().optional(),
});

export async function handleEvaluateLead(
  request: Request,
  env: Env,
  user: AuthUser,
  leadId: string,
  ctx: ExecutionContext,
): Promise<Response> {
  const sql = createSql(env);

  // Fetch lead for ownership + status check
  const [lead] = await sql<{
    id: string;
    expert_id: string | null;
    status: string | null;
    evaluation_score: number | null;
  }[]>`
    SELECT id, expert_id, status, evaluation_score
    FROM leads
    WHERE id = ${leadId}
  `;

  if (!lead) {
    return new Response(JSON.stringify({ error: 'Lead not found' }), {
      status: 404,
      headers: JSON_HEADERS,
    });
  }

  // Ownership check
  if (lead.expert_id !== user.id) {
    return forbidden();
  }

  // Status check — must be confirmed
  if (lead.status !== 'confirmed') {
    return new Response(JSON.stringify({ error: 'Lead must have status confirmed' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  // Already evaluated check
  if (lead.evaluation_score !== null) {
    return new Response(JSON.stringify({ error: 'Lead already evaluated' }), {
      status: 409,
      headers: JSON_HEADERS,
    });
  }

  // Parse + validate body
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  const parsed = EvaluateLeadSchema.safeParse(body);
  if (!parsed.success) {
    return new Response(
      JSON.stringify({ error: 'Validation failed', details: parsed.error.flatten().fieldErrors }),
      { status: 422, headers: JSON_HEADERS },
    );
  }

  const { score, notes = null, conversion_declared = false } = parsed.data;

  // Update lead
  const [updated] = await sql<{
    id: string;
    status: string | null;
    evaluation_score: number | null;
    evaluation_notes: string | null;
    conversion_declared: boolean;
    evaluated_at: string | null;
  }[]>`
    UPDATE leads
    SET evaluation_score = ${score},
        evaluation_notes = ${notes},
        conversion_declared = ${conversion_declared},
        evaluated_at = NOW()
    WHERE id = ${leadId}
    RETURNING id, status, evaluation_score, evaluation_notes, conversion_declared, evaluated_at
  `;

  // Fire-and-forget PostHog event (AC25)
  ctx.waitUntil(
    captureEvent(env.POSTHOG_API_KEY, {
      distinctId: `expert:${user.id}`,
      event: 'expert.lead_evaluated',
      properties: {
        lead_id: leadId,
        score,
        conversion_declared,
      },
    }),
  );

  return new Response(JSON.stringify(updated), { status: 200, headers: JSON_HEADERS });
}
