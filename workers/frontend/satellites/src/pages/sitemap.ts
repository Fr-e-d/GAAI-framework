import type { SatelliteConfig } from '../types/config';

// AC7 (E03S04): Fetch expert slugs from Core API to include individual profile URLs in sitemap.
// CF-edge-cached at 86400s — fetched once per day per edge node.
async function fetchExpertSlugs(coreApiUrl: string, vertical: string | null): Promise<string[]> {
  try {
    const url = new URL(`${coreApiUrl}/api/experts/public`);
    url.searchParams.set('per_page', '50');
    url.searchParams.set('page', '1');
    if (vertical) url.searchParams.set('vertical', vertical);
    const res = await fetch(url.toString());
    if (!res.ok) return [];
    const data = await res.json() as { experts?: { slug: string }[] };
    return (data.experts ?? []).map((e) => e.slug).filter(Boolean);
  } catch {
    return [];
  }
}

export async function renderSitemapXml(
  config: SatelliteConfig,
  coreApiUrl?: string,
): Promise<string> {
  const slugs = coreApiUrl
    ? await fetchExpertSlugs(coreApiUrl, config.vertical)
    : [];

  const expertProfileUrls = slugs.length > 0
    ? slugs.map((slug) => `  <url><loc>https://${config.domain}/experts/${slug}</loc></url>`).join('\n') + '\n'
    : '';

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${config.domain}/</loc></url>
  <url><loc>https://${config.domain}/match</loc></url>
  <url><loc>https://${config.domain}/experts</loc></url>
${expertProfileUrls}</urlset>`;
}
