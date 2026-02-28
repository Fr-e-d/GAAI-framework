import type { SatelliteConfig } from '../types/config';
import { getBookingWidgetStyles, getBookingWidgetScript } from './booking-widget';

// ── Types ─────────────────────────────────────────────────────────────────────

interface AnonymizedExpertDetail {
  slug: string;
  headline: string | null;
  skills: string[];
  industries: string[];
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  quality_tier: string | null;
  completed_projects: number;
  languages: string[];
  bio_excerpt: string | null;
  availability_status: string | null;
  outcome_tags: string[];
  direct_booking_url?: string | null;
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

function tierLabel(tier: string | null): string {
  if (tier === 'top') return 'Top Expert';
  if (tier === 'confirmed') return 'Expert Confirmé';
  return 'Expert Prometteur';
}

function tierAvatarColor(tier: string | null): string {
  if (tier === 'top') return '#F59E0B';
  if (tier === 'confirmed') return '#64748B';
  return '#7C3AED';
}

function tierBadgeClass(tier: string | null): string {
  if (tier === 'top') return 'tier--top';
  if (tier === 'confirmed') return 'tier--confirmed';
  return 'tier--promising';
}

function availabilityLabel(status: string | null): string {
  if (status === 'available') return 'Disponible';
  if (status === 'available_soon') return 'Disponible prochainement';
  return 'Disponibilité non renseignée';
}

function availabilityClass(status: string | null): string {
  if (status === 'available') return 'avail--available';
  if (status === 'available_soon') return 'avail--soon';
  return 'avail--unknown';
}

// ── Main render function ───────────────────────────────────────────────────────

export async function renderExpertProfilePage(
  config: SatelliteConfig,
  posthogApiKey: string,
  coreApiUrl: string,
  slug: string,
): Promise<{ html: string; status: number }> {
  const theme = config.theme;
  const brand = config.brand;

  // AC4: Fetch expert detail from Core API server-side
  let expert: AnonymizedExpertDetail | null = null;
  try {
    const res = await fetch(`${coreApiUrl}/api/experts/public/${encodeURIComponent(slug)}`);
    if (res.status === 404) {
      return { html: '', status: 404 };
    }
    if (res.ok) {
      expert = await res.json();
    }
  } catch {
    // Graceful degradation
  }

  if (!expert) {
    return { html: renderErrorPage(config, brand?.name ?? 'Callibrate'), status: 500 };
  }

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

  const color = tierAvatarColor(expert.quality_tier);
  const label = tierLabel(expert.quality_tier);
  const badgeClass = tierBadgeClass(expert.quality_tier);
  const initials = expert.headline ? expert.headline.charAt(0).toUpperCase() : 'E';
  const score = expert.composite_score !== null ? Math.round(expert.composite_score) : null;
  const topSkill = expert.skills[0] ?? config.content?.vertical_label ?? config.vertical ?? 'Automatisation';

  // AC7: JSON-LD Person (anonymized — no name, use headline + skills)
  const personData = {
    '@context': 'https://schema.org',
    '@type': 'Person',
    jobTitle: expert.headline ?? label,
    knowsAbout: expert.skills,
    url: `https://${config.domain}/experts/${expert.slug}`,
    description: expert.bio_excerpt ?? '',
  };
  const jsonLdScript = `<script type="application/ld+json">${JSON.stringify(personData).replace(/</g, '\\u003c')}</script>`;

  // PostHog head snippet
  const posthogHeadSnippet = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
    : '';

  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({
    apiUrl: coreApiUrl,
    satelliteId: config.id,
    expertSlug: expert.slug,
  }).replace(/</g, '\\u003c')};</script>`;

  // Render tags
  const skillsHtml = expert.skills.map((s) => `<span class="tag">${escapeHtml(s)}</span>`).join('');
  const industriesHtml = expert.industries.map((i) => `<span class="tag tag--industry">${escapeHtml(i)}</span>`).join('');
  const languagesHtml = expert.languages.map((l) => `<span class="tag tag--lang">${escapeHtml(l)}</span>`).join('');

  const rateHtml = (expert.rate_min !== null || expert.rate_max !== null)
    ? `<div class="rate-range">\u20AC${expert.rate_min ?? '?'} \u2014 \u20AC${expert.rate_max ?? '?'} / h</div>`
    : '';

  const scoreHtml = score !== null
    ? `<div class="score-block"><span class="score-label">Score</span><span class="score-badge">${score}/100</span></div>`
    : '';

  const bioHtml = expert.bio_excerpt
    ? `<div class="bio-block"><p class="bio-text">${escapeHtml(expert.bio_excerpt)}</p></div>`
    : '';

  const projectsHtml = expert.completed_projects > 0
    ? `<div class="meta-item">${expert.completed_projects} projet${expert.completed_projects > 1 ? 's' : ''} réalisé${expert.completed_projects > 1 ? 's' : ''}</div>`
    : '';

  // AC11: Direct booking CTA (conditional — only shown if direct_booking_url is returned by API)
  const directBookingUrl = expert.direct_booking_url ?? null;
  const directCtaHtml = directBookingUrl
    ? `<a href="${escapeHtml(directBookingUrl)}" class="cta-secondary cta-direct" target="_blank" rel="noopener noreferrer">Prendre un rendez-vous direct</a>`
    : '';

  // AC4: "Débloquer ce profil" — inline email gate
  const unlockSectionHtml = `<section id="unlock-section" aria-label="Débloquer ce profil">
  <button type="button" id="unlock-trigger-btn" class="cta-secondary">D\u00e9bloquer ce profil</button>
  <div id="unlock-form" style="display:none" class="unlock-form">
    <p class="unlock-description">Entrez votre email pour accéder aux disponibilités et prendre rendez-vous avec cet expert.</p>
    <input type="email" id="unlock-email" placeholder="votre@email.com" aria-label="Votre adresse email" class="email-input">
    <div id="unlock-error" role="alert" style="display:none" class="form-error"></div>
    <button type="button" id="unlock-submit-btn" class="cta-primary">
      <span id="unlock-btn-text">Accéder aux disponibilités</span>
      <span id="unlock-spinner" class="spinner" style="display:none" aria-hidden="true"></span>
    </button>
  </div>
  <div id="unlock-success" style="display:none" class="unlock-success">
    <p>Vos disponibilités ont été chargées. Vous pouvez maintenant prendre rendez-vous.</p>
  </div>
</section>`;

  // AC8: PostHog events
  const posthogBodyScript = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>(function(){
    posthog.capture('satellite.expert_profile_viewed',{satellite_id:${JSON.stringify(config.id)},expert_slug:${JSON.stringify(expert.slug)},quality_tier:${JSON.stringify(expert.quality_tier||'')}});
    var matchBtn=document.getElementById('cta-match-btn');
    if(matchBtn)matchBtn.addEventListener('click',function(){
      posthog.capture('satellite.expert_cta_match_clicked',{satellite_id:${JSON.stringify(config.id)},expert_slug:${JSON.stringify(expert.slug)}});
    });
    var unlockTrigger=document.getElementById('unlock-trigger-btn');
    if(unlockTrigger)unlockTrigger.addEventListener('click',function(){
      posthog.capture('satellite.expert_cta_unlock_clicked',{satellite_id:${JSON.stringify(config.id)},expert_slug:${JSON.stringify(expert.slug)}});
    });
  })();</script>`
    : '';

