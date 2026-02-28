import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderExpertsDirectoryPage } from './experts-directory';
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

const mockExpert = {
  slug: 'exp-abc12345',
  headline: 'Expert en automatisation n8n',
  skills: ['n8n', 'Python', 'Make'],
  industries: ['SaaS', 'E-commerce'],
  rate_min: 80,
  rate_max: 120,
  composite_score: 87,
  quality_tier: 'top',
  completed_projects: 12,
  languages: ['fr', 'en'],
};

const mockApiResponse = {
  experts: [mockExpert],
  total: 1,
  page: 1,
  per_page: 12,
};

// ── Mock fetch ────────────────────────────────────────────────────────────────

beforeEach(() => {
  vi.restoreAllMocks();
});

function mockFetchOk(data: unknown) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    json: async () => data,
  }));
}

function mockFetchError() {
  vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('network error')));
}

// ── AC1: Server-side data fetch ───────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC1: server-side data fetch', () => {
  it('fetches from Core API with vertical param', async () => {
    const fetchSpy = vi.fn().mockResolvedValue({ ok: true, json: async () => mockApiResponse });
    vi.stubGlobal('fetch', fetchSpy);
    await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(fetchSpy).toHaveBeenCalledWith(expect.stringContaining('/api/experts/public'));
    expect(fetchSpy).toHaveBeenCalledWith(expect.stringContaining('vertical=automation'));
  });

  it('renders with expert count in heading', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('1 expert');
    expect(html).toContain('Automatisation');
  });
});

// ── AC2: Directory page structure ─────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC2: page structure', () => {
  it('includes nav links to Accueil and Trouver un expert', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('href="/"');
    expect(html).toContain('Accueil');
    expect(html).toContain('href="/match"');
    expect(html).toContain('Trouver un expert');
  });

  it('includes brand name in header', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('TestBrand');
  });

  it('renders filter bar when skills are present', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('skill-filter');
    expect(html).toContain('data-skill');
  });

  it('renders experts-grid container', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('id="experts-grid"');
    expect(html).toContain('experts-grid');
  });
});

// ── AC3: Expert card content ──────────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC3: expert card', () => {
  it('renders quality tier badge', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('tier--top');
    expect(html).toContain('Top');
  });

  it('renders composite score badge', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('87/100');
  });

  it('renders headline', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('Expert en automatisation n8n');
  });

  it('renders top 3 skills as tags', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('n8n');
    expect(html).toContain('Python');
    expect(html).toContain('Make');
  });

  it('renders rate range', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('80');
    expect(html).toContain('120');
  });

  it('renders "Voir le profil" link pointing to /experts/:slug', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('href="/experts/exp-abc12345"');
    expect(html).toContain('Voir le profil');
  });
});

// ── AC7: SEO ──────────────────────────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC7: SEO', () => {
  it('includes robots index follow meta tag', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('content="index, follow"');
  });

  it('includes canonical URL', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain(`href="https://test.example.com/experts"`);
  });

  it('includes page title with vertical and brand', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('Automatisation');
    expect(html).toContain('TestBrand');
  });

  it('includes JSON-LD ItemList structured data', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('"@type":"ItemList"');
  });

  it('JSON-LD does not contain raw </script> (XSS protection)', async () => {
    const xssConfig: SatelliteConfig = {
      ...baseConfig,
      brand: { name: '</script><img onerror=alert(1)>', tagline: '' },
    };
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(xssConfig, '', 'https://api.test.com');
    expect(html).not.toContain('</script><img');
  });
});

// ── AC9: Empty state ──────────────────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC9: empty state', () => {
  it('renders empty state when no experts returned', async () => {
    mockFetchOk({ experts: [], total: 0, page: 1, per_page: 12 });
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('Aucun expert');
    expect(html).toContain('Réinitialiser les filtres');
    expect(html).toContain('href="/match"');
  });

  it('renders empty state gracefully on API error', async () => {
    mockFetchError();
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('Aucun expert');
    expect(html).not.toContain('undefined');
  });
});

// ── AC6: Load more button ─────────────────────────────────────────────────────

describe('renderExpertsDirectoryPage — AC6: load more', () => {
  it('renders load-more button', async () => {
    mockFetchOk(mockApiResponse);
    const html = await renderExpertsDirectoryPage(baseConfig, '', 'https://api.test.com');
    expect(html).toContain('id="load-more-btn"');
    expect(html).toContain('Charger plus');
  });
});

// ── AC10: E03S05 compliance — robots.txt (tested via robots.ts, not here) ─────
// The robots.txt already blocks /experts/ for PerplexityBot/OAI-SearchBot per E03S05.
// This is verified in the existing robots.ts implementation.
