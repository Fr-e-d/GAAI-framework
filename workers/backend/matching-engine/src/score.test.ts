import { describe, expect, it } from 'vitest';
import {
  DEFAULT_WEIGHTS,
  OUTCOME_WEIGHT,
  type ExpertPreferences,
  type ExpertProfile,
  type MatchingWeights,
  type ProspectRequirements,
} from './types';
import { scoreMatch, applyReliabilityModifier, scoreOutcomeAlignment } from './score';

// ── Helpers ───────────────────────────────────────────────────────────────────

const emptyProfile: ExpertProfile = {};
const emptyPrefs: ExpertPreferences = {};
const emptyRequirements: ProspectRequirements = {};

// ── scoreMatch — scoring formula ──────────────────────────────────────────────

describe('scoreMatch', () => {
  it('returns score 100 on a perfect match', () => {
    const profile: ExpertProfile = {
      skills: ['n8n', 'python', 'openai'],
      industries: ['fintech'],
      languages: ['en', 'fr'],
      rate_min: 500,
      rate_max: 700,
    };
    const prefs: ExpertPreferences = {
      accepted_timelines: ['urgent', 'flexible'],
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python', 'openai'],
      industry: 'fintech',
      budget_range: { min: 8000, max: 15000 },
      timeline: 'urgent',
      languages: ['en'],
    };

    const result = scoreMatch(profile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(100);
    expect(result.breakdown.deal_breaker).toBeUndefined();
  });

  it('returns score 0 when no criteria match', () => {
    const profile: ExpertProfile = {
      skills: ['java', 'spring'],
      industries: ['logistics'],
      languages: ['de'],
      rate_min: 600,
      rate_max: 800,
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python'],
      industry: 'fintech',
      budget_range: { min: 0, max: 5000 },
      timeline: 'urgent',
      languages: ['fr'],
    };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(0);
    expect(result.breakdown.deal_breaker).toBeUndefined();
    expect(result.breakdown.skills_overlap).toBe(0);
    expect(result.breakdown.industry_match).toBe(0);
    expect(result.breakdown.budget_compatibility).toBe(0);
    expect(result.breakdown.language_match).toBe(0);
  });

  it('returns score 0 with deal_breaker true when industry is excluded', () => {
    const prefs: ExpertPreferences = { excluded_industries: ['gambling'] };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n'],
      industry: 'gambling',
      budget_range: { min: 5000, max: 10000 },
      languages: ['en'],
    };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(0);
    expect(result.breakdown.deal_breaker).toBe(true);
    expect(result.breakdown.skills_overlap).toBe(0);
    expect(result.breakdown.industry_match).toBe(0);
  });

  it('scores partial skills overlap proportionally', () => {
    const profile: ExpertProfile = { skills: ['n8n', 'python'] };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python', 'openai', 'langchain'],
    };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    // skills_overlap = (2/4) * 40 = 20
    expect(result.breakdown.skills_overlap).toBe(20);
    // no timeline requirement → full 10pts
    expect(result.breakdown.timeline_match).toBe(DEFAULT_WEIGHTS.timeline_match);
    // no language requirement → full 10pts
    expect(result.breakdown.language_match).toBe(DEFAULT_WEIGHTS.language_match);
    expect(result.score).toBe(20 + 10 + 10);
  });

  it('handles missing optional fields gracefully without throwing', () => {
    expect(() =>
      scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS),
    ).not.toThrow();

    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.skills_overlap).toBe(0);
    expect(result.breakdown.industry_match).toBe(0);
    expect(result.breakdown.budget_compatibility).toBe(0);
    expect(result.breakdown.timeline_match).toBe(DEFAULT_WEIGHTS.timeline_match);
    expect(result.breakdown.language_match).toBe(DEFAULT_WEIGHTS.language_match);
    expect(result.score).toBe(20);
  });

  it('triggers deal-breaker case-insensitively ("Gambling" vs "gambling")', () => {
    const prefs: ExpertPreferences = { excluded_industries: ['Gambling'] };
    const requirements: ProspectRequirements = { industry: 'gambling' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(0);
    expect(result.breakdown.deal_breaker).toBe(true);
  });
});