  // Unlock + booking widget interaction script
  const interactiveScript = `<script>(function(){
    var unlockTrigger=document.getElementById('unlock-trigger-btn');
    var unlockForm=document.getElementById('unlock-form');
    var unlockSubmit=document.getElementById('unlock-submit-btn');
    var unlockEmail=document.getElementById('unlock-email');
    var unlockError=document.getElementById('unlock-error');
    var unlockSuccess=document.getElementById('unlock-success');
    var btnText=document.getElementById('unlock-btn-text');
    var spinner=document.getElementById('unlock-spinner');
    var isSubmitting=false;

    if(unlockTrigger){
      unlockTrigger.addEventListener('click',function(){
        unlockTrigger.style.display='none';
        unlockForm.style.display='';
        unlockEmail.focus();
      });
    }

    if(unlockSubmit){
      unlockSubmit.addEventListener('click',handleUnlock);
    }
    if(unlockEmail){
      unlockEmail.addEventListener('keydown',function(e){if(e.key==='Enter')handleUnlock();});
    }

    function handleUnlock(){
      if(isSubmitting)return;
      var email=unlockEmail?unlockEmail.value.trim():'';
      if(unlockError)unlockError.style.display='none';
      if(!email||!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)){
        if(unlockError){unlockError.textContent='Veuillez entrer une adresse email valide.';unlockError.style.display='';}
        return;
      }
      isSubmitting=true;
      if(unlockSubmit)unlockSubmit.disabled=true;
      if(btnText)btnText.style.display='none';
      if(spinner)spinner.style.display='';
      fetch(window.__SAT__.apiUrl+'/api/prospects/create-from-directory',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:email,expert_slug:window.__SAT__.expertSlug})
      })
      .then(function(res){
        if(!res.ok){throw{status:res.status};}
        return res.json();
      })
      .then(function(data){
        try{
          sessionStorage.setItem('dir:prospect_id',data.prospect_id);
          sessionStorage.setItem('dir:token',data.token);
          sessionStorage.setItem('dir:expert_id',data.expert_id);
        }catch(e){}
        if(unlockForm)unlockForm.style.display='none';
        if(unlockSuccess)unlockSuccess.style.display='';
        // Open booking widget
        window.dispatchEvent(new CustomEvent('booking-open',{detail:{expertId:data.expert_id,expertName:''}}));
      })
      .catch(function(){
        isSubmitting=false;
        if(unlockSubmit)unlockSubmit.disabled=false;
        if(btnText)btnText.style.display='';
        if(spinner)spinner.style.display='none';
        if(unlockError){unlockError.textContent='Une erreur est survenue. Veuillez r\u00e9essayer.';unlockError.style.display='';}
      });
    }
  })();</script>`;

