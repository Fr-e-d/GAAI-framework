import type {
  ExpertPreferences,
  ExpertProfile,
  MatchScore,
  MatchingWeights,
  ProspectRequirements,
  ScoreBreakdown,
} from '../types/matching';
import { OUTCOME_WEIGHT } from '../types/matching';
import { normalizeSkill, getIndustryProximity, parseTimelineDays } from './normalize';

// ── scoreMatch — pure function, no side effects ───────────────────────────────
// AC1: scoreMatch(expertProfile, expertPreferences, prospectRequirements, weights): MatchScore
// Returns { score: number (0–100), breakdown: ScoreBreakdown }

export function scoreMatch(
  expertProfile: ExpertProfile,
  expertPreferences: ExpertPreferences,
  prospectRequirements: ProspectRequirements,
  weights: MatchingWeights,
  semanticSimilarity?: number, // AC4/AC5/AC6: cosine similarity from Vectorize (0.0–1.0), undefined in fallback path
  outcomeAlignment?: number | null, // AC11/E06S37: pre-computed outcome alignment (0.0–1.0), null/undefined = no data
): MatchScore {
  // AC6: bi-directional deal-breaker check (short-circuit)
  // Fix DEC-49: case-insensitive comparison
  const excludedIndustries = (expertPreferences.excluded_industries ?? []).map((i) => i.toLowerCase());
  if (
    prospectRequirements.industry &&
    excludedIndustries.includes(prospectRequirements.industry.toLowerCase())
  ) {
    return {
      score: 0,
      breakdown: {
        skills_overlap: 0,
        industry_match: 0,
        budget_compatibility: 0,
        timeline_match: 0,
        language_match: 0,
        deal_breaker: true,
      },
    };
  }

  // AC11/E06S37: when outcome alignment is available, take OUTCOME_WEIGHT from skills_overlap
  // This keeps the total score ceiling at 100 (skills_overlap reduced + outcome_alignment added)
  const hasOutcomeData = outcomeAlignment != null;
  const effectiveSkillsWeight = hasOutcomeData
    ? weights.skills_overlap - OUTCOME_WEIGHT
    : weights.skills_overlap;

  const breakdown: ScoreBreakdown = {
    skills_overlap: scoreSkillsOverlap(expertProfile, prospectRequirements, effectiveSkillsWeight, semanticSimilarity),
    industry_match: scoreIndustryMatch(expertProfile, prospectRequirements, weights.industry_match, semanticSimilarity),
    budget_compatibility: scoreBudgetCompatibility(expertProfile, prospectRequirements, weights),
    timeline_match: scoreTimelineMatch(expertPreferences, prospectRequirements, weights.timeline_match),
    language_match: scoreLanguageMatch(expertProfile, expertPreferences, prospectRequirements, weights.language_match),
    ...(semanticSimilarity !== undefined ? { semantic_similarity: semanticSimilarity } : {}),
    ...(hasOutcomeData ? { outcome_alignment: outcomeAlignment * OUTCOME_WEIGHT } : {}),
  };

  const score =
    breakdown.skills_overlap +
    breakdown.industry_match +
    breakdown.budget_compatibility +
    breakdown.timeline_match +
    breakdown.language_match +
    (hasOutcomeData ? (breakdown.outcome_alignment ?? 0) : 0);

  return { score, breakdown };
}

// ── scoreOutcomeAlignment — pure scoring function (AC8/E06S37) ────────────────
// Takes pre-computed pairwise cosine similarities (rows=desired_outcomes, cols=expert_outcome_tags).
// Returns max-pairwise similarity averaged across desired outcomes (0.0–1.0).
// Returns null when either side has no data (AC10: does not penalize).

export function scoreOutcomeAlignment(
  expertOutcomeTags: string[],
  prospectDesiredOutcomes: string[],
  pairwiseSimilarities: number[][], // [desired_idx][expert_tag_idx] = cosine similarity (0.0–1.0)
): number | null {
  if (expertOutcomeTags.length === 0 || prospectDesiredOutcomes.length === 0) return null;
  if (pairwiseSimilarities.length === 0) return null;

  let totalMaxSim = 0;
  for (let d = 0; d < prospectDesiredOutcomes.length; d++) {
    const sims = pairwiseSimilarities[d] ?? [];
    const maxSim = sims.length > 0 ? Math.max(...sims) : 0;
    totalMaxSim += maxSim;
  }

  return Math.min(1.0, totalMaxSim / prospectDesiredOutcomes.length);
}

// ── Reliability modifier (DEC-50) ───────────────────────────────────────────

export interface ReliabilityContext {
  composite_score: number | null;
  total_leads: number;
}

export function applyReliabilityModifier(
  matchScore: MatchScore,
  context: ReliabilityContext,
): MatchScore {
  // Cold start protection: < 5 leads or no composite data → no penalty
  if (context.total_leads < 5 || context.composite_score == null || context.composite_score === 0) {
    return matchScore;
  }

  // composite >= 50 → no penalty
  if (context.composite_score >= 50) {
    return {
      score: matchScore.score,
      breakdown: { ...matchScore.breakdown, reliability_modifier: 1.0 },
    };
  }

  // composite < 50 → progressive penalty (0.5 to 1.0)
  const multiplier = 0.5 + (context.composite_score / 50) * 0.5;
  return {
    score: matchScore.score * multiplier,
    breakdown: { ...matchScore.breakdown, reliability_modifier: multiplier },
  };
}

