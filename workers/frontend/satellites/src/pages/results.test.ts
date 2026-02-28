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

// ── Group 1: Session guard ────────────────────────────────────────────────────

describe('renderResultsPage — Session guard', () => {
  it('reads match:extraction from sessionStorage', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('match:extraction');
  });

  it('redirects to /match when match:extraction is missing', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain("window.location.href='/match'");
  });
});

// ── Group 2: Extraction summary AC4 ──────────────────────────────────────────

describe('renderResultsPage — Extraction summary (AC4)', () => {
  it('includes summary-section element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="summary-section"');
  });

  it('includes summary-collapsed element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="summary-collapsed"');
  });

  it('includes summary-expanded element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="summary-expanded"');
  });

  it('includes fields-container element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="fields-container"');
  });

  it('includes Modifier button', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('Modifier');
  });

  it('includes Fermer button', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('Fermer');
  });

  it('includes confidence-indicator class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('confidence-indicator');
  });

  it('includes field-label class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('field-label');
  });

  it('references FIELD_LABELS in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('FIELD_LABELS');
  });

  it('includes summary-one-liner element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="summary-one-liner"');
  });
});

// ── Group 3: Confirmation questions AC2/AC3 ───────────────────────────────────

describe('renderResultsPage — Confirmation questions (AC2, AC3)', () => {
  it('includes questions-section element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="questions-section"');
  });

  it('includes questions-container element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="questions-container"');
  });

  it('includes confirm-btn element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="confirm-btn"');
  });

  it('limits confirmation questions to max 3', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('displayed>=3');
  });

  it('includes cf-turnstile-container element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="cf-turnstile-container"');
  });

  it('includes Turnstile SDK script in head', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('challenges.cloudflare.com/turnstile/v0/api.js');
  });
});

// ── Group 4: Turnstile AC6 ────────────────────────────────────────────────────

describe('renderResultsPage — Turnstile (AC6)', () => {
  it('loads Turnstile SDK from challenges.cloudflare.com', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('challenges.cloudflare.com/turnstile/v0/api.js');
  });

  it('includes turnstileSiteKey in window.__SAT__', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'my-key-999');
    expect(html).toContain('turnstileSiteKey');
    expect(html).toContain('my-key-999');
  });

  it('includes turnstile.render call in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('turnstile.render');
  });

  it('uses interaction-only appearance', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('interaction-only');
  });

  it('escapes </script> in turnstileSiteKey to prevent XSS', () => {
    const maliciousKey = 'key</script><script>alert(1)';
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', maliciousKey);
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });
});

// ── Group 5: Match loading AC1 ────────────────────────────────────────────────

describe('renderResultsPage — Match loading (AC1)', () => {
  it('includes matches-loading element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="matches-loading"');
  });

  it('includes skeleton-card class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('skeleton-card');
  });

  it('includes shimmer CSS animation', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('shimmer');
  });

  it('includes 3 skeleton cards', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    const count = (html.match(/class="skeleton-card"/g) || []).length;
    expect(count).toBe(3);
  });
});

// ── Group 6: Computing state AC2 ──────────────────────────────────────────────

describe('renderResultsPage — Computing state (AC2)', () => {
  it('includes computing-msg element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="computing-msg"');
  });

  it('includes "Nous affinons les correspondances" text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('Nous affinons les correspondances');
  });

  it('includes MAX_RETRIES=3', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('MAX_RETRIES=3');
  });

  it('includes exponential backoff logic', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('Math.pow(2,retryCount)');
  });

  it('includes no-available-msg element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="no-available-msg"');
  });

  it('includes computing timeout fallback text', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('Le calcul des correspondances prend plus de temps');
  });
});

// ── Group 7: Match cards AC3 ──────────────────────────────────────────────────

describe('renderResultsPage — Match cards (AC3)', () => {
  it('includes match-card class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('match-card');
  });

  it('includes rank-badge--1, --2, --3 classes', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('rank-badge--1');
    expect(html).toContain('rank-badge--2');
    expect(html).toContain('rank-badge--3');
  });

  it('includes tier--top, tier--confirmed, tier--promising classes', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('tier--top');
    expect(html).toContain('tier--confirmed');
    expect(html).toContain('tier--promising');
  });

  it('includes score-bar-track and score-bar-fill classes', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('score-bar-track');
    expect(html).toContain('score-bar-fill');
  });

  it('references criteria_scores in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('criteria_scores');
  });

  it('references skills_matched in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('skills_matched');
  });
});

// ── Group 8: No matches ───────────────────────────────────────────────────────

describe('renderResultsPage — No matches', () => {
  it('includes no-matches element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="no-matches"');
  });

  it('includes link to /experts directory', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('href="/experts"');
  });
});

// ── Group 9: Email gate + OTP (E06S39) ───────────────────────────────────────

describe('renderResultsPage — Email gate + OTP (AC4, E06S39)', () => {
  it('includes email-gate-section element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="email-gate-section"');
  });

  it('includes email-input of type email', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="email-input"');
    expect(html).toContain('type="email"');
  });

  it('includes unlock-btn button', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="unlock-btn"');
  });

  it('includes otp-section element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="otp-section"');
  });

  it('includes reference to /otp/send endpoint', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('/otp/send');
  });

  it('includes reference to /otp/verify endpoint', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('/otp/verify');
  });

  it('includes email-gate-section hidden by default', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="email-gate-section"');
    expect(html).toContain('style="display:none"');
  });

  it('includes resend-otp-btn element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="resend-otp-btn"');
  });

  it('includes verify-otp-btn element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="verify-otp-btn"');
  });
});

