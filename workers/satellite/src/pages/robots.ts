import type { SatelliteConfig } from '../types/config';

export function renderRobotsTxt(config: SatelliteConfig): string {
  return `User-agent: *
Allow: /

# AI training bots — blocked entirely
User-agent: GPTBot
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: Google-Extended
Disallow: /

User-agent: anthropic-ai
Disallow: /

User-agent: ClaudeBot
Disallow: /

# AI answer/search bots — platform pages allowed, expert profiles blocked
User-agent: PerplexityBot
Allow: /
Disallow: /experts/
Disallow: /profiles/

User-agent: OAI-SearchBot
Allow: /
Disallow: /experts/
Disallow: /profiles/

Sitemap: https://${config.domain}/sitemap.xml
`;
}
