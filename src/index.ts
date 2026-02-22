import { Env } from './types/env';
import { handleMatchCompute, handleMatchGet } from './routes/matches';
import { handleExtract } from './routes/extract';
import { authenticate } from './middleware/auth';
import { handleRegister } from './handlers/experts/register';
import { handleGetProfile, handlePatchProfile } from './handlers/experts/profile';
import { handleSatelliteConfig } from './routes/satellites';
import { handleProspectSubmit, handleProspectMatches, handleProspectIdentify } from './routes/prospects';
import { handleCors, addCorsHeaders, corsForbidden } from './lib/cors';
import { handleGcalAuthUrl, handleGcalStatus, handleGcalDisconnect, handleGcalCallback } from './handlers/experts/gcal';
import { consumeEmailNotifications } from './queues/email-notifications';
import { consumeLeadBilling } from './queues/lead-billing';
import { consumeScoreComputation } from './queues/score-computation';
import { EmailNotificationMessage } from './types/queues';
import { LeadBillingMessage } from './types/queues';
import { ScoreComputationMessage } from './types/queues';

const QUEUES = ['email-notifications', 'lead-billing', 'score-computation'] as const;

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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const { pathname, method } = { pathname: url.pathname, method: request.method };

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
      return handleMatchCompute(request, env);
    }

    // GET /api/matches/:prospect_id
    const matchGetPattern = pathname.match(/^\/api\/matches\/([^/]+)$/);
    if (method === 'GET' && matchGetPattern && matchGetPattern[1]) {
      const prospectId = matchGetPattern[1];
      return handleMatchGet(request, env, prospectId);
    }

    // ── AI Extraction ────────────────────────────────────────────────────────
    // POST /api/extract
    if (method === 'POST' && pathname === '/api/extract') {
      return handleExtract(request, env);
    }

    // ── GCal OAuth callback (unauthenticated — Google redirects here) ─────────
    if (method === 'GET' && pathname === '/api/gcal/callback') {
      return handleGcalCallback(request, env);
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
        const response = await handleProspectSubmit(request, env);
        return addCorsHeaders(response, corsResult.origin);
      }

      const prospectId = pathname.match(/^\/api\/prospects\/([^/]+)\//)?.[1];

      if (prospectId) {
        // GET /api/prospects/:id/matches?token=xxx
        if (method === 'GET' && pathname === `/api/prospects/${prospectId}/matches`) {
          const response = await handleProspectMatches(request, env, prospectId);
          return addCorsHeaders(response, corsResult.origin);
        }

        // POST /api/prospects/:id/identify
        if (method === 'POST' && pathname === `/api/prospects/${prospectId}/identify`) {
          const response = await handleProspectIdentify(request, env, prospectId);
          return addCorsHeaders(response, corsResult.origin);
        }
      }

      return addCorsHeaders(
        new Response(JSON.stringify({ error: 'Not Found' }), { status: 404, headers: { 'Content-Type': 'application/json' } }),
        corsResult.origin,
      );
    }

    // ── Expert routes (authenticated) ───────────────────────────────────────
    if (pathname.startsWith('/api/experts/')) {
      const authResult = await authenticate(request, env);
      if (authResult.response) {
        return authResult.response;
      }
      const user = authResult.user;

      if (method === 'POST' && pathname === '/api/experts/register') {
        return handleRegister(request, env, user);
      }

      const profileMatch = pathname.match(/^\/api\/experts\/([^/]+)\/profile$/);
      if (profileMatch) {
        if (method === 'GET') {
          return handleGetProfile(request, env, user, profileMatch[1]!);
        }
        if (method === 'PATCH') {
          return handlePatchProfile(request, env, user, profileMatch[1]!);
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
          return handleGcalDisconnect(request, env, user, gcalExpertId);
        }
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