// ── scoreMatch — edge cases ───────────────────────────────────────────────────

describe('scoreMatch — edge cases', () => {
  it('resolves skill aliases ("React.js" vs "ReactJS")', () => {
    const profile: ExpertProfile = { skills: ['React.js', 'Node.js'] };
    const requirements: ProspectRequirements = { skills_needed: ['ReactJS', 'nodejs'] };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    // Both map to react + nodejs → 2/2 match → 40pts
    expect(result.breakdown.skills_overlap).toBe(40);
  });

  it('scores industry proximity for related industries (fintech vs banking → 0.8 × 20 = 16)', () => {
    const profile: ExpertProfile = { industries: ['fintech'] };
    const requirements: ProspectRequirements = { industry: 'banking' };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.industry_match).toBe(16);
  });

  it('scores 0 for unrelated industries with no proximity mapping', () => {
    const profile: ExpertProfile = { industries: ['logistics'] };
    const requirements: ProspectRequirements = { industry: 'fintech' };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.industry_match).toBe(0);
  });

  it('scores timeline proximity for parseable timelines ("2 months" vs "3 months" → ~6.67)', () => {
    const prefs: ExpertPreferences = { accepted_timelines: ['3 months'] };
    const requirements: ProspectRequirements = { timeline: '2 months' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    // 60/90 × 10 ≈ 6.67
    expect(result.breakdown.timeline_match).toBeCloseTo(6.67, 1);
  });

  it('falls back to exact string match for non-parseable timelines', () => {
    const prefs: ExpertPreferences = { accepted_timelines: ['custom'] };
    const requirements: ProspectRequirements = { timeline: 'custom' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.timeline_match).toBe(10);
  });

  it('uses configurable budget_conversion_factor', () => {
    const profile: ExpertProfile = { rate_min: 500, rate_max: 700 };
    const requirements: ProspectRequirements = {
      budget_range: { min: 7000, max: 8000 },
    };
    const customWeights: MatchingWeights = {
      ...DEFAULT_WEIGHTS,
      budget_conversion_factor: 15,
    };

    // factor 15: expertMonthly = 7500 → within [7000, 8000] → full 20pts
    const resultFactor15 = scoreMatch(profile, emptyPrefs, requirements, customWeights);
    expect(resultFactor15.breakdown.budget_compatibility).toBe(20);

    // default factor 20: expertMonthly = 10000 → outside [7000, 8000], max 14000 > 7000 → partial 10pts
    const resultFactor20 = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);
    expect(resultFactor20.breakdown.budget_compatibility).toBe(0);
  });

  it('scores partial budget overlap (expert range overlaps prospect range)', () => {
    // expertMonthly = 200*20 = 4000, expertMonthlyMax = 500*20 = 10000
    // budget = [8000, 12000]: expertMonthly 4000 < budgetMin 8000 → no full match
    // but expertMonthlyMax 10000 >= budgetMin 8000 AND expertMonthly 4000 <= budgetMax 12000 → overlap → 0.5×weight
    const profile: ExpertProfile = { rate_min: 200, rate_max: 500 };
    const requirements: ProspectRequirements = {
      budget_range: { min: 8000, max: 12000 },
    };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.budget_compatibility).toBe(DEFAULT_WEIGHTS.budget_compatibility * 0.5);
  });

  it('returns 0 for skills overlap when skills_needed is empty', () => {
    const profile: ExpertProfile = { skills: ['n8n', 'python'] };
    const requirements: ProspectRequirements = { skills_needed: [] };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.skills_overlap).toBe(0);
  });

  it('returns full timeline weight when no timeline requirement', () => {
    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS);
    expect(result.breakdown.timeline_match).toBe(DEFAULT_WEIGHTS.timeline_match);
  });

  it('returns 0 timeline score when expert has no accepted_timelines', () => {
    const requirements: ProspectRequirements = { timeline: 'urgent' };
    const result = scoreMatch(emptyProfile, emptyPrefs, requirements, DEFAULT_WEIGHTS);
    expect(result.breakdown.timeline_match).toBe(0);
  });
});

