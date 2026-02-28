// E02S12 AC7-AC8: Direct booking page renderer
// Route: GET /book/:slug?t=<token>
// noindex, nofollow, no canonical, no JSON-LD
// Full expert data, booking form with honeypot+timing+hidden attribution, Turnstile
// "Powered by Callibrate" footer, no nav
// The ?t= token determines attribution (direct | callibrate) — validated server-side by internal API.

const SITE_URL = 'https://callibrate.io';
const APP_URL = 'https://app.callibrate.io';

// ── Types ──────────────────────────────────────────────────────────────────────

export interface InternalExpertData {
  id: string;
  slug: string;
  display_name: string | null;
  headline: string | null;
  bio: string | null;
  skills: string[];
  languages: string[];
  portfolio_links: string[];
  rate_min: number | null;
  rate_max: number | null;
  quality_tier: 'new' | 'rising' | 'established' | 'top';
  availability: string | null;
  direct_link_token: string | null;
  direct_submissions_this_month: number;
  attribution: 'direct' | 'callibrate';
}

// ── Fetch helper ───────────────────────────────────────────────────────────────

export async function fetchInternalExpert(
  apiBaseUrl: string,
  internalApiKey: string,
  slug: string,
  token?: string,
): Promise<InternalExpertData | null> {
  try {
    const url = new URL(`${apiBaseUrl}/api/experts/internal/${encodeURIComponent(slug)}`);
    if (token) url.searchParams.set('t', token);

    const res = await fetch(url.toString(), {
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${internalApiKey}`,
      },
    });
    if (!res.ok) return null;
    const data = await res.json() as InternalExpertData;
    return data;
  } catch {
    return null;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatRateRange(rateMin: number | null, rateMax: number | null): string {
  if (!rateMin && !rateMax) return 'Rate on request';
  if (rateMin && rateMax) return `€${rateMin}–€${rateMax}/hr`;
  if (rateMin) return `From €${rateMin}/hr`;
  if (rateMax) return `Up to €${rateMax}/hr`;
  return 'Rate on request';
}

const QUALITY_TIER_LABELS: Record<string, string> = {
  new: 'New Expert',
  rising: 'Rising Expert',
  established: 'Established Expert',
  top: 'Top Expert',
};

// ── Page renderer ─────────────────────────────────────────────────────────────

export function renderDirectBookingPage(
  expert: InternalExpertData,
  attribution: 'direct' | 'callibrate',
  posthogApiKey: string,
  turnstileSiteKey: string,
): string {
  const tierLabel = QUALITY_TIER_LABELS[expert.quality_tier] ?? 'Expert';
  const rateStr = formatRateRange(expert.rate_min, expert.rate_max);
  const top5Skills = expert.skills.slice(0, 5);
  const expertName = expert.display_name ?? 'Expert';
  const directToken = expert.direct_link_token ?? '';

  // PostHog — minimal, no page_view capture (noindex page)
  const posthogHead = posthogApiKey
    ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:false,capture_pageview:false,disable_session_recording:true});</script>`
    : '';

  const skillBadges = top5Skills
    .map(s => `<span class="skill-badge">${escapeHtml(s)}</span>`)
    .join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Book a call with ${escapeHtml(expertName)} — Callibrate</title>
  <meta name="robots" content="noindex, nofollow">
  ${posthogHead}
  <!-- Turnstile -->
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root { --primary: #4F46E5; --text: #1a1a2e; --subtle: #6b7280; --border: #e5e7eb; --bg: #fff; }
    body { font-family: 'Inter', system-ui, -apple-system, sans-serif; color: var(--text); background: var(--bg); min-height: 100vh; display: flex; flex-direction: column; }
    .page { flex: 1; max-width: 560px; margin: 0 auto; width: 100%; padding: 2rem 1.5rem; }
    .expert-card { background: #f9fafb; border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; margin-bottom: 1.5rem; }
    .tier-badge { display: inline-block; background: #EEF2FF; color: var(--primary); font-size: 0.75rem; font-weight: 600; padding: 0.2rem 0.6rem; border-radius: 999px; margin-bottom: 0.5rem; }
    .expert-name { font-size: 1.125rem; font-weight: 700; margin-bottom: 0.25rem; }
    .expert-headline { color: var(--subtle); font-size: 0.9375rem; margin-bottom: 0.75rem; }
    .meta-row { font-size: 0.875rem; color: var(--subtle); margin-bottom: 0.5rem; }
    .skills-row { display: flex; flex-wrap: wrap; gap: 0.375rem; margin-top: 0.75rem; }
    .skill-badge { background: #F3F4F6; color: var(--text); font-size: 0.75rem; font-weight: 500; padding: 0.2rem 0.6rem; border-radius: 999px; }
    h1 { font-size: 1.25rem; font-weight: 700; margin-bottom: 1.5rem; }
    .form-group { margin-bottom: 1rem; }
    label { display: block; font-size: 0.875rem; font-weight: 500; margin-bottom: 0.375rem; }
    input, textarea { width: 100%; padding: 0.625rem 0.875rem; border: 1px solid var(--border); border-radius: 0.5rem; font-size: 0.9375rem; font-family: inherit; transition: border-color 0.15s; }
    input:focus, textarea:focus { outline: none; border-color: var(--primary); }
    textarea { resize: vertical; min-height: 120px; }
    .btn-submit { width: 100%; padding: 0.875rem; background: var(--primary); color: #fff; border: none; border-radius: 0.5rem; font-size: 1rem; font-weight: 600; cursor: pointer; transition: opacity 0.15s; min-height: 48px; }
    .btn-submit:hover { opacity: 0.88; }
    .btn-submit:disabled { opacity: 0.5; cursor: not-allowed; }
    /* Honeypot — visually hidden but accessible to real browsers */
    .hp-field { position: absolute; left: -9999px; top: -9999px; }
    .form-note { font-size: 0.8125rem; color: var(--subtle); margin-top: 0.5rem; }
    .success-msg { display: none; padding: 1rem; background: #ECFDF5; border: 1px solid #A7F3D0; border-radius: 0.5rem; color: #065F46; font-size: 0.9375rem; margin-top: 1rem; }
    .error-msg { display: none; padding: 1rem; background: #FEF2F2; border: 1px solid #FECACA; border-radius: 0.5rem; color: #991B1B; font-size: 0.9375rem; margin-top: 1rem; }
    footer { padding: 1.5rem; text-align: center; font-size: 0.8125rem; color: var(--subtle); border-top: 1px solid var(--border); }
    footer a { color: var(--primary); }
    @media (max-width: 600px) { .page { padding: 1rem; } }
  </style>
</head>
<body>
  <div class="page">
    <!-- Expert card -->
    <div class="expert-card">
      <span class="tier-badge">${escapeHtml(tierLabel)}</span>
      <div class="expert-name">${escapeHtml(expertName)}</div>
      ${expert.headline ? `<div class="expert-headline">${escapeHtml(expert.headline)}</div>` : ''}
      <div class="meta-row">${escapeHtml(rateStr)}</div>
      ${skillBadges ? `<div class="skills-row">${skillBadges}</div>` : ''}
    </div>

    <h1>Send a booking request</h1>

    <form id="booking-form" novalidate>
      <!-- Hidden fields -->
      <input type="hidden" name="token" value="${escapeHtml(directToken)}">
      <input type="hidden" name="attribution" value="${escapeHtml(attribution)}">
      <input type="hidden" name="form_started_at" id="form_started_at">

      <!-- Name -->
      <div class="form-group">
        <label for="prospect_name">Your name *</label>
        <input type="text" id="prospect_name" name="prospect_name" required autocomplete="name" placeholder="Jane Smith">
      </div>

      <!-- Email -->
      <div class="form-group">
        <label for="prospect_email">Your email *</label>
        <input type="email" id="prospect_email" name="prospect_email" required autocomplete="email" placeholder="jane@company.com">
      </div>

      <!-- Description -->
      <div class="form-group">
        <label for="description">What do you need help with? *</label>
        <textarea id="description" name="description" required placeholder="Describe your project, goals, and current situation. Minimum 30 characters."></textarea>
        <p class="form-note">Be specific — this helps the expert prepare for your call.</p>
      </div>

      <!-- Honeypot (CSS-hidden, tabindex=-1, autocomplete=off — AC14) -->
      <div class="hp-field" aria-hidden="true">
        <label for="website">Website (leave blank)</label>
        <input type="text" id="website" name="website" tabindex="-1" autocomplete="off">
        <label for="phone_backup">Phone backup (leave blank)</label>
        <input type="text" id="phone_backup" name="phone_backup" tabindex="-1" autocomplete="off">
      </div>

      <!-- Turnstile invisible widget -->
      <div class="cf-turnstile" data-sitekey="${escapeHtml(turnstileSiteKey)}" data-callback="onTurnstileSuccess" data-size="invisible"></div>

      <button type="submit" class="btn-submit" id="submit-btn">Send request</button>
    </form>

    <div class="success-msg" id="success-msg">
      Your booking request has been received. Please check your email to confirm your address.
    </div>
    <div class="error-msg" id="error-msg"></div>
  </div>

  <footer>
    Powered by <a href="${SITE_URL}">Callibrate</a> &mdash; AI Expert Marketplace
  </footer>

  <script>
    // Record form start time for bot timing detection
    document.getElementById('form_started_at').value = Date.now().toString();

    var turnstileToken = null;
    function onTurnstileSuccess(token) {
      turnstileToken = token;
    }

    var form = document.getElementById('booking-form');
    var submitBtn = document.getElementById('submit-btn');
    var successMsg = document.getElementById('success-msg');
    var errorMsg = document.getElementById('error-msg');

    form.addEventListener('submit', async function(e) {
      e.preventDefault();
      submitBtn.disabled = true;
      submitBtn.textContent = 'Sending...';
      errorMsg.style.display = 'none';

      // Trigger Turnstile if no token yet
      if (!turnstileToken && window.turnstile) {
        try {
          turnstileToken = await new Promise(function(resolve, reject) {
            window.turnstile.execute('.cf-turnstile', {
              callback: resolve,
              'error-callback': reject,
            });
            setTimeout(function() { reject(new Error('Turnstile timeout')); }, 10000);
          });
        } catch (err) {
          errorMsg.textContent = 'Security check failed. Please reload and try again.';
          errorMsg.style.display = 'block';
          submitBtn.disabled = false;
          submitBtn.textContent = 'Send request';
          return;
        }
      }

      var payload = {
        token: form.querySelector('[name="token"]').value,
        attribution: form.querySelector('[name="attribution"]').value,
        form_started_at: parseInt(form.querySelector('#form_started_at').value, 10) || 0,
        prospect_name: form.querySelector('#prospect_name').value,
        prospect_email: form.querySelector('#prospect_email').value,
        description: form.querySelector('#description').value,
        turnstile_token: turnstileToken || '',
        website: form.querySelector('#website').value,
        phone_backup: form.querySelector('#phone_backup').value,
      };

      try {
        var res = await fetch('/api/bookings/direct/${expert.slug}', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        var data = await res.json();

        if (res.ok && data.status === 'pending_email_confirmation') {
          form.style.display = 'none';
          successMsg.style.display = 'block';
          ${posthogApiKey ? `posthog.capture('booking.direct_form_submitted', { expert_slug: '${expert.slug}', attribution: '${attribution}' });` : ''}
        } else {
          var msg = data.error || 'Something went wrong. Please try again.';
          errorMsg.textContent = msg;
          errorMsg.style.display = 'block';
          submitBtn.disabled = false;
          submitBtn.textContent = 'Send request';
        }
      } catch (err) {
        errorMsg.textContent = 'Network error. Please check your connection and try again.';
        errorMsg.style.display = 'block';
        submitBtn.disabled = false;
        submitBtn.textContent = 'Send request';
      }
    });
  </script>
</body>
</html>`;
}