// ── Scorers ─────────────────────────────────────────────────────────────────

// AC3: skills_overlap = (matching skills count / prospect.skills_needed.length) * weight
// AC4: blends 0.7 × exactMatch + 0.3 × vectorSimilarity when semanticSimilarity provided
// Uses normalizeSkill() for alias resolution (DEC-49)
function scoreSkillsOverlap(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
  semanticSimilarity?: number,
): number {
  const needed = requirements.skills_needed ?? [];
  if (needed.length === 0) return 0;

  const expertSkills = (profile.skills ?? []).map(normalizeSkill);
  const matchCount = needed.filter((s) => expertSkills.includes(normalizeSkill(s))).length;
  const exactRatio = matchCount / needed.length;

  // AC4: blend 0.7 × exact + 0.3 × vector when semanticSimilarity available
  const blendedRatio = semanticSimilarity !== undefined
    ? 0.7 * exactRatio + 0.3 * semanticSimilarity
    : exactRatio;

  return blendedRatio * weight;
}

// AC4 (original): graduated industry match with proximity scoring (DEC-49)
// Exact match → full weight; proximity match → proximity × weight
// AC5: unknown industry pair (proximity = 0) → use vector similarity as fallback
function scoreIndustryMatch(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
  semanticSimilarity?: number,
): number {
  if (!requirements.industry) return 0;

  const expertIndustries = profile.industries ?? [];
  if (expertIndustries.length === 0) return 0;

  let bestProximity = 0;
  for (const expertInd of expertIndustries) {
    const proximity = getIndustryProximity(expertInd, requirements.industry);
    if (proximity > bestProximity) bestProximity = proximity;
    if (bestProximity === 1) break; // exact match — can't improve
  }

  // AC5: known pair → use proximity; unknown pair → vector similarity fallback
  if (bestProximity > 0) return bestProximity * weight;
  return (semanticSimilarity ?? 0) * weight;
}

// AC5: budget_compatibility with configurable conversion factor (DEC-49)
// full: budget_range.min <= expert.rate_min * factor <= budget_range.max
// partial: ranges overlap → 0.5 * weight
// 0: no overlap or missing data
function scoreBudgetCompatibility(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weights: MatchingWeights,
): number {
  const weight = weights.budget_compatibility;
  const budgetRange = requirements.budget_range;
  if (!budgetRange || profile.rate_min == null) return 0;

  const factor = weights.budget_conversion_factor ?? 20;
  const expertMonthly = profile.rate_min * factor;
  const expertMonthlyMax = (profile.rate_max ?? profile.rate_min) * factor;
  const budgetMin = budgetRange.min ?? 0;
  const budgetMax = budgetRange.max;

  // Full: rate_min * factor falls within budget_range
  if (expertMonthly >= budgetMin && expertMonthly <= budgetMax) {
    return weight;
  }

  // Partial: ranges overlap (expert max reaches into budget, or expert min just exceeds budget max)
  const overlaps = expertMonthly <= budgetMax && expertMonthlyMax >= budgetMin;
  if (overlaps) {
    return weight * 0.5;
  }

  return 0;
}

// timeline_match with temporal proximity (DEC-49)
// Exact string match first (backward compat), then parse to days for proximity scoring
function scoreTimelineMatch(
  preferences: ExpertPreferences,
  requirements: ProspectRequirements,
  weight: number,
): number {
  if (!requirements.timeline) return weight; // no prospect requirement → full points

  const accepted = preferences.accepted_timelines;
  if (!accepted || accepted.length === 0) return 0; // expert hasn't specified → no confirmed match

  // Exact string match (backward compat)
  if (accepted.map((t) => t.toLowerCase()).includes(requirements.timeline.toLowerCase())) {
    return weight;
  }

  // Parse prospect timeline to days
  const prospectDays = parseTimelineDays(requirements.timeline);
  if (prospectDays === null) return 0; // non-parseable, no string match → 0

  // Find best proximity among accepted timelines
  let bestScore = 0;
  for (const t of accepted) {
    const expertDays = parseTimelineDays(t);
    if (expertDays === null) continue;

    // Both flexible → full match
    if (prospectDays === Infinity && expertDays === Infinity) {
      return weight;
    }
    // One flexible, one specific → half points
    if (prospectDays === Infinity || expertDays === Infinity) {
      bestScore = Math.max(bestScore, 0.5);
      continue;
    }
    // Both finite → ratio-based proximity
    const ratio = Math.min(prospectDays, expertDays) / Math.max(prospectDays, expertDays);
    bestScore = Math.max(bestScore, ratio);
  }

  return bestScore * weight;
}

// language_match: proportional overlap between prospect required languages and expert languages
// Full if prospect has no language requirement
function scoreLanguageMatch(
  profile: ExpertProfile,
  preferences: ExpertPreferences,
  requirements: ProspectRequirements,
  weight: number,
): number {
  const required = requirements.languages ?? [];
  if (required.length === 0) return weight; // no requirement → full points

  const expertLangs = [
    ...(profile.languages ?? []),
    ...(preferences.languages ?? []),
  ].map((l) => l.toLowerCase());

  if (expertLangs.length === 0) return 0;

  const matchCount = required.filter((l) => expertLangs.includes(l.toLowerCase())).length;
  return (matchCount / required.length) * weight;
}
