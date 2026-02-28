import { Env } from './types/env';
export { ExpertPoolDO } from './durable-objects/expertPoolDO';
import { handleMatchCompute, handleMatchGet } from './routes/matches';
import { handleExtract } from './routes/extract';
import { authenticate } from './middleware/auth';
import { handleRegister } from './handlers/experts/register';
import { handleGetProfile, handlePatchProfile } from './handlers/experts/profile';
import { handleSatelliteConfig } from './routes/satellites';
import { handleProspectSubmit, handleProspectMatches, handleProspectIdentify } from './routes/prospects';
import { handleCors, addCorsHeaders, corsForbidden } from './lib/cors';
import { handleGcalAuthUrl, handleGcalStatus, handleGcalDisconnect, handleGcalCallback } from './handlers/experts/gcal';
import { handleLsWebhook } from './handlers/webhooks/lemonsqueezy';
import { consumeEmailNotifications } from './queues/email-notifications';
import { consumeLeadBilling } from './queues/lead-billing';
import { consumeScoreComputation } from './queues/score-computation';
import { EmailNotificationMessage } from './types/queues';
import { LeadBillingMessage } from './types/queues';
import { ScoreComputationMessage } from './types/queues';
import { handleGetAvailability } from './handlers/bookings/availability';
import { handleHold } from './handlers/bookings/hold';
import { handleConfirm } from './handlers/bookings/confirm';
import { handleCancel } from './handlers/bookings/cancel';
import { handleReschedule } from './handlers/bookings/reschedule';
import { handleGetPrep } from './handlers/bookings/prep';
import { handleScheduled } from './handlers/bookings/cron';
import { handleVectorizeReindex } from './handlers/admin/vectorize';
import { handleFlagLead } from './handlers/leads/flag';
import { handleConfirmLead } from './handlers/leads/confirm';
import { handleCallExperienceSurvey } from './handlers/surveys/call-experience';
import { handleProjectSatisfactionSurvey } from './handlers/surveys/project-satisfaction';
import { handleLeadEvaluation } from './handlers/evaluations/lead';
import { applySecurityHeaders } from './lib/securityHeaders';
// E06S38: Dashboard API endpoints
import { handleGetLeads, handleEvaluateLead } from './handlers/experts/leads';
import { handleGetBookings } from './handlers/experts/bookings';
import { handleGetBilling } from './handlers/experts/billing';
import { handleGetDashboard } from './handlers/experts/dashboard';
import { handleGetPublicExperts, handleGetPublicExpertBySlug } from './handlers/experts/public';

// CF Workflows — must be named exports so the runtime can locate the classes
export { BookingConfirmedWorkflow } from './workflows/booking-confirmed.workflow';
export { BookingCompletedWorkflow } from './workflows/booking-completed.workflow';

const QUEUES = ['email-notifications', 'lead-billing', 'score-computation'] as const;

