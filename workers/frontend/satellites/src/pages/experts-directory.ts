import type { SatelliteConfig } from '../types/config';

// ── Types ─────────────────────────────────────────────────────────────────────

interface AnonymizedExpert {
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
}

interface ExpertsApiResponse {
  experts: AnonymizedExpert[];
  total: number;
  page: number;
  per_page: number;
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
  if (tier === 'top') return 'Top';
  if (tier === 'confirmed') return 'Confirmé';
  return 'Prometteur';
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

function renderExpertCard(expert: AnonymizedExpert): string {
  const initials = expert.headline ? expert.headline.charAt(0).toUpperCase() : 'E';
  const color = tierAvatarColor(expert.quality_tier);
  const label = tierLabel(expert.quality_tier);
  const badgeClass = tierBadgeClass(expert.quality_tier);
  const score = expert.composite_score !== null ? Math.round(expert.composite_score) : null;

  const skillsHtml = expert.skills.slice(0, 3).map((s) =>
    `<span class="tag">${escapeHtml(s)}</span>`
  ).join('');

  const rateHtml = (expert.rate_min !== null || expert.rate_max !== null)
    ? `<div class="rate-range">\u20AC${expert.rate_min ?? '?'} \u2014 \u20AC${expert.rate_max ?? '?'} / h</div>`
    : '';

  const scoreHtml = score !== null
    ? `<span class="score-badge">${score}/100</span>`
    : '';

  return `<div class="expert-card">
  <div class="card-avatar" style="background:${escapeHtml(color)}" aria-hidden="true">${escapeHtml(initials)}</div>
  <div class="card-body">
    <div class="card-header-row">
      <span class="tier-badge ${badgeClass}">${escapeHtml(label)}</span>
      ${scoreHtml}
    </div>
    <p class="card-headline">${escapeHtml(expert.headline ?? '')}</p>
    <div class="tags-row">${skillsHtml}</div>
    ${rateHtml}
  </div>
  <a href="/experts/${escapeHtml(expert.slug)}" class="card-link" aria-label="Voir le profil de cet expert">Voir le profil</a>
</div>`;
}

// ── Main render function ───────────────────────────────────────────────────────

export async function renderExpertsDirectoryPage(
  config: SatelliteConfig,
  posthogApiKey: string,
  coreApiUrl: string,
): Promise<string> {
  const theme = config.theme;
  const brand = config.brand;
  const vertical = config.vertical ?? '';
  const verticalLabel = config.content?.vertical_label ?? vertical ?? 'Automatisation';

  // AC1: Fetch from Core API server-side
  let experts: AnonymizedExpert[] = [];
  let total = 0;
  let allSkills: string[] = [];
  try {
    const apiUrl = new URL(`${coreApiUrl}/api/experts/public`);
    if (vertical) apiUrl.searchParams.set('vertical', vertical);
    apiUrl.searchParams.set('per_page', '12');
    apiUrl.searchParams.set('page', '1');
    const res = await fetch(apiUrl.toString());
    if (res.ok) {
      const data: ExpertsApiResponse = await res.json();
      experts = data.experts ?? [];
      total = data.total ?? 0;
      // Collect unique skills for filter bar
      const skillSet = new Set<string>();
      for (const e of experts) {
        for (const s of e.skills) skillSet.add(s);
      }
      allSkills = Array.from(skillSet).slice(0, 12);
    }
  } catch {
    // Graceful degradation — empty state
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

  // AC7: JSON-LD ItemList for directory
  const itemListData = {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    name: `Experts en ${verticalLabel} — ${brand?.name ?? 'Callibrate'}`,
    numberOfItems: total,
    itemListElement: experts.map((e, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      url: `https://${config.domain}/experts/${e.slug}`,
    })),
  };
  const jsonLdScript = `<script type="application/ld+json">${JSON.stringify(itemListData).replace(/</g, '\\u003c')}</script>`;

  // PostHog head snippet
  const posthogHeadSnippet = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`
    : '';

  // AC8: PostHog events
  const satConfigScript = `<script>window.__SAT__=${JSON.stringify({
    apiUrl: coreApiUrl,
    satelliteId: config.id,
    vertical,
  }).replace(/</g, '\\u003c')};</script>`;

  const posthogBodyScript = (config.tracking_enabled !== false && posthogApiKey)
    ? `<script>(function(){
    posthog.capture('satellite.directory_viewed',{satellite_id:${JSON.stringify(config.id)},filter_skills:[],page:1});
    document.querySelectorAll('.skill-filter').forEach(function(btn){
      btn.addEventListener('click',function(){
        var skill=btn.getAttribute('data-skill')||'';
        var active=btn.classList.contains('active');
        btn.classList.toggle('active');
        posthog.capture('satellite.directory_filter_applied',{satellite_id:${JSON.stringify(config.id)},filter_type:'skill',filter_value:skill});
        filterCards();
      });
    });
    document.querySelectorAll('.expert-card').forEach(function(card){
      var link=card.querySelector('.card-link');
      if(link){link.addEventListener('click',function(){
        var slug=link.getAttribute('href')||'';
        var tierEl=card.querySelector('.tier-badge');
        var tier=tierEl?tierEl.textContent||'':'';
        posthog.capture('satellite.expert_profile_viewed',{satellite_id:${JSON.stringify(config.id)},expert_slug:slug,quality_tier:tier});
      });}
    });
  })();</script>`
    : '';

  // Filter + load-more script (AC2, AC6)
  const interactiveScript = `<script>(function(){
    var allCards=Array.from(document.querySelectorAll('.expert-card'));
    var activeSkills=[];
    var currentPage=1;
    var total=${total};
    var perPage=12;
    var vertical=${JSON.stringify(vertical)};
    var loadMoreBtn=document.getElementById('load-more-btn');
    var emptyState=document.getElementById('empty-state');
    var grid=document.getElementById('experts-grid');

    if(loadMoreBtn){
      loadMoreBtn.style.display=total>perPage?'block':'none';
      loadMoreBtn.addEventListener('click',function(){
        currentPage++;
        loadMoreBtn.disabled=true;
        loadMoreBtn.textContent='Chargement\u2026';
        var url=window.__SAT__.apiUrl+'/api/experts/public?per_page='+perPage+'&page='+currentPage;
        if(vertical)url+='&vertical='+encodeURIComponent(vertical);
        if(activeSkills.length)url+='&skills='+encodeURIComponent(activeSkills.join(','));
        fetch(url)
          .then(function(r){return r.json();})
          .then(function(data){
            if(data.experts&&data.experts.length>0){
              data.experts.forEach(function(e){
                var div=document.createElement('div');
                div.innerHTML=renderCard(e);
                var card=div.firstElementChild;
                if(card)grid.appendChild(card);
              });
              allCards=Array.from(grid.querySelectorAll('.expert-card'));
              if(currentPage*perPage>=data.total)loadMoreBtn.style.display='none';
              else{loadMoreBtn.disabled=false;loadMoreBtn.textContent='Charger plus d\u2019experts';}
            }else{loadMoreBtn.style.display='none';}
          })
          .catch(function(){
            loadMoreBtn.disabled=false;
            loadMoreBtn.textContent='Charger plus d\u2019experts';
          });
      });
    }

    window.filterCards=function(){
      activeSkills=[];
      document.querySelectorAll('.skill-filter.active').forEach(function(b){
        activeSkills.push(b.getAttribute('data-skill')||'');
      });
      var visible=0;
      allCards.forEach(function(card){
        if(activeSkills.length===0){card.style.display='';visible++;return;}
        var skillEls=card.querySelectorAll('.tag');
        var cardSkills=Array.from(skillEls).map(function(el){return(el.textContent||'').toLowerCase();});
        var match=activeSkills.some(function(s){return cardSkills.includes(s.toLowerCase());});
        card.style.display=match?'':'none';
        if(match)visible++;
      });
      if(emptyState)emptyState.style.display=visible===0?'':'none';
    };

    function renderCard(e){
      var color=tierColor(e.quality_tier);
      var label=tierLbl(e.quality_tier);
      var badge=tierCls(e.quality_tier);
      var init=e.headline?e.headline.charAt(0).toUpperCase():'E';
      var score=e.composite_score!==null?Math.round(e.composite_score):null;
      var skills=(e.skills||[]).slice(0,3).map(function(s){return'<span class="tag">'+esc(s)+'</span>';}).join('');
      var rate=(e.rate_min!==null||e.rate_max!==null)
        ?'<div class="rate-range">\u20AC'+(e.rate_min||'?')+' \u2014 \u20AC'+(e.rate_max||'?')+' / h</div>':'';
      var scoreHtml=score!==null?'<span class="score-badge">'+score+'/100</span>':'';
      return'<div class="expert-card"><div class="card-avatar" style="background:'+esc(color)+'" aria-hidden="true">'+esc(init)+'</div><div class="card-body"><div class="card-header-row"><span class="tier-badge '+badge+'">'+esc(label)+'</span> '+scoreHtml+'</div><p class="card-headline">'+esc(e.headline||'')+'</p><div class="tags-row">'+skills+'</div>'+rate+'</div><a href="/experts/'+esc(e.slug)+'" class="card-link" aria-label="Voir le profil">Voir le profil</a></div>';
    }
    function tierColor(t){if(t==='top')return'#F59E0B';if(t==='confirmed')return'#64748B';return'#7C3AED';}
    function tierLbl(t){if(t==='top')return'Top';if(t==='confirmed')return'Confirm\u00e9';return'Prometteur';}
    function tierCls(t){if(t==='top')return'tier--top';if(t==='confirmed')return'tier--confirmed';return'tier--promising';}
    function esc(s){if(!s)return'';return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}
  })();</script>`;

  // Render cards
  const cardsHtml = experts.map(renderExpertCard).join('\n');

  // Filter bar (AC2)
  const filterBarHtml = allSkills.length > 0
    ? `<div class="filter-bar" role="toolbar" aria-label="Filtrer par compétence">
    ${allSkills.map((s) => `<button class="skill-filter" data-skill="${escapeHtml(s)}" aria-pressed="false" type="button">${escapeHtml(s)}</button>`).join('')}
  </div>`
    : '';

  // AC9: Empty state
  const emptyStateHtml = `<div id="empty-state" style="display:${experts.length === 0 ? '' : 'none'}" class="empty-state">
  <p>Aucun expert ne correspond à ces critères.</p>
  <button type="button" class="reset-filters-btn" onclick="document.querySelectorAll('.skill-filter.active').forEach(function(b){b.classList.remove('active')});window.filterCards();this.closest('.empty-state').style.display='none'">Réinitialiser les filtres</button>
  <a href="/match" class="cta-link">Décrire votre projet</a>
</div>`;

  // Load more button (AC6)
  const loadMoreHtml = `<div class="load-more-container">
  <button type="button" id="load-more-btn" class="load-more-btn" style="display:none">Charger plus d'experts</button>
</div>`;

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Experts en ${escapeHtml(verticalLabel)} \u2014 ${escapeHtml(brand?.name ?? 'Callibrate')}</title>
  <meta name="description" content="D\u00e9couvrez nos experts en ${escapeHtml(verticalLabel)}. Profiles v\u00e9rifi\u00e9s, disponibilit\u00e9s en temps r\u00e9el.">
  <meta name="robots" content="index, follow">
  <link rel="canonical" href="https://${escapeHtml(config.domain)}/experts">
  <meta property="og:title" content="Experts en ${escapeHtml(verticalLabel)} \u2014 ${escapeHtml(brand?.name ?? 'Callibrate')}">
  <meta property="og:url" content="https://${escapeHtml(config.domain)}/experts">
  <meta property="og:type" content="website">
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
    .container { max-width: 1100px; margin: 0 auto; padding: 2rem 1.5rem; }
    h1 { font-size: 1.75rem; font-weight: 700; color: #1a1a2e; margin-bottom: 0.5rem; }
    .subtitle { color: #6b7280; font-size: 0.9375rem; margin-bottom: 1.5rem; }
    .filter-bar { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1.5rem; }
    .skill-filter { padding: 0.375rem 0.75rem; border: 1.5px solid #d1d5db; border-radius: 999px; background: #fff; font-size: 0.875rem; cursor: pointer; color: #374151; transition: all 0.15s; }
    .skill-filter:hover { border-color: var(--color-primary, #4F46E5); color: var(--color-primary, #4F46E5); }
    .skill-filter.active { background: var(--color-primary, #4F46E5); color: #fff; border-color: var(--color-primary, #4F46E5); }
    .experts-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.25rem; margin-bottom: 2rem; }
    @media (max-width: 900px) { .experts-grid { grid-template-columns: repeat(2, 1fr); } }
    @media (max-width: 580px) { .experts-grid { grid-template-columns: 1fr; } }
    .expert-card { background: #fff; border: 1px solid #e5e7eb; border-radius: var(--radius-card, 0.5rem); padding: 1.25rem; display: flex; flex-direction: column; gap: 0.75rem; }
    .card-avatar { width: 2.5rem; height: 2.5rem; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 1rem; flex-shrink: 0; }
    .card-body { flex: 1; display: flex; flex-direction: column; gap: 0.5rem; }
    .card-header-row { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
    .tier-badge { padding: 0.2rem 0.5rem; border-radius: 999px; font-size: 0.75rem; font-weight: 600; }
    .tier--top { background: #fef3c7; color: #92400e; }
    .tier--confirmed { background: #f1f5f9; color: #475569; }
    .tier--promising { background: #ede9fe; color: #5b21b6; }
    .score-badge { display: inline-block; padding: 0.2rem 0.4rem; background: var(--color-primary, #4F46E5); color: #fff; border-radius: 0.25rem; font-size: 0.75rem; font-weight: 600; }
    .card-headline { font-size: 0.9375rem; color: #374151; font-weight: 500; line-height: 1.4; }
    .tags-row { display: flex; flex-wrap: wrap; gap: 0.25rem; }
    .tag { padding: 0.2rem 0.4rem; background: #f3f4f6; border-radius: 0.25rem; font-size: 0.8125rem; color: #374151; }
    .rate-range { font-size: 0.875rem; color: #6b7280; font-weight: 500; }
    .card-link { display: block; text-align: center; padding: 0.5rem 1rem; background: var(--color-primary, #4F46E5); color: #fff; text-decoration: none; border-radius: var(--radius-card, 0.375rem); font-size: 0.875rem; font-weight: 600; transition: opacity 0.15s; }
    .card-link:hover { opacity: 0.9; }
    .load-more-container { text-align: center; margin-bottom: 2rem; }
    .load-more-btn { padding: 0.75rem 2rem; border: 1.5px solid var(--color-primary, #4F46E5); background: #fff; color: var(--color-primary, #4F46E5); border-radius: var(--radius-card, 0.5rem); font-size: 0.9375rem; font-weight: 600; cursor: pointer; transition: all 0.15s; }
    .load-more-btn:hover:not(:disabled) { background: var(--color-primary, #4F46E5); color: #fff; }
    .load-more-btn:disabled { opacity: 0.5; cursor: not-allowed; }
    .empty-state { text-align: center; padding: 3rem 1rem; background: #fff; border: 1px solid #e5e7eb; border-radius: var(--radius-card, 0.5rem); }
    .empty-state p { color: #6b7280; margin-bottom: 1rem; }
    .reset-filters-btn { padding: 0.5rem 1.25rem; border: 1.5px solid #d1d5db; background: #fff; color: #374151; border-radius: var(--radius-card, 0.375rem); font-size: 0.875rem; cursor: pointer; margin-right: 0.75rem; }
    .cta-link { display: inline-block; padding: 0.5rem 1.25rem; background: var(--color-primary, #4F46E5); color: #fff; text-decoration: none; border-radius: var(--radius-card, 0.375rem); font-size: 0.875rem; font-weight: 600; }
    @media (max-width: 640px) { h1 { font-size: 1.375rem; } .container { padding: 1.5rem 1rem; } }
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
    <h1>${total} expert${total !== 1 ? 's' : ''} en ${escapeHtml(verticalLabel)}</h1>
    <p class="subtitle">Profils v\u00e9rifi\u00e9s — Disponibilit\u00e9s en temps r\u00e9el</p>
    ${filterBarHtml}
    <div id="experts-grid" class="experts-grid">
      ${cardsHtml}
    </div>
    ${emptyStateHtml}
    ${loadMoreHtml}
  </main>
  ${satConfigScript}
  ${interactiveScript}
  ${posthogBodyScript}
</body>
</html>`;
}
