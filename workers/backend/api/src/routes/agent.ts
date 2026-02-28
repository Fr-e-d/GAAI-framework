// E06S43: Agent API handlers
// These handlers are called by both the direct agent routes (/api/agent/*) and the MCP server.
// Authentication is handled by the caller (agentAuth middleware).

import type { Env } from '../types/env';
import { validateFreetext } from '../lib/inputValidation';
import { performExtraction } from '../lib/extraction';
import { checkAgentRateLimit } from '../lib/agentRateLimit';
import { signRevealConfirmToken, verifyRevealConfirmToken } from '../lib/jwt';
import { sendEmail, buildAgentRevealEmail, buildAgentBookingEmail } from '../lib/email';
import { captureEvent } from '../lib/posthog';
import { createSql } from '../lib/db';
import type { ProspectRequirements } from '../types/matching';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface AgentCtx {
  prospect_id: string;
  key_id: string;
  key_hash: string;
}

const JSON_HEADERS = { 'Content-Type': 'application/json' };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function errorResponse(error: string, status: number, details?: unknown): Response {
  return jsonResponse({ error, ...(details ? { details } : {}) }, status);
}

// ── POST /api/agent/extract ───────────────────────────────────────────────────
// Extract requirements from a freetext project description.
// Rate limit: 10/min per API key.

export async function handleAgentExtract(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  agent: AgentCtx,
): Promise<Response> {
  // Rate limit
  const rateCheck = await checkAgentRateLimit(env.SESSIONS, agent.key_hash, 'extract');
  if (!rateCheck.allowed) {
    return new Response(JSON.stringify({ error: 'rate_limit_exceeded' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json', 'Retry-After': String(rateCheck.retryAfter ?? 60) },
    });
  }

  // Parse body
  let body: { text?: unknown; satellite_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { text, satellite_id } = body;

  if (typeof text !== 'string' || !text.trim()) {
    return errorResponse('Validation failed', 422, { text: 'required, non-empty string' });
  }

  if (text.length > 2000) {
    return errorResponse('Validation failed', 422, { text: `max 2000 characters (got ${text.length})` });
  }

  const freetextValidation = validateFreetext(text);
  if (!freetextValidation.valid) {
    return errorResponse('invalid_input', 422, { message: freetextValidation.reason });
  }

  const effectiveSatelliteId = typeof satellite_id === 'string' && satellite_id ? satellite_id : null;
  const result = await performExtraction(text, effectiveSatelliteId, env, ctx);

  if (!result.ok) {
    if (result.status === 503) {
      return jsonResponse({ error: result.error, message: result.detail, retry_after: 300 }, 503);
    }
    return errorResponse(result.error, result.status, result.detail);
  }

  return jsonResponse(result.data);
}

// ── POST /api/agent/match ─────────────────────────────────────────────────────
// Run matching for extracted requirements. Creates a prospect_projects record.
// Returns anonymized match results (no expert_id exposed).
// Rate limit: 5/min per API key.

export async function handleAgentMatch(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  agent: AgentCtx,
): Promise<Response> {
  // Rate limit
  const rateCheck = await checkAgentRateLimit(env.SESSIONS, agent.key_hash, 'match');
  if (!rateCheck.allowed) {
    return new Response(JSON.stringify({ error: 'rate_limit_exceeded' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json', 'Retry-After': String(rateCheck.retryAfter ?? 60) },
    });
  }

  // Parse body
  let body: { requirements?: unknown; satellite_id?: unknown; freetext?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { requirements, satellite_id, freetext } = body;

  if (!requirements || typeof requirements !== 'object' || Array.isArray(requirements)) {
    return errorResponse('Validation failed', 422, { requirements: 'required object' });
  }

  const sql = createSql(env);

  try {
    // Create a prospect_projects record
    const projectRows = await sql<{ id: string }[]>`
      INSERT INTO prospect_projects (prospect_id, satellite_id, freetext, requirements, status)
      VALUES (
        ${agent.prospect_id},
        ${typeof satellite_id === 'string' && satellite_id ? satellite_id : null},
        ${typeof freetext === 'string' && freetext ? freetext : null},
        ${JSON.stringify(requirements)},
        'pending'
      )
      RETURNING id
    `;

    const project = projectRows[0];
    if (!project) {
      return errorResponse('internal_error', 500);
    }

    await sql.end().catch(() => {});

    // Delegate to match compute
    const matchRequest = new Request('https://internal/api/matches/compute', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prospect_id: agent.prospect_id,
        satellite_id: typeof satellite_id === 'string' && satellite_id ? satellite_id : null,
        project_id: project.id,
      }),
    });

    const matchResponse = await import('./matches').then(m => m.handleMatchCompute(matchRequest, env, ctx));

    if (!matchResponse.ok) {
      return matchResponse;
    }

    const matchData = await matchResponse.json() as {
      computed: number;
      top_matches: { match_id?: string; score?: number; score_breakdown?: unknown }[];
    };

    // Anonymize results — return match_id + score but NOT expert_id
    const anonymized = (matchData.top_matches ?? []).map((m: Record<string, unknown>) => ({
      match_id: m['match_id'] ?? m['id'],
      score: m['score'],
      score_breakdown: m['score_breakdown'],
    }));

    // PostHog event
    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: agent.prospect_id,
      event: 'agent.match_computed',
      properties: {
        key_id: agent.key_id,
        project_id: project.id,
        matches_computed: matchData.computed,
      },
    }));

    return jsonResponse({
      project_id: project.id,
      computed: matchData.computed,
      top_matches: anonymized,
    });
  } catch (err) {
    await sql.end().catch(() => {});
    throw err;
  }
}