// ── scoreMatch — score ordering ───────────────────────────────────────────────

describe('scoreMatch — score ordering', () => {
  it('expert with more matching skills scores higher', () => {
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python', 'openai', 'langchain'],
    };
    const profileFull: ExpertProfile = { skills: ['n8n', 'python', 'openai', 'langchain'] };
    const profilePartial: ExpertProfile = { skills: ['n8n', 'python'] };

    const scoreFull = scoreMatch(profileFull, emptyPrefs, requirements, DEFAULT_WEIGHTS).score;
    const scorePartial = scoreMatch(profilePartial, emptyPrefs, requirements, DEFAULT_WEIGHTS).score;

    expect(scoreFull).toBeGreaterThan(scorePartial);
  });

  it('exact industry match scores higher than proximity match', () => {
    const requirements: ProspectRequirements = { industry: 'fintech' };
    const profileExact: ExpertProfile = { industries: ['fintech'] };
    const profileProximity: ExpertProfile = { industries: ['banking'] };

    const scoreExact = scoreMatch(profileExact, emptyPrefs, requirements, DEFAULT_WEIGHTS).score;
    const scoreProximity = scoreMatch(profileProximity, emptyPrefs, requirements, DEFAULT_WEIGHTS).score;

    expect(scoreExact).toBeGreaterThan(scoreProximity);
  });
});

// ── scoreMatch — semantic scoring ─────────────────────────────────────────────

describe('scoreMatch — semantic scoring', () => {
  it('blends 0.7×exact + 0.3×vector for skills_overlap', () => {
    const profile: ExpertProfile = { skills: ['n8n', 'java'] };
    const requirements: ProspectRequirements = { skills_needed: ['n8n', 'python'] };

    // 1/2 exact (0.5) + vector 0.6 → blend = 0.7*0.5 + 0.3*0.6 = 0.53 → 0.53*40 = 21.2
    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS, 0.6);
    expect(result.breakdown.skills_overlap).toBeCloseTo(21.2, 1);
    expect(result.breakdown.semantic_similarity).toBe(0.6);
  });

  it('semantic_similarity stored in breakdown when provided', () => {
    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS, 0.75);
    expect(result.breakdown.semantic_similarity).toBe(0.75);
  });

  it('semantic_similarity absent from breakdown when not provided', () => {
    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS);
    expect(result.breakdown.semantic_similarity).toBeUndefined();
  });

  it('uses vector similarity fallback for unknown industry pairs', () => {
    const profile: ExpertProfile = { industries: ['logistics'] };
    const requirements: ProspectRequirements = { industry: 'fintech' };

    // Without vector: 0
    const noVector = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);
    expect(noVector.breakdown.industry_match).toBe(0);

    // With vector 0.7: 0.7 * 20 = 14
    const withVector = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS, 0.7);
    expect(withVector.breakdown.industry_match).toBeCloseTo(14, 1);
  });
});

// ── scoreMatch — outcome alignment ───────────────────────────────────────────

