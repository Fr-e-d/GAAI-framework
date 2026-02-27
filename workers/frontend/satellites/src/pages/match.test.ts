import { describe, it, expect } from 'vitest';
import { renderMatchPage } from './match';
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

// ── Group 1: AC8 — SEO / head tags ───────────────────────────────────────────

describe('renderMatchPage — SEO / head tags (AC8)', () => {
  it('includes canonical link pointing to /match', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('rel="canonical"');
    expect(html).toContain('/match');
  });

  it('includes meta robots index, follow', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('<meta name="robots" content="index, follow">');
  });

  it('includes og:url pointing to /match', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('og:url');
    expect(html).toContain(`${baseConfig.domain}/match`);
  });

  it('title falls back to default when content and brand are null', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('<title>');
    expect(html).toContain('Callibrate');
  });

  it('title includes brand name when brand is set', () => {
    const html = renderMatchPage(configWithTheme, 'key', 'https://api.example.com');
    expect(html).toContain('TestBrand');
  });

  it('title contains "Décrivez votre projet" in fallback case', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('D\u00e9crivez votre projet');
  });

  it('includes JSON-LD WebPage structured data', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('WebPage');
  });
});

// ── Group 2: AC3 — API config injection ──────────────────────────────────────

describe('renderMatchPage — API config injection (AC3)', () => {
  it('includes window.__SAT__ assignment', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('window.__SAT__');
  });

  it('includes the correct apiUrl value', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.callibrate.io');
    expect(html).toContain('https://api.callibrate.io');
  });

  it('includes the correct satelliteId value', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('"test-satellite"');
  });

  it('escapes </script> in coreApiUrl to prevent script injection', () => {
    const maliciousUrl = 'https://evil.com</script><script>alert(1)';
    const html = renderMatchPage(baseConfig, '', maliciousUrl);
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });
});

// ── Group 3: AC1 — Page structure ─────────────────────────────────────────────

describe('renderMatchPage — Page structure (AC1)', () => {
  it('includes textarea with maxlength 2000', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('maxlength="2000"');
  });

  it('includes submit button with text "Analyser mon projet"', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('Analyser mon projet');
  });

  it('includes character counter element with id char-counter', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="char-counter"');
  });

  it('renders logo img when theme.logo_url is set', () => {
    const html = renderMatchPage(configWithTheme, 'key', 'https://api.example.com');
    expect(html).toContain('<img');
    expect(html).toContain('https://test.example.com/logo.png');
  });

  it('does not render logo img when theme is null', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).not.toContain('<img');
  });

  it('includes loading message element', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="loading-msg"');
  });

  it('includes error div with role alert', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('id="match-error"');
    expect(html).toContain('role="alert"');
  });
});

// ── Group 4: AC7 — PostHog tracking ──────────────────────────────────────────

describe('renderMatchPage — PostHog tracking (AC7)', () => {
  it('includes PostHog head snippet when tracking_enabled and key provided', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('posthog.init');
  });

  it('does not include PostHog head snippet when tracking_enabled is false', () => {
    const html = renderMatchPage(baseConfig, 'test-api-key', 'https://api.example.com');
    expect(html).not.toContain('posthog.init');
  });

  it('does not include PostHog head snippet when posthogApiKey is empty', () => {
    const html = renderMatchPage({ ...baseConfig, tracking_enabled: true }, '', 'https://api.example.com');
    expect(html).not.toContain('posthog.init');
  });

  it('includes satellite.match_page_viewed event name in body script', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('satellite.match_page_viewed');
  });

  it('includes satellite.match_form_submitted event name in form JS', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('satellite.match_form_submitted');
  });

  it('includes satellite.extraction_completed event name in form JS', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('satellite.extraction_completed');
  });

  it('includes satellite.extraction_error event name in form JS', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('satellite.extraction_error');
  });

  it('uses persistence:memory for cookieless tracking', () => {
    const html = renderMatchPage(configWithTheme, 'test-api-key', 'https://api.example.com');
    expect(html).toContain('persistence:"memory"');
  });
});

// ── Group 5: AC2 — Validation constants ──────────────────────────────────────

describe('renderMatchPage — Validation constants (AC2)', () => {
  it('includes min chars threshold of 30 in JS', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('MIN_CHARS=30');
  });

  it('includes warn threshold of 1800 in JS', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('WARN_CHARS=1800');
  });

  it('includes max chars of 2000 in JS', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('MAX_CHARS=2000');
  });

  it('submit button starts as disabled', () => {
    const html = renderMatchPage(baseConfig, '', 'https://api.example.com');
    expect(html).toContain('disabled');
  });
});

// ── Group 6: HTML escaping ───────────────────────────────────────────────────

describe('renderMatchPage — HTML escaping', () => {
  it('escapes <script> in brand.name', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      brand: { name: '<script>alert(1)</script>', tagline: '' },
    };
    const html = renderMatchPage(config, '', 'https://api.example.com');
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
    const html = renderMatchPage(config, '', 'https://api.example.com');
    expect(html).not.toContain('#4F46E5</style>');
    expect(html).toContain('&lt;/style&gt;');
  });
});