// AC6: Reject POST requests without Content-Type: application/json.
// Exception: webhook endpoints that may receive other content types.
function checkContentType(method: string, pathname: string, request: Request): Response | null {
  if (method !== 'POST') return null;
  if (pathname.startsWith('/api/webhooks/')) return null;
  const ct = request.headers.get('Content-Type');
  if (!ct || !ct.includes('application/json')) {
    return new Response(JSON.stringify({ error: 'Unsupported Media Type' }), {
      status: 415,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  return null;
}

async function checkSupabase(env: Env): Promise<'connected' | 'error'> {
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/`, {
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
    });
    return res.ok ? 'connected' : 'error';
  } catch {
    return 'error';
  }
}

async function routeRequest(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url);
  const { pathname, method } = { pathname: url.pathname, method: request.method };

  // ── Content-Type guard (AC6) ─────────────────────────────────────────────
  const ctError = checkContentType(method, pathname, request);
  if (ctError) return ctError;

  // ── Health ──────────────────────────────────────────────────────────────
  if (method === 'GET' && pathname === '/api/health') {
    const supabaseStatus = await checkSupabase(env);
    const body = { status: 'ok', supabase: supabaseStatus, queues: [...QUEUES] };
    const statusCode = supabaseStatus === 'connected' ? 200 : 503;
    return new Response(JSON.stringify(body), {
      status: statusCode,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Matching ────────────────────────────────────────────────────────────
  // POST /api/matches/compute
  if (method === 'POST' && pathname === '/api/matches/compute') {
    return handleMatchCompute(request, env, ctx);
  }

  // GET /api/matches/:prospect_id
  const matchGetPattern = pathname.match(/^\/api\/matches\/([^/]+)$/);
  if (method === 'GET' && matchGetPattern && matchGetPattern[1]) {
    const prospectId = matchGetPattern[1];
    return handleMatchGet(request, env, prospectId);
  }

  // ── AI Extraction (CORS-gated — called browser-side from satellite pages) ──
  if (pathname === '/api/extract') {
    const corsResult = await handleCors(request, env);
    if (corsResult.preflight) return corsResult.preflight;
    if (!corsResult.allowed) return corsForbidden(corsResult.origin);

    if (method === 'POST') {
      const response = await handleExtract(request, env, ctx);
      return addCorsHeaders(response, corsResult.origin);
    }

    return addCorsHeaders(
      new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
      corsResult.origin,
    );
  }

  // ── GCal OAuth callback (unauthenticated — Google redirects here) ─────────
  if (method === 'GET' && pathname === '/api/gcal/callback') {
    return handleGcalCallback(request, env, ctx);
  }

  // ── LemonSqueezy webhook (unauthenticated — LS sends HMAC-signed requests) ──
  if (method === 'POST' && pathname === '/api/webhooks/lemonsqueezy') {
    return handleLsWebhook(request, env);
  }

  // ── Satellite routes (AC9: CORS enforced) ───────────────────────────────
  if (pathname.startsWith('/api/satellites/')) {
    const corsResult = await handleCors(request, env);
    if (corsResult.preflight) return corsResult.preflight;
    if (!corsResult.allowed) return corsForbidden(corsResult.origin);

    // GET /api/satellites/:id/config
    const satConfigMatch = pathname.match(/^\/api\/satellites\/([^/]+)\/config$/);
    if (method === 'GET' && satConfigMatch && satConfigMatch[1]) {
      const response = await handleSatelliteConfig(request, env, satConfigMatch[1]);
      return addCorsHeaders(response, corsResult.origin);
    }

    return addCorsHeaders(
      new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
      corsResult.origin,
    );
  }

  // ── Prospect routes (AC9: CORS enforced) ────────────────────────────────
  if (pathname.startsWith('/api/prospects/')) {
    const corsResult = await handleCors(request, env);
    if (corsResult.preflight) return corsResult.preflight;
    if (!corsResult.allowed) return corsForbidden(corsResult.origin);

    // POST /api/prospects/submit
    if (method === 'POST' && pathname === '/api/prospects/submit') {
      const response = await handleProspectSubmit(request, env, ctx);
      return addCorsHeaders(response, corsResult.origin);
    }

    const prospectId = pathname.match(/^\/api\/prospects\/([^/]+)\//)?.[1];

    if (prospectId) {
      // GET /api/prospects/:id/matches?token=xxx
      if (method === 'GET' && pathname === `/api/prospects/${prospectId}/matches`) {
        const response = await handleProspectMatches(request, env, prospectId, ctx);
        return addCorsHeaders(response, corsResult.origin);
      }

      // POST /api/prospects/:id/identify
      if (method === 'POST' && pathname === `/api/prospects/${prospectId}/identify`) {
        const response = await handleProspectIdentify(request, env, prospectId, ctx);
        return addCorsHeaders(response, corsResult.origin);
      }
    }

    return addCorsHeaders(
      new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
      corsResult.origin,
    );
  }

  // ── Expert availability (CORS-gated, no JWT) ─────────────────────────────────
  const expertAvailMatch = pathname.match(/^\/api\/experts\/([^/]+)\/availability$/);
  if (method === 'GET' && expertAvailMatch && expertAvailMatch[1]) {
    const corsResult = await handleCors(request, env);
    if (corsResult.preflight) return corsResult.preflight;
    if (!corsResult.allowed) return corsForbidden(corsResult.origin);
    const response = await handleGetAvailability(request, env, expertAvailMatch[1], ctx);
    return addCorsHeaders(response, corsResult.origin);
  }

  // ── Booking routes (CORS-gated) ───────────────────────────────────────────
  if (pathname.startsWith('/api/bookings/')) {
    // GET /api/bookings/:token/prep — public, no CORS check
    const prepMatch = pathname.match(/^\/api\/bookings\/([^/]+)\/prep$/);
    if (method === 'GET' && prepMatch && prepMatch[1]) {
      return handleGetPrep(request, env, prepMatch[1]);
    }

    const corsResult = await handleCors(request, env);
    if (corsResult.preflight) return corsResult.preflight;
    if (!corsResult.allowed) return corsForbidden(corsResult.origin);

    // POST /api/bookings/hold
    if (method === 'POST' && pathname === '/api/bookings/hold') {
      const response = await handleHold(request, env, ctx);
      return addCorsHeaders(response, corsResult.origin);
    }

    const bookingIdMatch = pathname.match(/^\/api\/bookings\/([^/]+)\/(confirm|reschedule)$/);
    if (bookingIdMatch && bookingIdMatch[1] && bookingIdMatch[2]) {
      const bookingId = bookingIdMatch[1];
      const action = bookingIdMatch[2];

      if (method === 'POST' && action === 'confirm') {
        const response = await handleConfirm(request, env, bookingId, ctx);
        return addCorsHeaders(response, corsResult.origin);
      }
      if (method === 'POST' && action === 'reschedule') {
        const response = await handleReschedule(request, env, bookingId);
        return addCorsHeaders(response, corsResult.origin);
      }
    }

    // DELETE /api/bookings/:id
    const bookingDeleteMatch = pathname.match(/^\/api\/bookings\/([^/]+)$/);
    if (method === 'DELETE' && bookingDeleteMatch && bookingDeleteMatch[1]) {
      const response = await handleCancel(request, env, bookingDeleteMatch[1], ctx);
      return addCorsHeaders(response, corsResult.origin);
    }

    return addCorsHeaders(
      new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
      corsResult.origin,
    );
  }

  // ── Lead routes (authenticated) ─────────────────────────────────────────
  if (pathname.startsWith('/api/leads/')) {
    const authResult = await authenticate(request, env);
    if (authResult.response) {
      return authResult.response;
    }
    const user = authResult.user;

    const leadIdMatch = pathname.match(/^\/api\/leads\/([^/]+)\/(flag|confirm)$/);
    if (leadIdMatch && leadIdMatch[1] && leadIdMatch[2]) {
      const leadId = leadIdMatch[1];
      const action = leadIdMatch[2];

      if (method === 'POST' && action === 'flag') {
        return handleFlagLead(request, env, user, leadId);
      }
      if (method === 'POST' && action === 'confirm') {
        return handleConfirmLead(request, env, user, leadId);
      }
    }

    // E06S38: POST /api/leads/:id/evaluate — expert lead evaluation
    const evaluateMatch = pathname.match(/^\/api\/leads\/([^/]+)\/evaluate$/);
    if (method === 'POST' && evaluateMatch && evaluateMatch[1]) {
      return handleEvaluateLead(request, env, user, evaluateMatch[1], ctx);
    }

    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Survey routes (token-gated — survey JWT via SURVEY_TOKEN_SECRET) ────────
  if (pathname.startsWith('/api/surveys/')) {
    if (method === 'POST' && pathname === '/api/surveys/call-experience') {
      return handleCallExperienceSurvey(request, env, ctx);
    }
    if (method === 'POST' && pathname === '/api/surveys/project-satisfaction') {
      return handleProjectSatisfactionSurvey(request, env);
    }
    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Evaluation routes (expert JWT authenticated) ──────────────────────────
  if (pathname.startsWith('/api/evaluations/')) {
    if (method === 'POST' && pathname === '/api/evaluations/lead') {
      return handleLeadEvaluation(request, env, ctx);
    }
    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Public expert routes (unauthenticated, E06S38) ───────────────────────
  // Must be registered BEFORE the authenticated expert block to avoid auth interception.

  // GET /api/experts/public — anonymized public listing
  if (method === 'GET' && pathname === '/api/experts/public') {
    return handleGetPublicExperts(request, env);
  }

  // GET /api/experts/public/:slug — anonymized expert detail
  const publicExpertMatch = pathname.match(/^\/api\/experts\/public\/([^/]+)$/);
  if (method === 'GET' && publicExpertMatch && publicExpertMatch[1]) {
    return handleGetPublicExpertBySlug(request, env, publicExpertMatch[1]);
  }

  // ── Expert routes (authenticated) ───────────────────────────────────────
  if (pathname.startsWith('/api/experts/')) {
    const authResult = await authenticate(request, env);
    if (authResult.response) {
      return authResult.response;
    }
    const user = authResult.user;

    if (method === 'POST' && pathname === '/api/experts/register') {
      return handleRegister(request, env, user, ctx);
    }

    const profileMatch = pathname.match(/^\/api\/experts\/([^/]+)\/profile$/);
    if (profileMatch) {
      if (method === 'GET') {
        return handleGetProfile(request, env, user, profileMatch[1]!);
      }
      if (method === 'PATCH') {
        return handlePatchProfile(request, env, user, profileMatch[1]!, ctx);
      }
    }

    // GCal routes
    const gcalIdMatch = pathname.match(/^\/api\/experts\/([^/]+)\/gcal\//);
    if (gcalIdMatch && gcalIdMatch[1]) {
      const gcalExpertId = gcalIdMatch[1];
      if (method === 'GET' && pathname === `/api/experts/${gcalExpertId}/gcal/auth-url`) {
        return handleGcalAuthUrl(request, env, user, gcalExpertId);
      }
      if (method === 'GET' && pathname === `/api/experts/${gcalExpertId}/gcal/status`) {
        return handleGcalStatus(request, env, user, gcalExpertId);
      }
      if (method === 'DELETE' && pathname === `/api/experts/${gcalExpertId}/gcal/disconnect`) {
        return handleGcalDisconnect(request, env, user, gcalExpertId, ctx);
      }
    }

    // E06S38: Dashboard read endpoints — GET /api/experts/:id/leads|bookings|billing|dashboard
    const leadsMatch = pathname.match(/^\/api\/experts\/([^/]+)\/leads$/);
    if (method === 'GET' && leadsMatch && leadsMatch[1]) {
      return handleGetLeads(request, env, user, leadsMatch[1]);
    }

    const expertBookingsMatch = pathname.match(/^\/api\/experts\/([^/]+)\/bookings$/);
    if (method === 'GET' && expertBookingsMatch && expertBookingsMatch[1]) {
      return handleGetBookings(request, env, user, expertBookingsMatch[1]);
    }

    const billingMatch = pathname.match(/^\/api\/experts\/([^/]+)\/billing$/);
    if (method === 'GET' && billingMatch && billingMatch[1]) {
      return handleGetBilling(request, env, user, billingMatch[1]);
    }

    const dashboardMatch = pathname.match(/^\/api\/experts\/([^/]+)\/dashboard$/);
    if (method === 'GET' && dashboardMatch && dashboardMatch[1]) {
      return handleGetDashboard(request, env, user, dashboardMatch[1]);
    }

    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // ── Admin routes (service-key auth) ─────────────────────────────────────────
  if (pathname.startsWith('/api/admin/')) {
    if (method === 'POST' && pathname === '/api/admin/vectorize/reindex') {
      return handleVectorizeReindex(request, env, ctx);
    }
    return new Response(JSON.stringify({ error: 'Not Found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ error: 'Not Found' }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const response = await routeRequest(request, env, ctx);
    return applySecurityHeaders(response);
  },

  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    await handleScheduled(controller, env);
  },

  async queue(batch: MessageBatch<unknown>, env: Env): Promise<void> {
    if (batch.queue.includes('email-notifications')) {
      await consumeEmailNotifications(batch as MessageBatch<EmailNotificationMessage>, env);
    } else if (batch.queue.includes('lead-billing')) {
      await consumeLeadBilling(batch as MessageBatch<LeadBillingMessage>, env);
    } else if (batch.queue.includes('score-computation')) {
      await consumeScoreComputation(batch as MessageBatch<ScoreComputationMessage>, env);
    } else {
      console.warn('queue: unknown queue', batch.queue);
      batch.ackAll();
    }
  },
} satisfies ExportedHandler<Env>;
