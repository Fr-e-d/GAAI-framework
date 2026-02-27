// E06S38: Shared quality tier derivation utility
// Extracted from routes/matches.ts to avoid duplication with dashboard + public endpoints.

export type QualityTier = 'new' | 'rising' | 'established' | 'top';

export function deriveQualityTier(compositeScore: number | null): QualityTier {
  if (!compositeScore || compositeScore === 0) return 'new';
  if (compositeScore <= 25) return 'rising';
  if (compositeScore <= 60) return 'established';
  return 'top';
}
