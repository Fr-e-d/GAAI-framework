import { describe, it, expect } from 'vitest';
import { renderConfirmPage } from './confirm';
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

// ── Group 1: AC1 — Summary section structure ──────────────────────────────────
describe('renderConfirmPage — Summary section (AC1)', () => {
  it('includes "Vos besoins identifiés" heading text', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('Vos besoins');
  });

  it('includes fields-container element', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="fields-container"');
  });

  it('includes confidence-indicator class in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('confidence-indicator');
  });

  it('includes modifier-btn class in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('modifier-btn');
  });

  it('includes field-label class in CSS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('field-label');
  });

  it('renders logo img when theme.logo_url is set', () => {
    const html = renderConfirmPage(configWithTheme, 'key', 'https://api.example.com', 'site-key');
    expect(html).toContain('<img');
    expect(html).toContain('https://test.example.com/logo.png');
  });

  it('does not render logo img when theme is null', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('<img');
  });

  it('includes confidence indicator logic for high confidence', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('getConfidenceIndicator');
  });
});

// ── Group 2: AC2 + AC3 — Page structure ───────────────────────────────────────
describe('renderConfirmPage — Page structure (AC2, AC3)', () => {
  it('includes confirm button with correct text', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="confirm-btn"');
    expect(html).toContain('Confirmer et trouver mes experts');
  });

  it('includes questions-section element', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="questions-section"');
  });

  it('includes questions-container element', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="questions-container"');
  });

  it('questions-section is hidden by default', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="questions-section"');
    expect(html).toContain('style="display:none"');
  });

  it('includes max 3 questions constraint in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('displayed>=3');
  });
});

// ── Group 3: AC5 + AC11 — Turnstile integration ───────────────────────────────
describe('renderConfirmPage — Turnstile (AC5, AC11)', () => {
  it('includes cf-turnstile-container element', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="cf-turnstile-container"');
  });

  it('loads Turnstile SDK from challenges.cloudflare.com', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('challenges.cloudflare.com/turnstile/v0/api.js');
  });

  it('includes turnstileSiteKey in window.__SAT__', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'my-site-key-123');
    expect(html).toContain('my-site-key-123');
    expect(html).toContain('turnstileSiteKey');
  });

  it('escapes </script> in turnstileSiteKey to prevent XSS', () => {
    const maliciousKey = 'key</script><script>alert(1)';
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', maliciousKey);
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });

  it('includes appearance interaction-only in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('interaction-only');
  });

  it('includes turnstile.render call in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('turnstile.render');
  });
});

// ── Group 4: AC6 + AC8 — Loading and error elements ──────────────────────────
describe('renderConfirmPage — Loading and error (AC6, AC8)', () => {
  it('includes loading-msg element', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="loading-msg"');
  });

  it('includes confirm-error element with role alert', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="confirm-error"');
    expect(html).toContain('role="alert"');
  });

  it('includes spinner CSS class definition', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('.spinner');
  });

  it('includes 422 error handling in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('status===422');
  });

  it('includes 429 rate limit message', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('Trop de tentatives');
  });
});

// ── Group 5: AC9 — PostHog events ────────────────────────────────────────────
describe('renderConfirmPage — PostHog events (AC9)', () => {
  it('includes PostHog head snippet when tracking_enabled and key provided', () => {
    const html = renderConfirmPage(configWithTheme, 'test-api-key', 'https://api.example.com', 'site-key');
    expect(html).toContain('posthog.init');
  });

  it('does not include PostHog snippet when tracking_enabled is false', () => {
    const html = renderConfirmPage(baseConfig, 'test-api-key', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('posthog.init');
  });

  it('does not include PostHog snippet when posthogApiKey is empty', () => {
    const html = renderConfirmPage({ ...baseConfig, tracking_enabled: true }, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('posthog.init');
  });

  it('includes satellite.confirmation_viewed event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('satellite.confirmation_viewed');
  });

  it('includes satellite.confirmation_field_edited event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('satellite.confirmation_field_edited');
  });

  it('includes satellite.confirmation_submitted event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('satellite.confirmation_submitted');
  });

  it('includes satellite.prospect_created event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('satellite.prospect_created');
  });

  it('uses persistence:memory for cookieless tracking', () => {
    const html = renderConfirmPage(configWithTheme, 'test-api-key', 'https://api.example.com', 'site-key');
    expect(html).toContain('persistence:"memory"');
  });
});

