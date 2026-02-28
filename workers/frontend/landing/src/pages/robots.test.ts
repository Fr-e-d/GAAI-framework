import { describe, it, expect } from 'vitest';
import { renderRobotsTxt } from './robots';

describe('renderRobotsTxt', () => {
  it('returns a non-empty string', () => {
    const result = renderRobotsTxt();
    expect(typeof result).toBe('string');
    expect(result.length).toBeGreaterThan(0);
  });

  it('includes sitemap URL', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('Sitemap: https://callibrate.io/sitemap.xml');
  });

  it('disallows /book/ for all bots', () => {
    const result = renderRobotsTxt();
    // The wildcard User-agent should disallow /book/
    expect(result).toContain('Disallow: /book/');
  });

  it('allows /experts/ for Googlebot', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: Googlebot');
    // Googlebot block should allow /experts/
    const googlebotSection = result.split('User-agent: Googlebot')[1]?.split('User-agent:')[0] ?? '';
    expect(googlebotSection).toContain('Allow: /experts/');
    expect(googlebotSection).toContain('Disallow: /book/');
  });

  it('allows /experts/ for Bingbot', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: Bingbot');
    const bingSection = result.split('User-agent: Bingbot')[1]?.split('User-agent:')[0] ?? '';
    expect(bingSection).toContain('Allow: /experts/');
  });

  it('disallows /experts/ for PerplexityBot', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: PerplexityBot');
    const section = result.split('User-agent: PerplexityBot')[1]?.split('User-agent:')[0] ?? '';
    expect(section).toContain('Disallow: /experts/');
  });

  it('disallows /experts/ for OAI-SearchBot', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: OAI-SearchBot');
    const section = result.split('User-agent: OAI-SearchBot')[1]?.split('User-agent:')[0] ?? '';
    expect(section).toContain('Disallow: /experts/');
  });

  it('disallows everything for GPTBot', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: GPTBot');
    const section = result.split('User-agent: GPTBot')[1]?.split('User-agent:')[0] ?? '';
    expect(section).toContain('Disallow: /');
  });

  it('disallows everything for anthropic-ai', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: anthropic-ai');
    const section = result.split('User-agent: anthropic-ai')[1]?.split('User-agent:')[0] ?? '';
    expect(section).toContain('Disallow: /');
  });

  it('disallows everything for Claude-Web', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: Claude-Web');
  });

  it('disallows everything for Google-Extended', () => {
    const result = renderRobotsTxt();
    expect(result).toContain('User-agent: Google-Extended');
    const section = result.split('User-agent: Google-Extended')[1]?.split('User-agent:')[0] ?? '';
    expect(section).toContain('Disallow: /');
  });
});
