// E02S12 AC14-AC16: POST /api/bookings/direct/:slug
// Direct booking submission — allows prospects to book an expert via their direct link.
// Security pipeline: HMAC re-validation → quota check → input validation →
//   honeypot + timing → CF Rate Limiting → Turnstile → email pre-check →
//   extract → increment quota → create booking → magic link JWT → send email → PostHog event.

import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { verifyDirectLinkToken } from '../../lib/directLinkToken';
import { signBookingToken } from '../../lib/bookingToken';
import { preCheckEmail } from '../../lib/emailValidation';
import { sendEmail, buildDirectConfirmationEmail } from '../../lib/email';
import { captureEvent } from '../../lib/posthog';

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const DIRECT_BOOKING_QUOTA = 100; // AC13: max 100 direct submissions per month
const MIN_DESCRIPTION_LENGTH = 30;
const MIN_TIMING_MS = 3000; // AC14: honeypot timing — reject if form submitted in < 3s

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

export async function handleDirectBookingSubmit(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  slug: string,
): Promise<Response> {
  // 1. Parse body
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const {
    token: directToken,
    prospect_name,
    prospect_email,
    description,
    turnstile_token,
    // Honeypot fields (AC14)
    website,
    phone_backup,
    // Timing field (AC14)
    form_started_at,
  } = body as Record<string, unknown>;

  // 2. Validate slug + HMAC token
  if (!slug.startsWith('exp-') || slug.length < 12) {
    return json({ error: 'Expert not found' }, 404);
  }
  const shortHash = slug.substring(4);

  if (!directToken || typeof directToken !== 'string') {
    return json({ error: 'Missing direct link token' }, 400);
  }

  const sql = createSql(env);

  let expertId: string;
  let expertNonce: string;
  let expertEmail: string | null;
  let expertName: string | null;
  let directSubmissionsThisMonth: number;

  try {
    const [expert] = await sql<{
      id: string;
      direct_link_nonce: string;
      direct_submissions_this_month: number;
      gcal_email: string | null;
      display_name: string | null;
    }[]>`
      SELECT id, direct_link_nonce, direct_submissions_this_month, gcal_email, display_name
      FROM experts
      WHERE LEFT(id::text, 8) = ${shortHash}
    `;

    if (!expert) {
      return json({ error: 'Expert not found' }, 404);
    }

    expertId = expert.id;
    expertNonce = expert.direct_link_nonce;
    expertEmail = expert.gcal_email;
    expertName = expert.display_name;
    directSubmissionsThisMonth = expert.direct_submissions_this_month;

    // 3. HMAC re-validation (AC14)
    const tokenValid = await verifyDirectLinkToken(directToken, expertId, expertNonce, env.DIRECT_LINK_SECRET);
    if (!tokenValid) {
      return json({ error: 'Invalid direct link token' }, 403);
    }

    // 4. Quota check — 100 submissions per month (AC13)
    if (directSubmissionsThisMonth >= DIRECT_BOOKING_QUOTA) {
      return json({ error: 'quota_exceeded', message: 'This expert has reached their monthly booking limit. Please try again next month.' }, 429);
    }

  } finally {
    await sql.end();
  }

  // 5. Honeypot check (AC14) — hidden fields should be empty
  if (website || phone_backup) {
    // Silently accept to not reveal the honeypot, but do not process
    return json({ status: 'pending_email_confirmation', booking_id: null });
  }

  // 6. Timing check (AC14) — form submitted in < 3s is likely a bot
  if (form_started_at && typeof form_started_at === 'number') {
    const elapsed = Date.now() - form_started_at;
    if (elapsed < MIN_TIMING_MS) {
      return json({ status: 'pending_email_confirmation', booking_id: null });
    }
  }

  // 7. CF Rate Limiting (AC14)
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const { success: rateLimitOk } = await env.RATE_LIMITER.limit({ key: `direct-book:${ip}` });
  if (!rateLimitOk) {
    return json({ error: 'Too Many Requests' }, 429);
  }

  // 8. Turnstile validation (AC14)
  if (!turnstile_token || typeof turnstile_token !== 'string') {
    return json({ error: 'Missing Turnstile token' }, 400);
  }

  const turnstileRes = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      secret: env.TURNSTILE_SECRET_KEY,
      response: turnstile_token,
      remoteip: ip,
    }),
  });
  const turnstileData = await turnstileRes.json() as { success: boolean };
  if (!turnstileData.success) {
    return json({ error: 'Turnstile verification failed' }, 400);
  }

  // 9. Input validation (AC14)
  if (!prospect_name || typeof prospect_name !== 'string' || prospect_name.trim().length < 2) {
    return json({ error: 'Name is required' }, 422);
  }
  if (!prospect_email || typeof prospect_email !== 'string') {
    return json({ error: 'Email is required' }, 422);
  }
  if (!description || typeof description !== 'string') {
    return json({ error: 'Description is required' }, 422);
  }

  // Min 30 chars, ≥3 distinct words
  const trimmedDesc = description.trim();
  if (trimmedDesc.length < MIN_DESCRIPTION_LENGTH) {
    return json({ error: `Description must be at least ${MIN_DESCRIPTION_LENGTH} characters` }, 422);
  }
  const distinctWords = new Set(trimmedDesc.toLowerCase().split(/\s+/).filter(w => w.length > 0));
  if (distinctWords.size < 3) {
    return json({ error: 'Description must contain at least 3 distinct words' }, 422);
  }

  // 10. Email pre-check (AC14)
  const emailCheck = await preCheckEmail(prospect_email);
  if (!emailCheck.ok) {
    const errorMessages: Record<string, string> = {
      invalid_syntax: 'Invalid email address',
      no_mx_record: 'Email domain does not accept email',
      disposable_domain: 'Disposable email addresses are not allowed',
    };
    return json({ error: errorMessages[emailCheck.error ?? ''] ?? 'Invalid email' }, 422);
  }
  const normalizedEmail = emailCheck.normalizedEmail ?? prospect_email.toLowerCase();

  // 11. POST /api/extract — extract requirements from description (best-effort)
  let extractedRequirements: unknown = null;
  try {
    const extractRes = await fetch(`${env.WORKER_BASE_URL}/api/extract`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Origin': 'https://callibrate.io',
      },
      body: JSON.stringify({ description: trimmedDesc }),
    });
    if (extractRes.ok) {
      extractedRequirements = await extractRes.json();
    }
  } catch {
    // Non-blocking — extraction failure does not block booking
  }

  // 12. Increment quota
  const sql2 = createSql(env);
  let bookingId: string;

  try {
    await sql2`
      UPDATE experts
      SET direct_submissions_this_month = direct_submissions_this_month + 1
      WHERE id = ${expertId}
    `;

    // 13. Create booking record (AC15) — status='pending_confirmation', lead_source='direct'
    const [booking] = await sql2<{ id: string }[]>`
      INSERT INTO bookings (
        expert_id, prospect_email, prospect_name, description,
        status, lead_source, created_at
      )
      VALUES (
        ${expertId}, ${normalizedEmail}, ${prospect_name.trim()}, ${trimmedDesc},
        'pending_confirmation', 'direct', ${new Date().toISOString()}
      )
      RETURNING id
    `;

    if (!booking) {
      return json({ error: 'Failed to create booking' }, 500);
    }

    bookingId = booking.id;

    // 14. Generate magic link JWT (24h TTL) using DIRECT_BOOKING_SECRET
    const confirmToken = await signBookingToken(
      bookingId,
      'confirm',
      env.DIRECT_BOOKING_SECRET,
      86400, // 24h
    );

    const confirmUrl = `${env.WORKER_BASE_URL}/api/bookings/${bookingId}/direct-email-confirm?token=${confirmToken}`;

    // 15. Send confirmation email (AC16)
    const { html, text } = buildDirectConfirmationEmail({
      confirmUrl,
      expiryHours: 24,
    });

    if (expertEmail) {
      // Save requirements to booking description for expert context
      if (extractedRequirements) {
        await sql2`
          UPDATE bookings SET description = ${JSON.stringify(extractedRequirements)}
          WHERE id = ${bookingId}
        `;
      }
    }

    try {
      await sendEmail(
        {
          to: normalizedEmail,
          subject: 'Confirm your booking request — Callibrate',
          html,
          text,
        },
        {
          apiKey: env.RESEND_API_KEY,
          fromDomain: env.EMAIL_FROM_DOMAIN || 'callibrate.io',
          replyTo: env.EMAIL_REPLY_TO || 'support@callibrate.io',
        },
      );
    } catch (emailErr) {
      console.error('direct-booking: failed to send confirmation email for booking', bookingId, emailErr);
      // Non-blocking — booking is created, prospect can request resend
    }

  } finally {
    await sql2.end();
  }

  // 16. PostHog event (AC16)
  ctx.waitUntil(captureEvent(env.POSTHOG_API_KEY, {
    distinctId: `expert:${expertId}`,
    event: 'booking.direct_submitted',
    properties: {
      expert_id: expertId,
      booking_id: bookingId,
      lead_source: 'direct',
    },
  }));

  return json({ status: 'pending_email_confirmation', booking_id: bookingId });
}
