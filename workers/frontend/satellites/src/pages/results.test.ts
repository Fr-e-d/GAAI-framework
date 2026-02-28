import { describe, it, expect } from 'vitest';
import { renderResultsPage } from './results';
import type { SatelliteConfig } from '../types/config';

const baseConfig: SatelliteConfig = {
  id: 'test-satellite',
  domain: 'test.example.com',
  label: null,
  vertical: null,
  active: true,
  theme: null,
  brand: null,
  content: null,
  structured_data: null,
  quiz_schema: null,
  matching_weights: null,
  tracking_enabled: false,
};

const configWithTheme: SatelliteConfig = {
  ...baseConfig,
  theme: {
    primary: '#4F46E5',
    accent: '#818CF8',
    font: 'Inter, sans-serif',
    radius: '0.5rem',
    logo_url: 'https://test.example.com/logo.png',
  },
  brand: { name: 'TestBrand', tagline: 'The best' },
  content: {
    meta_title: 'TestBrand — Matching',
    meta_description: 'Find your expert',
    hero_headline: 'Find an expert',
    hero_sub: 'Quickly',
    value_props: [],
  },
  tracking_enabled: true,
};

// ── Group 1: AC12 — Robots meta ───────────────────────────────────────────────
describe('renderResultsPage — Robots meta (AC12)', () => {
  it('includes noindex, nofollow robots meta', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('noindex, nofollow');
  });

  it('does not include canonical link', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).not.toContain('rel="canonical"');
  });
});

// ── Group 2: AC1 — Loading skeleton ──────────────────────────────────────────
describe('renderResultsPage — Loading skeleton (AC1)', () => {
  it('includes matches-loading element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="matches-loading"');
  });

  it('includes skeleton-card class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('skeleton-card');
  });

  it('includes shimmer CSS animation', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('shimmer');
  });

  it('includes aria-live="polite" on loading container', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('aria-live="polite"');
  });

  it('includes 3 skeleton cards', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    const count = (html.match(/class="skeleton-card"/g) || []).length;
    expect(count).toBe(3);
  });
});

// ── Group 3: AC2 — Computing state ───────────────────────────────────────────
describe('renderResultsPage — Computing state (AC2)', () => {
  it('includes computing-msg element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="computing-msg"');
  });

  it('includes "Nous affinons les correspondances" text (AC2 E03S11)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Nous affinons les correspondances');
  });

  it('includes MAX_RETRIES constant equal to 3', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('MAX_RETRIES=3');
  });

  it('includes exponential backoff logic', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Math.pow(2,retryCount)');
  });

  it('includes no-available-msg element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="no-available-msg"');
  });

  it('includes computing timeout fallback text (AC6 E03S11)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Le calcul des correspondances prend plus de temps');
  });
});

// ── Group 4: AC3 — Anonymized card elements ───────────────────────────────────
describe('renderResultsPage — Anonymized card elements (AC3)', () => {
  it('includes match-card class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('match-card');
  });

  it('includes match-card--prominent class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('match-card--prominent');
  });

  it('includes rank-badge--1 class (gold)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('rank-badge--1');
  });

  it('includes rank-badge--2 class (silver)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('rank-badge--2');
  });

  it('includes rank-badge--3 class (bronze)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('rank-badge--3');
  });

  it('includes tier--top class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('tier--top');
  });

  it('includes tier--confirmed class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('tier--confirmed');
  });

  it('includes tier--promising class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('tier--promising');
  });

  it('includes score-bar-track and score-bar-fill classes', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('score-bar-track');
    expect(html).toContain('score-bar-fill');
  });

  it('includes criteria_scores reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('criteria_scores');
  });

  it('includes skills_matched reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('skills_matched');
  });

  it('includes rate_min and rate_max references in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('rate_min');
    expect(html).toContain('rate_max');
  });

  it('includes avatar-silhouette class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('avatar-silhouette');
  });

  it('includes SVG silhouette avatar', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('<svg');
    expect(html).toContain('9ca3af');
  });
});

// ── Group 5: AC4 — Results header ────────────────────────────────────────────
describe('renderResultsPage — Results header (AC4)', () => {
  it('includes results-header element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="results-header"');
  });

  it('includes results-count-heading element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="results-count-heading"');
  });

  it('includes plural logic for experts', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain("matches.length>1?'s':''");
  });
});

