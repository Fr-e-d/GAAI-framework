import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderExpertProfilePage } from './experts-profile';
import type { SatelliteConfig } from '../types/config';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const baseConfig: SatelliteConfig = {
  id: 'test-satellite',
  domain: 'test.example.com',
  label: 'Test Satellite',
  vertical: 'automation',
  active: true,
  theme: {
    primary: '#4F46E5',
    accent: '#818CF8',
    font: 'Inter, sans-serif',
    radius: '0.5rem',
    logo_url: null,
  },
  brand: { name: 'TestBrand', tagline: 'Test tagline' },
  content: {
    meta_title: 'Test',
    meta_description: 'Test description',
    hero_headline: 'Hero',
    hero_sub: 'Sub',
    value_props: [],
    vertical_label: 'Automatisation',
  },
  structured_data: null,
  quiz_schema: null,
  matching_weights: null,
  tracking_enabled: false,
};

const mockExpertDetail = {
  slug: 'exp-abc12345',
  headline: 'Expert en automatisation n8n',
  skills: ['n8n', 'Python', 'Make', 'Zapier'],
  industries: ['SaaS', 'E-commerce'],
  rate_min: 80,
  rate_max: 120,
  composite_score: 87,
  quality_tier: 'top',
  completed_projects: 12,
  languages: ['fr', 'en'],
  bio_excerpt: 'Spécialiste en automatisation des processus métier avec 5 ans d\'expérience.',
  availability_status: 'available',
  outcome_tags: ['lead-gen', 'data-sync'],
  direct_booking_url: null,
};

// ── Mock fetch ────────────────────────────────────────────────────────────────

beforeEach(() => {
  vi.restoreAllMocks();
});

function mockFetchOk(data: unknown) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => data,
  }));
}

function mockFetch404() {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: false,
    status: 404,
    json: async () => ({ error: 'Expert not found' }),
  }));
}

function mockFetchError() {
  vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('network error')));
}

// ── AC4: Profile page structure ───────────────────────────────────────────────

describe('renderExpertProfilePage — AC4: profile page structure', () => {
  it('returns status 200 for a valid expert', async () => {
    mockFetchOk(mockExpertDetail);
    const { status } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(status).toBe(200);
  });

  it('returns status 404 when expert not found', async () => {
    mockFetch404();
    const { status } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-notexist');
    expect(status).toBe(404);
  });

  it('returns status 500 on network error', async () => {
    mockFetchError();
    const { status } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(status).toBe(500);
  });

  it('renders anonymized avatar (initial-based)', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('class="avatar"');
    // Initial is first char of headline
    expect(html).toContain('>E<'); // 'Expert...' → 'E'
  });

  it('renders quality tier badge', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('tier--top');
    expect(html).toContain('Top Expert');
  });

  it('renders composite score', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('87/100');
  });

  it('renders headline', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Expert en automatisation n8n');
  });

  it('renders full skills list', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('n8n');
    expect(html).toContain('Python');
    expect(html).toContain('Make');
    expect(html).toContain('Zapier');
  });

  it('renders industries', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('SaaS');
    expect(html).toContain('E-commerce');
  });

  it('renders rate range', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('80');
    expect(html).toContain('120');
  });

  it('renders bio excerpt', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Spécialiste en automatisation');
  });

  it('renders languages', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('fr');
    expect(html).toContain('en');
  });

  it('renders availability indicator "Disponible" for available status', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Disponible');
    expect(html).toContain('avail--available');
  });

  it('renders "Disponible prochainement" for available_soon status', async () => {
    mockFetchOk({ ...mockExpertDetail, availability_status: 'available_soon' });
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Disponible prochainement');
    expect(html).toContain('avail--soon');
  });
});

// ── AC4: CTAs ─────────────────────────────────────────────────────────────────