// ── Group 10: Full profile reveal AC5 ────────────────────────────────────────

describe('renderResultsPage — Full profile reveal (AC5)', () => {
  it('includes avatar-initial class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('avatar-initial');
  });

  it('includes booking-btn class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('booking-btn');
  });

  it('includes bio-text class', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('bio-text');
  });

  it('references display_name in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('display_name');
  });

  it('references expert.bio in JS', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('expert.bio');
  });

  it('dispatches booking-open custom event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('booking-open');
    expect(html).toContain('CustomEvent');
  });
});

// ── Group 11: PostHog AC9 ─────────────────────────────────────────────────────

describe('renderResultsPage — PostHog events (AC9)', () => {
  it('includes satellite.funnel_page2_loaded event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.funnel_page2_loaded');
  });

  it('includes satellite.extraction_edited event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.extraction_edited');
  });

  it('includes satellite.rematch_triggered event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.rematch_triggered');
  });

  it('includes satellite.matches_viewed event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.matches_viewed');
  });

  it('includes satellite.profiles_unlocked event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.profiles_unlocked');
  });

  it('includes satellite.matching_error event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.matching_error');
  });

  it('includes satellite.email_gate_submitted event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.email_gate_submitted');
  });

  it('includes satellite.prospect_created event', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.prospect_created');
  });

  it('includes PostHog head snippet when tracking enabled and key provided', () => {
    const html = renderResultsPage(configWithTheme, 'test-api-key', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('posthog.init');
  });

  it('does not include PostHog snippet when tracking_enabled is false', () => {
    const html = renderResultsPage(baseConfig, 'test-api-key', 'https://api.example.com', 'test-site-key');
    expect(html).not.toContain('posthog.init');
  });

  it('uses persistence:"memory" for cookieless tracking', () => {
    const html = renderResultsPage(configWithTheme, 'test-api-key', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('persistence:"memory"');
  });
});

// ── Group 12: Re-match AC5 ────────────────────────────────────────────────────

describe('renderResultsPage — Re-match (AC5)', () => {
  it('includes reference to /requirements endpoint', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('/requirements');
  });

  it('includes satellite.extraction_edited event for re-match trigger', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.extraction_edited');
  });

  it('includes satellite.rematch_triggered event for re-match', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('satellite.rematch_triggered');
  });

  it('includes extraction_edit source in rematch trigger', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('extraction_edit');
  });
});

// ── Group 13: Security ────────────────────────────────────────────────────────

describe('renderResultsPage — Security', () => {
  it('escapes <script> in brand.name', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      brand: { name: '<script>alert(1)</script>', tagline: '' },
    };
    const html = renderResultsPage(config, '', 'https://api.example.com', 'test-site-key');
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
    const html = renderResultsPage(config, '', 'https://api.example.com', 'test-site-key');
    expect(html).not.toContain('#4F46E5</style>');
    expect(html).toContain('&lt;/style&gt;');
  });

  it('escapes </script> in coreApiUrl to prevent script injection', () => {
    const maliciousUrl = 'https://evil.com</script><script>alert(1)';
    const html = renderResultsPage(baseConfig, '', maliciousUrl, 'test-site-key');
    expect(html).not.toContain('</script><script>');
    expect(html).toContain('\\u003c/script>');
  });
});

// ── Group 14: window.__SAT__ ──────────────────────────────────────────────────

describe('renderResultsPage — window.__SAT__', () => {
  it('includes window.__SAT__ assignment', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('window.__SAT__');
  });

  it('includes apiUrl in __SAT__', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('"apiUrl"');
  });

  it('includes satelliteId in __SAT__', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('"satelliteId"');
  });

  it('includes turnstileSiteKey in __SAT__', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('turnstileSiteKey');
  });
});

// ── Group 15: Logo rendering ──────────────────────────────────────────────────

describe('renderResultsPage — Logo rendering', () => {
  it('renders logo img when theme.logo_url is set', () => {
    const html = renderResultsPage(configWithTheme, 'key', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('<img');
    expect(html).toContain('https://test.example.com/logo.png');
  });

  it('does not render logo img when theme is null', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).not.toContain('<img');
  });
});

// ── Group 16: Robots meta ─────────────────────────────────────────────────────

describe('renderResultsPage — Robots meta', () => {
  it('includes noindex, nofollow robots meta', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('noindex, nofollow');
  });

  it('does not include canonical link', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).not.toContain('rel="canonical"');
  });
});

// ── Group 17: Error states ────────────────────────────────────────────────────

describe('renderResultsPage — Error states', () => {
  it('includes fetch-error element with role alert', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="fetch-error"');
    expect(html).toContain('role="alert"');
  });

  it('includes retry-btn element', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('id="retry-btn"');
  });

  it('includes 409 handling (already identified)', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('res.status===409');
  });

  it('includes networkErrorRetried variable', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('networkErrorRetried');
  });

  it('includes computing_timeout error type', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('computing_timeout');
  });

  it('includes server_5xx error type', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain('server_5xx');
  });

  it('includes page:results property', () => {
    const html = renderResultsPage(baseConfig, '', 'https://api.example.com', 'test-site-key');
    expect(html).toContain("page:'results'");
  });
});
