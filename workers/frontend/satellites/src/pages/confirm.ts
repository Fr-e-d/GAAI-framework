import type { SatelliteConfig } from '../types/config';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderConfirmPage(
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

  // AC9: PostHog head snippet — identical to match.ts pattern
  const posthogHeadSnippet =
    config.tracking_enabled !== false && posthogApiKey
      ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
      : '';

  // AC5 + AC11: Inject config for client-side JS — includes turnstileSiteKey
  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({
    apiUrl: coreApiUrl,
    satelliteId: config.id,
    turnstileSiteKey: turnstileSiteKey,
  }).replace(/</g, '\\u003c')};</script>`;

  // AC9: PostHog body snippet — reserved for future use (confirmation_viewed fires in IIFE)
  const posthogBodyScript = '';

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(brand?.name ?? 'Callibrate')} — Confirmez vos besoins</title>
  <meta name="robots" content="noindex, nofollow">
  ${posthogHeadSnippet}
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
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
    .summary-section {
      margin-bottom: 2rem;
    }
    .summary-section h3 {
      font-size: 1rem;
      font-weight: 600;
      color: #555;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 1rem;
    }
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
    .questions-section {
      margin-bottom: 2rem;
    }
    .question-block {
      margin-bottom: 1.5rem;
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
    .actions { margin-top: 2rem; }
    .back-link {
      display: inline-block;
      color: #6b7280;
      font-size: 0.875rem;
      text-decoration: none;
      margin-bottom: 1rem;
    }
    .back-link:hover { color: #1a1a2e; }
    button#confirm-btn {
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
    }
    button#confirm-btn:hover:not(:disabled) { opacity: 0.9; }
    button#confirm-btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    #loading-msg {
      color: #1a1a2e;
      margin-top: 0.75rem;
      text-align: center;
    }
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
      .field-row { flex-wrap: wrap; }
      .field-label { min-width: 100%; }
    }
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>
    <h2>Vos besoins identifiés</h2>
    <section class="summary-section" aria-label="Résumé de vos besoins">
      <div id="fields-container"></div>
    </section>
    <section class="questions-section" id="questions-section" style="display:none" aria-label="Questions de clarification">
      <div id="questions-container"></div>
    </section>
    <div class="actions">
      <a href="/match" class="back-link" id="back-link">← Retour</a>
      <div id="confirm-error" role="alert" aria-live="assertive" style="display:none"></div>
      <div id="cf-turnstile-container" style="display:none"></div>
      <button type="button" id="confirm-btn">Confirmer et trouver mes experts</button>
      <div id="loading-msg" style="display:none" aria-live="polite">Recherche en cours parmi nos experts qualifi\u00e9s</div>
    </div>
  </main>
  ${posthogBodyScript}
  ${satConfigScript}
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

    var extraction=null;
    var mergedReqs={};
    var editedFields={};
    var isSubmitting=false;
    var widgetId=null;

    var fieldsContainer=document.getElementById('fields-container');
    var questionsSection=document.getElementById('questions-section');
    var questionsContainer=document.getElementById('questions-container');
    var confirmBtn=document.getElementById('confirm-btn');
    var confirmError=document.getElementById('confirm-error');
    var loadingMsg=document.getElementById('loading-msg');
    var turnstileContainer=document.getElementById('cf-turnstile-container');

    // AC1: Load extraction from sessionStorage
    try{
      var raw=sessionStorage.getItem('match:extraction');
      if(!raw){window.location.href='/match';return;}
      extraction=JSON.parse(raw);
    }catch(e){window.location.href='/match';return;}

    mergedReqs=Object.assign({},extraction.requirements||{});

    // AC9: Fire confirmation_viewed event
    if(typeof posthog!=='undefined'){
      posthog.capture('satellite.confirmation_viewed',{
        satellite_id:window.__SAT__.satelliteId,
        ready_to_match:extraction.ready_to_match||null,
        fields_needing_confirmation:extraction.needs_confirmation||[]
      });
    }

    renderSummaryFields();
    renderConfirmationQuestions();

    confirmBtn.addEventListener('click',handleConfirm);

    // AC1: Render summary fields with confidence indicators
    function renderSummaryFields(){
      var html='';
      FIELD_ORDER.forEach(function(field){
        var label=FIELD_LABELS[field]||field;
        var confidence=extraction.confidence?(extraction.confidence[field]||0):0;
        var indicator=getConfidenceIndicator(confidence);
        var value=mergedReqs[field];
        var displayValue=formatFieldValue(field,value);
        var isEmpty=!value||(Array.isArray(value)&&value.length===0);
        html+='<div class="field-row" data-field="'+field+'">';
        html+='<span class="confidence-indicator">'+indicator+'</span>';
        html+='<span class="field-label">'+escHtml(label)+'</span>';
        html+='<span class="field-value'+(isEmpty?' field-value--empty':'')+'" id="display-'+field+'">';
        html+=isEmpty?'Non identifi\u00e9':escHtml(displayValue);
        html+='</span>';
        html+='<div class="field-edit" id="edit-'+field+'">';
        html+=buildEditInput(field,value);
        html+='</div>';
        html+='<button class="modifier-btn" data-field="'+field+'" aria-label="Modifier '+escHtml(label)+'">Modifier</button>';
        html+='</div>';
      });
      fieldsContainer.innerHTML=html;
      fieldsContainer.querySelectorAll('.modifier-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var f=btn.getAttribute('data-field');
          activateEditMode(f);
          if(!editedFields[f]&&typeof posthog!=='undefined'){
            posthog.capture('satellite.confirmation_field_edited',{
              satellite_id:window.__SAT__.satelliteId,
              field_name:f
            });
          }
          editedFields[f]=true;
        });
      });
    }

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

    function activateEditMode(field){
      var displayEl=document.getElementById('display-'+field);
      var editEl=document.getElementById('edit-'+field);
      var btn=fieldsContainer.querySelector('.modifier-btn[data-field="'+field+'"]');
      if(displayEl)displayEl.style.display='none';
      if(btn)btn.style.display='none';
      if(editEl){
        editEl.classList.add('visible');
        var first=editEl.querySelector('input,select');
        if(first)first.focus();
      }
    }

    // AC3: Render confirmation questions (max 3)
    function renderConfirmationQuestions(){
      var questions=extraction.confirmation_questions||[];
      var needsConf=extraction.needs_confirmation||[];
      if(needsConf.length===0)return;
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
      if(html){
        questionsContainer.innerHTML=html;
        questionsSection.style.display='block';
        needsConf.slice(0,3).forEach(function(field){
          activateEditMode(field);
        });
      }
    }

    // Collect current form values into mergedReqs
    function collectMergedReqs(){
      FIELD_ORDER.forEach(function(field){
        var editEl=document.getElementById('edit-'+field);
        if(!editEl||!editEl.classList.contains('visible'))return;
        if(field==='budget_range'){
          var minEl=document.getElementById('edit-budget-min');
          var maxEl=document.getElementById('edit-budget-max');
          var budgetObj={};
          if(minEl&&minEl.value)budgetObj.min=parseInt(minEl.value,10);
          if(maxEl&&maxEl.value)budgetObj.max=parseInt(maxEl.value,10);
          if(Object.keys(budgetObj).length>0)mergedReqs.budget_range=budgetObj;
        }else if(field==='skills_needed'||field==='languages'){
          var inp=document.getElementById('edit-'+field+'-input');
          if(inp&&inp.value.trim())mergedReqs[field]=inp.value.split(',').map(function(s){return s.trim();}).filter(Boolean);
        }else{
          var inp2=document.getElementById('edit-'+field+'-input');
          if(inp2&&inp2.value.trim())mergedReqs[field]=inp2.value.trim();
        }
      });
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

    // AC5: Handle confirm click
    function handleConfirm(){
      if(isSubmitting)return;
      isSubmitting=true;
      collectMergedReqs();
      confirmBtn.disabled=true;
      confirmBtn.innerHTML='<span class="spinner"></span>V\u00e9rification\u2026';
      confirmError.style.display='none';
      setFormReadonly(true);
      if(typeof posthog!=='undefined'){
        posthog.capture('satellite.confirmation_submitted',{
          satellite_id:window.__SAT__.satelliteId,
          fields_edited_count:Object.keys(editedFields).length,
          turnstile_passed:false
        });
      }
      turnstileContainer.style.display='block';
      loadingMsg.style.display='block';
      loadingMsg.textContent='V\u00e9rification de s\u00e9curit\u00e9\u2026';
      if(typeof turnstile==='undefined'){
        loadingMsg.textContent='Chargement du widget de s\u00e9curit\u00e9\u2026';
        var maxWait=10000;
        var waited=0;
        var interval=setInterval(function(){
          waited+=250;
          if(typeof turnstile!=='undefined'){
            clearInterval(interval);
            renderTurnstile();
          }else if(waited>=maxWait){
            clearInterval(interval);
            handleSubmitError('turnstile_timeout',null);
          }
        },250);
      }else{
        renderTurnstile();
      }
    }

    function renderTurnstile(){
      widgetId=turnstile.render('#cf-turnstile-container',{
        sitekey:window.__SAT__.turnstileSiteKey,
        appearance:'interaction-only',
        callback:function(token){
          loadingMsg.textContent='Recherche en cours parmi nos experts qualifi\u00e9s';
          doSubmit(token);
        },
        'error-callback':function(){
          handleSubmitError('turnstile_error',null);
        },
        'expired-callback':function(){
          if(widgetId!==null&&typeof turnstile!=='undefined')turnstile.reset(widgetId);
        }
      });
    }

    // AC5: POST to Core API
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
        // AC7: store and navigate
        try{
          sessionStorage.setItem('match:prospect_id',data.prospect_id);
          sessionStorage.setItem('match:token',data.token);
        }catch(e){}
        if(typeof posthog!=='undefined'){
          posthog.capture('satellite.prospect_created',{
            satellite_id:window.__SAT__.satelliteId,
            prospect_id:data.prospect_id
          });
        }
        window.location.href='/results';
      })
      .catch(function(err){
        handleSubmitError(err&&err.status?err.status:'network',err&&err.data?err.data:null);
      });
    }

    // AC8: Error handling
    function handleSubmitError(status,data){
      isSubmitting=false;
      confirmBtn.disabled=false;
      confirmBtn.textContent='Confirmer et trouver mes experts';
      setFormReadonly(false);
      loadingMsg.style.display='none';
      // AC7: PostHog matching_error event
      var errorType='network';
      if(status===422)errorType='validation_422';
      else if(status===429)errorType='rate_limit_429';
      else if(status==='turnstile_error'||status==='turnstile_timeout')errorType='turnstile';
      if(typeof posthog!=='undefined'){
        posthog.capture('satellite.matching_error',{
          satellite_id:window.__SAT__.satelliteId,
          prospect_id:null,
          error_type:errorType,
          page:'confirm',
          retry_count:0
        });
      }
      if(status===422){
        var msg='Les donn\u00e9es saisies sont invalides.';
        if(data&&data.error)msg=data.error;
        showError(msg);
      }else if(status===429){
        showError('Trop de tentatives. Veuillez patienter.');
      }else if(status==='turnstile_error'||status==='turnstile_timeout'){
        showError('La v\u00e9rification de s\u00e9curit\u00e9 a \u00e9chou\u00e9. Veuillez r\u00e9essayer.');
        if(widgetId!==null&&typeof turnstile!=='undefined'){
          turnstile.reset(widgetId);
        }else{
          turnstileContainer.style.display='none';
        }
      }else{
        showError('La connexion au serveur a \u00e9chou\u00e9. V\u00e9rifiez votre connexion internet et r\u00e9essayez.');
      }
    }

    function showError(msg){
      confirmError.textContent=msg;
      confirmError.style.display='block';
    }

    function setFormReadonly(readonly){
      var inputs=document.querySelectorAll('.field-edit input,.field-edit select,.questions-section input,.questions-section select');
      inputs.forEach(function(el){el.disabled=readonly;});
    }

    function escHtml(str){
      if(!str)return'';
      return String(str)
        .replace(/&/g,'&amp;')
        .replace(/</g,'&lt;')
        .replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;')
        .replace(/'/g,'&#39;');
    }
  })();</script>
</body>
</html>`;
}