// ── Group 6: AC5 — Email gate ─────────────────────────────────────────────────
describe('renderResultsPage — Email gate (AC5)', () => {
  it('includes email-gate-section element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="email-gate-section"');
  });

  it('includes email-input of type email', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="email-input"');
    expect(html).toContain('type="email"');
  });

  it('includes unlock-btn button', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="unlock-btn"');
  });

  it('includes "Débloquer les profils" text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('D\u00e9bloquer les profils');
  });

  it('includes "Découvrez le profil complet" text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('D\u00e9couvrez le profil complet');
  });

  it('includes email regex validation in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('[^\\s@]+@[^\\s@]+\\.[^\\s@]+');
  });

  it('email-gate-section is hidden by default', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="email-gate-section"');
    expect(html).toContain('style="display:none"');
  });
});

// ── Group 7: AC6 — Identify API call ─────────────────────────────────────────
describe('renderResultsPage — Identify API call (AC6)', () => {
  it('includes POST fetch to /identify in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('/identify');
    expect(html).toContain("method:'POST'");
  });

  it('includes disabled state logic on unlock-btn', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('unlockBtn.disabled=true');
  });

  it('includes spinner class usage in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('spinner');
  });
});

// ── Group 8: AC7 — Full profile reveal ───────────────────────────────────────
describe('renderResultsPage — Full profile reveal (AC7)', () => {
  it('includes avatar-initial class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('avatar-initial');
  });

  it('includes booking-btn class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('booking-btn');
  });

  it('includes data-expert-id attribute reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('data-expert-id');
  });

  it('includes "Réserver un appel" text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('R\u00e9server un appel');
  });

  it('includes bio-text class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('bio-text');
  });

  it('includes bio-expand-btn class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('bio-expand-btn');
  });

  it('includes display_name reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('display_name');
  });

  it('includes headline reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('headline');
  });

  it('includes bio reference in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('expert.bio');
  });

  it('includes booking-open custom event dispatch', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('booking-open');
  });

  it('includes CustomEvent constructor usage', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('CustomEvent');
  });
});

// ── Group 9: AC8 — Error states ──────────────────────────────────────────────
describe('renderResultsPage — Error states (AC8)', () => {
  it('includes 403 handling with session expired text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('err.status===403');
    expect(html).toContain('Votre session a expir');
  });

  it('includes 409 handling branch', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('res.status===409');
  });

  it('includes 422 inline email error handling', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('err.status===422');
  });

  it('includes fetch-error element with role alert', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="fetch-error"');
    expect(html).toContain('role="alert"');
  });

  it('includes retry-btn element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="retry-btn"');
  });
});

// ── Group 10: AC9 — No matches ───────────────────────────────────────────────
describe('renderResultsPage — No matches (AC9)', () => {
  it('includes no-matches element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="no-matches"');
  });

  it('includes link to /confirm for modify criteria', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('href="/confirm"');
  });

  it('includes link to /experts for directory', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('href="/experts"');
  });

  it('includes empty array check in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('matchesData.length===0');
  });
});

// ── Group 11: AC10 — PostHog events ──────────────────────────────────────────
describe('renderResultsPage — PostHog events (AC10)', () => {
  it('includes satellite.matches_viewed event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.matches_viewed');
  });

  it('includes satellite.match_card_expanded event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.match_card_expanded');
  });

  it('includes satellite.email_gate_submitted event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.email_gate_submitted');
  });

  it('includes satellite.profiles_unlocked event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.profiles_unlocked');
  });

  it('includes satellite.booking_cta_clicked event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.booking_cta_clicked');
  });

  it('includes PostHog head snippet when tracking_enabled and key provided', () => {
    const html = renderResultsPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('posthog.init');
  });

  it('does not include PostHog snippet when tracking_enabled is false', () => {
    const html = renderResultsPage(baseConfig, 'test-api-key', 'https://api.example.com');
    expect(html).not.toContain('posthog.init');
  });

  it('does not include PostHog snippet when posthogApiKey is empty', () => {
    const html = renderResultsPage({ ...baseConfig, tracking_enabled: true }, '', 'https://api.example.com');
    expect(html).not.toContain('posthog.init');
  });

  it('uses persistence:"memory" for cookieless tracking', () => {
    const html = renderResultsPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('persistence:"memory"');
  });
});