// ── POST /api/agent/reveal ────────────────────────────────────────────────────
// Request reveal of an expert profile. Sends confirmation email to the prospect.
// Rate limit: 3/hour per API key.

export async function handleAgentRevealRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  agent: AgentCtx,
): Promise<Response> {
  // Rate limit
  const rateCheck = await checkAgentRateLimit(env.SESSIONS, agent.key_hash, 'reveal');
  if (!rateCheck.allowed) {
    return new Response(JSON.stringify({ error: 'rate_limit_exceeded' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json', 'Retry-After': String(rateCheck.retryAfter ?? 3600) },
    });
  }

  // Parse body
  let body: { match_id?: unknown; project_summary?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { match_id, project_summary } = body;

  if (typeof match_id !== 'string' || !match_id) {
    return errorResponse('Validation failed', 422, { match_id: 'required string' });
  }

  const projectSummary = typeof project_summary === 'string' && project_summary
    ? project_summary
    : 'AI automation project';

  const sql = createSql(env);

  try {
    // Verify this match belongs to the prospect
    const matchRows = await sql<{ id: string; expert_id: string }[]>`
      SELECT m.id, m.expert_id
      FROM matches m
      WHERE m.id = ${match_id}
        AND m.prospect_id = ${agent.prospect_id}
      LIMIT 1
    `;

    if (matchRows.length === 0) {
      return errorResponse('not_found', 404);
    }

    const match = matchRows[0]!;

    // Get expert display_name for email
    const expertRows = await sql<{ display_name: string | null; email: string | null }[]>`
      SELECT e.display_name, p.email
      FROM experts e
      LEFT JOIN prospects p ON p.id = ${agent.prospect_id}
      WHERE e.id = ${match.expert_id}
      LIMIT 1
    `;

    await sql.end().catch(() => {});

    const expertName = expertRows[0]?.display_name ?? 'Expert';
    const prospectEmail = expertRows[0]?.email;

    if (!prospectEmail) {
      return errorResponse('prospect_email_missing', 422);
    }

    // Sign reveal confirmation token (24h TTL)
    const confirmToken = await signRevealConfirmToken(match_id, agent.prospect_id, env.AGENT_API_KEY_SECRET);
    const refuseToken = await signRevealConfirmToken(match_id, agent.prospect_id, env.AGENT_API_KEY_SECRET);

    // Store reveal state in KV (48h TTL)
    const kvKey = `agent-reveal:${match_id}`;
    await env.SESSIONS.put(
      kvKey,
      JSON.stringify({
        match_id,
        prospect_id: agent.prospect_id,
        expert_id: match.expert_id,
        status: 'pending',
        requested_at: new Date().toISOString(),
      }),
      { expirationTtl: 172800 }, // 48h
    );

    // Build email URLs
    const baseUrl = env.WORKER_BASE_URL;
    const confirmUrl = `${baseUrl}/api/agent/reveal/confirm?token=${encodeURIComponent(confirmToken)}`;
    const refuseUrl = `${baseUrl}/api/agent/reveal/refuse?token=${encodeURIComponent(refuseToken)}`;

    const { html, text } = buildAgentRevealEmail({
      expertName,
      projectSummary,
      confirmUrl,
      refuseUrl,
    });

    ctx.waitUntil(
      sendEmail(
        {
          to: prospectEmail,
          subject: 'Votre assistant IA demande accès à un profil expert',
          html,
          text,
        },
        {
          apiKey: env.RESEND_API_KEY,
          fromDomain: env.EMAIL_FROM_DOMAIN,
          replyTo: env.EMAIL_REPLY_TO,
        },
      ).catch((err) => console.error('[agent.reveal] email send failed:', err)),
    );

    // PostHog event
    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: agent.prospect_id,
      event: 'agent.reveal_requested',
      properties: { key_id: agent.key_id, match_id },
    }));

    return jsonResponse({ match_id, status: 'pending', message: 'Confirmation email sent to prospect.' });
  } catch (err) {
    await sql.end().catch(() => {});
    throw err;
  }
}