// ── Group 6: AC10 — Back navigation ──────────────────────────────────────────
describe('renderConfirmPage — Back navigation (AC10)', () => {
  it('includes back link pointing to /match', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('href="/match"');
  });

  it('includes back-link id', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('id="back-link"');
  });

  it('includes Retour text', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('Retour');
  });
});

// ── Group 7: AC7 — SessionStorage and navigation ─────────────────────────────
describe('renderConfirmPage — SessionStorage and navigation (AC7)', () => {
  it('stores match:prospect_id in sessionStorage', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('match:prospect_id');
  });

  it('stores match:token in sessionStorage', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('match:token');
  });

  it('navigates to /results on success', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('/results');
  });

  it('reads match:extraction from sessionStorage', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('match:extraction');
  });
});

// ── Group 8: Security — HTML escaping ────────────────────────────────────────
describe('renderConfirmPage — HTML escaping', () => {
  it('escapes <script> in brand.name', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      brand: { name: '<script>alert(1)</script>', tagline: '' },
    };
    const html = renderConfirmPage(config, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });

  it('escapes < in theme values to prevent CSS injection', () => {
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
    const html = renderConfirmPage(config, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('#4F46E5</style>');
    expect(html).toContain('&lt;/style&gt;');
  });

  it('escapes </script> in coreApiUrl to prevent script injection', () => {
    const maliciousUrl = 'https://evil.com</script><script>alert(1)';
    const html = renderConfirmPage(baseConfig, '', maliciousUrl, 'site-key');
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });
});

// ── Group 9: AC1 — Robots meta ────────────────────────────────────────────────
describe('renderConfirmPage — Robots meta (AC1)', () => {
  it('includes noindex, nofollow robots meta', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('noindex, nofollow');
  });

  it('does not include canonical link (non-indexed page)', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('rel="canonical"');
  });
});

// ── Group 10: AC3 — Budget range handling ────────────────────────────────────
describe('renderConfirmPage — Budget range (AC3)', () => {
  it('includes edit-budget-min input ID in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('edit-budget-min');
  });

  it('includes edit-budget-max input ID in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('edit-budget-max');
  });

  it('includes budget_range field handling in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('budget_range');
  });

  it('includes q-budget-min for question-mode budget input', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('q-budget-min');
  });
});

// ── Group 7: E03S11 — AC1 loading msg, AC4 error specificity, AC7 error tracking ─
describe('renderConfirmPage — E03S11 (AC1, AC4, AC7)', () => {
  it('AC1: loading-msg uses body text color (#1a1a2e), not muted grey', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('color: #1a1a2e');
  });

  it('AC1: loading-msg does not override font-size to reduced size in CSS block', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    // The loading-msg CSS block should not contain font-size: 0.875rem
    const loadingMsgBlock = html.substring(html.indexOf('#loading-msg'), html.indexOf('#confirm-error'));
    expect(loadingMsgBlock).not.toContain('font-size: 0.875rem');
  });

  it('AC1: loading-msg element appears after confirm-btn in HTML', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html.indexOf('id="loading-msg"')).toBeGreaterThan(html.indexOf('id="confirm-btn"'));
  });

  it('AC1: loading message text matches AC spec', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('Recherche en cours parmi nos experts qualifi');
  });

  it('AC4: catch-all error is specific connection failure message', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('La connexion au serveur a');
  });

  it('AC4: catch-all error does not use old generic message', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('Une erreur est survenue. Veuillez r');
  });

  it('AC7: includes satellite.matching_error event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('satellite.matching_error');
  });

  it('AC7: includes error_type property in matching_error event', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('error_type');
  });

  it('AC7: includes page:confirm property', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain("page:'confirm'");
  });

  it('AC7: includes validation_422 error type', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('validation_422');
  });

  it('AC7: includes rate_limit_429 error type', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('rate_limit_429');
  });

  it('AC7: includes turnstile error type', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain("'turnstile'");
  });
});
