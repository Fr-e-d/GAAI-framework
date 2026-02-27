const SITE_URL = 'https://callibrate.io';
const APP_URL = 'https://app.callibrate.io';
const SIGNUP_URL = `${APP_URL}/signup`;
const SUPPORT_EMAIL = 'support@callibrate.io';
const OG_IMAGE_URL = `${SITE_URL}/og-image.png`;

const PAGE_TITLE = 'Callibrate \u2014 Pre-qualified leads, booked to your calendar';
const META_DESCRIPTION =
  'Callibrate connecte les experts en int\u00e9gration IA avec des prospects qualifi\u00e9s qui ont un budget confirm\u00e9 et des d\u00e9lais r\u00e9els. Pas de tire kickers. Payez uniquement pour les leads confirm\u00e9s.';

const JSON_LD_DATA = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: 'Callibrate',
  url: SITE_URL,
  description: META_DESCRIPTION,
  contactPoint: {
    '@type': 'ContactPoint',
    email: SUPPORT_EMAIL,
    contactType: 'customer support',
  },
};

const JSON_LD = JSON.stringify(JSON_LD_DATA).replace(/</g, '\\u003c');

function buildPosthogHeadSnippet(posthogApiKey: string): string {
  if (!posthogApiKey) return '';
  return `<script>!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",r=t.getElementsByTagName("script")[0],p.async=!0,p.src=s.api_host+"/static/array.js",r.parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+" (stub)"},o="init capture register register_once register_for_session unregister unregister_for_session getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey getNextSurveyStep identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty createPersonProfile opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing clear_opt_in_out_capturing debug".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);posthog.init(${JSON.stringify(posthogApiKey)},{api_host:"https://ph.callibrate.io",ui_host:"https://eu.posthog.com",persistence:"memory",autocapture:true,capture_pageview:false,disable_session_recording:false});</script>`;
}

function buildPosthogBodyScript(posthogApiKey: string): string {
  if (!posthogApiKey) return '';
  return `<script>(function(){var params=new URLSearchParams(window.location.search);posthog.capture('page_view',{page:'landing',referrer:document.referrer||null,utm_source:params.get('utm_source')||null,utm_campaign:params.get('utm_campaign')||null,utm_medium:params.get('utm_medium')||null,utm_content:params.get('utm_content')||null});var ctaEls=document.querySelectorAll('.cta[data-cta-location]');ctaEls.forEach(function(el){el.addEventListener('click',function(){posthog.capture('landing.cta_clicked',{cta_location:el.getAttribute('data-cta-location')});});});})();</script>`;
}

