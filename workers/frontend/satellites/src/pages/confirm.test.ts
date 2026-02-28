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

// ── renderConfirmPage — redirect (AC7, AC8) ───────────────────────────────────

describe('renderConfirmPage — redirect (AC7, AC8)', () => {
  it('returns valid HTML', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('<html');
    expect(html).toContain('</html>');
  });

  it('includes meta http-equiv refresh to /results', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('http-equiv="refresh"');
    expect(html).toContain('/results');
  });

  it('includes window.location.replace to /results in JS', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain("window.location.replace('/results')");
  });

  it('does not include Vos besoins identifiés heading', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('Vos besoins');
  });

  it('includes noindex, nofollow robots meta', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).toContain('noindex, nofollow');
  });

  it('does not render logo img (redirect page)', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('<img');
  });

  it('does not include confirm-btn', () => {
    const html = renderConfirmPage(baseConfig, '', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('confirm-btn');
  });

  it('does not include PostHog init (no tracking on redirect)', () => {
    const configWithTracking: SatelliteConfig = { ...baseConfig, tracking_enabled: true };
    const html = renderConfirmPage(configWithTracking, 'test-api-key', 'https://api.example.com', 'site-key');
    expect(html).not.toContain('posthog.init');
  });
});
