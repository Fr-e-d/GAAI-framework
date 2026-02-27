export function renderRobotsTxt(): string {
  return `User-agent: *
Allow: /

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

User-agent: PerplexityBot
Allow: /

User-agent: OAI-SearchBot
Allow: /

Sitemap: https://callibrate.io/sitemap.xml
`;
}
