import type { SatelliteConfig } from '../types/config';

export function renderSitemapXml(config: SatelliteConfig): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${config.domain}/</loc></url>
  <url><loc>https://${config.domain}/match</loc></url>
  <url><loc>https://${config.domain}/experts</loc></url>
</urlset>`;
}