  return {
    status: 200,
    html: `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(label)} en ${escapeHtml(topSkill)} \u2014 ${escapeHtml(brand?.name ?? 'Callibrate')}</title>
  <meta name="description" content="${escapeHtml(expert.bio_excerpt ?? `${label} en ${topSkill}. Disponible sur ${brand?.name ?? 'Callibrate'}.`)}">
  <meta name="robots" content="index, follow">
  <link rel="canonical" href="https://${escapeHtml(config.domain)}/experts/${escapeHtml(expert.slug)}">
  <meta property="og:title" content="${escapeHtml(label)} en ${escapeHtml(topSkill)} \u2014 ${escapeHtml(brand?.name ?? 'Callibrate')}">
  <meta property="og:url" content="https://${escapeHtml(config.domain)}/experts/${escapeHtml(expert.slug)}">
  <meta property="og:type" content="profile">
  ${jsonLdScript}
  ${posthogHeadSnippet}
  <style>
    ${cssVars}
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: var(--font-family, 'Inter, sans-serif'); color: #1a1a2e; background: #fafafa; line-height: 1.6; min-height: 100vh; }
    .page-header { background: #fff; border-bottom: 1px solid #e5e7eb; padding: 1rem 1.5rem; display: flex; align-items: center; gap: 1rem; }
    .logo { max-height: 36px; }
    .brand-name { font-weight: 700; font-size: 1rem; color: var(--color-primary, #4F46E5); }
    nav { margin-left: auto; display: flex; gap: 1.25rem; }
    nav a { font-size: 0.9375rem; color: #374151; text-decoration: none; }
    nav a:hover { color: var(--color-primary, #4F46E5); }
    .container { max-width: 720px; margin: 0 auto; padding: 2rem 1.5rem; }
    .back-link { font-size: 0.875rem; color: #6b7280; text-decoration: none; display: inline-flex; align-items: center; gap: 0.25rem; margin-bottom: 1.5rem; }
    .back-link:hover { color: var(--color-primary, #4F46E5); }
    .profile-card { background: #fff; border: 1px solid #e5e7eb; border-radius: var(--radius-card, 0.5rem); padding: 2rem; margin-bottom: 1.5rem; }
    .profile-header { display: flex; align-items: flex-start; gap: 1rem; margin-bottom: 1.5rem; }
    .avatar { width: 3.5rem; height: 3.5rem; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 1.375rem; flex-shrink: 0; }
    .profile-meta { flex: 1; }
    .profile-badges { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 0.5rem; }
    .tier-badge { padding: 0.25rem 0.625rem; border-radius: 999px; font-size: 0.8125rem; font-weight: 600; }
    .tier--top { background: #fef3c7; color: #92400e; }
    .tier--confirmed { background: #f1f5f9; color: #475569; }
    .tier--promising { background: #ede9fe; color: #5b21b6; }
    .score-badge { display: inline-block; padding: 0.25rem 0.5rem; background: var(--color-primary, #4F46E5); color: #fff; border-radius: 0.25rem; font-size: 0.8125rem; font-weight: 600; }
    .headline { font-size: 1.0625rem; font-weight: 600; color: #1a1a2e; line-height: 1.4; }
    .avail-indicator { display: inline-flex; align-items: center; gap: 0.4rem; font-size: 0.875rem; font-weight: 500; margin-top: 0.5rem; }
    .avail-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
    .avail--available .avail-dot { background: #059669; }
    .avail--available { color: #059669; }
    .avail--soon .avail-dot { background: #d97706; }
    .avail--soon { color: #d97706; }
    .avail--unknown .avail-dot { background: #9ca3af; }
    .avail--unknown { color: #6b7280; }
    .section-title { font-size: 0.8125rem; font-weight: 600; color: #6b7280; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.5rem; margin-top: 1.25rem; }
    .tags-row { display: flex; flex-wrap: wrap; gap: 0.375rem; }
    .tag { padding: 0.25rem 0.5rem; background: #f3f4f6; border-radius: 0.25rem; font-size: 0.8125rem; color: #374151; }
    .tag--industry { background: #eff6ff; color: #1d4ed8; }
    .tag--lang { background: #f0fdf4; color: #166534; }
    .rate-range { font-size: 1rem; font-weight: 600; color: #1a1a2e; margin-top: 1rem; }
    .score-block { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.75rem; }
    .score-label { font-size: 0.875rem; color: #6b7280; }
    .bio-block { margin-top: 1rem; }
    .bio-text { font-size: 0.9375rem; color: #374151; line-height: 1.6; }
    .meta-item { font-size: 0.875rem; color: #6b7280; margin-top: 0.5rem; }
    .ctas { display: flex; flex-direction: column; gap: 0.75rem; margin-top: 1.5rem; }
    .cta-primary { display: flex; align-items: center; justify-content: center; gap: 0.5rem; padding: 0.875rem 2rem; background: var(--color-primary, #4F46E5); color: #fff; text-decoration: none; border: none; border-radius: var(--radius-card, 0.5rem); font-size: 1.0625rem; font-weight: 600; font-family: inherit; cursor: pointer; transition: opacity 0.15s; width: 100%; min-height: 44px; }
    .cta-primary:hover { opacity: 0.9; }
    .cta-primary:disabled { opacity: 0.5; cursor: not-allowed; }
    .cta-secondary { display: block; text-align: center; padding: 0.75rem 2rem; background: #fff; color: var(--color-primary, #4F46E5); border: 1.5px solid var(--color-primary, #4F46E5); border-radius: var(--radius-card, 0.5rem); font-size: 0.9375rem; font-weight: 600; text-decoration: none; cursor: pointer; font-family: inherit; transition: all 0.15s; width: 100%; min-height: 44px; }
    .cta-secondary:hover { background: var(--color-primary, #4F46E5); color: #fff; }
    .cta-direct { border-color: var(--color-accent, #818CF8); color: var(--color-accent, #818CF8); }
    .cta-direct:hover { background: var(--color-accent, #818CF8); color: #fff; border-color: var(--color-accent, #818CF8); }
    .unlock-form { margin-top: 1rem; }
    .unlock-description { font-size: 0.9375rem; color: #6b7280; margin-bottom: 0.75rem; }
    .email-input { display: block; width: 100%; padding: 0.75rem; border: 1.5px solid var(--color-primary, #4F46E5); border-radius: var(--radius-card, 0.375rem); font-size: 1rem; font-family: inherit; color: #1a1a2e; background: #fff; margin-bottom: 0.75rem; }
    .form-error { color: #dc2626; font-size: 0.875rem; margin-bottom: 0.75rem; padding: 0.5rem 0.75rem; background: #fef2f2; border-left: 3px solid #dc2626; border-radius: 0.25rem; }
    .unlock-success { padding: 1rem; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: var(--radius-card, 0.375rem); color: #166534; font-size: 0.9375rem; margin-top: 0.75rem; }
    @keyframes spin { from{transform:rotate(0deg)} to{transform:rotate(360deg)} }
    .spinner { width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.4); border-top-color: #fff; border-radius: 50%; animation: spin 0.7s linear infinite; }
    @media (max-width: 640px) { .container { padding: 1.5rem 1rem; } .profile-card { padding: 1.25rem; } }
    ${getBookingWidgetStyles()}
  </style>
</head>
<body>
  <header class="page-header">
    ${logoHtml}
    <span class="brand-name">${escapeHtml(brand?.name ?? 'Callibrate')}</span>
    <nav>
      <a href="/">Accueil</a>
      <a href="/match">Trouver un expert</a>
    </nav>
  </header>
  <main class="container">
    <a href="/experts" class="back-link">\u2190 Retour au répertoire</a>
    <div class="profile-card">
      <div class="profile-header">
        <div class="avatar" style="background:${escapeHtml(color)}" aria-hidden="true">${escapeHtml(initials)}</div>
        <div class="profile-meta">
          <div class="profile-badges">
            <span class="tier-badge ${badgeClass}">${escapeHtml(label)}</span>
            ${score !== null ? `<span class="score-badge">${score}/100</span>` : ''}
          </div>
          <p class="headline">${escapeHtml(expert.headline ?? label)}</p>
          <div class="avail-indicator ${availabilityClass(expert.availability_status)}">
            <span class="avail-dot" aria-hidden="true"></span>
            ${escapeHtml(availabilityLabel(expert.availability_status))}
          </div>
        </div>
      </div>

      ${bioHtml}
      ${scoreHtml}
      ${rateHtml}
      ${projectsHtml}

      ${expert.skills.length > 0 ? `<p class="section-title">Compétences</p><div class="tags-row">${skillsHtml}</div>` : ''}
      ${expert.industries.length > 0 ? `<p class="section-title">Secteurs</p><div class="tags-row">${industriesHtml}</div>` : ''}
      ${expert.languages.length > 0 ? `<p class="section-title">Langues</p><div class="tags-row">${languagesHtml}</div>` : ''}

      <div class="ctas">
        <a href="/match" id="cta-match-btn" class="cta-primary">V\u00e9rifier la compatibilité</a>
        ${unlockSectionHtml}
        ${directCtaHtml}
      </div>
    </div>
    <!-- AC3S06: Booking widget (opens when booking-open event dispatched) -->
    <div id="booking-widget-container" class="bw-container" aria-label="Réserver un appel" role="region" style="display:none">
      <div class="bw-inner"></div>
    </div>
  </main>
  ${satConfigScript}
  ${getBookingWidgetScript()}
  ${interactiveScript}
  ${posthogBodyScript}
</body>
</html>`,
  };
}

// ── 404 / error fallback ──────────────────────────────────────────────────────

function renderErrorPage(config: SatelliteConfig, brandName: string): string {
  const cssVars = config.theme
    ? `:root { --color-primary: ${config.theme.primary}; --radius-card: ${config.theme.radius}; }`
    : '';
  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Expert introuvable — ${escapeHtml(brandName)}</title>
  <meta name="robots" content="noindex, nofollow">
  <style>${cssVars} body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;background:#fafafa;color:#1a1a2e;} .msg{text-align:center;} a{color:var(--color-primary,#4F46E5);}</style>
</head>
<body>
  <div class="msg">
    <h1>Expert introuvable</h1>
    <p>Ce profil n\u2019existe pas ou a \u00e9t\u00e9 supprim\u00e9.</p>
    <p><a href="/experts">Retour au r\u00e9pertoire</a></p>
  </div>
</body>
</html>`;
}
