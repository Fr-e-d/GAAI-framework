import type { SatelliteConfig } from '../types/config';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderLandingPage(config: SatelliteConfig): string {
  const theme = config.theme;
  const brand = config.brand;
  const content = config.content;

  const cssVars = theme
    ? `:root {
      --color-primary: ${escapeHtml(theme.primary)};
      --color-accent: ${escapeHtml(theme.accent)};
      --font-family: ${escapeHtml(theme.font)};
      --radius-card: ${escapeHtml(theme.radius)};
    }`
    : '';

  const logoHtml =
    theme?.logo_url
      ? `<img src="${escapeHtml(theme.logo_url)}" alt="${escapeHtml(brand?.name ?? '')}" class="logo">`
      : '';

  const valuePropsHtml =
    content?.value_props && content.value_props.length > 0
      ? `<ul class="value-props">${content.value_props.map((vp) => `<li>${escapeHtml(vp)}</li>`).join('')}</ul>`
      : '';

  const jsonLdScript =
    config.structured_data
      ? `<script type="application/ld+json">${JSON.stringify(config.structured_data)}</script>`
      : '';

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(content?.meta_title ?? brand?.name ?? 'Callibrate')}</title>
  <meta name="description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta name="robots" content="index, follow">
  <meta property="og:title" content="${escapeHtml(content?.meta_title ?? brand?.name ?? '')}">
  <meta property="og:description" content="${escapeHtml(content?.meta_description ?? '')}">
  <meta property="og:url" content="https://${escapeHtml(config.domain)}/">
  <meta property="og:type" content="website">
  <link rel="canonical" href="https://${escapeHtml(config.domain)}/">
  ${jsonLdScript}
  <style>
    ${cssVars}

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: var(--font-family, 'Inter, sans-serif');
      color: #1a1a2e;
      background: #fafafa;
      line-height: 1.6;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .container {
      max-width: 720px;
      width: 100%;
      padding: 3rem 1.5rem;
      text-align: center;
    }
    .logo {
      max-height: 48px;
      margin-bottom: 1.5rem;
    }
    h1 {
      font-size: 1.25rem;
      font-weight: 600;
      color: var(--color-primary, #4F46E5);
      margin-bottom: 0.5rem;
    }
    h2 {
      font-size: 2rem;
      font-weight: 700;
      line-height: 1.2;
      margin-bottom: 1rem;
      color: #1a1a2e;
    }
    .hero-sub {
      font-size: 1.125rem;
      color: #555;
      margin-bottom: 2rem;
    }
    .value-props {
      list-style: none;
      text-align: left;
      max-width: 480px;
      margin: 0 auto 2.5rem;
    }
    .value-props li {
      padding: 0.5rem 0;
      padding-left: 1.5rem;
      position: relative;
      font-size: 1rem;
      color: #333;
    }
    .value-props li::before {
      content: '';
      position: absolute;
      left: 0;
      top: 50%;
      transform: translateY(-50%);
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--color-accent, #818CF8);
    }
    .cta {
      display: inline-block;
      padding: 0.875rem 2rem;
      background: var(--color-primary, #4F46E5);
      color: #fff;
      text-decoration: none;
      border-radius: var(--radius-card, 0.5rem);
      font-size: 1.0625rem;
      font-weight: 600;
      transition: opacity 0.15s;
    }
    .cta:hover { opacity: 0.9; }
    @media (max-width: 640px) {
      h2 { font-size: 1.5rem; }
      .container { padding: 2rem 1rem; }
    }
  </style>
</head>
<body>
  <main class="container">
    ${logoHtml}
    <h1>${escapeHtml(brand?.name ?? 'Callibrate')}</h1>
    <h2>${escapeHtml(content?.hero_headline ?? '')}</h2>
    <p class="hero-sub">${escapeHtml(content?.hero_sub ?? '')}</p>
    ${valuePropsHtml}
    <a href="/match" class="cta">D\u00e9crire mon projet</a>
  </main>
</body>
</html>`;
}
