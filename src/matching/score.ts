import type {
  ExpertPreferences,
  ExpertProfile,
  MatchScore,
  MatchingWeights,
  ProspectRequirements,
  ScoreBreakdown,
} from '../types/matching';
import { normalizeSkill, getIndustryProximity, parseTimelineDays } from './normalize';

// ── scoreMatch — pure function, no side effects ───────────────────────────────
// AC1: scoreMatch(expertProfile, expertPreferences, prospectRequirements, weights): MatchScore
// Returns { score: number (0–100), breakdown: ScoreBreakdown }

export function scoreMatch(
  expertProfile: ExpertProfile,
  expertPreferences: ExpertPreferences,
  prospectRequirements: ProspectRequirements,
  weights: MatchingWeights,
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

  const breakdown: ScoreBreakdown = {
    skills_overlap: scoreSkillsOverlap(expertProfile, prospectRequirements, weights.skills_overlap),
    industry_match: scoreIndustryMatch(expertProfile, prospectRequirements, weights.industry_match),
    budget_compatibility: scoreBudgetCompatibility(expertProfile, prospectRequirements, weights),
    timeline_match: scoreTimelineMatch(expertPreferences, prospectRequirements, weights.timeline_match),
    language_match: scoreLanguageMatch(expertProfile, expertPreferences, prospectRequirements, weights.language_match),
  };

  const score =
    breakdown.skills_overlap +
    breakdown.industry_match +
    breakdown.budget_compatibility +
    breakdown.timeline_match +
    breakdown.language_match;

  return { score, breakdown };
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
// Uses normalizeSkill() for alias resolution (DEC-49)
function scoreSkillsOverlap(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
): number {
  const needed = requirements.skills_needed ?? [];
  if (needed.length === 0) return 0;

  const expertSkills = (profile.skills ?? []).map(normalizeSkill);
  const matchCount = needed.filter((s) => expertSkills.includes(normalizeSkill(s))).length;

  return (matchCount / needed.length) * weight;
}

// AC4: graduated industry match with proximity scoring (DEC-49)
// Exact match → full weight; proximity match → proximity × weight; unknown pair → 0
function scoreIndustryMatch(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
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

  return bestProximity * weight;
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
