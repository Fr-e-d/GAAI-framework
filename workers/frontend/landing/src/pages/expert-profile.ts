// E02S12 AC2-AC6: Expert public profile page renderer
// Route: GET /experts/:slug
// SEO: index,follow,max-snippet:150, canonical, JSON-LD Person (no PII)
// Fetches from /api/experts/public/:slug on the backend API.

const SITE_URL = 'https://callibrate.io';
const APP_URL = 'https://app.callibrate.io';

// ── Types ──────────────────────────────────────────────────────────────────────

export interface PublicExpertData {
  slug: string;
  headline: string | null;
  skills: string[];
  industries: string[];
  rate_min: number | null;
  rate_max: number | null;
  quality_tier: 'new' | 'rising' | 'established' | 'top';
  completed_projects: number;
  languages: string[];
  bio_excerpt: string | null;
  availability_status: string | null;
  outcome_tags: string[];
  direct_link_url: string | null;
}

// ── Fetch helper ───────────────────────────────────────────────────────────────

export async function fetchPublicExpert(
  apiBaseUrl: string,
  slug: string,
): Promise<PublicExpertData | null> {
  try {
    const res = await fetch(`${apiBaseUrl}/api/experts/public/${encodeURIComponent(slug)}`, {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) return null;
    const data = await res.json() as PublicExpertData;
    return data;
  } catch {
    return null;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const QUALITY_TIER_LABELS: Record<string, string> = {
  new: 'New Expert',
  rising: 'Rising Expert',
  established: 'Established Expert',
  top: 'Top Expert',
};

const AVAILABILITY_LABELS: Record<string, string> = {
  available: 'Available',
  busy: 'Limited availability',
  unavailable: 'Currently unavailable',
};

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

function buildPosthogHeadSnippet(posthogApiKey: string): string {
  if (!posthogApiKey) return '';
  return `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`;
}

// ── Page renderer ─────────────────────────────────────────────────────────────

export function renderExpertProfilePage(
  expert: PublicExpertData,
  posthogApiKey: string,
): string {
  const canonicalUrl = `${SITE_URL}/experts/${expert.slug}`;
  const tierLabel = QUALITY_TIER_LABELS[expert.quality_tier] ?? 'Expert';
  const availLabel = AVAILABILITY_LABELS[expert.availability_status ?? ''] ?? 'Status unknown';
  const rateStr = formatRateRange(expert.rate_min, expert.rate_max);
  const top5Skills = expert.skills.slice(0, 5);
  const bioExcerpt = expert.bio_excerpt
    ? expert.bio_excerpt.substring(0, 150)
    : 'AI Integration Expert on Callibrate.';
  const metaDescription = `${tierLabel} on Callibrate. ${bioExcerpt}`.substring(0, 160);
  const pageTitle = expert.headline
    ? `${escapeHtml(expert.headline)} — Callibrate Expert`
    : 'Callibrate Expert Profile';

  // JSON-LD: Person (no PII — no name, no email, no phone)
  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'Person',
    url: canonicalUrl,
    description: metaDescription,
    jobTitle: expert.headline ?? 'AI Integration Expert',
    knowsAbout: top5Skills,
    knowsLanguage: expert.languages,
    worksFor: { '@type': 'Organization', name: 'Callibrate', url: SITE_URL },
  }).replace(/</g, '\\u003c');

  const skillBadges = top5Skills
    .map(s => `<span class="skill-badge">${escapeHtml(s)}</span>`)
    .join('');

  const langBadges = expert.languages.slice(0, 4)
    .map(l => `<span class="lang-badge">${escapeHtml(l)}</span>`)
    .join('');

  const outcomeTags = expert.outcome_tags.slice(0, 3)
    .map(t => `<span class="outcome-tag">${escapeHtml(t)}</span>`)
    .join('');

  const bookingCta = expert.direct_link_url
    ? `<a href="${escapeHtml(expert.direct_link_url)}" class="cta-primary" data-event="profile.direct_book_clicked">Book directly</a>
       <a href="${APP_URL}/signup" class="cta-secondary" data-event="profile.callibrate_cta_clicked">Get matched via Callibrate</a>`
    : `<a href="${APP_URL}/signup" class="cta-primary" data-event="profile.callibrate_cta_clicked">Get matched via Callibrate</a>`;

  const posthogHead = buildPosthogHeadSnippet(posthogApiKey);
  const posthogBody = posthogApiKey
    ? `<script>(function(){var p=new URLSearchParams(window.location.search);posthog.capture('page_view',{page:'expert_profile',expert_slug:'${expert.slug}',referrer:document.referrer||null});document.querySelectorAll('[data-event]').forEach(function(el){el.addEventListener('click',function(){posthog.capture(el.getAttribute('data-event'),{expert_slug:'${expert.slug}'});});});})();</script>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${pageTitle}</title>
  <meta name="description" content="${escapeHtml(metaDescription)}">
  <meta name="robots" content="index, follow, max-snippet:150">
  <meta property="og:title" content="${pageTitle}">
  <meta property="og:description" content="${escapeHtml(metaDescription)}">
  <meta property="og:url" content="${canonicalUrl}">
  <meta property="og:type" content="profile">
  <link rel="canonical" href="${canonicalUrl}">
  <script type="application/ld+json">${jsonLd}</script>
  ${posthogHead}
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --color-primary: #4F46E5;
      --color-text: #1a1a2e;
      --color-subtle: #6b7280;
      --color-border: #e5e7eb;
      --color-bg: #ffffff;
      --color-bg-alt: #f9fafb;
    }
    body { font-family: 'Inter', system-ui, -apple-system, sans-serif; color: var(--color-text); background: var(--color-bg); line-height: 1.6; }
    .container { max-width: 800px; width: 100%; margin: 0 auto; padding: 0 1.5rem; }
    a { color: var(--color-primary); }
    nav { height: 56px; border-bottom: 1px solid var(--color-border); display: flex; align-items: center; background: #fff; position: sticky; top: 0; z-index: 100; }
    .nav-inner { display: flex; align-items: center; justify-content: space-between; width: 100%; }
    .brand { font-size: 1.125rem; font-weight: 700; color: var(--color-primary); text-decoration: none; }
    .profile-header { padding: 2.5rem 0 1.5rem; border-bottom: 1px solid var(--color-border); }
    .tier-badge { display: inline-block; background: #EEF2FF; color: var(--color-primary); font-size: 0.75rem; font-weight: 600; padding: 0.25rem 0.75rem; border-radius: 999px; margin-bottom: 0.75rem; }
    .headline { font-size: 1.75rem; font-weight: 700; margin-bottom: 0.5rem; }
    .meta-row { display: flex; flex-wrap: wrap; gap: 1rem; color: var(--color-subtle); font-size: 0.9375rem; margin-top: 0.5rem; }
    .meta-item { display: flex; align-items: center; gap: 0.25rem; }
    .skills-row { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 1rem; }
    .skill-badge { background: #F3F4F6; color: var(--color-text); font-size: 0.8125rem; font-weight: 500; padding: 0.25rem 0.75rem; border-radius: 999px; }
    .lang-badge { background: #ECFDF5; color: #065F46; font-size: 0.8125rem; font-weight: 500; padding: 0.25rem 0.75rem; border-radius: 999px; }
    .outcome-tag { background: #FFF7ED; color: #92400E; font-size: 0.8125rem; font-weight: 500; padding: 0.25rem 0.75rem; border-radius: 999px; }
    .section { padding: 1.5rem 0; border-bottom: 1px solid var(--color-border); }
    .section-title { font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem; }
    .bio-text { color: var(--color-subtle); line-height: 1.7; }
    .cta-block { padding: 2rem 0; display: flex; flex-wrap: wrap; gap: 1rem; }
    .cta-primary { display: inline-block; padding: 0.75rem 1.75rem; background: var(--color-primary); color: #fff !important; text-decoration: none; border-radius: 0.5rem; font-weight: 600; min-height: 44px; }
    .cta-primary:hover { opacity: 0.88; }
    .cta-secondary { display: inline-block; padding: 0.75rem 1.75rem; background: #fff; color: var(--color-primary) !important; text-decoration: none; border-radius: 0.5rem; font-weight: 600; border: 2px solid var(--color-primary); min-height: 44px; }
    .cta-secondary:hover { background: #F5F3FF; }
    .avail-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 4px; background: #9CA3AF; }
    .avail-dot--available { background: #10B981; }
    .avail-dot--busy { background: #F59E0B; }
    footer { padding: 2rem 1.5rem; background: var(--color-bg-alt); border-top: 1px solid var(--color-border); font-size: 0.875rem; color: var(--color-subtle); text-align: center; }
    @media (max-width: 600px) { .headline { font-size: 1.375rem; } .cta-block { flex-direction: column; } }
  </style>
</head>
<body>
  <nav>
    <div class="container nav-inner">
      <a href="/" class="brand">Callibrate</a>
      <a href="${APP_URL}/signup" style="font-size:0.875rem;font-weight:600;color:var(--color-primary);text-decoration:none;">Join as an expert</a>
    </div>
  </nav>

  <div class="container">
    <div class="profile-header">
      <span class="tier-badge">${escapeHtml(tierLabel)}</span>
      <h1 class="headline">${expert.headline ? escapeHtml(expert.headline) : 'AI Integration Expert'}</h1>
      <div class="meta-row">
        <span class="meta-item">
          <span class="avail-dot${expert.availability_status === 'available' ? ' avail-dot--available' : expert.availability_status === 'busy' ? ' avail-dot--busy' : ''}"></span>
          ${escapeHtml(availLabel)}
        </span>
        <span class="meta-item">${escapeHtml(rateStr)}</span>
        ${expert.languages.length > 0 ? `<span class="meta-item">${escapeHtml(expert.languages.slice(0, 2).join(', '))}</span>` : ''}
      </div>
      ${skillBadges ? `<div class="skills-row">${skillBadges}</div>` : ''}
      ${langBadges ? `<div class="skills-row">${langBadges}</div>` : ''}
      ${outcomeTags ? `<div class="skills-row">${outcomeTags}</div>` : ''}
    </div>

    ${expert.bio_excerpt ? `
    <div class="section">
      <h2 class="section-title">About</h2>
      <p class="bio-text">${escapeHtml(expert.bio_excerpt)}</p>
    </div>` : ''}

    <div class="cta-block">
      ${bookingCta}
    </div>
  </div>

  <footer>
    <p>Expert profile powered by <a href="${SITE_URL}">Callibrate</a> &mdash; Pre-qualified leads for AI Integration experts.</p>
  </footer>

  ${posthogBody}
</body>
</html>`;
}
