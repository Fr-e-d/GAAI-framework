import { describe, it, expect, vi } from 'vitest';
import { fetchInternalExpert, renderDirectBookingPage } from './direct-booking';
import type { InternalExpertData } from './direct-booking';

const MOCK_EXPERT: InternalExpertData = {
  id: 'abcdef12-1234-5678-abcd-ef1234567890',
  slug: 'exp-abcdef12',
  display_name: 'Alice Expert',
  headline: 'n8n & Python AI Integration Specialist',
  bio: 'I help companies automate their workflows.',
  skills: ['n8n', 'Python', 'Claude', 'OpenAI', 'Docker'],
  languages: ['English', 'French'],
  portfolio_links: ['https://example.com'],
  rate_min: 100,
  rate_max: 200,
  quality_tier: 'established',
  availability: 'available',
  direct_link_token: 'abc123token',
  direct_submissions_this_month: 5,
  attribution: 'direct',
};

describe('fetchInternalExpert', () => {
  it('returns expert data on 200 response with valid token', async () => {
    (globalThis as any).fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(MOCK_EXPERT), { status: 200 }),
    );
    const result = await fetchInternalExpert(
      'https://api.callibrate.io',
      'test-internal-key',
      'exp-abcdef12',
      'valid-token',
    );
    expect(result).toBeTruthy();
    expect(result?.display_name).toBe('Alice Expert');
    expect(result?.attribution).toBe('direct');
  });

  it('returns null on 404 response', async () => {
    (globalThis as any).fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: 'Expert not found' }), { status: 404 }),
    );
    const result = await fetchInternalExpert(
      'https://api.callibrate.io',
      'test-internal-key',
      'exp-notfound',
    );
    expect(result).toBeNull();
  });

  it('returns null on 401 (wrong internal key)', async () => {
    (globalThis as any).fetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 }),
    );
    const result = await fetchInternalExpert(
      'https://api.callibrate.io',
      'wrong-key',
      'exp-abcdef12',
    );
    expect(result).toBeNull();
  });

  it('includes Authorization header in request', async () => {
    const mockFetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(MOCK_EXPERT), { status: 200 }),
    );
    (globalThis as any).fetch = mockFetch;
    await fetchInternalExpert(
      'https://api.callibrate.io',
      'test-internal-key',
      'exp-abcdef12',
    );
    const call = mockFetch.mock.calls[0];
    const headers = call?.[1]?.headers as Record<string, string>;
    expect(headers?.['Authorization']).toBe('Bearer test-internal-key');
  });

  it('includes ?t= param in URL when token is provided', async () => {
    const mockFetch = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(MOCK_EXPERT), { status: 200 }),
    );
    (globalThis as any).fetch = mockFetch;
    await fetchInternalExpert(
      'https://api.callibrate.io',
      'test-internal-key',
      'exp-abcdef12',
      'mytoken123',
    );
    const url = mockFetch.mock.calls[0]?.[0] as string;
    expect(url).toContain('t=mytoken123');
  });

  it('returns null on network error', async () => {
    (globalThis as any).fetch = vi.fn().mockRejectedValue(new Error('Network error'));
    const result = await fetchInternalExpert('https://api.callibrate.io', 'key', 'exp-abcdef12');
    expect(result).toBeNull();
  });
});

describe('renderDirectBookingPage', () => {
  it('returns a valid HTML string', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(typeof html).toBe('string');
    expect(html).toContain('<!DOCTYPE html>');
  });

  it('includes noindex, nofollow robots meta', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('noindex, nofollow');
  });

  it('does NOT include canonical link', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).not.toContain('rel="canonical"');
  });

  it('does NOT include JSON-LD schema', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).not.toContain('application/ld+json');
  });

  it('includes expert display name', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('Alice Expert');
  });

  it('includes expert skills', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('n8n');
    expect(html).toContain('Python');
  });

  it('includes direct link token in hidden field', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('abc123token');
  });

  it('includes attribution in hidden field', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('value="direct"');
  });

  it('includes Turnstile widget with site key', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'my-turnstile-site-key');
    expect(html).toContain('cf-turnstile');
    expect(html).toContain('my-turnstile-site-key');
  });

  it('includes honeypot fields (hidden)', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('name="website"');
    expect(html).toContain('name="phone_backup"');
    expect(html).toContain('tabindex="-1"');
    expect(html).toContain('autocomplete="off"');
  });

  it('includes "Powered by Callibrate" in footer', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('Powered by');
    expect(html).toContain('Callibrate');
  });

  it('does NOT include main nav', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    // No nav links to other pages
    expect(html).not.toContain('<nav>');
  });

  it('includes form_started_at timing field', () => {
    const html = renderDirectBookingPage(MOCK_EXPERT, 'direct', '', 'site-key-test');
    expect(html).toContain('form_started_at');
    expect(html).toContain('Date.now()');
  });

  it('escapes HTML in expert data to prevent XSS', () => {
    const xssExpert = { ...MOCK_EXPERT, display_name: '<script>alert(1)</script>' };
    const html = renderDirectBookingPage(xssExpert, 'direct', '', 'site-key-test');
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });
});