// ── GET /api/agent/reveal/confirm?token=... ────────────────────────────────────
// Called from email link. Confirms the reveal and returns HTML response.

export async function handleAgentRevealConfirm(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  if (!token) {
    return htmlResponse('<h1>Lien invalide</h1><p>Ce lien de confirmation est invalide ou a expiré.</p>', 400);
  }

  const claims = await verifyRevealConfirmToken(token, env.AGENT_API_KEY_SECRET);
  if (!claims) {
    return htmlResponse('<h1>Lien expiré</h1><p>Ce lien de confirmation a expiré ou est invalide. Demandez à votre assistant de renouveler la demande.</p>', 400);
  }

  const kvKey = `agent-reveal:${claims.match_id}`;
  const kvValue = await env.SESSIONS.get(kvKey);

  if (!kvValue) {
    return htmlResponse('<h1>Demande introuvable</h1><p>Cette demande d\'accès n\'existe plus ou a déjà été traitée.</p>', 404);
  }

  const revealState = JSON.parse(kvValue) as { status: string; expert_id: string };

  if (revealState.status !== 'pending') {
    return htmlResponse('<h1>Déjà traité</h1><p>Cette demande d\'accès a déjà été traitée.</p>', 200);
  }

  // Update status to confirmed
  const updatedState = { ...revealState, status: 'confirmed', confirmed_at: new Date().toISOString() };
  await env.SESSIONS.put(kvKey, JSON.stringify(updatedState), { expirationTtl: 172800 });

  // PostHog event
  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: claims.prospect_id,
    event: 'agent.reveal_confirmed',
    properties: { match_id: claims.match_id },
  }));

  return htmlResponse(
    '<h1>Accès confirmé</h1><p>Votre assistant IA peut maintenant consulter le profil de cet expert. Vous serez notifié si une mise en relation est engagée.</p>',
    200,
  );
}

// ── GET /api/agent/reveal/refuse?token=... ─────────────────────────────────────
// Called from email link. Refuses the reveal and returns HTML response.

export async function handleAgentRevealRefuse(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  if (!token) {
    return htmlResponse('<h1>Lien invalide</h1><p>Ce lien est invalide ou a expiré.</p>', 400);
  }

  const claims = await verifyRevealConfirmToken(token, env.AGENT_API_KEY_SECRET);
  if (!claims) {
    return htmlResponse('<h1>Lien expiré</h1><p>Ce lien a expiré ou est invalide.</p>', 400);
  }

  const kvKey = `agent-reveal:${claims.match_id}`;
  const kvValue = await env.SESSIONS.get(kvKey);

  if (!kvValue) {
    return htmlResponse('<h1>Demande introuvable</h1><p>Cette demande d\'accès n\'existe plus.</p>', 404);
  }

  const revealState = JSON.parse(kvValue) as { status: string };
  if (revealState.status !== 'pending') {
    return htmlResponse('<h1>Déjà traité</h1><p>Cette demande d\'accès a déjà été traitée.</p>', 200);
  }

  // Update status to refused
  const updatedState = { ...revealState, status: 'refused', refused_at: new Date().toISOString() };
  await env.SESSIONS.put(kvKey, JSON.stringify(updatedState), { expirationTtl: 172800 });

  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: claims.prospect_id,
    event: 'agent.reveal_refused',
    properties: { match_id: claims.match_id },
  }));

  return htmlResponse(
    '<h1>Accès refusé</h1><p>Vous avez refusé l\'accès à ce profil expert. Votre assistant IA ne pourra pas le consulter.</p>',
    200,
  );
}

// ── GET /api/agent/reveal/:matchId/status ─────────────────────────────────────
// Poll reveal status for an agent match.

