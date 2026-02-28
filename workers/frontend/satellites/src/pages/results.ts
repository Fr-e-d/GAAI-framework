import type { SatelliteConfig } from '../types/config';
import { getBookingWidgetStyles, getBookingWidgetScript } from './booking-widget';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// E03S08: Merged Page 2 — extraction summary + confirmation questions + match results + email/OTP gate + full profiles + booking
export function renderResultsPage(
  config: SatelliteConfig,
  posthogApiKey: string,
  coreApiUrl: string,
  turnstileSiteKey: string
): string {
  const theme = config.theme;
  const brand = config.brand;

  const cssVars = theme
    ? `:root {
      --color-primary: ${escapeHtml(theme.primary)};
      --color-accent: ${escapeHtml(theme.accent)};
      --font-family: ${escapeHtml(theme.font)};
      --radius-card: ${escapeHtml(theme.radius)};
    }`
    : '';

  const logoHtml = theme?.logo_url
    ? `<img src="${escapeHtml(theme.logo_url)}" alt="${escapeHtml(brand?.name ?? '')}" class="logo">`
    : '';

  // AC9: PostHog head snippet — identical to confirm.ts pattern
  const posthogHeadSnippet =
    config.tracking_enabled !== false && posthogApiKey
      ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
      : '';

  // AC6: Turnstile SDK loaded in head
  const turnstileSdkScript = `<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>`;

  // AC6: Inject config including turnstileSiteKey
  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({
    apiUrl: coreApiUrl,
    satelliteId: config.id,
    turnstileSiteKey: turnstileSiteKey,
  }).replace(/</g, '\\u003c')};</script>`;

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(brand?.name ?? 'Callibrate')} \u2014 Vos experts correspondants</title>
  <meta name="robots" content="noindex, nofollow">
  ${posthogHeadSnippet}
  ${turnstileSdkScript}
  <style>
    ${cssVars}

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: var(--font-family, 'Inter, sans-serif');
      color: #1a1a2e;
      background: #fafafa;
      line-height: 1.6;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .container {
      max-width: 720px;
      width: 100%;
      padding: 3rem 1.5rem;
    }
    .logo {
      max-height: 48px;
      margin-bottom: 1.5rem;
      display: block;
    }
    h1 {
      font-size: 1.25rem;
      font-weight: 600;
      color: var(--color-primary, #4F46E5);
      margin-bottom: 0.5rem;
    }
    h2 {
      font-size: 1.75rem;
      font-weight: 700;
      line-height: 1.2;
      margin-bottom: 1.5rem;
      color: #1a1a2e;
    }

    /* AC4: Extraction summary */
    .summary-section {
      background: #fff;
      border: 1px solid #e5e7eb;
      border-radius: var(--radius-card, 0.5rem);
      padding: 1rem 1.25rem;
      margin-bottom: 1.5rem;
    }
    .summary-collapsed {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
    }
    .summary-one-liner {
      font-size: 0.9375rem;
      color: #374151;
      flex: 1;
    }
    .summary-expanded {
      display: none;
      margin-top: 1rem;
    }
    .summary-expanded.visible { display: block; }
    .summary-toggle-btn {
      background: none;
      border: none;
      color: var(--color-primary, #4F46E5);
      font-size: 0.875rem;
      cursor: pointer;
      padding: 0;
      text-decoration: underline;
      white-space: nowrap;
      flex-shrink: 0;
    }
    .summary-toggle-btn:hover { opacity: 0.7; }
    .summary-close-btn {
      display: block;
      margin-top: 1rem;
      background: none;
      border: none;
      color: #6b7280;
      font-size: 0.875rem;
      cursor: pointer;
      padding: 0;
      text-decoration: underline;
    }
    .summary-close-btn:hover { color: #1a1a2e; }

    /* Field rows (shared with summary expanded + confirmation questions) */
    .field-row {
      display: flex;
      align-items: flex-start;
      gap: 0.75rem;
      padding: 0.75rem 0;
      border-bottom: 1px solid #e5e7eb;
    }
    .field-row:last-child { border-bottom: none; }
    .confidence-indicator {
      font-size: 1rem;
      flex-shrink: 0;
      width: 1.5rem;
      text-align: center;
    }
    .field-label {
      font-size: 0.875rem;
      font-weight: 500;
      color: #6b7280;
      min-width: 160px;
      flex-shrink: 0;
      padding-top: 0.125rem;
    }
    .field-value {
      flex: 1;
      font-size: 1rem;
      color: #1a1a2e;
    }
    .field-value--empty {
      color: #9ca3af;
      font-style: italic;
    }
    .modifier-btn {
      background: none;
      border: none;
      color: var(--color-primary, #4F46E5);
      font-size: 0.875rem;
      cursor: pointer;
      padding: 0;
      text-decoration: underline;
      white-space: nowrap;
      flex-shrink: 0;
    }
    .modifier-btn:hover { opacity: 0.7; }
    .field-edit {
      display: none;
      flex: 1;
    }
    .field-edit.visible { display: block; }
    .field-edit input[type="text"],
    .field-edit input[type="number"],
    .field-edit select {
      width: 100%;
      padding: 0.5rem 0.625rem;
      border: 1.5px solid var(--color-primary, #4F46E5);
      border-radius: var(--radius-card, 0.375rem);
      font-size: 0.9375rem;
      font-family: inherit;
      color: #1a1a2e;
      background: #fff;
    }
    .budget-inputs {
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    .budget-inputs input { width: 100px; }
    .budget-inputs span { color: #555; font-size: 0.875rem; }
    .save-edit-btn {
      display: inline-block;
      margin-top: 0.5rem;
      padding: 0.375rem 0.875rem;
      background: var(--color-primary, #4F46E5);
      color: #fff;
      border: none;
      border-radius: var(--radius-card, 0.375rem);
      font-size: 0.875rem;
      font-weight: 600;
      font-family: inherit;
      cursor: pointer;
    }
    .save-edit-btn:hover { opacity: 0.9; }

    /* AC2: Confirmation questions */
    .questions-section {
      background: #fffbeb;
      border: 1px solid #fde68a;
      border-radius: var(--radius-card, 0.5rem);
      padding: 1.25rem;
      margin-bottom: 1.5rem;
    }
    .questions-section h3 {
      font-size: 1rem;
      font-weight: 600;
      color: #92400e;
      margin-bottom: 1rem;
    }
    .question-block {
      margin-bottom: 1.25rem;
    }
    .question-block > label {
      display: block;
      font-size: 0.9375rem;
      font-weight: 500;
      color: #1a1a2e;
      margin-bottom: 0.5rem;
    }
    .question-block input[type="text"],
    .question-block input[type="number"],
    .question-block select {
      width: 100%;
      padding: 0.5rem 0.625rem;
      border: 1.5px solid var(--color-primary, #4F46E5);
      border-radius: var(--radius-card, 0.375rem);
      font-size: 0.9375rem;
      font-family: inherit;
      color: #1a1a2e;
      background: #fff;
    }
    .radio-group {
      display: flex;
      flex-direction: column;
      gap: 0.375rem;
    }
    .radio-group label {
      font-weight: 400;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      cursor: pointer;
      font-size: 0.9375rem;
    }
    .radio-group input[type="radio"] { flex-shrink: 0; }
    #confirm-btn {
      display: flex;
      width: 100%;
      padding: 0.875rem 2rem;
      background: var(--color-primary, #4F46E5);
      color: #fff;
      border: none;
      border-radius: var(--radius-card, 0.5rem);
      font-size: 1.0625rem;
      font-weight: 600;
      font-family: var(--font-family, 'Inter, sans-serif');
      cursor: pointer;
      transition: opacity 0.15s;
      min-height: 44px;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
      margin-top: 1rem;
    }
    #confirm-btn:hover:not(:disabled) { opacity: 0.9; }
    #confirm-btn:disabled { opacity: 0.5; cursor: not-allowed; }
    #confirm-error {
      color: #dc2626;
      font-size: 0.875rem;
      margin-top: 0.5rem;
      padding: 0.5rem 0.75rem;
      background: #fef2f2;
      border-left: 3px solid #dc2626;
      border-radius: 0.25rem;
    }
    #cf-turnstile-container { margin-top: 1rem; }

    /* Matches section */
    #matches-placeholder {
      padding: 2rem 1rem;
      text-align: center;
      color: #6b7280;
      font-size: 0.9375rem;
      background: #f9fafb;
      border-radius: var(--radius-card, 0.5rem);
      border: 1px dashed #d1d5db;
      margin-bottom: 1.5rem;
    }

    /* Skeleton shimmer */
    @keyframes shimmer { 0%{background-position:-468px 0} 100%{background-position:468px 0} }
    .skeleton-card { background:#fff; border-radius:var(--radius-card,0.5rem); padding:1.5rem; margin-bottom:1rem; border:1px solid #e5e7eb; }
    .skeleton-line { height:14px; border-radius:4px; background:linear-gradient(to right,#f0f0f0 8%,#e0e0e0 18%,#f0f0f0 33%); background-size:800px 104px; animation:shimmer 1.2s linear infinite; margin-bottom:0.75rem; }
    .skeleton-line--short { width:60%; }
    .skeleton-line--medium { width:80%; }

    /* Match cards */
    .match-card { background:#fff; border-radius:var(--radius-card,0.5rem); border:1px solid #e5e7eb; padding:1.5rem; margin-bottom:1rem; }
    .match-card--prominent { border:2px solid var(--color-accent,#818CF8); padding:1.75rem; }
    .card-header { display:flex; align-items:center; gap:0.75rem; margin-bottom:1rem; }
    .rank-badge { width:2rem; height:2rem; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:0.75rem; font-weight:700; flex-shrink:0; }
    .rank-badge--1 { background:#FFD700; color:#78350F; }
    .rank-badge--2 { background:#C0C0C0; color:#1F2937; }
    .rank-badge--3 { background:#CD7F32; color:#fff; }
    .rank-badge--other { background:#e5e7eb; color:#374151; }
    .card-header-meta { flex:1; }
    .expert-name { font-weight:600; color:#1a1a2e; }
    .expert-headline { font-size:0.875rem; color:#6b7280; }
    .score-badge { display:inline-block; padding:0.25rem 0.5rem; background:var(--color-primary,#4F46E5); color:#fff; border-radius:0.25rem; font-size:0.875rem; font-weight:600; }
    .tier-badge { padding:0.25rem 0.625rem; border-radius:999px; font-size:0.75rem; font-weight:600; }
    .tier--top { background:#fef3c7; color:#92400e; }
    .tier--confirmed { background:#f1f5f9; color:#475569; }
    .tier--promising { background:#ede9fe; color:#5b21b6; }
    .score-breakdown { margin-bottom:1rem; }
    .criterion-row { display:flex; align-items:center; gap:0.5rem; margin-bottom:0.375rem; }
    .criterion-label { font-size:0.8125rem; color:#6b7280; width:100px; flex-shrink:0; }
    .score-bar-track { flex:1; background:#e5e7eb; border-radius:999px; height:6px; }
    .score-bar-fill { background:var(--color-primary,#4F46E5); border-radius:999px; height:6px; }
    .criterion-score { font-size:0.8125rem; color:#374151; width:2rem; text-align:right; flex-shrink:0; }
    .tags-row { display:flex; flex-wrap:wrap; gap:0.375rem; margin-bottom:0.75rem; }
    .tag { padding:0.25rem 0.5rem; background:#f3f4f6; border-radius:0.25rem; font-size:0.8125rem; color:#374151; }
    .lang-tag { padding:0.25rem 0.5rem; background:#eff6ff; border-radius:0.25rem; font-size:0.8125rem; color:#1d4ed8; }
    .rate-range { font-size:0.9375rem; font-weight:500; color:#1a1a2e; margin-bottom:0.75rem; }
    .expand-btn { background:none; border:none; color:var(--color-primary,#4F46E5); font-size:0.875rem; cursor:pointer; padding:0; text-decoration:underline; }
    .avatar-silhouette { width:2.5rem; height:2.5rem; border-radius:50%; background:#e5e7eb; display:flex; align-items:center; justify-content:center; flex-shrink:0; }
    .avatar-initial { width:2.5rem; height:2.5rem; border-radius:50%; display:flex; align-items:center; justify-content:center; flex-shrink:0; color:#fff; font-weight:600; font-size:1rem; }
    .bio-block { margin-bottom:1rem; }
    .bio-text { display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; font-size:0.9375rem; color:#374151; }
    .bio-text.expanded { display:block; -webkit-line-clamp:unset; overflow:visible; }
    .bio-expand-btn { background:none; border:none; color:var(--color-primary,#4F46E5); font-size:0.875rem; cursor:pointer; padding:0; text-decoration:underline; }
    .booking-btn { display:block; width:100%; padding:0.75rem 1rem; background:var(--color-accent,#818CF8); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); font-size:0.9375rem; font-weight:600; font-family:var(--font-family,'Inter, sans-serif'); cursor:pointer; margin-top:1rem; min-height:44px; }
    .booking-btn:hover { opacity:0.9; }

    /* Computing message */
    #computing-msg { text-align:center; padding:3rem 1rem; color:#6b7280; }

    /* Email gate + OTP */
    #email-gate-section { border-top:1px solid #e5e7eb; margin-top:2rem; padding-top:2rem; }
    #email-gate-section h3 { font-size:1.25rem; font-weight:700; color:#1a1a2e; margin-bottom:0.5rem; }
    #email-gate-section>p { color:#6b7280; font-size:0.9375rem; margin-bottom:1.5rem; }
    #email-input { display:block; width:100%; padding:0.75rem; border:1.5px solid var(--color-primary,#4F46E5); border-radius:var(--radius-card,0.375rem); font-size:1rem; font-family:inherit; color:#1a1a2e; background:#fff; margin-bottom:0.75rem; }
    #email-error { color:#dc2626; font-size:0.875rem; margin-bottom:0.75rem; padding:0.5rem 0.75rem; background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; }
    #unlock-btn { display:flex; width:100%; padding:0.875rem 2rem; background:var(--color-primary,#4F46E5); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); font-size:1.0625rem; font-weight:600; font-family:inherit; cursor:pointer; transition:opacity 0.15s; min-height:44px; align-items:center; justify-content:center; gap:0.5rem; }
    #unlock-btn:hover:not(:disabled) { opacity:0.9; }
    #unlock-btn:disabled { opacity:0.5; cursor:not-allowed; }
    #otp-section { margin-top:1.25rem; }
    #otp-section p { font-size:0.9375rem; color:#374151; margin-bottom:0.75rem; }
    #otp-input { display:block; width:100%; padding:0.75rem; border:1.5px solid var(--color-primary,#4F46E5); border-radius:var(--radius-card,0.375rem); font-size:1.25rem; font-family:inherit; color:#1a1a2e; background:#fff; margin-bottom:0.75rem; letter-spacing:0.2em; text-align:center; }
    #otp-error { color:#dc2626; font-size:0.875rem; margin-bottom:0.75rem; padding:0.5rem 0.75rem; background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; }
    #verify-otp-btn { display:flex; width:100%; padding:0.875rem 2rem; background:var(--color-primary,#4F46E5); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); font-size:1.0625rem; font-weight:600; font-family:inherit; cursor:pointer; transition:opacity 0.15s; min-height:44px; align-items:center; justify-content:center; gap:0.5rem; margin-bottom:0.75rem; }
    #verify-otp-btn:hover:not(:disabled) { opacity:0.9; }
    #verify-otp-btn:disabled { opacity:0.5; cursor:not-allowed; }
    #resend-otp-btn { background:none; border:none; color:var(--color-primary,#4F46E5); font-size:0.875rem; cursor:pointer; padding:0; text-decoration:underline; }
    #resend-otp-btn:disabled { opacity:0.5; cursor:not-allowed; text-decoration:none; }

    /* Fetch error */
    #fetch-error { background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; padding:1rem; margin-bottom:1rem; }
    #retry-btn { background:none; border:none; color:#dc2626; font-size:0.875rem; cursor:pointer; text-decoration:underline; padding:0; margin-top:0.5rem; }

    /* No matches */
    #no-matches { text-align:center; padding:3rem 1rem; }
    #no-matches p { color:#6b7280; margin-bottom:1.5rem; }
    .no-matches-actions { display:flex; gap:1rem; justify-content:center; flex-wrap:wrap; }
    .no-matches-btn { padding:0.75rem 1.5rem; border-radius:var(--radius-card,0.5rem); text-decoration:none; font-weight:500; }
    .no-matches-btn--primary { background:var(--color-primary,#4F46E5); color:#fff; }
    .no-matches-btn--secondary { border:1px solid #d1d5db; color:#374151; }

    /* Spinner */
    @keyframes spin { from{transform:rotate(0deg)} to{transform:rotate(360deg)} }
    .spinner { width:16px; height:16px; border:2px solid rgba(255,255,255,0.4); border-top-color:#fff; border-radius:50%; animation:spin 0.7s linear infinite; flex-shrink:0; }

    /* No available msg */
    #no-available-msg { text-align:center; padding:3rem 1rem; color:#6b7280; }

    /* Responsive */
    @media (max-width:640px) {
      h2 { font-size:1.375rem; }
      .container { padding:2rem 1rem; }
      .criterion-row { flex-wrap:wrap; }
      .criterion-label { width:auto; }
      .field-row { flex-wrap:wrap; }
      .field-label { min-width:100%; }
    }
    ${getBookingWidgetStyles()}
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>

    <!-- AC4: Collapsible extraction summary -->
    <section class="summary-section" id="summary-section" style="display:none" aria-label="R\u00e9sum\u00e9 de votre projet">
      <div class="summary-collapsed" id="summary-collapsed">
        <span class="summary-one-liner" id="summary-one-liner"></span>
        <button type="button" class="summary-toggle-btn" id="summary-modifier-btn">Modifier</button>
      </div>
      <div class="summary-expanded" id="summary-expanded">
        <div id="fields-container"></div>
        <button type="button" class="summary-close-btn" id="summary-close-btn">Fermer</button>
      </div>
    </section>

    <!-- AC2: Confirmation questions (needs_confirmation) -->
    <section class="questions-section" id="questions-section" style="display:none" aria-label="Questions de clarification">
      <h3>Aidez-nous \u00e0 affiner votre recherche</h3>
      <div id="questions-container"></div>
      <div id="confirm-error" role="alert" style="display:none"></div>
      <div id="cf-turnstile-container" style="display:none"></div>
      <button type="button" id="confirm-btn">Confirmer et trouver mes experts</button>
    </section>

    <!-- AC1: Skeleton loading -->
    <div id="matches-loading" aria-live="polite" style="display:none">
      <div class="skeleton-card">
        <div class="skeleton-line" style="width:40%"></div>
        <div class="skeleton-line skeleton-line--medium"></div>
        <div class="skeleton-line skeleton-line--short"></div>
        <div class="skeleton-line" style="width:70%"></div>
      </div>
      <div class="skeleton-card">
        <div class="skeleton-line" style="width:40%"></div>
        <div class="skeleton-line skeleton-line--medium"></div>
        <div class="skeleton-line skeleton-line--short"></div>
        <div class="skeleton-line" style="width:70%"></div>
      </div>
      <div class="skeleton-card">
        <div class="skeleton-line" style="width:40%"></div>
        <div class="skeleton-line skeleton-line--medium"></div>
        <div class="skeleton-line skeleton-line--short"></div>
      </div>
    </div>
    <!-- AC2: Computing state -->
    <div id="computing-msg" style="display:none" aria-live="polite">
      <p id="computing-msg-text">Nous affinons les correspondances, quelques secondes\u2026</p>
    </div>
    <!-- Placeholder for needs_confirmation (before submit) -->
    <div id="matches-placeholder" style="display:none">
      <p>R\u00e9pondez aux questions ci-dessus pour affiner vos r\u00e9sultats.</p>
    </div>
    <!-- Match cards (filled by JS) -->
    <div id="results-header" style="display:none">
      <h2 id="results-count-heading"></h2>
    </div>
    <div id="matches-container" style="display:none" aria-label="Experts correspondants"></div>
    <!-- No matches -->
    <div id="no-matches" style="display:none">
      <p>Aucun expert ne correspond exactement \u00e0 vos crit\u00e8res pour le moment.</p>
      <div class="no-matches-actions">
        <a href="/experts" class="no-matches-btn no-matches-btn--secondary">Parcourir le r\u00e9pertoire</a>
      </div>
    </div>
    <!-- Computing timeout fallback -->
    <div id="no-available-msg" style="display:none">
      <p>Le calcul des correspondances prend plus de temps que pr\u00e9vu. Vous recevrez vos r\u00e9sultats par email d\u00e8s qu\u2019ils sont pr\u00eats.</p>
      <a href="/experts" style="display:inline-block;margin-top:1rem;color:#6b7280;font-size:0.9375rem;text-decoration:none">En attendant, parcourir le r\u00e9pertoire</a>
    </div>
    <!-- Fetch error -->
    <div id="fetch-error" style="display:none" role="alert">
      <p id="fetch-error-msg">Une erreur est survenue.</p>
      <button type="button" id="retry-btn">R\u00e9essayer</button>
      <a href="/experts" id="fetch-error-browse" style="display:block;margin-top:0.5rem;font-size:0.875rem;color:#6b7280;text-decoration:none">Parcourir le r\u00e9pertoire d\u2019experts</a>
    </div>
    <!-- Email gate + OTP -->
    <section id="email-gate-section" style="display:none" aria-label="D\u00e9bloquer les profils complets">
      <h3>D\u00e9couvrez le profil complet de vos experts</h3>
      <p>Acc\u00e9dez aux noms, parcours et disponibilit\u00e9s de vos experts</p>
      <input type="email" id="email-input" placeholder="votre@email.com" aria-label="Votre adresse email">
      <div id="email-error" role="alert" style="display:none"></div>
      <button type="button" id="unlock-btn">D\u00e9bloquer les profils</button>
      <div id="otp-section" style="display:none">
        <p id="otp-hint"></p>
        <input type="text" id="otp-input" placeholder="000000" maxlength="6" inputmode="numeric" aria-label="Code de v\u00e9rification">
        <div id="otp-error" role="alert" style="display:none"></div>
        <button type="button" id="verify-otp-btn">V\u00e9rifier le code</button>
        <button type="button" id="resend-otp-btn" disabled>Renvoyer le code (<span id="resend-countdown">60</span>s)</button>
      </div>
    </section>
  </main>
  ${satConfigScript}
  ${getBookingWidgetScript()}
  <script>(function(){
    var FIELD_LABELS={
      challenge:'D\u00e9fi principal',
      skills_needed:'Comp\u00e9tences recherch\u00e9es',
      industry:'Secteur',
      budget_range:'Budget (EUR)',
      timeline:'Calendrier',
      company_size:'Taille de l\u2019entreprise',
      languages:'Langues'
    };
    var FIELD_ORDER=['challenge','skills_needed','industry','budget_range','timeline','company_size','languages'];
    var CRITERIA_LABELS={skills:'Comp\u00e9tences',industry:'Secteur',budget:'Budget',timeline:'Calendrier',languages:'Langues'};
    var TIER_LABELS={top:'Top Expert',confirmed:'Expert Confirm\u00e9',promising:'Expert Prometteur'};
    var TIER_CLASSES={top:'tier--top',confirmed:'tier--confirmed',promising:'tier--promising'};
    var TIER_AVATAR_COLORS={top:'#F59E0B',confirmed:'#64748B',promising:'#7C3AED'};

    var prospect_id=null;
    var token=null;
    var extraction=null;
    var mergedReqs={};
    var retryCount=0;
    var MAX_RETRIES=3;
    var waitStart=0;
    var networkErrorRetried=false;
    var isIdentifying=false;
    var matchesData=null;
    var widgetId=null;
    var isConfirming=false;
    var resendTimer=null;

    // AC9: Fire funnel_page2_loaded
    function firePage2Loaded(ext){
      firePostHog('satellite.funnel_page2_loaded',{
        satellite_id:window.__SAT__.satelliteId,
        ready_to_match:ext?ext.ready_to_match:null,
        needs_confirmation_count:ext&&Array.isArray(ext.needs_confirmation)?ext.needs_confirmation.length:0
      });
    }

    // AC1: Load extraction from sessionStorage
    try{
      var raw=sessionStorage.getItem('match:extraction');
      if(!raw){window.location.href='/match';return;}
      extraction=JSON.parse(raw);
    }catch(e){window.location.href='/match';return;}

    mergedReqs=Object.assign({},extraction.requirements||{});

    firePage2Loaded(extraction);

    // Render extraction summary
    renderSummarySection();

    // AC1 vs AC2: decide initial UI state
    if(extraction.ready_to_match===true){
      // AC1: auto-submit path — check for existing prospect_id (back navigation)
      try{
        prospect_id=sessionStorage.getItem('match:prospect_id');
        token=sessionStorage.getItem('match:token');
      }catch(e){}
      if(prospect_id&&token){
        // Back navigation: skip Turnstile, poll directly
        showEl('matches-loading');
        fetchMatches();
      }else{
        // First time: render Turnstile immediately (auto-fires)
        showEl('matches-loading');
        waitForTurnstileAndRender(true);
      }
    }else{
      // AC2: needs_confirmation — show questions + placeholder
      renderConfirmationQuestions();
      showEl('questions-section');
      showEl('matches-placeholder');
    }

    // ── Summary section (AC4) ──────────────────────────────────────────────────

    function renderSummarySection(){
      var reqs=extraction.requirements||{};
      var parts=[];
      FIELD_ORDER.forEach(function(field){
        if(parts.length>=3)return;
        var val=reqs[field];
        if(!val||(Array.isArray(val)&&val.length===0))return;
        var label=FIELD_LABELS[field]||field;
        parts.push(escHtml(label)+': '+escHtml(formatFieldValue(field,val)));
      });
      var oneLiner=parts.join(' \u00b7 ')||'Analyse de votre projet';
      document.getElementById('summary-one-liner').textContent=oneLiner;

      // Render editable fields in expanded view
      var fieldsContainer=document.getElementById('fields-container');
      var confidence=extraction.confidence||{};
      var html='';
      FIELD_ORDER.forEach(function(field){
        var label=FIELD_LABELS[field]||field;
        var conf=confidence[field]||0;
        var indicator=getConfidenceIndicator(conf);
        var value=mergedReqs[field];
        var displayValue=formatFieldValue(field,value);
        var isEmpty=!value||(Array.isArray(value)&&value.length===0);
        html+='<div class="field-row" data-field="'+field+'">';
        html+='<span class="confidence-indicator">'+indicator+'</span>';
        html+='<span class="field-label">'+escHtml(label)+'</span>';
        html+='<span class="field-value'+(isEmpty?' field-value--empty':'')+'" id="disp-'+field+'">';
        html+=isEmpty?'Non identifi\u00e9':escHtml(displayValue);
        html+='</span>';
        html+='<div class="field-edit" id="edit-'+field+'">';
        html+=buildEditInput(field,value);
        html+='<button class="save-edit-btn" data-field="'+field+'" type="button">Enregistrer</button>';
        html+='</div>';
        html+='<button class="modifier-btn" data-field="'+field+'" aria-label="Modifier '+escHtml(label)+'">Modifier</button>';
        html+='</div>';
      });
      fieldsContainer.innerHTML=html;

      // Wire Modifier buttons
      fieldsContainer.querySelectorAll('.modifier-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var f=btn.getAttribute('data-field');
          activateEditMode(f);
        });
      });

      // Wire Save buttons (AC5 — only fires re-match if prospect_id exists)
      fieldsContainer.querySelectorAll('.save-edit-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var f=btn.getAttribute('data-field');
          saveEditedField(f);
        });
      });

      // Show section
      showEl('summary-section');

      document.getElementById('summary-modifier-btn').addEventListener('click',function(){
        document.getElementById('summary-expanded').classList.add('visible');
        document.getElementById('summary-collapsed').style.display='none';
      });
      document.getElementById('summary-close-btn').addEventListener('click',function(){
        document.getElementById('summary-expanded').classList.remove('visible');
        document.getElementById('summary-collapsed').style.display='';
      });
    }

    // AC5: save edited field, optionally trigger re-match
    function saveEditedField(field){
      // Collect new value from the edit input
      var newVal=collectFieldValue(field);
      if(newVal!==undefined){
        mergedReqs[field]=newVal;
        // Update display span
        var dispEl=document.getElementById('disp-'+field);
        if(dispEl){
          var displayValue=formatFieldValue(field,newVal);
          var isEmpty=!newVal||(Array.isArray(newVal)&&newVal.length===0);
          if(isEmpty){
            dispEl.textContent='Non identifi\u00e9';
            dispEl.classList.add('field-value--empty');
          }else{
            dispEl.textContent=displayValue;
            dispEl.classList.remove('field-value--empty');
          }
        }
      }
      // Collapse back
      deactivateEditMode(field);
      document.getElementById('summary-expanded').classList.remove('visible');
      document.getElementById('summary-collapsed').style.display='';

      // AC9: fire extraction_edited
      var newValHash=newVal?String(JSON.stringify(newVal)).length.toString():'empty';
      firePostHog('satellite.extraction_edited',{
        satellite_id:window.__SAT__.satelliteId,
        field_name:field,
        new_value_hash:newValHash
      });

      // AC5: trigger re-match only if prospect_id already exists
      if(prospect_id&&token){
        firePostHog('satellite.rematch_triggered',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:prospect_id,
          edit_source:'extraction_edit'
        });
        triggerRematch();
      }
    }

    // AC5: POST /api/prospects/:id/requirements
    function triggerRematch(){
      hideEl('matches-container');
      hideEl('no-matches');
      hideEl('no-available-msg');
      hideEl('fetch-error');
      showEl('matches-loading');
      document.getElementById('results-count-heading').textContent='Mise \u00e0 jour de vos r\u00e9sultats\u2026';
      showEl('results-header');

      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/requirements',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({requirements:mergedReqs,token:token})
      })
      .then(function(res){
        if(res.status===429){throw{status:429};}
        if(!res.ok){throw{status:res.status};}
        return res.json();
      })
      .then(function(){
        // Reset polling state
        retryCount=0;
        waitStart=0;
        networkErrorRetried=false;
        fetchMatches();
      })
      .catch(function(err){
        hideEl('matches-loading');
        var msg=err&&err.status===429
          ?'Trop de modifications. Veuillez patienter avant de r\u00e9essayer.'
          :'Erreur lors de la mise \u00e0 jour. Veuillez r\u00e9essayer.';
        document.getElementById('fetch-error-msg').textContent=msg;
        showEl('fetch-error');
        firePostHog('satellite.matching_error',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:prospect_id,
          error_type:'rematch_error',
          page:'results',
          retry_count:0
        });
      });
    }

    function collectFieldValue(field){
      var editEl=document.getElementById('edit-'+field);
      if(!editEl||!editEl.classList.contains('visible'))return undefined;
      if(field==='budget_range'){
        var minEl=document.getElementById('edit-budget-min');
        var maxEl=document.getElementById('edit-budget-max');
        var budgetObj={};
        if(minEl&&minEl.value)budgetObj.min=parseInt(minEl.value,10);
        if(maxEl&&maxEl.value)budgetObj.max=parseInt(maxEl.value,10);
        return Object.keys(budgetObj).length>0?budgetObj:undefined;
      }else if(field==='skills_needed'||field==='languages'){
        var inp=document.getElementById('edit-'+field+'-input');
        if(inp&&inp.value.trim())return inp.value.split(',').map(function(s){return s.trim();}).filter(Boolean);
        return undefined;
      }else{
        var inp2=document.getElementById('edit-'+field+'-input');
        if(inp2&&inp2.value.trim())return inp2.value.trim();
        return undefined;
      }
    }

    function activateEditMode(field){
      var dispEl=document.getElementById('disp-'+field);
      var editEl=document.getElementById('edit-'+field);
      var btn=document.querySelector('.modifier-btn[data-field="'+field+'"]');
      if(dispEl)dispEl.style.display='none';
      if(btn)btn.style.display='none';
      if(editEl){
        editEl.classList.add('visible');
        var first=editEl.querySelector('input,select');
        if(first)first.focus();
      }
    }

    function deactivateEditMode(field){
      var dispEl=document.getElementById('disp-'+field);
      var editEl=document.getElementById('edit-'+field);
      var btn=document.querySelector('.modifier-btn[data-field="'+field+'"]');
      if(dispEl)dispEl.style.display='';
      if(btn)btn.style.display='';
      if(editEl)editEl.classList.remove('visible');
    }

    // ── Confirmation questions (AC2) ───────────────────────────────────────────

    function renderConfirmationQuestions(){
      var questions=extraction.confirmation_questions||[];
      var needsConf=extraction.needs_confirmation||[];
      var questionsContainer=document.getElementById('questions-container');
      var displayed=0;
      var html='';
      questions.forEach(function(q){
        if(displayed>=3)return;
        if(needsConf.indexOf(q.field)===-1)return;
        displayed++;
        html+='<div class="question-block" data-field="'+q.field+'">';
        html+='<label for="q-'+q.field+'">'+escHtml(q.question)+'</label>';
        if(q.options&&q.options.length>0){
          if(q.options.length<=5){
            html+='<div class="radio-group" role="group">';
            q.options.forEach(function(opt,idx){
              html+='<label><input type="radio" name="q-'+q.field+'" id="q-'+q.field+'-'+idx+'" value="'+escHtml(opt)+'"> '+escHtml(opt)+'</label>';
            });
            html+='</div>';
          }else{
            html+='<select id="q-'+q.field+'" aria-label="'+escHtml(q.question)+'">';
            html+='<option value="">S\u00e9lectionnez\u2026</option>';
            q.options.forEach(function(opt){
              html+='<option value="'+escHtml(opt)+'">'+escHtml(opt)+'</option>';
            });
            html+='</select>';
          }
        }else if(q.field==='budget_range'){
          html+='<div class="budget-inputs">';
          html+='<input type="number" id="q-budget-min" placeholder="Min" min="0" aria-label="Budget minimum">';
          html+='<span>\u20ac \u2013</span>';
          html+='<input type="number" id="q-budget-max" placeholder="Max" min="0" aria-label="Budget maximum">';
          html+='<span>\u20ac</span>';
          html+='</div>';
        }else{
          html+='<input type="text" id="q-'+q.field+'" aria-label="'+escHtml(q.question)+'">';
        }
        html+='</div>';
      });
      questionsContainer.innerHTML=html;

      document.getElementById('confirm-btn').addEventListener('click',handleConfirm);
    }

    function collectConfirmationAnswers(){
      var questions=extraction.confirmation_questions||[];
      var needsConf=extraction.needs_confirmation||[];
      questions.slice(0,3).forEach(function(q){
        if(needsConf.indexOf(q.field)===-1)return;
        if(q.field==='budget_range'){
          var minEl=document.getElementById('q-budget-min');
          var maxEl=document.getElementById('q-budget-max');
          var budgetObj={};
          if(minEl&&minEl.value)budgetObj.min=parseInt(minEl.value,10);
          if(maxEl&&maxEl.value)budgetObj.max=parseInt(maxEl.value,10);
          if(Object.keys(budgetObj).length>0)mergedReqs.budget_range=budgetObj;
        }else if(q.options&&q.options.length>0&&q.options.length<=5){
          var checked=document.querySelector('input[name="q-'+q.field+'"]:checked');
          if(checked)mergedReqs[q.field]=checked.value;
        }else{
          var el=document.getElementById('q-'+q.field);
          if(el&&el.value&&el.value.trim())mergedReqs[q.field]=el.value.trim();
        }
      });
    }

    function handleConfirm(){
      if(isConfirming)return;
      isConfirming=true;
      collectConfirmationAnswers();
      var confirmBtn=document.getElementById('confirm-btn');
      var confirmError=document.getElementById('confirm-error');
      confirmBtn.disabled=true;
      confirmBtn.innerHTML='<span class="spinner"></span>V\u00e9rification\u2026';
      confirmError.style.display='none';
      firePostHog('satellite.rematch_triggered',{
        satellite_id:window.__SAT__.satelliteId,
        prospect_id:null,
        edit_source:'confirmation_answer'
      });
      showEl('cf-turnstile-container');
      waitForTurnstileAndRender(false);
    }

    // ── Turnstile (AC6) ────────────────────────────────────────────────────────

    function waitForTurnstileAndRender(autoFire){
      if(typeof turnstile!=='undefined'){
        renderTurnstile(autoFire);
      }else{
        var waited=0;
        var maxWait=10000;
        var interval=setInterval(function(){
          waited+=250;
          if(typeof turnstile!=='undefined'){
            clearInterval(interval);
            renderTurnstile(autoFire);
          }else if(waited>=maxWait){
            clearInterval(interval);
            handleTurnstileError('turnstile_timeout');
          }
        },250);
      }
    }

    function renderTurnstile(autoFire){
      var containerId=autoFire?'cf-turnstile-auto':'cf-turnstile-container';
      // Create auto-fire container if needed
      if(autoFire){
        var autoDiv=document.getElementById('cf-turnstile-auto');
        if(!autoDiv){
          autoDiv=document.createElement('div');
          autoDiv.id='cf-turnstile-auto';
          autoDiv.style.display='none';
          document.body.appendChild(autoDiv);
        }
        containerId='cf-turnstile-auto';
      }
      widgetId=turnstile.render('#'+containerId,{
        sitekey:window.__SAT__.turnstileSiteKey,
        appearance:'interaction-only',
        callback:function(tsToken){
          doSubmit(tsToken);
        },
        'error-callback':function(){
          handleTurnstileError('turnstile_error');
        },
        'expired-callback':function(){
          if(widgetId!==null&&typeof turnstile!=='undefined')turnstile.reset(widgetId);
        }
      });
    }

    function handleTurnstileError(errType){
      if(extraction.ready_to_match===true&&!prospect_id){
        hideEl('matches-loading');
        firePostHog('satellite.matching_error',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:null,
          error_type:'turnstile',
          page:'results',
          retry_count:0
        });
        document.getElementById('fetch-error-msg').textContent='La v\u00e9rification de s\u00e9curit\u00e9 a \u00e9chou\u00e9. Veuillez r\u00e9essayer.';
        showEl('fetch-error');
      }else{
        isConfirming=false;
        var confirmBtn=document.getElementById('confirm-btn');
        confirmBtn.disabled=false;
        confirmBtn.textContent='Confirmer et trouver mes experts';
        var confirmError=document.getElementById('confirm-error');
        confirmError.textContent='La v\u00e9rification de s\u00e9curit\u00e9 a \u00e9chou\u00e9. Veuillez r\u00e9essayer.';
        confirmError.style.display='block';
        hideEl('cf-turnstile-container');
      }
    }

    // ── Submit (AC1/AC2) ───────────────────────────────────────────────────────

    function doSubmit(turnstileToken){
      var utmData={};
      try{
        var rawUtm=sessionStorage.getItem('match:utm');
        if(rawUtm)utmData=JSON.parse(rawUtm);
      }catch(e){}
      var body={
        satellite_id:window.__SAT__.satelliteId,
        quiz_answers:mergedReqs,
        'cf-turnstile-response':turnstileToken
      };
      if(utmData.utm_source)body.utm_source=utmData.utm_source;
      if(utmData.utm_campaign)body.utm_campaign=utmData.utm_campaign;
      if(utmData.utm_medium)body.utm_medium=utmData.utm_medium;
      if(utmData.utm_content)body.utm_content=utmData.utm_content;

      // Retrieve flow_token stored by match.ts extraction
      var rawExtraction=null;
      try{rawExtraction=sessionStorage.getItem('match:extraction');}catch(e){}
      if(rawExtraction){
        try{
          var ext=JSON.parse(rawExtraction);
          if(ext&&ext.flow_token)body.flow_token=ext.flow_token;
        }catch(e){}
      }

      fetch(window.__SAT__.apiUrl+'/api/prospects/submit',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify(body)
      })
      .then(function(res){
        if(res.status===422){return res.json().then(function(d){throw{status:422,data:d};});}
        if(res.status===429){throw{status:429,data:null};}
        if(!res.ok){throw{status:res.status,data:null};}
        return res.json();
      })
      .then(function(data){
        try{
          sessionStorage.setItem('match:prospect_id',data.prospect_id);
          sessionStorage.setItem('match:token',data.token);
        }catch(e){}
        prospect_id=data.prospect_id;
        token=data.token;
        firePostHog('satellite.prospect_created',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:data.prospect_id
        });
        // If coming from confirmation path, hide the questions section
        if(!extraction.ready_to_match){
          hideEl('questions-section');
          hideEl('matches-placeholder');
          showEl('matches-loading');
        }
        // Reset polling state
        retryCount=0;
        waitStart=0;
        networkErrorRetried=false;
        fetchMatches();
      })
      .catch(function(err){
        handleSubmitError(err&&err.status?err.status:'network',err&&err.data?err.data:null);
      });
    }

    function handleSubmitError(status,data){
      isConfirming=false;
      var confirmBtn=document.getElementById('confirm-btn');
      if(confirmBtn){
        confirmBtn.disabled=false;
        confirmBtn.textContent='Confirmer et trouver mes experts';
      }
      if(extraction.ready_to_match===true){
        hideEl('matches-loading');
      }
      var errorType='network';
      if(status===422)errorType='validation_422';
      else if(status===429)errorType='rate_limit_429';
      firePostHog('satellite.matching_error',{
        satellite_id:window.__SAT__.satelliteId,
        prospect_id:null,
        error_type:errorType,
        page:'results',
        retry_count:0
      });
      var msg='La connexion au serveur a \u00e9chou\u00e9. V\u00e9rifiez votre connexion internet et r\u00e9essayez.';
      if(status===422){
        msg='Les donn\u00e9es saisies sont invalides.';
        if(data&&data.error)msg=data.error;
        var confirmError=document.getElementById('confirm-error');
        if(confirmError){
          confirmError.textContent=msg;
          confirmError.style.display='block';
          return;
        }
      }else if(status===429){
        msg='Trop de tentatives. Veuillez patienter.';
      }
      document.getElementById('fetch-error-msg').textContent=msg;
      showEl('fetch-error');
    }

    // ── Match polling (AC1/AC2) ────────────────────────────────────────────────

    function fetchMatches(){
      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/matches?token='+encodeURIComponent(token))
      .then(function(res){
        if(res.status===202){return res.json().then(function(d){handle202(d);return null;});}
        if(!res.ok){throw{status:res.status};}
        return res.json();
      })
      .then(function(data){
        if(!data)return;
        matchesData=data.matches||[];
        if(matchesData.length===0){
          hideEl('matches-loading');
          showEl('no-matches');
          return;
        }
        renderAnonymizedCards(matchesData);
        firePostHog('satellite.matches_viewed',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:prospect_id,
          match_count:matchesData.length,
          top_score:matchesData[0]?matchesData[0].overall_score:null
        });
      })
      .catch(function(err){
        if(!networkErrorRetried){
          networkErrorRetried=true;
          hideEl('computing-msg');
          setTimeout(function(){fetchMatches();},2000);
          return;
        }
        hideEl('matches-loading');
        hideEl('computing-msg');
        var isServer=err&&err.status&&err.status>=500;
        var errorMsg=isServer
          ?'Nos serveurs sont momentan\u00e9ment indisponibles. R\u00e9essayez dans quelques instants.'
          :'Connexion interrompue. V\u00e9rifiez votre connexion et r\u00e9essayez.';
        var errorType=isServer?'server_5xx':'network';
        document.getElementById('fetch-error-msg').textContent=errorMsg;
        showEl('fetch-error');
        firePostHog('satellite.matching_error',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:prospect_id,
          error_type:errorType,
          page:'results',
          retry_count:1
        });
      });
    }

    function handle202(data){
      if(retryCount===0){waitStart=Date.now();}
      if(retryCount>=MAX_RETRIES){
        hideEl('matches-loading');
        hideEl('computing-msg');
        showEl('no-available-msg');
        firePostHog('satellite.matching_error',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:prospect_id,
          error_type:'computing_timeout',
          page:'results',
          retry_count:retryCount
        });
        return;
      }
      hideEl('matches-loading');
      var msgEl=document.getElementById('computing-msg-text');
      if(msgEl&&Date.now()-waitStart>10000){
        msgEl.textContent='Cela prend un peu plus de temps que pr\u00e9vu. Votre recherche est en cours.';
      }
      showEl('computing-msg');
      var base=(data&&data.estimated_seconds?data.estimated_seconds*1000:3000);
      var delay=base*Math.pow(2,retryCount);
      retryCount++;
      setTimeout(function(){
        hideEl('computing-msg');
        showEl('matches-loading');
        fetchMatches();
      },delay);
    }

    // ── Anonymized cards ──────────────────────────────────────────────────────

    function renderAnonymizedCards(matches){
      hideEl('matches-loading');
      var container=document.getElementById('matches-container');
      var heading=document.getElementById('results-count-heading');
      heading.textContent=matches.length+' expert'+(matches.length>1?'s':'')+' correspondent \u00e0 votre projet';
      showEl('results-header');

      var svgAvatar='<svg width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="8" r="4" fill="#9ca3af"/><path d="M4 20c0-4.418 3.582-8 8-8s8 3.582 8 8" fill="#9ca3af"/></svg>';
      var html='';
      matches.forEach(function(match,idx){
        var rank=match.rank||(idx+1);
        var isProminent=rank<=3;
        var tierKey=(match.tier||'promising');
        var tierLabel=TIER_LABELS[tierKey]||tierKey;
        var tierClass=TIER_CLASSES[tierKey]||'tier--promising';
        var rankClass=rank<=3?'rank-badge--'+rank:'rank-badge--other';
        html+='<div class="match-card'+(isProminent?' match-card--prominent':'')+'" data-rank="'+rank+'">';
        html+='<div class="card-header">';
        html+='<div class="rank-badge '+rankClass+'">#'+rank+'</div>';
        html+='<div class="avatar-silhouette">'+svgAvatar+'</div>';
        html+='<div class="card-header-meta">';
        html+='<span class="tier-badge '+tierClass+'">'+escHtml(tierLabel)+'</span> ';
        html+='<span class="score-badge">'+Math.round(match.overall_score||0)+'/100</span>';
        html+='</div></div>';
        html+='<div class="score-breakdown">';
        var criteria=match.criteria_scores||{};
        ['skills','industry','budget','timeline','languages'].forEach(function(key){
          var score=criteria[key]!==undefined?Math.round(criteria[key]):0;
          var label=CRITERIA_LABELS[key]||key;
          html+='<div class="criterion-row">';
          html+='<span class="criterion-label">'+escHtml(label)+'</span>';
          html+='<div class="score-bar-track"><div class="score-bar-fill" style="width:'+score+'%;min-width:0"></div></div>';
          html+='<span class="criterion-score">'+score+'</span>';
          html+='</div>';
        });
        html+='</div>';
        var skills=match.skills_matched||[];
        if(skills.length>0){
          html+='<div class="tags-row">';
          skills.forEach(function(s){html+='<span class="tag">'+escHtml(String(s))+'</span>';});
          html+='</div>';
        }
        if(match.rate_min!==undefined||match.rate_max!==undefined){
          html+='<div class="rate-range">\u20AC'+(match.rate_min||'?')+' \u2014 \u20AC'+(match.rate_max||'?')+' / heure</div>';
        }
        var industries=match.industries||[];
        var projectTypes=match.project_types||[];
        if(industries.length>0||projectTypes.length>0){
          html+='<div class="tags-row">';
          industries.forEach(function(i){html+='<span class="tag">'+escHtml(String(i))+'</span>';});
          projectTypes.forEach(function(pt){html+='<span class="tag">'+escHtml(String(pt))+'</span>';});
          html+='</div>';
        }
        var langs=match.languages||[];
        if(langs.length>0){
          html+='<div class="tags-row">';
          langs.forEach(function(l){html+='<span class="lang-tag">'+escHtml(String(l))+'</span>';});
          html+='</div>';
        }
        html+='<button class="expand-btn" data-rank="'+rank+'" aria-expanded="false">Voir le d\u00e9tail</button>';
        html+='</div>';
      });
      container.innerHTML=html;
      showEl('matches-container');
      showEl('email-gate-section');

      container.querySelectorAll('.expand-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var r=btn.getAttribute('data-rank');
          var expanded=btn.getAttribute('aria-expanded')==='true';
          btn.setAttribute('aria-expanded',expanded?'false':'true');
          btn.textContent=expanded?'Voir le d\u00e9tail':'Masquer le d\u00e9tail';
          if(!expanded){
            firePostHog('satellite.match_card_expanded',{
              satellite_id:window.__SAT__.satelliteId,
              expert_rank:parseInt(r||'0',10)
            });
          }
        });
      });
    }

    // ── Email gate + OTP (E06S39) ─────────────────────────────────────────────

    document.getElementById('unlock-btn').addEventListener('click',handleEmailSubmit);
    document.getElementById('retry-btn').addEventListener('click',function(){
      hideEl('fetch-error');
      showEl('matches-loading');
      retryCount=0;
      networkErrorRetried=false;
      fetchMatches();
    });

    function handleEmailSubmit(){
      if(isIdentifying)return;
      var emailInput=document.getElementById('email-input');
      var emailError=document.getElementById('email-error');
      var unlockBtn=document.getElementById('unlock-btn');
      var email=emailInput.value.trim();
      emailError.style.display='none';
      if(!email||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){
        emailError.textContent='Veuillez entrer une adresse email valide.';
        emailError.style.display='block';
        return;
      }
      isIdentifying=true;
      unlockBtn.disabled=true;
      unlockBtn.innerHTML='<span class="spinner"></span>Chargement\u2026';
      emailInput.disabled=true;
      firePostHog('satellite.email_gate_submitted',{
        satellite_id:window.__SAT__.satelliteId,
        prospect_id:prospect_id
      });
      // E06S39: POST /otp/send
      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/otp/send',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:email,token:token})
      })
      .then(function(res){
        if(res.status===409){return fetchProfilesDirect();}
        if(res.status===429){throw{status:429};}
        if(!res.ok){throw{status:res.status};}
        return res.json().then(function(data){
          showOtpSection(data.email||email);
          return null;
        });
      })
      .then(function(result){
        if(result===null)return;
        // fetchProfilesDirect returned data
        if(result&&result.experts){
          revealFullProfiles(result.experts||[]);
        }
      })
      .catch(function(err){
        isIdentifying=false;
        unlockBtn.disabled=false;
        unlockBtn.textContent='D\u00e9bloquer les profils';
        emailInput.disabled=false;
        var msg='Une erreur est survenue. Veuillez r\u00e9essayer.';
        if(err&&err.status===429)msg='Trop de tentatives. Veuillez r\u00e9essayer plus tard.';
        emailError.textContent=msg;
        emailError.style.display='block';
      });
    }

    function showOtpSection(maskedEmail){
      var unlockBtn=document.getElementById('unlock-btn');
      var emailInput=document.getElementById('email-input');
      unlockBtn.style.display='none';
      emailInput.disabled=true;
      var otpHint=document.getElementById('otp-hint');
      otpHint.textContent='Un code de v\u00e9rification a \u00e9t\u00e9 envoy\u00e9 \u00e0 '+maskedEmail+'. V\u00e9rifiez votre bo\u00eete mail.';
      showEl('otp-section');
      document.getElementById('verify-otp-btn').addEventListener('click',handleOtpVerify);
      document.getElementById('resend-otp-btn').addEventListener('click',handleResendOtp);
      startResendCountdown();
    }

    function startResendCountdown(){
      var resendBtn=document.getElementById('resend-otp-btn');
      var countdownEl=document.getElementById('resend-countdown');
      var seconds=60;
      resendBtn.disabled=true;
      if(resendTimer)clearInterval(resendTimer);
      resendTimer=setInterval(function(){
        seconds--;
        if(countdownEl)countdownEl.textContent=String(seconds);
        if(seconds<=0){
          clearInterval(resendTimer);
          resendTimer=null;
          resendBtn.disabled=false;
          resendBtn.textContent='Renvoyer le code';
        }
      },1000);
    }

    function handleOtpVerify(){
      var otpInput=document.getElementById('otp-input');
      var otpError=document.getElementById('otp-error');
      var verifyBtn=document.getElementById('verify-otp-btn');
      var code=otpInput.value.trim();
      otpError.style.display='none';
      if(!code||code.length!==6){
        otpError.textContent='Veuillez entrer le code \u00e0 6 chiffres.';
        otpError.style.display='block';
        return;
      }
      verifyBtn.disabled=true;
      verifyBtn.innerHTML='<span class="spinner"></span>V\u00e9rification\u2026';
      // POST /otp/verify
      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/otp/verify',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({code:code,token:token})
      })
      .then(function(res){
        if(!res.ok){
          return res.json().then(function(d){throw{status:res.status,data:d};});
        }
        return res.json();
      })
      .then(function(data){
        if(!data.verified){
          verifyBtn.disabled=false;
          verifyBtn.textContent='V\u00e9rifier le code';
          otpError.textContent='Code incorrect. '+(data.remaining_attempts||0)+' tentative(s) restante(s).';
          otpError.style.display='block';
          return;
        }
        // OTP verified — call identify (no email in body, taken from KV)
        return fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/identify',{
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body:JSON.stringify({token:token})
        })
        .then(function(res){
          if(res.status===409){return fetchProfilesDirect();}
          if(!res.ok){throw{status:res.status};}
          return res.json();
        })
        .then(function(identifyData){
          if(!identifyData)return;
          revealFullProfiles(identifyData.experts||[]);
        });
      })
      .catch(function(err){
        verifyBtn.disabled=false;
        verifyBtn.textContent='V\u00e9rifier le code';
        var msg='Une erreur est survenue. Veuillez r\u00e9essayer.';
        if(err&&err.status===410)msg='Code expir\u00e9. Veuillez demander un nouveau code.';
        else if(err&&err.status===429)msg='Trop de tentatives. Demandez un nouveau code.';
        otpError.textContent=msg;
        otpError.style.display='block';
      });
    }

    function handleResendOtp(){
      var emailInput=document.getElementById('email-input');
      var email=emailInput.value.trim();
      if(!email)return;
      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/otp/send',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:email,token:token})
      })
      .then(function(res){return res.json();})
      .then(function(){
        startResendCountdown();
        var otpError=document.getElementById('otp-error');
        otpError.style.display='none';
      })
      .catch(function(){});
    }

    function fetchProfilesDirect(){
      return fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/matches?token='+encodeURIComponent(token)+'&identified=true')
      .then(function(res){return res.json();})
      .then(function(data){
        revealFullProfiles(data.experts||data.matches||[]);
        return null;
      });
    }

    function revealFullProfiles(experts){
      hideEl('email-gate-section');
      var container=document.getElementById('matches-container');
      var cards=container.querySelectorAll('.match-card');
      experts.forEach(function(expert,idx){
        var card=cards[idx];
        if(!card)return;
        var rank=parseInt(card.getAttribute('data-rank')||'0',10);
        var tierKey=expert.tier||(matchesData&&matchesData[idx]?matchesData[idx].tier:'promising')||'promising';
        var avatarColor=TIER_AVATAR_COLORS[tierKey]||'#64748B';
        var initial=expert.display_name?expert.display_name.charAt(0).toUpperCase():'?';
        var headerEl=card.querySelector('.card-header');
        if(headerEl){
          var rankClass=rank<=3?'rank-badge--'+rank:'rank-badge--other';
          var tierClass=TIER_CLASSES[tierKey]||'tier--promising';
          var tierLabel=TIER_LABELS[tierKey]||tierKey;
          headerEl.innerHTML=
            '<div class="rank-badge '+rankClass+'">#'+rank+'</div>'
            +'<div class="avatar-initial" style="background:'+escHtml(avatarColor)+'">'+escHtml(initial)+'</div>'
            +'<div class="card-header-meta">'
            +'<div class="expert-name">'+escHtml(expert.display_name||'')+'</div>'
            +'<div class="expert-headline">'+escHtml(expert.headline||'')+'</div>'
            +'<span class="tier-badge '+tierClass+'">'+escHtml(tierLabel)+'</span>'
            +'</div>';
        }
        var scoreBreakdown=card.querySelector('.score-breakdown');
        if(scoreBreakdown){
          var bioHtml='<div class="bio-block">'
            +'<p class="bio-text" id="bio-'+idx+'">'+escHtml(expert.bio||'')+'</p>'
            +'<button class="bio-expand-btn" data-idx="'+idx+'" type="button">Lire la suite</button>'
            +'</div>';
          scoreBreakdown.insertAdjacentHTML('beforebegin',bioHtml);
        }
        var expertId=expert.expert_id||'';
        card.insertAdjacentHTML('beforeend','<button class="booking-btn" data-expert-id="'+escHtml(expertId)+'" type="button">R\u00e9server un appel</button>');
      });
      container.querySelectorAll('.bio-expand-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var idx=btn.getAttribute('data-idx');
          var bioEl=document.getElementById('bio-'+idx);
          if(!bioEl)return;
          bioEl.classList.toggle('expanded');
          btn.textContent=bioEl.classList.contains('expanded')?'R\u00e9duire':'Lire la suite';
        });
      });
      var expertNameMap={};
      experts.forEach(function(expert){ var id=expert.expert_id||''; if(id)expertNameMap[id]=expert.display_name||''; });
      container.querySelectorAll('.booking-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var expertId=btn.getAttribute('data-expert-id')||'';
          var expertName=expertNameMap[expertId]||'';
          var matchCard=btn.closest('.match-card');
          var rank=matchCard?parseInt(matchCard.getAttribute('data-rank')||'0',10):0;
          firePostHog('satellite.booking_cta_clicked',{
            satellite_id:window.__SAT__.satelliteId,
            prospect_id:prospect_id,
            expert_rank:rank
          });
          window.dispatchEvent(new CustomEvent('booking-open',{detail:{expertId:expertId,expertName:expertName}}));
        });
      });
      firePostHog('satellite.profiles_unlocked',{
        satellite_id:window.__SAT__.satelliteId,
        prospect_id:prospect_id,
        match_count:experts.length
      });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function getConfidenceIndicator(c){
      if(c>=0.7)return'\u2705';
      if(c>=0.4)return'\ud83d\udfe0';
      return'\u2753';
    }

    function formatFieldValue(field,value){
      if(!value)return'';
      if(field==='budget_range'&&typeof value==='object'&&!Array.isArray(value)){
        var parts=[];
        if(value.min!==undefined)parts.push(value.min+'\u00a0\u20ac');
        if(value.max!==undefined)parts.push(value.max+'\u00a0\u20ac');
        return parts.join(' \u2013 ');
      }
      if(Array.isArray(value))return value.join(', ');
      return String(value);
    }

    function buildEditInput(field,currentValue){
      if(field==='budget_range'){
        var minVal=(currentValue&&currentValue.min!==undefined)?currentValue.min:'';
        var maxVal=(currentValue&&currentValue.max!==undefined)?currentValue.max:'';
        return'<div class="budget-inputs">'
          +'<input type="number" id="edit-budget-min" placeholder="Min" value="'+escHtml(String(minVal))+'" min="0" aria-label="Budget minimum en euros">'
          +'<span>\u20ac \u2013</span>'
          +'<input type="number" id="edit-budget-max" placeholder="Max" value="'+escHtml(String(maxVal))+'" min="0" aria-label="Budget maximum en euros">'
          +'<span>\u20ac</span>'
          +'</div>';
      }
      if(field==='skills_needed'||field==='languages'){
        var arrVal=Array.isArray(currentValue)?currentValue.join(', '):(currentValue||'');
        return'<input type="text" id="edit-'+field+'-input" value="'+escHtml(String(arrVal))+'" placeholder="S\u00e9par\u00e9es par des virgules" aria-label="'+escHtml(FIELD_LABELS[field]||field)+'">';
      }
      return'<input type="text" id="edit-'+field+'-input" value="'+escHtml(String(currentValue||''))+'" aria-label="'+escHtml(FIELD_LABELS[field]||field)+'">';
    }

    function showEl(id){var el=document.getElementById(id);if(el)el.style.display='';}
    function hideEl(id){var el=document.getElementById(id);if(el)el.style.display='none';}
    function firePostHog(event,props){
      if(typeof posthog!=='undefined')posthog.capture(event,props);
    }
    function escHtml(str){
      if(!str)return'';
      return String(str)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
    }
  })();</script>
</body>
</html>`;
}
