export function renderRobotsTxt(): string {
  return `# E02S12 AC9: robots.txt — SEO and AI bot policy
# Human search engines: index expert profiles, never index /book/ pages
# AI scrapers: disallow expert profiles to prevent content theft

User-agent: *
Allow: /
Disallow: /book/

# ── Human search engine crawlers (explicit allow for /experts/) ────────────────

User-agent: Googlebot
Allow: /experts/
Disallow: /book/

User-agent: Bingbot
Allow: /experts/
Disallow: /book/

# ── AI scraper bots (disallow expert profiles) ────────────────────────────────

User-agent: PerplexityBot
Disallow: /experts/

User-agent: OAI-SearchBot
Disallow: /experts/

User-agent: GPTBot
Disallow: /

User-agent: Google-Extended
Disallow: /

User-agent: anthropic-ai
Disallow: /

User-agent: Claude-Web
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: ClaudeBot
Disallow: /

Sitemap: https://callibrate.io/sitemap.xml
`;
}