export async function handleAgentRevealStatus(
  request: Request,
  env: Env,
  agent: AgentCtx,
  matchId: string,
): Promise<Response> {
  // Verify match ownership
  const sql = createSql(env);
  try {
    const matchRows = await sql<{ id: string }[]>`
      SELECT id FROM matches
      WHERE id = ${matchId} AND prospect_id = ${agent.prospect_id}
      LIMIT 1
    `;

    if (matchRows.length === 0) {
      return errorResponse('not_found', 404);
    }
  } finally {
    await sql.end().catch(() => {});
  }

  const kvKey = `agent-reveal:${matchId}`;
  const kvValue = await env.SESSIONS.get(kvKey);

  if (!kvValue) {
    return jsonResponse({ match_id: matchId, status: 'not_requested' });
  }

  const state = JSON.parse(kvValue) as { status: string; confirmed_at?: string; refused_at?: string };

  return jsonResponse({
    match_id: matchId,
    status: state.status,
    ...(state.confirmed_at ? { confirmed_at: state.confirmed_at } : {}),
    ...(state.refused_at ? { refused_at: state.refused_at } : {}),
  });
}

// ── POST /api/agent/booking ───────────────────────────────────────────────────
// Request a booking for an expert that has been confirmed via reveal.
// Rate limit: 3/hour per API key.

export async function handleAgentBookingRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  agent: AgentCtx,
): Promise<Response> {
  // Rate limit
  const rateCheck = await checkAgentRateLimit(env.SESSIONS, agent.key_hash, 'booking');
  if (!rateCheck.allowed) {
    return new Response(JSON.stringify({ error: 'rate_limit_exceeded' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json', 'Retry-After': String(rateCheck.retryAfter ?? 3600) },
    });
  }

  // Parse body
  let body: { match_id?: unknown; project_summary?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { match_id, project_summary } = body;

  if (typeof match_id !== 'string' || !match_id) {
    return errorResponse('Validation failed', 422, { match_id: 'required string' });
  }

  const projectSummary = typeof project_summary === 'string' && project_summary
    ? project_summary
    : 'AI automation project';

  // Verify reveal was confirmed
  const kvKey = `agent-reveal:${match_id}`;
  const kvValue = await env.SESSIONS.get(kvKey);

  if (!kvValue) {
    return errorResponse('reveal_required', 422, {
      message: 'Expert must be revealed before booking. Use /api/agent/reveal first.',
    });
  }

  const revealState = JSON.parse(kvValue) as { status: string; expert_id: string };

  if (revealState.status !== 'confirmed') {
    return errorResponse('reveal_not_confirmed', 422, {
      message: `Reveal status is "${revealState.status}". Prospect must confirm reveal before booking.`,
    });
  }

  const sql = createSql(env);

  try {
    // Get expert booking link and prospect email
    const expertRows = await sql<{ display_name: string | null; cal_username: string | null }[]>`
      SELECT display_name, cal_username FROM experts WHERE id = ${revealState.expert_id} LIMIT 1
    `;

    const prospectRows = await sql<{ email: string | null }[]>`
      SELECT email FROM prospects WHERE id = ${agent.prospect_id} LIMIT 1
    `;

    await sql.end().catch(() => {});

    const expert = expertRows[0];
    const prospectEmail = prospectRows[0]?.email;

    if (!expert || !prospectEmail) {
      return errorResponse('not_found', 404);
    }

    const expertName = expert.display_name ?? 'Expert';
    const bookingLink = expert.cal_username
      ? `https://cal.com/${expert.cal_username}`
      : env.WORKER_BASE_URL;

    const { html, text } = buildAgentBookingEmail({
      expertName,
      projectSummary,
      bookingLink,
    });

    ctx.waitUntil(
      sendEmail(
        {
          to: prospectEmail,
          subject: `Votre assistant IA souhaite réserver un appel avec ${expertName}`,
          html,
          text,
        },
        {
          apiKey: env.RESEND_API_KEY,
          fromDomain: env.EMAIL_FROM_DOMAIN,
          replyTo: env.EMAIL_REPLY_TO,
        },
      ).catch((err) => console.error('[agent.booking] email send failed:', err)),
    );

    ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
      distinctId: agent.prospect_id,
      event: 'agent.booking_requested',
      properties: { key_id: agent.key_id, match_id, expert_id: revealState.expert_id },
    }));

    return jsonResponse({
      match_id,
      status: 'booking_email_sent',
      booking_link: bookingLink,
      message: 'Booking email sent to prospect.',
    });
  } catch (err) {
    await sql.end().catch(() => {});
    throw err;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function htmlResponse(body: string, status: number): Response {
  return new Response(
    `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Callibrate</title></head><body style="font-family:sans-serif;max-width:480px;margin:40px auto;padding:24px;">${body}</body></html>`,
    {
      status,
      headers: { 'Content-Type': 'text/html; charset=UTF-8' },
    },
  );
}