// ── Group 12: AC11 — SessionStorage guard ────────────────────────────────────
describe('renderResultsPage — SessionStorage guard (AC11)', () => {
  it('reads match:prospect_id from sessionStorage', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('match:prospect_id');
  });

  it('reads match:token from sessionStorage', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('match:token');
  });

  it('redirects to /match when session keys missing', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain("window.location.href='/match'");
  });
});

// ── Group 13: Security — HTML escaping ───────────────────────────────────────
describe('renderResultsPage — HTML escaping', () => {
  it('escapes <script> in brand.name', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      brand: { name: '<script>alert(1)</script>', tagline: '' },
    };
    const html = renderResultsPage(config, '', 'https://api.example.com');
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });

  it('escapes < in theme values', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      theme: {
        primary: '#4F46E5</style>',
        accent: '#818CF8',
        font: 'Inter, sans-serif',
        radius: '0.5rem',
        logo_url: null,
      },
    };
    const html = renderResultsPage(config, '', 'https://api.example.com');
    expect(html).not.toContain('#4F46E5</style>');
    expect(html).toContain('&lt;/style&gt;');
  });

  it('escapes </script> in coreApiUrl', () => {
    const maliciousUrl = 'https://evil.com</script><script>alert(1)';
    const html = renderResultsPage(baseConfig, '', maliciousUrl);
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });
});

// ── Group 14: window.__SAT__ injection ───────────────────────────────────────
describe('renderResultsPage — window.__SAT__ injection', () => {
  it('includes window.__SAT__ assignment', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('window.__SAT__');
  });

  it('includes apiUrl value', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('"apiUrl"');
  });

  it('includes satelliteId value', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('"satelliteId"');
  });

  it('does NOT include turnstileSiteKey', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).not.toContain('turnstileSiteKey');
  });
});

// ── Group 15: Logo rendering ──────────────────────────────────────────────────
describe('renderResultsPage — Logo rendering', () => {
  it('renders logo img when theme.logo_url is set', () => {
    const html = renderResultsPage(configWithTheme, 'key', 'https://api.example.com');
    expect(html).toContain('<img');
    expect(html).toContain('https://test.example.com/logo.png');
  });

  it('does not render logo img when theme is null', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).not.toContain('<img');
  });
});

// ── Group 12: E03S11 — AC2, AC3, AC5, AC6, AC7 ────────────────────────────────
describe('renderResultsPage — E03S11 (AC2, AC3, AC5, AC6, AC7)', () => {
  it('AC2: includes computing-msg-text id for dynamic updates', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="computing-msg-text"');
  });

  it('AC2: includes waitStart variable for elapsed time tracking', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('waitStart');
  });

  it('AC2: includes 10000ms threshold for extended wait message', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('10000');
  });

  it('AC2: includes extended wait reassurance message', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Cela prend un peu plus de temps');
  });

  it('AC3: includes networkErrorRetried variable for silent retry', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('networkErrorRetried');
  });

  it('AC3: includes 2000ms silent retry delay', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('2000');
  });

  it('AC3: networkErrorRetried resets on retry-btn click', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('networkErrorRetried=false');
  });

  it('AC5: includes network-specific error message', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Connexion interrompue');
  });

  it('AC5: includes server-specific error message', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Nos serveurs sont moment');
  });

  it('AC5: includes fetch-error-browse secondary link element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="fetch-error-browse"');
  });

  it('AC6: includes email promise in computing timeout fallback', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('r\u00e9sultats par email');
  });

  it('AC6: includes secondary directory link in computing timeout fallback', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('parcourir le r');
  });

  it('AC7: includes satellite.matching_error event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('satellite.matching_error');
  });

  it('AC7: includes computing_timeout error type', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('computing_timeout');
  });

  it('AC7: includes server_5xx error type', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('server_5xx');
  });

  it('AC7: includes page:results property', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain("page:'results'");
  });
});
