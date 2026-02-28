import type { Env } from '../types/env';
import type {
  ExtractionResponse,
  FieldConfidence,
  ProspectRequirements,
} from '../types/matching';
import { validateFreetext } from '../lib/inputValidation';
import { signFlowToken, isValidProspectToken } from '../lib/jwt';
import { checkRateLimit } from '../lib/rateLimit';
import { performExtraction } from '../lib/extraction';

// ── Constants ─────────────────────────────────────────────────────────────────

const JSON_HEADERS = { 'Content-Type': 'application/json' };

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

// ── POST /api/extract ─────────────────────────────────────────────────────────
// 6-layer defense (E06S40 DEC-120) + abuse prevention (DEC-122).
// Layers ordered cheapest-first: reject garbage before it costs anything.
// OpenAI call delegated to lib/extraction.ts (E06S43 refactor).

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

  // ── Delegate to lib/extraction.ts (E06S43) ────────────────────────────────────
  // Circuit breaker check + OpenAI call + result parsing
  const effectiveSatelliteId = typeof satellite_id === 'string' && satellite_id ? satellite_id : null;
  const extractResult = await performExtraction(text, effectiveSatelliteId, env, ctx);

  if (!extractResult.ok) {
    if (extractResult.status === 503) {
      return jsonResponse(
        {
          error: extractResult.error,
          message: extractResult.detail,
          retry_after: 300,
        },
        503,
      );
    }
    return errorResponse(extractResult.error, extractResult.status, extractResult.detail);
  }

  // ── Post-extraction side effects (fire-and-forget) ────────────────────────────

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

  // ── Return structured response ────────────────────────────────────────────────
  const response: ExtractionResponse & { flow_token: string } = {
    ...extractResult.data,
    flow_token: flowToken, // AC11: client must include in Authorization header or flow_token body field on /api/prospects/submit
  };

  return jsonResponse(response, 200, responseHeaders);
}
