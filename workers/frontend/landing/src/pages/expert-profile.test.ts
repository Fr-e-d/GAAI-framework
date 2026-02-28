import { describe, it, expect, vi } from 'vitest';
import { fetchPublicExpert, renderExpertProfilePage } from './expert-profile';
import type { PublicExpertData } from './expert-profile';

const MOCK_EXPERT: PublicExpertData = {
  slug: 'exp-abcdef12',
  headline: 'n8n & Python AI Integration Expert',
  skills: ['n8n', 'Python', 'Claude', 'OpenAI', 'Docker'],
  industries: ['SaaS', 'E-commerce'],
  rate_min: 100,
  rate_max: 200,
  quality_tier: 'established',
  completed_projects: 12,
  languages: ['English', 'French'],
  bio_excerpt: 'I help SaaS companies build AI-powered automation workflows using n8n and Python.',
  availability_status: 'available',
  outcome_tags: ['Lead generation automation', 'CRM integration'],
  direct_link_url: 'https://callibrate.io/book/exp-abcdef12?t=abc123',
};

describe('fetchPublicExpert', () => {
  it('returns expert data on 200 response', async () => {
    (globalThis as any).fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(MOCK_EXPERT), { status: 200 }),
    );
    const result = await fetchPublicExpert('https://api.callibrate.io', 'exp-abcdef12');
    expect(result).toBeTruthy();
    expect(result?.slug).toBe('exp-abcdef12');
    expect(result?.skills).toContain('n8n');
  });

  it('returns null on 404 response', async () => {
    (globalThis as any).fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: 'Expert not found' }), { status: 404 }),
    );
    const result = await fetchPublicExpert('https://api.callibrate.io', 'exp-notfound');
    expect(result).toBeNull();
  });

  it('returns null on network error', async () => {
    (globalThis as any).fetch = vi.fn().mockRejectedValue(new Error('Network error'));
    const result = await fetchPublicExpert('https://api.callibrate.io', 'exp-abcdef12');
    expect(result).toBeNull();
  });
});

describe('renderExpertProfilePage', () => {
  it('returns a valid HTML string', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(typeof html).toBe('string');
    expect(html).toContain('<!DOCTYPE html>');
  });

  it('includes canonical URL with expert slug', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('canonical');
    expect(html).toContain('exp-abcdef12');
  });

  it('includes JSON-LD Person schema', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('"@type":"Person"');
    expect(html).toContain('n8n');
  });

  it('includes robots meta with index,follow,max-snippet:150', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('index, follow, max-snippet:150');
  });

  it('includes quality tier badge', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('Established Expert');
  });

  it('includes rate range', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('\u20ac100');
    expect(html).toContain('\u20ac200');
  });

  it('includes top 5 skills', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('n8n');
    expect(html).toContain('Python');
    expect(html).toContain('Claude');
  });

  it('includes bio excerpt', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('SaaS companies');
  });

  it('includes direct booking CTA when direct_link_url is present', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).toContain('Book directly');
    expect(html).toContain('https://callibrate.io/book/exp-abcdef12?t=abc123');
  });

  it('shows only Callibrate CTA when no direct_link_url', () => {
    const expertNoLink = { ...MOCK_EXPERT, direct_link_url: null };
    const html = renderExpertProfilePage(expertNoLink, '');
    expect(html).not.toContain('Book directly');
    expect(html).toContain('Get matched via Callibrate');
  });

  it('includes PostHog snippet when key is provided', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, 'phk_test123');
    expect(html).toContain('posthog');
    expect(html).toContain('expert_profile');
  });

  it('does not include PostHog snippet when key is empty', () => {
    const html = renderExpertProfilePage(MOCK_EXPERT, '');
    expect(html).not.toContain('posthog.init');
  });

  it('escapes HTML in expert data to prevent XSS', () => {
    const xssExpert = { ...MOCK_EXPERT, headline: '<script>alert(1)</script>' };
    const html = renderExpertProfilePage(xssExpert, '');
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });

  it('handles missing optional fields gracefully', () => {
    const minimalExpert: PublicExpertData = {
      slug: 'exp-minimal1',
      headline: null,
      skills: [],
      industries: [],
      rate_min: null,
      rate_max: null,
      quality_tier: 'new',
      completed_projects: 0,
      languages: [],
      bio_excerpt: null,
      availability_status: null,
      outcome_tags: [],
      direct_link_url: null,
    };
    const html = renderExpertProfilePage(minimalExpert, '');
    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('New Expert');
    expect(html).toContain('Rate on request');
  });
});
