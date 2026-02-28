// E02S12 AC10: Sitemap — includes expert profile URLs
// Fetches expert slugs from the public API (paginated, fail-open on error).
// Changed from sync to async for API calls.

const SITE_URL = 'https://callibrate.io';
const MAX_PAGES = 10;
const PER_PAGE = 50;

interface ExpertListItem {
  slug: string;
}

interface ExpertsApiResponse {
  experts: ExpertListItem[];
  total: number;
  page: number;
  per_page: number;
}

async function fetchExpertSlugs(apiBaseUrl: string): Promise<string[]> {
  const slugs: string[] = [];
  try {
    for (let page = 1; page <= MAX_PAGES; page++) {
      const url = `${apiBaseUrl}/api/experts/public?page=${page}&per_page=${PER_PAGE}`;
      const res = await fetch(url, { headers: { Accept: 'application/json' } });
      if (!res.ok) break;

      const data = await res.json() as ExpertsApiResponse;
      const pageExperts = data.experts ?? [];
      for (const expert of pageExperts) {
        if (expert.slug) slugs.push(expert.slug);
      }

      const totalFetched = (page - 1) * PER_PAGE + pageExperts.length;
      if (totalFetched >= (data.total ?? 0) || pageExperts.length < PER_PAGE) break;
    }
  } catch {
    // Fail-open: return whatever slugs we have so far (may be empty)
  }
  return slugs;
}

export async function renderSitemapXml(apiBaseUrl?: string): Promise<string> {
  const expertSlugs = apiBaseUrl ? await fetchExpertSlugs(apiBaseUrl) : [];

  const staticUrls = [
    `  <url><loc>${SITE_URL}/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>`,
  ];

  const expertUrls = expertSlugs.map(
    (slug) =>
      `  <url><loc>${SITE_URL}/experts/${slug}</loc><changefreq>weekly</changefreq><priority>0.8</priority></url>`,
  );

  const allUrls = [...staticUrls, ...expertUrls].join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${allUrls}
</urlset>`;
}