export function renderLandingPage(posthogApiKey: string): string {
  const posthogHead = buildPosthogHeadSnippet(posthogApiKey);
  const posthogBody = buildPosthogBodyScript(posthogApiKey);

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${PAGE_TITLE}</title>
  <meta name="description" content="${META_DESCRIPTION}">
  <meta name="robots" content="index, follow">
  <meta property="og:title" content="${PAGE_TITLE}">
  <meta property="og:description" content="${META_DESCRIPTION}">
  <meta property="og:image" content="${OG_IMAGE_URL}">
  <meta property="og:url" content="${SITE_URL}/">
  <meta property="og:type" content="website">
  <link rel="canonical" href="${SITE_URL}/">
  <script type="application/ld+json">${JSON_LD}</script>
  ${posthogHead}
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --color-primary: #4F46E5;
      --color-accent: #818CF8;
      --color-text: #1a1a2e;
      --color-subtle: #6b7280;
      --color-border: #e5e7eb;
      --color-bg: #ffffff;
      --color-bg-alt: #f9fafb;
    }
    body {
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      color: var(--color-text);
      background: var(--color-bg);
      line-height: 1.6;
    }
    .container { max-width: 1100px; width: 100%; margin: 0 auto; padding: 0 1.5rem; }
    a { color: inherit; }

    /* Navigation */
    nav {
      height: 64px;
      border-bottom: 1px solid var(--color-border);
      display: flex;
      align-items: center;
      background: #fff;
      position: sticky;
      top: 0;
      z-index: 100;
    }
    .nav-inner { display: flex; align-items: center; justify-content: space-between; width: 100%; }
    .brand { font-size: 1.25rem; font-weight: 700; color: var(--color-primary); text-decoration: none; }

    /* CTA button */
    .cta {
      display: inline-block;
      padding: 0.75rem 1.75rem;
      background: var(--color-primary);
      color: #fff !important;
      text-decoration: none;
      border-radius: 0.5rem;
      font-size: 1rem;
      font-weight: 600;
      transition: opacity 0.15s;
      min-height: 44px;
      min-width: 44px;
      line-height: 1.4;
    }
    .cta:hover { opacity: 0.88; }
    .cta--sm { padding: 0.5rem 1.25rem; font-size: 0.9375rem; }
    .cta--lg { padding: 1rem 2.5rem; font-size: 1.0625rem; }

    /* Hero */
    .hero { padding: 7rem 1.5rem 5rem; text-align: center; background: linear-gradient(180deg, #f5f3ff 0%, #fff 100%); }
    .hero-eyebrow { font-size: 0.875rem; font-weight: 600; color: var(--color-primary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 1rem; }
    .hero h1 { font-size: 3rem; font-weight: 800; line-height: 1.15; color: var(--color-text); margin-bottom: 1.25rem; }
    .hero-sub { font-size: 1.125rem; color: var(--color-subtle); max-width: 600px; margin: 0 auto 2.5rem; }

    /* Sections */
    .section { padding: 5rem 1.5rem; }
    .section--alt { background: var(--color-bg-alt); }
    .section-title { font-size: 2rem; font-weight: 700; text-align: center; margin-bottom: 0.75rem; color: var(--color-text); }
    .section-sub { text-align: center; color: var(--color-subtle); margin-bottom: 3rem; font-size: 1rem; }

    /* Value prop cards */
    .cards-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1.5rem; margin-top: 2.5rem; }
    .card { background: #fff; border: 1px solid var(--color-border); border-radius: 0.75rem; padding: 1.75rem; }
    .card-icon { font-size: 1.75rem; margin-bottom: 0.75rem; }
    .card h3 { font-size: 1.0625rem; font-weight: 600; margin-bottom: 0.5rem; color: var(--color-text); }
    .card p { font-size: 0.9375rem; color: var(--color-subtle); line-height: 1.5; }

    /* Pricing table */
    .pricing-table { overflow-x: auto; margin-top: 2.5rem; }
    .pricing-table table { min-width: 560px; width: 100%; border-collapse: collapse; font-size: 0.9375rem; }
    .pricing-table th { background: var(--color-primary); color: #fff; padding: 0.75rem 1rem; text-align: left; font-weight: 600; }
    .pricing-table td { padding: 0.75rem 1rem; border-bottom: 1px solid var(--color-border); }
    .pricing-table tr:last-child td { border-bottom: none; }
    .pricing-table tr:nth-child(even) td { background: var(--color-bg-alt); }
    .pricing-cta { text-align: center; margin-top: 2.5rem; }

    /* How it works */
    .steps-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 2rem; margin-top: 2.5rem; }
    .step { text-align: center; }
    .step-number { display: inline-flex; align-items: center; justify-content: center; width: 48px; height: 48px; background: var(--color-primary); color: #fff; border-radius: 50%; font-size: 1.25rem; font-weight: 700; margin-bottom: 1rem; }
    .step h3 { font-size: 1.0625rem; font-weight: 600; margin-bottom: 0.5rem; color: var(--color-text); }
    .step p { font-size: 0.9375rem; color: var(--color-subtle); }

    /* Social proof */
    .testimonials-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1.5rem; margin-top: 2.5rem; }
    .testimonial-card { background: #fff; border: 1px solid var(--color-border); border-radius: 0.75rem; padding: 1.75rem; }
    .testimonial-card--placeholder { opacity: 0.55; }
    .testimonial-avatar { width: 48px; height: 48px; border-radius: 50%; background: var(--color-border); margin-bottom: 1rem; }
    .testimonial-text { font-size: 0.9375rem; color: var(--color-subtle); margin-bottom: 1rem; font-style: italic; }
    .testimonial-author { font-size: 0.875rem; font-weight: 600; color: var(--color-text); }

    /* Footer */
    footer { background: var(--color-text); color: #e5e7eb; padding: 3rem 1.5rem; }
    .footer-inner { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1.5rem; }
    .footer-links { display: flex; gap: 1.5rem; flex-wrap: wrap; }
    .footer-links a { color: #9ca3af; text-decoration: none; font-size: 0.9375rem; }
    .footer-links a:hover { color: #fff; }
    .footer-right { display: flex; flex-direction: column; align-items: flex-end; gap: 0.75rem; }
    .footer-copy { font-size: 0.8125rem; color: #6b7280; }

    /* Mobile */
    @media (max-width: 768px) {
      .hero { padding: 5rem 1rem 3rem; }
      .hero h1 { font-size: 2rem; }
      .hero-sub { font-size: 1rem; }
      .section { padding: 3rem 1rem; }
      .section-title { font-size: 1.5rem; }
      .cards-grid { grid-template-columns: 1fr; }
      .steps-grid { grid-template-columns: 1fr; }
      .testimonials-grid { grid-template-columns: 1fr; }
      .footer-inner { flex-direction: column; align-items: flex-start; }
      .footer-right { align-items: flex-start; }
    }
  </style>
</head>
<body>

  <nav>
    <div class="container nav-inner">
      <a href="/" class="brand">Callibrate</a>
      <a href="${SIGNUP_URL}" class="cta cta--sm" data-cta-location="nav">Commencer</a>
    </div>
  </nav>

  <!-- Hero (AC3) -->
  <section class="hero">
    <div class="container">
      <p class="hero-eyebrow">Pour les experts en int\u00e9gration IA</p>
      <h1>Stop aux tire kickers.<br>Des leads avec budgets confirm\u00e9s,<br>livr\u00e9s dans votre agenda.</h1>
      <p class="hero-sub">Callibrate vous connecte uniquement avec des prospects qui ont un budget r\u00e9el, un calendrier d\u00e9fini et un probl\u00e8me qui vaut la peine d&rsquo;\u00eatre r\u00e9solu.</p>
      <a href="${SIGNUP_URL}" class="cta cta--lg" data-cta-location="hero">Commencer</a>
    </div>
  </section>

  <!-- Value propositions (AC4) -->
  <section class="section section--alt" id="avantages">
    <div class="container">
      <h2 class="section-title">Pourquoi Callibrate</h2>
      <p class="section-sub">Tout ce qu&rsquo;il vous faut pour d\u00e9velopper votre activit\u00e9 en int\u00e9gration IA.</p>
      <div class="cards-grid">
        <div class="card">
          <div class="card-icon">&#127919;</div>
          <h3>Leads pr\u00e9-qualifi\u00e9s</h3>
          <p>Budget confirm\u00e9, calendrier r\u00e9el, besoin identifi\u00e9. Fini les conversations sans suite avec des tire kickers.</p>
        </div>
        <div class="card">
          <div class="card-icon">&#128176;</div>
          <h3>Tarification transparente</h3>
          <p>Grille publi\u00e9e de 49\u20ac \u00e0 263\u20ac selon le budget du projet. Payez uniquement pour les leads confirm\u00e9s.</p>
        </div>
        <div class="card">
          <div class="card-icon">&#128197;</div>
          <h3>Votre agenda, vos r\u00e8gles</h3>
          <p>Int\u00e9gration Google Calendar. Contr\u00f4lez vos disponibilit\u00e9s et signalez un lead non qualifi\u00e9 sous 7 jours.</p>
        </div>
        <div class="card">
          <div class="card-icon">&#128200;</div>
          <h3>Dashboard de performance</h3>
          <p>Score composite, analytics leads, taux de conversion. Visibilit\u00e9 compl\u00e8te sur votre activit\u00e9 Callibrate.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- Pricing (AC5) -->
  <section class="section" id="tarifs">
    <div class="container">
      <h2 class="section-title">Tarification transparente</h2>
      <p class="section-sub">Pas d&rsquo;abonnement. Payez uniquement pour les leads confirm\u00e9s.<br>100\u20ac de cr\u00e9dit offerts \u00e0 l&rsquo;inscription.</p>
      <div class="pricing-table">
        <table>
          <thead>
            <tr>
              <th>Budget du projet</th>
              <th>Standard</th>
              <th>Premium</th>
            </tr>
          </thead>
          <tbody>
            <tr><td>Non d\u00e9clar\u00e9</td><td>49\u20ac</td><td>56\u20ac</td></tr>
            <tr><td>&lt;\u202f5\u202f000\u20ac</td><td>49\u20ac</td><td>56\u20ac</td></tr>
            <tr><td>5\u202f000 \u2013 20\u202f000\u20ac</td><td>89\u20ac</td><td>102\u20ac</td></tr>
            <tr><td>20\u202f000 \u2013 50\u202f000\u20ac</td><td>149\u20ac</td><td>171\u20ac</td></tr>
            <tr><td>50\u202f000\u20ac+</td><td>229\u20ac</td><td>263\u20ac</td></tr>
          </tbody>
        </table>
      </div>
      <div class="pricing-cta">
        <a href="${SIGNUP_URL}" class="cta cta--lg" data-cta-location="pricing">Commencer avec 100\u20ac offerts</a>
      </div>
    </div>
  </section>

  <!-- How it works (AC6) -->
  <section class="section section--alt" id="comment">
    <div class="container">
      <h2 class="section-title">Comment \u00e7a marche</h2>
      <p class="section-sub">Quatre \u00e9tapes pour commencer \u00e0 recevoir des leads qualifi\u00e9s.</p>
      <div class="steps-grid">
        <div class="step">
          <div class="step-number">1</div>
          <h3>Cr\u00e9ez votre profil</h3>
          <p>D\u00e9crivez votre expertise, vos sp\u00e9cialit\u00e9s IA et connectez votre Google Calendar.</p>
        </div>
        <div class="step">
          <div class="step-number">2</div>
          <h3>Recevez des leads qualifi\u00e9s</h3>
          <p>Chaque lead est match\u00e9 \u00e0 votre profil. Budget et besoin v\u00e9rifi\u00e9s avant envoi.</p>
        </div>
        <div class="step">
          <div class="step-number">3</div>
          <h3>Confirmez ou signalez</h3>
          <p>Acceptez le lead et r\u00e9servez un appel, ou signalez-le sous 7 jours si non qualifi\u00e9.</p>
        </div>
        <div class="step">
          <div class="step-number">4</div>
          <h3>Suivez vos performances</h3>
          <p>Score composite, taux de conversion et historique dans votre dashboard d\u00e9di\u00e9.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- Social proof (AC7) -->
  <section class="section" id="temoignages">
    <div class="container">
      <h2 class="section-title">Ce qu&rsquo;en disent les experts</h2>
      <p class="section-sub">Les t\u00e9moignages sont ajout\u00e9s apr\u00e8s le lancement.</p>
      <div class="testimonials-grid">
        <div class="testimonial-card testimonial-card--placeholder">
          <div class="testimonial-avatar"></div>
          <p class="testimonial-text">&ldquo;Les t\u00e9moignages de vrais experts en int\u00e9gration IA appara\u00eetront ici apr\u00e8s le lancement.&rdquo;</p>
          <p class="testimonial-author">Expert Callibrate</p>
        </div>
        <div class="testimonial-card testimonial-card--placeholder">
          <div class="testimonial-avatar"></div>
          <p class="testimonial-text">&ldquo;Les t\u00e9moignages de vrais experts en int\u00e9gration IA appara\u00eetront ici apr\u00e8s le lancement.&rdquo;</p>
          <p class="testimonial-author">Expert Callibrate</p>
        </div>
        <div class="testimonial-card testimonial-card--placeholder">
          <div class="testimonial-avatar"></div>
          <p class="testimonial-text">&ldquo;Les t\u00e9moignages de vrais experts en int\u00e9gration IA appara\u00eetront ici apr\u00e8s le lancement.&rdquo;</p>
          <p class="testimonial-author">Expert Callibrate</p>
        </div>
      </div>
    </div>
  </section>

  <!-- Footer (AC8) -->
  <footer>
    <div class="container footer-inner">
      <div class="footer-links">
        <a href="https://app.callibrate.io">Dashboard</a>
        <a href="https://callibrate.io/privacy">Confidentialit\u00e9</a>
        <a href="https://callibrate.io/terms">Conditions</a>
        <a href="mailto:${SUPPORT_EMAIL}">Contact</a>
      </div>
      <div class="footer-right">
        <a href="${SIGNUP_URL}" class="cta cta--sm" data-cta-location="footer">Commencer</a>
        <p class="footer-copy">&copy; 2026 Callibrate. Tous droits r\u00e9serv\u00e9s.</p>
      </div>
    </div>
  </footer>

  ${posthogBody}
</body>
</html>`;
}