describe('scoreMatch — outcome alignment', () => {
  it('outcome alignment present: skills_overlap reduced by OUTCOME_WEIGHT, outcome_alignment added', () => {
    const profile: ExpertProfile = { skills: ['n8n', 'python'] };
    const requirements: ProspectRequirements = { skills_needed: ['n8n', 'python'] };

    // Without outcome: skills = 2/2 * 40 = 40; total = 60
    const resultNoOutcome = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);
    expect(resultNoOutcome.breakdown.skills_overlap).toBe(40);

    // With outcome (1.0): skills = 2/2 * (40-OUTCOME_WEIGHT) = 30; outcome = 10; total still 60
    const resultWithOutcome = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS, undefined, 1.0);
    expect(resultWithOutcome.breakdown.skills_overlap).toBe(30);
    expect(resultWithOutcome.breakdown.outcome_alignment).toBe(OUTCOME_WEIGHT);
    expect(resultWithOutcome.score).toBe(resultNoOutcome.score);
  });

  it('null outcomeAlignment: no penalty, outcome_alignment absent from breakdown', () => {
    const profile: ExpertProfile = { skills: ['n8n'] };
    const requirements: ProspectRequirements = { skills_needed: ['n8n'] };

    const resultNull = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS, undefined, null);
    const resultUndefined = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(resultNull.score).toBe(resultUndefined.score);
    expect(resultNull.breakdown.outcome_alignment).toBeUndefined();
    expect(resultNull.breakdown.skills_overlap).toBe(40);
  });

  it('partial outcome alignment contributes proportionally', () => {
    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS, undefined, 0.5);
    expect(result.breakdown.outcome_alignment).toBeCloseTo(5, 5); // 0.5 * 10
  });
});

// ── scoreOutcomeAlignment ─────────────────────────────────────────────────────

describe('scoreOutcomeAlignment', () => {
  it('returns null when expertOutcomeTags is empty', () => {
    expect(scoreOutcomeAlignment([], ['save time'], [[0.9]])).toBeNull();
  });

  it('returns null when prospectDesiredOutcomes is empty', () => {
    expect(scoreOutcomeAlignment(['tag'], [], [])).toBeNull();
  });

  it('returns null when pairwiseSimilarities is empty', () => {
    expect(scoreOutcomeAlignment(['tag'], ['save time'], [])).toBeNull();
  });

  it('returns high score for high pairwise similarities', () => {
    const result = scoreOutcomeAlignment(
      ['25h/week saved on RFP', 'automated lead qualification'],
      ['save time on RFP', 'automate lead qualification'],
      [[0.92, 0.30], [0.25, 0.95]],
    );
    // avg max = (0.92 + 0.95) / 2 = 0.935
    expect(result).not.toBeNull();
    expect(result!).toBeCloseTo(0.935, 2);
  });

  it('picks max similarity across expert tags for each desired outcome', () => {
    const result = scoreOutcomeAlignment(
      ['invoicing automation', 'lead gen', 'data entry reduction'],
      ['reduce invoicing time'],
      [[0.3, 0.2, 0.85]],
    );
    expect(result).toBeCloseTo(0.85, 2);
  });

  it('caps return value at 1.0', () => {
    const result = scoreOutcomeAlignment(['save time'], ['save time'], [[1.1]]);
    expect(result).toBe(1.0);
  });
});

// ── applyReliabilityModifier ──────────────────────────────────────────────────

describe('applyReliabilityModifier', () => {
  const baseScore = {
    score: 80,
    breakdown: {
      skills_overlap: 40, industry_match: 20,
      budget_compatibility: 20, timeline_match: 0, language_match: 0,
    },
  };

  it('returns unchanged score for cold start (< 5 leads)', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 25, total_leads: 3 });
    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBeUndefined();
  });

  it('returns unchanged score when composite_score is null', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: null, total_leads: 10 });
    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBeUndefined();
  });

  it('applies progressive penalty for low composite score (25 → multiplier 0.75)', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 25, total_leads: 10 });
    expect(result.score).toBe(60); // 80 × 0.75
    expect(result.breakdown.reliability_modifier).toBe(0.75);
  });

  it('applies no penalty for high composite score (≥ 50 → modifier 1.0)', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 75, total_leads: 10 });
    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBe(1.0);
  });

  it('returns unchanged score when composite_score is 0', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 0, total_leads: 10 });
    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBeUndefined();
  });
});
