import { describe, it, expect } from 'vitest';
import { renderLandingPage } from './landing';

describe('renderLandingPage — SEO head tags (AC10)', () => {
  it('includes correct page title', () => {
    const html = renderLandingPage('');
    expect(html).toContain('Callibrate');
    expect(html).toContain('Pre-qualified leads');
  });

  it('includes meta description', () => {
    const html = renderLandingPage('');
    expect(html).toContain('<meta name="description"');
  });

  it('includes og:title', () => {
    const html = renderLandingPage('');
    expect(html).toContain('property="og:title"');
  });

  it('includes og:description', () => {
    const html = renderLandingPage('');
    expect(html).toContain('property="og:description"');
  });

  it('includes og:image with placeholder URL', () => {
    const html = renderLandingPage('');
    expect(html).toContain('property="og:image"');
    expect(html).toContain('og-image.png');
  });

  it('includes og:url pointing to callibrate.io', () => {
    const html = renderLandingPage('');
    expect(html).toContain('property="og:url"');
    expect(html).toContain('callibrate.io');
  });

  it('includes canonical link', () => {
    const html = renderLandingPage('');
    expect(html).toContain('rel="canonical"');
    expect(html).toContain('https://callibrate.io/');
  });

  it('includes robots index follow', () => {
    const html = renderLandingPage('');
    expect(html).toContain('content="index, follow"');
  });

  it('includes JSON-LD Organization structured data', () => {
    const html = renderLandingPage('');
    expect(html).toContain('application/ld+json');
    expect(html).toContain('"@type":"Organization"');
  });
});

describe('renderLandingPage — PostHog tracking (AC9)', () => {
  it('includes PostHog head snippet when API key provided', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain('posthog.init');
  });

  it('does not include PostHog snippet when API key is empty', () => {
    const html = renderLandingPage('');
    expect(html).not.toContain('posthog.init');
  });

  it('uses persistence memory for cookieless tracking', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain('persistence:"memory"');
  });

  it('fires page_view event on load', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain("posthog.capture('page_view'");
  });

  it('fires landing.cta_clicked on CTA click', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain('landing.cta_clicked');
  });

  it('tracks cta_location property', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain('cta_location');
  });

  it('uses ph.callibrate.io as api_host', () => {
    const html = renderLandingPage('phc_test123');
    expect(html).toContain('https://ph.callibrate.io');
  });
});

describe('renderLandingPage — Hero section (AC3)', () => {
  it('includes hero headline with tire kicker vocabulary', () => {
    const html = renderLandingPage('');
    expect(html).toContain('tire kickers');
  });

  it('includes primary CTA pointing to signup', () => {
    const html = renderLandingPage('');
    expect(html).toContain('https://app.callibrate.io/signup');
  });

  it('includes Commencer CTA text', () => {
    const html = renderLandingPage('');
    expect(html).toContain('Commencer');
  });

  it('CTA has data-cta-location=hero attribute', () => {
    const html = renderLandingPage('');
    expect(html).toContain('data-cta-location="hero"');
  });
});

describe('renderLandingPage — Value propositions (AC4)', () => {
  it('includes pre-qualified leads card', () => {
    const html = renderLandingPage('');
    expect(html.toLowerCase()).toMatch(/leads pr/);
  });

  it('includes pricing range 49 to 263', () => {
    const html = renderLandingPage('');
    expect(html).toContain('49');
    expect(html).toContain('263');
  });

  it('includes Google Calendar integration mention', () => {
    const html = renderLandingPage('');
    expect(html).toContain('Google Calendar');
  });

  it('includes performance dashboard mention', () => {
    const html = renderLandingPage('');
    expect(html).toContain('Dashboard');
  });
});

describe('renderLandingPage — Pricing section (AC5)', () => {
  it('includes all pricing tier values', () => {
    const html = renderLandingPage('');
    expect(html).toContain('49');
    expect(html).toContain('56');
    expect(html).toContain('89');
    expect(html).toContain('102');
    expect(html).toContain('149');
    expect(html).toContain('171');
    expect(html).toContain('229');
    expect(html).toContain('263');
  });

  it('includes 100 welcome credit mention', () => {
    const html = renderLandingPage('');
    expect(html).toContain('100');
  });

  it('mentions no subscription model', () => {
    const html = renderLandingPage('');
    expect(html).toContain('abonnement');
  });

  it('pricing CTA has data-cta-location=pricing', () => {
    const html = renderLandingPage('');
    expect(html).toContain('data-cta-location="pricing"');
  });
});

describe('renderLandingPage — How it works (AC6)', () => {
  it('includes 4 step-number elements', () => {
    const html = renderLandingPage('');
    const matches = html.match(/class="step-number"/g);
    expect(matches).not.toBeNull();
    expect(matches!.length).toBe(4);
  });

  it('mentions profile creation in step 1', () => {
    const html = renderLandingPage('');
    expect(html).toContain('profil');
  });

  it('mentions 7-day flag window in step 3', () => {
    const html = renderLandingPage('');
    expect(html).toContain('7 jours');
  });
});

describe('renderLandingPage — Social proof (AC7)', () => {
  it('includes testimonial placeholder cards', () => {
    const html = renderLandingPage('');
    expect(html).toContain('testimonial-card');
  });

  it('includes 3 placeholder testimonial cards', () => {
    const html = renderLandingPage('');
    const matches = html.match(/class="testimonial-card/g);
    expect(matches).not.toBeNull();
    expect(matches!.length).toBe(3);
  });
});

describe('renderLandingPage — Footer (AC8)', () => {
  it('includes link to app.callibrate.io dashboard', () => {
    const html = renderLandingPage('');
    expect(html).toContain('https://app.callibrate.io');
  });

  it('includes privacy link', () => {
    const html = renderLandingPage('');
    expect(html).toContain('https://callibrate.io/privacy');
  });

  it('includes terms link', () => {
    const html = renderLandingPage('');
    expect(html).toContain('https://callibrate.io/terms');
  });

  it('includes contact email link', () => {
    const html = renderLandingPage('');
    expect(html).toContain('mailto:support@callibrate.io');
  });

  it('includes copyright notice', () => {
    const html = renderLandingPage('');
    expect(html).toContain('2026 Callibrate');
  });

  it('footer CTA has data-cta-location=footer', () => {
    const html = renderLandingPage('');
    expect(html).toContain('data-cta-location="footer"');
  });
});

describe('renderLandingPage — JSON-LD XSS protection', () => {
  it('JSON-LD does not contain unescaped < character', () => {
    const html = renderLandingPage('');
    const match = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
    expect(match).not.toBeNull();
    expect(match![1]).not.toContain('<');
  });

  it('JSON-LD parses correctly after escaping', () => {
    const html = renderLandingPage('');
    const match = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
    expect(match).not.toBeNull();
    const parsed = JSON.parse(match![1]!);
    expect(parsed['@type']).toBe('Organization');
    expect(parsed.name).toBe('Callibrate');
  });
});

describe('renderLandingPage — Mobile responsive (AC12)', () => {
  it('includes max-width 768px media query', () => {
    const html = renderLandingPage('');
    expect(html).toContain('max-width: 768px');
  });

  it('pricing table has overflow-x', () => {
    const html = renderLandingPage('');
    expect(html).toContain('overflow-x');
  });

  it('CTA has min-height 44px for touch targets', () => {
    const html = renderLandingPage('');
    expect(html).toContain('min-height: 44px');
  });
});
