import type { SatelliteConfig } from '../types/config';

// AC7/AC8 (E03S08): /confirm is now a redirect-only page.
// All funnel logic has been merged into /results (Page 2).
// This file keeps the same function signature for backwards compatibility
// with the /confirm route in index.ts.

export function renderConfirmPage(
  _config: SatelliteConfig,
  _posthogApiKey: string,
  _coreApiUrl: string,
  _turnstileSiteKey: string
): string {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Redirection\u2026</title>
  <meta name="robots" content="noindex, nofollow">
  <meta http-equiv="refresh" content="0;url=/results">
</head>
<body>
  <script>window.location.replace('/results');</script>
</body>
</html>`;
}
