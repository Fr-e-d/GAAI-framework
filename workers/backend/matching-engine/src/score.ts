// ── Scoring engine (ported from core src/matching/score.ts + normalize.ts) ────
// Pure functions — no side effects, no env deps.

import type {
  ExpertPreferences,
  ExpertProfile,
  MatchScore,
  MatchingWeights,
  ProspectRequirements,
  ScoreBreakdown,
} from './types';
import { OUTCOME_WEIGHT } from './types';

// ── Normalize utilities (inlined from core src/matching/normalize.ts) ─────────

const SKILL_ALIASES: Record<string, string> = {
  'react.js': 'react', 'reactjs': 'react',
  'node.js': 'nodejs',
  'vue.js': 'vue', 'vuejs': 'vue',
  'next.js': 'nextjs',
  'nuxt.js': 'nuxtjs',
  'ts': 'typescript',
  'js': 'javascript',
  'py': 'python', 'python3': 'python',
  'gpt-4': 'gpt4', 'gpt-4o': 'gpt4o',
  'open ai': 'openai', 'chat gpt': 'chatgpt', 'chatgpt': 'chatgpt',
  'langchain.js': 'langchain',
  'express.js': 'express', 'expressjs': 'express',
  'angular.js': 'angular', 'angularjs': 'angular',
  'svelte.js': 'svelte',
};

function normalizeSkill(skill: string): string {
  const key = skill.toLowerCase().trim();
  return SKILL_ALIASES[key] ?? key;
}

const INDUSTRY_PROXIMITY: Record<string, number> = {
  'ai|machine-learning': 0.9,
  'banking|fintech': 0.8,
  'e-commerce|retail': 0.9,
  'edtech|education': 0.9,
  'fintech|insurtech': 0.7,
  'healthtech|medtech': 0.85,
  'logistics|supply-chain': 0.8,
  'saas|software': 0.85,
};

function getIndustryProximity(a: string, b: string): number {
  const la = a.toLowerCase().trim();
  const lb = b.toLowerCase().trim();
  if (la === lb) return 1;
  const key = la < lb ? `${la}|${lb}` : `${lb}|${la}`;
  return INDUSTRY_PROXIMITY[key] ?? 0;
}

const TIMELINE_LOOKUP: Record<string, number> = {
  'urgent': 7, 'asap': 7, '1 week': 7,
  '2 weeks': 14, '3 weeks': 21,
  '1 month': 30, '2 months': 60, '3 months': 90,
  '4 months': 120, '6 months': 180, '1 year': 365,
};
const FLEXIBLE_VALUES = new Set(['flexible', 'no rush', 'no deadline', 'whenever']);
const TIMELINE_REGEX = /^(\d+)\s*(days?|weeks?|months?|years?)$/i;

function parseTimelineDays(timeline: string): number | null {
  const normalized = timeline.toLowerCase().trim();
  if (FLEXIBLE_VALUES.has(normalized)) return Infinity;
  const lookupResult = TIMELINE_LOOKUP[normalized];
  if (lookupResult !== undefined) return lookupResult;
  const match = TIMELINE_REGEX.exec(normalized);
  if (match && match[1] && match[2]) {
    const value = parseInt(match[1], 10);
    const unit = match[2].toLowerCase().replace(/s$/, '');
    switch (unit) {
      case 'day': return value;
      case 'week': return value * 7;
      case 'month': return value * 30;
      case 'year': return value * 365;
    }
  }
  return null;
}

// ── scoreMatch ────────────────────────────────────────────────────────────────

export function scoreMatch(
  expertProfile: ExpertProfile,
  expertPreferences: ExpertPreferences,
  prospectRequirements: ProspectRequirements,
  weights: MatchingWeights,
  semanticSimilarity?: number,
  outcomeAlignment?: number | null, // AC11/E06S37: pre-computed outcome alignment (0.0–1.0), null/undefined = no data
): MatchScore {
  const excludedIndustries = (expertPreferences.excluded_industries ?? []).map((i) => i.toLowerCase());
  if (
    prospectRequirements.industry &&
    excludedIndustries.includes(prospectRequirements.industry.toLowerCase())
  ) {
    return {
      score: 0,
      breakdown: {
        skills_overlap: 0, industry_match: 0,
        budget_compatibility: 0, timeline_match: 0, language_match: 0,
        deal_breaker: true,
      },
    };
  }

  // AC11/E06S37: when outcome alignment is available, take OUTCOME_WEIGHT from skills_overlap
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
    breakdown.skills_overlap + breakdown.industry_match +
    breakdown.budget_compatibility + breakdown.timeline_match + breakdown.language_match +
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

// ── Reliability modifier ──────────────────────────────────────────────────────

export interface ReliabilityContext {
  composite_score: number | null;
  total_leads: number;
}

export function applyReliabilityModifier(matchScore: MatchScore, context: ReliabilityContext): MatchScore {
  if (context.total_leads < 5 || context.composite_score == null || context.composite_score === 0) {
    return matchScore;
  }
  if (context.composite_score >= 50) {
    return { score: matchScore.score, breakdown: { ...matchScore.breakdown, reliability_modifier: 1.0 } };
  }
  const multiplier = 0.5 + (context.composite_score / 50) * 0.5;
  return { score: matchScore.score * multiplier, breakdown: { ...matchScore.breakdown, reliability_modifier: multiplier } };
}

// ── Component scorers ─────────────────────────────────────────────────────────

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
  const blendedRatio = semanticSimilarity !== undefined
    ? 0.7 * exactRatio + 0.3 * semanticSimilarity
    : exactRatio;
  return blendedRatio * weight;
}

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
    if (bestProximity === 1) break;
  }
  if (bestProximity > 0) return bestProximity * weight;
  return (semanticSimilarity ?? 0) * weight;
}

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
  if (expertMonthly >= budgetMin && expertMonthly <= budgetMax) return weight;
  const overlaps = expertMonthly <= budgetMax && expertMonthlyMax >= budgetMin;
  if (overlaps) return weight * 0.5;
  return 0;
}

function scoreTimelineMatch(
  preferences: ExpertPreferences,
  requirements: ProspectRequirements,
  weight: number,
): number {
  if (!requirements.timeline) return weight;
  const accepted = preferences.accepted_timelines;
  if (!accepted || accepted.length === 0) return 0;
  if (accepted.map((t) => t.toLowerCase()).includes(requirements.timeline.toLowerCase())) return weight;
  const prospectDays = parseTimelineDays(requirements.timeline);
  if (prospectDays === null) return 0;
  let bestScore = 0;
  for (const t of accepted) {
    const expertDays = parseTimelineDays(t);
    if (expertDays === null) continue;
    if (prospectDays === Infinity && expertDays === Infinity) return weight;
    if (prospectDays === Infinity || expertDays === Infinity) {
      bestScore = Math.max(bestScore, 0.5);
      continue;
    }
    const ratio = Math.min(prospectDays, expertDays) / Math.max(prospectDays, expertDays);
    bestScore = Math.max(bestScore, ratio);
  }
  return bestScore * weight;
}

function scoreLanguageMatch(
  profile: ExpertProfile,
  preferences: ExpertPreferences,
  requirements: ProspectRequirements,
  weight: number,
): number {
  const required = requirements.languages ?? [];
  if (required.length === 0) return weight;
  const expertLangs = [
    ...(profile.languages ?? []),
    ...(preferences.languages ?? []),
  ].map((l) => l.toLowerCase());
  if (expertLangs.length === 0) return 0;
  const matchCount = required.filter((l) => expertLangs.includes(l.toLowerCase())).length;
  return (matchCount / required.length) * weight;
}