describe('renderExpertProfilePage — AC4: CTAs', () => {
  it('renders primary CTA "Vérifier la compatibilité" → /match', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('id="cta-match-btn"');
    expect(html).toContain('href="/match"');
    expect(html).toContain('V\u00e9rifier la compatibilit\u00e9');
  });

  it('renders secondary CTA "Débloquer ce profil" with unlock form', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('id="unlock-trigger-btn"');
    expect(html).toContain('D\u00e9bloquer ce profil');
    expect(html).toContain('id="unlock-form"');
    expect(html).toContain('id="unlock-email"');
    expect(html).toContain('id="unlock-submit-btn"');
  });

  it('unlock form calls create-from-directory endpoint', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('create-from-directory');
  });
});

// ── AC11: Direct booking CTA ──────────────────────────────────────────────────

describe('renderExpertProfilePage — AC11: direct booking CTA', () => {
  it('does NOT render direct CTA when direct_booking_url is null', async () => {
    mockFetchOk({ ...mockExpertDetail, direct_booking_url: null });
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    // The CTA link text must not appear — .cta-direct is a CSS class defined in the stylesheet so we check text instead
    expect(html).not.toContain('Prendre un rendez-vous direct');
  });

  it('renders direct CTA as link when direct_booking_url is provided', async () => {
    mockFetchOk({ ...mockExpertDetail, direct_booking_url: 'https://callibrate.io/book/exp-abc12345?t=token123' });
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Prendre un rendez-vous direct');
    expect(html).toContain('cta-direct');
    expect(html).toContain('https://callibrate.io/book/exp-abc12345');
  });
});

// ── AC7: SEO ──────────────────────────────────────────────────────────────────

describe('renderExpertProfilePage — AC7: SEO', () => {
  it('includes robots index follow', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('content="index, follow"');
  });

  it('includes canonical URL with slug', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('https://test.example.com/experts/exp-abc12345');
  });

  it('includes page title with tier and top skill', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('Top Expert');
    expect(html).toContain('TestBrand');
  });

  it('includes JSON-LD Person structured data', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('"@type":"Person"');
  });

  it('JSON-LD does not contain raw </script> (XSS protection)', async () => {
    const xssExpert = {
      ...mockExpertDetail,
      headline: '</script><script>alert(1)</script>',
      bio_excerpt: '<script>evil()</script>',
    };
    mockFetchOk(xssExpert);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).not.toContain('</script><script>alert(1)</script>');
  });
});

// ── AC8: PostHog events ───────────────────────────────────────────────────────

describe('renderExpertProfilePage — AC8: PostHog events', () => {
  it('includes satellite.expert_profile_viewed event', async () => {
    const configWithTracking = { ...baseConfig, tracking_enabled: true };
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(configWithTracking, 'ph-key-test', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('satellite.expert_profile_viewed');
    expect(html).toContain('exp-abc12345');
  });

  it('includes satellite.expert_cta_match_clicked event', async () => {
    const configWithTracking = { ...baseConfig, tracking_enabled: true };
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(configWithTracking, 'ph-key-test', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('satellite.expert_cta_match_clicked');
  });

  it('includes satellite.expert_cta_unlock_clicked event', async () => {
    const configWithTracking = { ...baseConfig, tracking_enabled: true };
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(configWithTracking, 'ph-key-test', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('satellite.expert_cta_unlock_clicked');
  });

  it('does not inject posthog script when tracking_enabled is false', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, 'ph-key-test', 'https://api.test.com', 'exp-abc12345');
    expect(html).not.toContain('posthog.init');
  });
});

// ── Back link ─────────────────────────────────────────────────────────────────

describe('renderExpertProfilePage — navigation', () => {
  it('renders back link to /experts', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('href="/experts"');
    expect(html).toContain('Retour au répertoire');
  });

  it('includes nav links', async () => {
    mockFetchOk(mockExpertDetail);
    const { html } = await renderExpertProfilePage(baseConfig, '', 'https://api.test.com', 'exp-abc12345');
    expect(html).toContain('href="/"');
    expect(html).toContain('href="/match"');
  });
});
