import type { SatelliteConfig } from '../types/config';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderMatchPage(
  config: SatelliteConfig,
  posthogApiKey: string,
  coreApiUrl: string
): string {
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

  const logoHtml = theme?.logo_url
    ? `<img src="${escapeHtml(theme.logo_url)}" alt="${escapeHtml(brand?.name ?? '')}" class="logo">`
    : '';

  // AC8: JSON-LD WebPage structured data for the /match page
  const jsonLdData = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    url: `https://${config.domain}/match`,
    name: content?.meta_title ?? `${brand?.name ?? 'Callibrate'} \u2014 D\u00e9crivez votre projet`,
    description: content?.meta_description ?? '',
  };
  const jsonLdScript = `<script type="application/ld+json">${JSON.stringify(jsonLdData).replace(/</g, '\\u003c')}</script>`;

  // AC7: PostHog head snippet — identical to landing.ts pattern
  const posthogHeadSnippet =
    config.tracking_enabled !== false && posthogApiKey
      ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
      : '';

  // AC3: Inject CORE_API_URL and satellite_id as window.__SAT__ for client-side JS
  // Both values are JSON-serialized and </script> is escaped to prevent injection
  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({ apiUrl: coreApiUrl, satelliteId: config.id }).replace(/</g, '\\u003c')};</script>`;

  // AC7: PostHog body script — fires page_view + form events
  const posthogBodyScript =
    config.tracking_enabled !== false && posthogApiKey
      ? `<script>(function(){if(typeof posthog==='undefined')return;var params=new URLSearchParams(window.location.search);posthog.capture('satellite.match_page_viewed',{satellite_id:${JSON.stringify(config.id)},referrer:document.referrer||null,utm_source:params.get('utm_source')||null,utm_campaign:params.get('utm_campaign')||null,utm_medium:params.get('utm_medium')||null,utm_content:params.get('utm_content')||null});})();</script>`
      : '';

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(content?.meta_title ?? `${brand?.name ?? 'Callibrate'} \u2014 D\u00e9crivez votre projet`)}</title>
  <meta name="description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta name="robots" content="index, follow">
  <meta property="og:title" content="${escapeHtml(content?.meta_title ?? `${brand?.name ?? 'Callibrate'} \u2014 D\u00e9crivez votre projet`)}">
  <meta property="og:description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta property="og:url" content="https://${escapeHtml(config.domain)}/match">
  <meta property="og:type" content="website">
  <link rel="canonical" href="https://${escapeHtml(config.domain)}/match">
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
    #match-form {
      width: 100%;
    }
    textarea#match-text {
      width: 100%;
      min-height: 120px;
      max-height: 400px;
      resize: vertical;
      overflow-y: auto;
      border: 2px solid var(--color-primary, #4F46E5);
      border-radius: var(--radius-card, 0.5rem);
      padding: 0.75rem;
      font-family: var(--font-family, 'Inter, sans-serif');
      font-size: 1rem;
      line-height: 1.5;
      color: #1a1a2e;
      background: #fff;
      transition: border-color 0.15s;
    }
    textarea#match-text:focus {
      outline: none;
      border-color: var(--color-accent, #818CF8);
    }
    textarea#match-text:read-only {
      background: #f5f5f5;
      cursor: not-allowed;
    }
    #char-counter {
      text-align: right;
      font-size: 0.875rem;
      color: #888;
      margin-top: 0.25rem;
      transition: color 0.15s;
    }
    #char-counter.counter--warn {
      color: #dc2626;
      font-weight: 600;
    }
    #match-error {
      color: #dc2626;
      font-size: 0.875rem;
      margin-top: 0.5rem;
      padding: 0.5rem 0.75rem;
      background: #fef2f2;
      border-left: 3px solid #dc2626;
      border-radius: 0.25rem;
    }
    button#submit-btn {
      display: block;
      width: 100%;
      margin-top: 1.25rem;
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
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
    }
    button#submit-btn:hover:not(:disabled) { opacity: 0.9; }
    button#submit-btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    #loading-msg {
      color: #555;
      font-size: 0.875rem;
      margin-top: 0.75rem;
      text-align: center;
    }
    @keyframes spin {
      from { transform: rotate(0deg); }
      to { transform: rotate(360deg); }
    }
    .spinner {
      width: 16px;
      height: 16px;
      border: 2px solid rgba(255,255,255,0.4);
      border-top-color: #fff;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      flex-shrink: 0;
    }
    @media (max-width: 640px) {
      h2 { font-size: 1.375rem; }
      .container { padding: 2rem 1rem; }
      textarea#match-text { min-height: 120px; }
    }
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>
    <h2>D\u00e9crivez votre projet</h2>
    <form id="match-form" novalidate>
      <textarea
        id="match-text"
        name="text"
        maxlength="2000"
        placeholder="D\u00e9crivez votre projet d&#39;int\u00e9gration IA\u00a0: quels probl\u00e8mes \u00e0 r\u00e9soudre, quels outils, quel secteur\u00a0?"
        rows="6"
        aria-describedby="char-counter match-error"
      ></textarea>
      <div id="char-counter" aria-live="polite">0/2000</div>
      <div id="match-error" role="alert" aria-live="assertive" style="display:none"></div>
      <button type="submit" id="submit-btn" disabled>Analyser mon projet</button>
    </form>
    <div id="loading-msg" style="display:none" aria-live="polite">Analyse en cours&hellip;</div>
  </main>
  ${posthogBodyScript}
  ${satConfigScript}
  <script>(function(){
    var textarea=document.getElementById('match-text');
    var counter=document.getElementById('char-counter');
    var errorDiv=document.getElementById('match-error');
    var submitBtn=document.getElementById('submit-btn');
    var loadingMsg=document.getElementById('loading-msg');
    var form=document.getElementById('match-form');
    var MIN_CHARS=30;
    var WARN_CHARS=1800;
    var MAX_CHARS=2000;
    var isSubmitting=false;

    // AC10: Restore textarea text from sessionStorage on back navigation
    try{
      var saved=sessionStorage.getItem('match:text');
      if(saved&&saved.length>=MIN_CHARS&&saved.length<=MAX_CHARS){
        textarea.value=saved;
        updateCounter();
      }
    }catch(e){}

    // E03S02 dependency: persist UTM params for passthrough to submit
    try{
      var utmParams=new URLSearchParams(window.location.search);
      var utmData={
        utm_source:utmParams.get('utm_source')||null,
        utm_campaign:utmParams.get('utm_campaign')||null,
        utm_medium:utmParams.get('utm_medium')||null,
        utm_content:utmParams.get('utm_content')||null
      };
      sessionStorage.setItem('match:utm',JSON.stringify(utmData));
    }catch(e){}

    function showError(msg){
      errorDiv.textContent=msg;
      errorDiv.style.display='block';
    }
    function hideError(){
      errorDiv.style.display='none';
      errorDiv.textContent='';
    }
    function updateCounter(){
      var len=textarea.value.length;
      counter.textContent=len+'/'+MAX_CHARS;
      if(len>WARN_CHARS){
        counter.classList.add('counter--warn');
      }else{
        counter.classList.remove('counter--warn');
      }
      if(len>=MIN_CHARS&&len<=MAX_CHARS){
        submitBtn.disabled=false;
      }else{
        submitBtn.disabled=true;
      }
    }

    // AC2: Character counter on input
    textarea.addEventListener('input',function(){
      updateCounter();
    });

    // AC2 + AC3–AC6: Form submission
    form.addEventListener('submit',function(e){
      e.preventDefault();
      if(isSubmitting)return;
      var text=textarea.value;
      if(text.length<MIN_CHARS){
        showError('Veuillez d\u00e9crire votre projet en au moins 30 caract\u00e8res.');
        return;
      }
      if(text.length>MAX_CHARS){
        showError('Le texte ne peut pas d\u00e9passer 2000 caract\u00e8res.');
        return;
      }
      isSubmitting=true;
      hideError();

      // AC7: fire match_form_submitted event
      if(typeof posthog!=='undefined'){
        posthog.capture('satellite.match_form_submitted',{
          satellite_id:window.__SAT__.satelliteId,
          text_length:text.length
        });
      }

      // AC10: persist text before API call (survives network error + back navigation)
      try{sessionStorage.setItem('match:text',text);}catch(e){}

      // AC4: Loading state
      textarea.readOnly=true;
      submitBtn.disabled=true;
      submitBtn.innerHTML='<span class="spinner"></span>Analyse en cours\u2026';
      loadingMsg.style.display='block';

      // AC3: Call Core API
      fetch(window.__SAT__.apiUrl+'/api/extract',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({text:text,satellite_id:window.__SAT__.satelliteId})
      })
      .then(function(res){
        if(!res.ok){
          return res.text().then(function(body){
            throw{status:res.status,body:body};
          });
        }
        return res.json();
      })
      .then(function(data){
        // AC5: Store extraction response + transition to confirmation step
        try{sessionStorage.setItem('match:extraction',JSON.stringify(data));}catch(e){}
        // AC7: fire extraction_completed event
        if(typeof posthog!=='undefined'){
          posthog.capture('satellite.extraction_completed',{
            satellite_id:window.__SAT__.satelliteId,
            ready_to_match:data.ready_to_match,
            needs_confirmation_count:Array.isArray(data.needs_confirmation)?data.needs_confirmation.length:0
          });
        }
        window.location.href='/confirm';
      })
      .catch(function(err){
        var status=err&&err.status?err.status:'network';
        console.error('extraction error',status,err&&err.body?err.body:err);
        // AC7: fire extraction_error event
        if(typeof posthog!=='undefined'){
          posthog.capture('satellite.extraction_error',{
            satellite_id:window.__SAT__.satelliteId,
            error_status:status
          });
        }
        // AC6: Restore form to interactive state
        isSubmitting=false;
        textarea.readOnly=false;
        submitBtn.disabled=false;
        submitBtn.textContent='Analyser mon projet';
        loadingMsg.style.display='none';
        showError('Une erreur est survenue. Veuillez r\u00e9essayer.');
      });
    });
  })();</script>
</body>
</html>`;
}
