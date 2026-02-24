import type { SatelliteConfig } from '../types/config';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderLandingPage(config: SatelliteConfig, posthogApiKey: string): string {
  const theme = config.theme;
  const brand = config.brand;
  const content = config.content;

  const cssVars = theme
    ? `:root {
      --color-primary: ${escapeHtml(theme.primary)};
      --color-accent: ${escapeHtml(theme.accent)};
      --font-family: ${escapeHtml(theme.font)};
      --radius-card: ${escapeHtml(theme.radius)};
    }`
    : '';

  const logoHtml =
    theme?.logo_url
      ? `<img src="${escapeHtml(theme.logo_url)}" alt="${escapeHtml(brand?.name ?? '')}" class="logo">`
      : '';

  const valuePropsHtml =
    content?.value_props && content.value_props.length > 0
      ? `<ul class="value-props">${content.value_props.map((vp) => `<li>${escapeHtml(vp)}</li>`).join('')}</ul>`
      : '';

  const jsonLdScript =
    config.structured_data
      ? `<script type="application/ld+json">${JSON.stringify(config.structured_data)}</script>`
      : '';

  const posthogHeadSnippet = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
    : '';

  const posthogBodyScript = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>(function(){var params=new URLSearchParams(window.location.search);posthog.capture('page_view',{satellite_id:${JSON.stringify(config.id)},referrer:document.referrer||null,utm_source:params.get('utm_source')||null,utm_campaign:params.get('utm_campaign')||null,utm_medium:params.get('utm_medium')||null});var ctaEl=document.querySelector('.cta');if(ctaEl){ctaEl.addEventListener('click',function(){posthog.capture('satellite.cta_clicked',{satellite_id:${JSON.stringify(config.id)},cta_text:ctaEl.textContent?ctaEl.textContent.trim():''});});}})();</script>`
    : '';

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(content?.meta_title ?? brand?.name ?? 'Callibrate')}</title>
  <meta name="description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta name="robots" content="index, follow">
  <meta property="og:title" content="${escapeHtml(content?.meta_title ?? brand?.name ?? '')}">
  <meta property="og:description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta property="og:url" content="https://${escapeHtml(config.domain)}/">
  <meta property="og:type" content="website">
  <link rel="canonical" href="https://${escapeHtml(config.domain)}/">
  ${jsonLdScript}
  ${posthogHeadSnippet}
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
      text-align: center;
    }
    .logo {
      max-height: 48px;
      margin-bottom: 1.5rem;
    }
    h1 {
      font-size: 1.25rem;
      font-weight: 600;
      color: var(--color-primary, #4F46E5);
      margin-bottom: 0.5rem;
    }
    h2 {
      font-size: 2rem;
      font-weight: 700;
      line-height: 1.2;
      margin-bottom: 1rem;
      color: #1a1a2e;
    }
    .hero-sub {
      font-size: 1.125rem;
      color: #555;
      margin-bottom: 2rem;
    }
    .value-props {
      list-style: none;
      text-align: left;
      max-width: 480px;
      margin: 0 auto 2.5rem;
    }
    .value-props li {
      padding: 0.5rem 0;
      padding-left: 1.5rem;
      position: relative;
      font-size: 1rem;
      color: #333;
    }
    .value-props li::before {
      content: '';
      position: absolute;
      left: 0;
      top: 50%;
      transform: translateY(-50%);
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--color-accent, #818CF8);
    }
    .cta {
      display: inline-block;
      padding: 0.875rem 2rem;
      background: var(--color-primary, #4F46E5);
      color: #fff;
      text-decoration: none;
      border-radius: var(--radius-card, 0.5rem);
      font-size: 1.0625rem;
      font-weight: 600;
      transition: opacity 0.15s;
    }
    .cta:hover { opacity: 0.9; }
    @media (max-width: 640px) {
      h2 { font-size: 1.5rem; }
      .container { padding: 2rem 1rem; }
    }
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>
    <h2>${escapeHtml(content?.hero_headline ?? '')}</h2>
    <p class="hero-sub">${escapeHtml(content?.hero_sub ?? '')}</p>
    ${valuePropsHtml}
    <a href="/match" class="cta">D\u00e9crire mon projet</a>
  </main>
  ${posthogBodyScript}
</body>
</html>`;
}
