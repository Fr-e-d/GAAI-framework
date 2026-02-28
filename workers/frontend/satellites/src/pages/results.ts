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

export function renderResultsPage(
  config: SatelliteConfig,
  posthogApiKey: string,
  coreApiUrl: string
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

  // AC10: PostHog head snippet — identical to confirm.ts pattern
  const posthogHeadSnippet =
    config.tracking_enabled !== false && posthogApiKey
      ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
      : '';

  // AC11: Inject config for client-side JS — no turnstileSiteKey on this page
  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({
    apiUrl: coreApiUrl,
    satelliteId: config.id,
  }).replace(/</g, '\\u003c')};</script>`;

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(brand?.name ?? 'Callibrate')} — Vos experts correspondants</title>
  <meta name="robots" content="noindex, nofollow">
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

    /* Email gate */
    #email-gate-section { border-top:1px solid #e5e7eb; margin-top:2rem; padding-top:2rem; }
    #email-gate-section h3 { font-size:1.25rem; font-weight:700; color:#1a1a2e; margin-bottom:0.5rem; }
    #email-gate-section>p { color:#6b7280; font-size:0.9375rem; margin-bottom:1.5rem; }
    #email-input { display:block; width:100%; padding:0.75rem; border:1.5px solid var(--color-primary,#4F46E5); border-radius:var(--radius-card,0.375rem); font-size:1rem; font-family:inherit; color:#1a1a2e; background:#fff; margin-bottom:0.75rem; }
    #email-error { color:#dc2626; font-size:0.875rem; margin-bottom:0.75rem; padding:0.5rem 0.75rem; background:#fef2f2; border-left:3px solid #dc2626; border-radius:0.25rem; }
    #unlock-btn { display:flex; width:100%; padding:0.875rem 2rem; background:var(--color-primary,#4F46E5); color:#fff; border:none; border-radius:var(--radius-card,0.5rem); font-size:1.0625rem; font-weight:600; font-family:inherit; cursor:pointer; transition:opacity 0.15s; min-height:44px; align-items:center; justify-content:center; gap:0.5rem; }
    #unlock-btn:hover:not(:disabled) { opacity:0.9; }
    #unlock-btn:disabled { opacity:0.5; cursor:not-allowed; }

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
    }
    ${getBookingWidgetStyles()}
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>
    <div id="results-header" style="display:none">
      <h2 id="results-count-heading"></h2>
    </div>
    <!-- AC1: Skeleton loading -->
    <div id="matches-loading" aria-live="polite">
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
    <!-- AC3+AC4: Match cards (filled by JS) -->
    <div id="matches-container" style="display:none" aria-label="Experts correspondants"></div>
    <!-- AC9: No matches -->
    <div id="no-matches" style="display:none">
      <p>Aucun expert ne correspond exactement à vos critères pour le moment.</p>
      <div class="no-matches-actions">
        <a href="/confirm" class="no-matches-btn no-matches-btn--primary">Modifier mes critères</a>
        <a href="/experts" class="no-matches-btn no-matches-btn--secondary">Parcourir le répertoire</a>
      </div>
    </div>
    <!-- AC6: Computing timeout fallback -->
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
    <!-- AC5: Email gate -->
    <section id="email-gate-section" style="display:none" aria-label="Débloquer les profils complets">
      <h3>Découvrez le profil complet de vos experts</h3>
      <p>Accédez aux noms, parcours et disponibilités de vos experts</p>
      <input type="email" id="email-input" placeholder="votre@email.com" aria-label="Votre adresse email">
      <div id="email-error" role="alert" style="display:none"></div>
      <button type="button" id="unlock-btn">Débloquer les profils</button>
    </section>
  </main>
  ${satConfigScript}
  ${getBookingWidgetScript()}
  <script>(function(){
    var prospect_id=null;
    var token=null;
    var retryCount=0;
    var MAX_RETRIES=3;
    var waitStart=0;
    var networkErrorRetried=false;
    var isIdentifying=false;
    var matchesData=null;
    var CRITERIA_LABELS={skills:'Comp\u00e9tences',industry:'Secteur',budget:'Budget',timeline:'Calendrier',languages:'Langues'};
    var TIER_LABELS={top:'Top Expert',confirmed:'Expert Confirm\u00e9',promising:'Expert Prometteur'};
    var TIER_CLASSES={top:'tier--top',confirmed:'tier--confirmed',promising:'tier--promising'};
    var TIER_AVATAR_COLORS={top:'#F59E0B',confirmed:'#64748B',promising:'#7C3AED'};

    // AC11: sessionStorage guard
    try{
      prospect_id=sessionStorage.getItem('match:prospect_id');
      token=sessionStorage.getItem('match:token');
    }catch(e){}
    if(!prospect_id||!token){window.location.href='/match';return;}

    document.getElementById('unlock-btn').addEventListener('click',handleEmailSubmit);
    document.getElementById('retry-btn').addEventListener('click',function(){
      hideEl('fetch-error');
      showEl('matches-loading');
      retryCount=0;
      networkErrorRetried=false;
      fetchMatches();
    });

    fetchMatches();

    // AC1: Fetch matches from API
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

    // AC2: Handle 202 computing state with exponential backoff
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

    // AC3+AC4: Render anonymized expert cards
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
        // Card header
        html+='<div class="card-header">';
        html+='<div class="rank-badge '+rankClass+'">#'+rank+'</div>';
        html+='<div class="avatar-silhouette">'+svgAvatar+'</div>';
        html+='<div class="card-header-meta">';
        html+='<span class="tier-badge '+tierClass+'">'+escHtml(tierLabel)+'</span> ';
        html+='<span class="score-badge">'+Math.round(match.overall_score||0)+'/100</span>';
        html+='</div></div>';
        // Score breakdown
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
        // Skills tags
        var skills=match.skills_matched||[];
        if(skills.length>0){
          html+='<div class="tags-row">';
          skills.forEach(function(s){html+='<span class="tag">'+escHtml(String(s))+'</span>';});
          html+='</div>';
        }
        // Rate range
        if(match.rate_min!==undefined||match.rate_max!==undefined){
          html+='<div class="rate-range">\u20AC'+(match.rate_min||'?')+' \u2014 \u20AC'+(match.rate_max||'?')+' / heure</div>';
        }
        // Industries + project types
        var industries=match.industries||[];
        var projectTypes=match.project_types||[];
        if(industries.length>0||projectTypes.length>0){
          html+='<div class="tags-row">';
          industries.forEach(function(i){html+='<span class="tag">'+escHtml(String(i))+'</span>';});
          projectTypes.forEach(function(pt){html+='<span class="tag">'+escHtml(String(pt))+'</span>';});
          html+='</div>';
        }
        // Languages
        var langs=match.languages||[];
        if(langs.length>0){
          html+='<div class="tags-row">';
          langs.forEach(function(l){html+='<span class="lang-tag">'+escHtml(String(l))+'</span>';});
          html+='</div>';
        }
        // Expand button
        html+='<button class="expand-btn" data-rank="'+rank+'" aria-expanded="false">Voir le d\u00e9tail</button>';
        html+='</div>';
      });
      container.innerHTML=html;
      showEl('matches-container');
      showEl('email-gate-section');
      // Wire expand buttons
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

    // AC5+AC6: Handle email gate submission
    function handleEmailSubmit(){
      if(isIdentifying)return;
      var emailInput=document.getElementById('email-input');
      var emailError=document.getElementById('email-error');
      var unlockBtn=document.getElementById('unlock-btn');
      var email=emailInput.value.trim();
      emailError.style.display='none';
      if(!email||!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)){
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
      fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/identify',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:email,token:token})
      })
      .then(function(res){
        if(res.status===409){return fetchProfilesDirect();}
        if(res.status===403){throw{status:403};}
        if(res.status===422){return res.json().then(function(d){throw{status:422,data:d};});}
        if(!res.ok){throw{status:res.status};}
        return res.json();
      })
      .then(function(data){
        if(!data)return;
        try{sessionStorage.setItem('match:identified_email',email);}catch(e){}
        revealFullProfiles(data.experts||[]);
      })
      .catch(function(err){
        handleIdentifyError(err);
      });
    }

    // AC8: 409 case — fetch profiles directly (already identified)
    function fetchProfilesDirect(){
      return fetch(window.__SAT__.apiUrl+'/api/prospects/'+encodeURIComponent(prospect_id)+'/matches?token='+encodeURIComponent(token)+'&identified=true')
      .then(function(res){return res.json();})
      .then(function(data){
        revealFullProfiles(data.experts||data.matches||[]);
        return null;
      });
    }

    // AC7: Reveal full expert profiles after identify success
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
      // Wire bio expand
      container.querySelectorAll('.bio-expand-btn').forEach(function(btn){
        btn.addEventListener('click',function(){
          var idx=btn.getAttribute('data-idx');
          var bioEl=document.getElementById('bio-'+idx);
          if(!bioEl)return;
          bioEl.classList.toggle('expanded');
          btn.textContent=bioEl.classList.contains('expanded')?'R\u00e9duire':'Lire la suite';
        });
      });
      // Wire booking buttons
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
      // AC10: profiles_unlocked
      firePostHog('satellite.profiles_unlocked',{
        satellite_id:window.__SAT__.satelliteId,
        prospect_id:prospect_id,
        match_count:experts.length
      });
    }

    // AC8: Handle identify errors
    function handleIdentifyError(err){
      isIdentifying=false;
      var unlockBtn=document.getElementById('unlock-btn');
      var emailInput=document.getElementById('email-input');
      var emailError=document.getElementById('email-error');
      unlockBtn.disabled=false;
      unlockBtn.textContent='D\u00e9bloquer les profils';
      emailInput.disabled=false;
      if(err&&err.status===403){
        emailError.innerHTML='Votre session a expir\u00e9. Veuillez <a href="/match">recommencer</a>.';
        emailError.style.display='block';
      }else if(err&&err.status===422){
        emailError.textContent='Adresse email invalide.';
        emailError.style.display='block';
      }else{
        emailError.innerHTML='Une erreur est survenue. <button type="button" id="retry-identify-btn" style="background:none;border:none;color:#dc2626;text-decoration:underline;cursor:pointer;padding:0;font-size:inherit">R\u00e9essayer</button>';
        emailError.style.display='block';
        var retryBtn=document.getElementById('retry-identify-btn');
        if(retryBtn){
          retryBtn.addEventListener('click',function(){
            emailError.style.display='none';
            handleEmailSubmit();
          });
        }
      }
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
