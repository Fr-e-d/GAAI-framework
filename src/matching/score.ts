import type {
  ExpertPreferences,
  ExpertProfile,
  MatchScore,
  MatchingWeights,
  ProspectRequirements,
  ScoreBreakdown,
} from '../types/matching';

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
  const excludedIndustries = expertPreferences.excluded_industries ?? [];
  if (
    prospectRequirements.industry &&
    excludedIndustries.includes(prospectRequirements.industry)
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
    budget_compatibility: scoreBudgetCompatibility(expertProfile, prospectRequirements, weights.budget_compatibility),
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

// AC3: skills_overlap = (matching skills count / prospect.skills_needed.length) * weight
// Returns 0 if prospect has no skills_needed
function scoreSkillsOverlap(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
): number {
  const needed = requirements.skills_needed ?? [];
  if (needed.length === 0) return 0;

  const expertSkills = (profile.skills ?? []).map((s) => s.toLowerCase());
  const matchCount = needed.filter((s) => expertSkills.includes(s.toLowerCase())).length;

  return (matchCount / needed.length) * weight;
}

// AC4: full points if expert.profile.industries includes prospect.requirements.industry; 0 otherwise
function scoreIndustryMatch(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
): number {
  if (!requirements.industry) return 0;

  const expertIndustries = (profile.industries ?? []).map((i) => i.toLowerCase());
  return expertIndustries.includes(requirements.industry.toLowerCase()) ? weight : 0;
}

// AC5: budget_compatibility
// full: budget_range.min <= expert.rate_min * 20 <= budget_range.max
// partial: [rate_min*20, rate_max*20] partially overlaps budget_range (expert affordable but at edge)
// 0: no overlap or missing data
function scoreBudgetCompatibility(
  profile: ExpertProfile,
  requirements: ProspectRequirements,
  weight: number,
): number {
  const budgetRange = requirements.budget_range;
  if (!budgetRange || profile.rate_min == null) return 0;

  const expertMonthly = profile.rate_min * 20;
  const expertMonthlyMax = (profile.rate_max ?? profile.rate_min) * 20;
  const budgetMin = budgetRange.min ?? 0;
  const budgetMax = budgetRange.max;

  // Full: rate_min * 20 falls within budget_range
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

// timeline_match: full if no prospect timeline requirement;
// full if expert accepts the prospect's timeline; 0 if expert hasn't specified or doesn't accept
function scoreTimelineMatch(
  preferences: ExpertPreferences,
  requirements: ProspectRequirements,
  weight: number,
): number {
  if (!requirements.timeline) return weight; // no prospect requirement → full points

  const accepted = preferences.accepted_timelines;
  if (!accepted || accepted.length === 0) return 0; // expert hasn't specified → no confirmed match

  return accepted.map((t) => t.toLowerCase()).includes(requirements.timeline.toLowerCase())
    ? weight
    : 0;
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
