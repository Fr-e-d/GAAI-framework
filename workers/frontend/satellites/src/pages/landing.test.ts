import { describe, it, expect } from 'vitest';
import { renderLandingPage } from './landing';
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

// AC7b: JSON-LD XSS payload </script><img onerror=...> is escaped
describe('renderLandingPage — JSON-LD XSS protection (AC7b)', () => {
  it('escapes </script> in structured_data to prevent script breakout', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      structured_data: {
        '@type': 'Organization',
        name: '</script><img src=x onerror=alert(1)>',
      },
    };

    const html = renderLandingPage(config, '');

    // The raw XSS payload must not appear verbatim in the output
    expect(html).not.toContain('</script><img');
    // The < character must be unicode-escaped
    expect(html).toContain('\\u003c/script>');
  });

  it('produces valid JSON that a browser would parse correctly after escaping', () => {
    const config: SatelliteConfig = {
      ...baseConfig,
      structured_data: { '@type': 'Organization', name: 'Callibrate<test>' },
    };

    const html = renderLandingPage(config, '');

    // Extract the JSON-LD content between the script tags
    const match = html.match(
      /<script type="application\/ld\+json">([\s\S]*?)<\/script>/
    );
    expect(match).not.toBeNull();
    // The extracted JSON should parse correctly
    const parsed = JSON.parse(match![1]!);
    // JSON.parse converts \u003c back to <
    expect(parsed.name).toBe('Callibrate<test>');
  });

  it('renders no JSON-LD script tag when structured_data is null', () => {
    const html = renderLandingPage(baseConfig, '');
    expect(html).not.toContain('application/ld+json');
  });
});
