import { describe, expect, it } from 'vitest';
import { DEFAULT_WEIGHTS, type ExpertPreferences, type ExpertProfile, type MatchingWeights, type ProspectRequirements } from '../types/matching';
import { scoreMatch, applyReliabilityModifier } from './score';

// ── Helpers ───────────────────────────────────────────────────────────────────

const emptyProfile: ExpertProfile = {};
const emptyPrefs: ExpertPreferences = {};
const emptyRequirements: ProspectRequirements = {};

// ── Existing test cases (AC11) — NON-REGRESSION ─────────────────────────────

describe('scoreMatch', () => {
  // AC11 — full match
  it('returns score 100 on a perfect match', () => {
    const profile: ExpertProfile = {
      skills: ['n8n', 'python', 'openai'],
      industries: ['fintech'],
      languages: ['en', 'fr'],
      rate_min: 500,
      rate_max: 700, // monthly: 10 000 – 14 000
    };
    const prefs: ExpertPreferences = {
      accepted_timelines: ['urgent', 'flexible'],
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python', 'openai'],
      industry: 'fintech',
      budget_range: { min: 8000, max: 15000 }, // expert monthly (10 000) within range
      timeline: 'urgent',
      languages: ['en'],
    };

    const result = scoreMatch(profile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(100);
    expect(result.breakdown.deal_breaker).toBeUndefined();
  });

  // AC11 — zero match
  it('returns score 0 when no criteria match', () => {
    const profile: ExpertProfile = {
      skills: ['java', 'spring'],
      industries: ['logistics'],
      languages: ['de'],
      rate_min: 600,
      rate_max: 800, // monthly: 12 000 – 16 000
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python'],
      industry: 'fintech',
      budget_range: { min: 0, max: 5000 }, // expert monthly (12 000) exceeds max
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

  // AC11 — deal-breaker
  it('returns score 0 with deal_breaker true when industry is excluded', () => {
    const profile: ExpertProfile = {
      skills: ['n8n', 'python'],
      industries: ['gambling'],
      languages: ['en'],
      rate_min: 300,
      rate_max: 400,
    };
    const prefs: ExpertPreferences = {
      excluded_industries: ['gambling'],
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n'],
      industry: 'gambling',
      budget_range: { min: 5000, max: 10000 },
      languages: ['en'],
    };

    const result = scoreMatch(profile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(0);
    expect(result.breakdown.deal_breaker).toBe(true);
    // All components must be 0
    expect(result.breakdown.skills_overlap).toBe(0);
    expect(result.breakdown.industry_match).toBe(0);
  });

  // AC11 — partial skills overlap
  it('scores partial skills overlap proportionally', () => {
    const profile: ExpertProfile = {
      skills: ['n8n', 'python'], // 2 out of 4 required
    };
    const requirements: ProspectRequirements = {
      skills_needed: ['n8n', 'python', 'openai', 'langchain'],
    };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    // skills_overlap = (2/4) * 40 = 20
    expect(result.breakdown.skills_overlap).toBe(20);
    // timeline: no requirements.timeline → full 10pts
    // language: no requirements.languages → full 10pts
    expect(result.breakdown.timeline_match).toBe(DEFAULT_WEIGHTS.timeline_match);
    expect(result.breakdown.language_match).toBe(DEFAULT_WEIGHTS.language_match);
    expect(result.score).toBe(20 + 10 + 10); // skills + timeline + language
  });

  // AC11 — missing optional fields
  it('handles missing optional fields gracefully without throwing', () => {
    expect(() =>
      scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS),
    ).not.toThrow();

    const result = scoreMatch(emptyProfile, emptyPrefs, emptyRequirements, DEFAULT_WEIGHTS);

    // skills_needed empty → 0; no industry → 0; no rates → 0
    // no timeline requirement → full 10; no language requirement → full 10
    expect(result.breakdown.skills_overlap).toBe(0);
    expect(result.breakdown.industry_match).toBe(0);
    expect(result.breakdown.budget_compatibility).toBe(0);
    expect(result.breakdown.timeline_match).toBe(DEFAULT_WEIGHTS.timeline_match);
    expect(result.breakdown.language_match).toBe(DEFAULT_WEIGHTS.language_match);
    expect(result.score).toBe(20); // only timeline + language full points
  });
});

// ── Phase 1 hardening tests (DEC-49) ───────────────────────────────────────

describe('scoreMatch — Phase 1 hardening', () => {
  // 1. Deal-breaker case-insensitive
  it('triggers deal-breaker regardless of case ("Gambling" vs "gambling")', () => {
    const prefs: ExpertPreferences = { excluded_industries: ['Gambling'] };
    const requirements: ProspectRequirements = { industry: 'gambling' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.score).toBe(0);
    expect(result.breakdown.deal_breaker).toBe(true);
  });

  // 2. Skill alias resolution
  it('resolves skill aliases ("React.js" + "Node.js" vs "ReactJS" + "nodejs")', () => {
    const profile: ExpertProfile = { skills: ['React.js', 'Node.js'] };
    const requirements: ProspectRequirements = { skills_needed: ['ReactJS', 'nodejs'] };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    // Both map to react + nodejs → 2/2 match → 40pts
    expect(result.breakdown.skills_overlap).toBe(40);
  });

  // 3. Industry proximity hit (fintech vs banking → 0.8 × 20 = 16)
  it('scores industry proximity for related industries', () => {
    const profile: ExpertProfile = { industries: ['fintech'] };
    const requirements: ProspectRequirements = { industry: 'banking' };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.industry_match).toBe(16); // 0.8 × 20
  });

  // 4. Industry proximity miss (logistics vs fintech → 0)
  it('scores 0 for unrelated industries with no proximity mapping', () => {
    const profile: ExpertProfile = { industries: ['logistics'] };
    const requirements: ProspectRequirements = { industry: 'fintech' };

    const result = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.industry_match).toBe(0);
  });

  // 5. Timeline proximity ("2 months" vs "3 months" → 60/90 × 10 ≈ 6.67)
  it('scores timeline proximity for parseable timelines', () => {
    const prefs: ExpertPreferences = { accepted_timelines: ['3 months'] };
    const requirements: ProspectRequirements = { timeline: '2 months' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    // 60/90 × 10 ≈ 6.67
    expect(result.breakdown.timeline_match).toBeCloseTo(6.67, 1);
  });

  // 6. Timeline string fallback ("custom" vs "custom" → 10pts)
  it('falls back to exact string match for non-parseable timelines', () => {
    const prefs: ExpertPreferences = { accepted_timelines: ['custom'] };
    const requirements: ProspectRequirements = { timeline: 'custom' };

    const result = scoreMatch(emptyProfile, prefs, requirements, DEFAULT_WEIGHTS);

    expect(result.breakdown.timeline_match).toBe(10);
  });

  // 7. Budget custom factor
  it('uses configurable budget_conversion_factor', () => {
    const profile: ExpertProfile = { rate_min: 500, rate_max: 700 };
    // With factor 15: expertMonthly = 500 * 15 = 7500
    const requirements: ProspectRequirements = {
      budget_range: { min: 7000, max: 10000 },
    };
    const customWeights: MatchingWeights = {
      ...DEFAULT_WEIGHTS,
      budget_conversion_factor: 15,
    };

    const result = scoreMatch(profile, emptyPrefs, requirements, customWeights);

    // 7500 within [7000, 10000] → full 20pts
    expect(result.breakdown.budget_compatibility).toBe(20);

    // With default factor 20: expertMonthly = 500 * 20 = 10000 — still within range
    const resultDefault = scoreMatch(profile, emptyPrefs, requirements, DEFAULT_WEIGHTS);
    expect(resultDefault.breakdown.budget_compatibility).toBe(20);

    // With factor 15 and tight budget that excludes default factor
    const tightBudget: ProspectRequirements = {
      budget_range: { min: 7000, max: 8000 },
    };
    const resultFactor15 = scoreMatch(profile, emptyPrefs, tightBudget, customWeights);
    expect(resultFactor15.breakdown.budget_compatibility).toBe(20); // 7500 in [7000, 8000]

    const resultFactor20 = scoreMatch(profile, emptyPrefs, tightBudget, DEFAULT_WEIGHTS);
    expect(resultFactor20.breakdown.budget_compatibility).toBe(0); // 10000 > 8000, max 14000 > 7000 but min 10000 > 8000
  });
});

// ── Reliability modifier tests (DEC-50) ────────────────────────────────────

describe('applyReliabilityModifier', () => {
  const baseScore = { score: 80, breakdown: { skills_overlap: 40, industry_match: 20, budget_compatibility: 20, timeline_match: 0, language_match: 0 } };

  // 8. Cold start — < 5 leads → score unchanged
  it('returns unchanged score for cold start (< 5 leads)', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 25, total_leads: 3 });

    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBeUndefined();
  });

  // 9. Null composite → score unchanged
  it('returns unchanged score when composite_score is null', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: null, total_leads: 10 });

    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBeUndefined();
  });

  // 10. Progressive penalty (composite 25, 10 leads → score × 0.75)
  it('applies progressive penalty for low composite score', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 25, total_leads: 10 });

    expect(result.score).toBe(60); // 80 × 0.75
    expect(result.breakdown.reliability_modifier).toBe(0.75);
  });

  // 11. No penalty (composite 75 → modifier 1.0)
  it('applies no penalty for high composite score', () => {
    const result = applyReliabilityModifier(baseScore, { composite_score: 75, total_leads: 10 });

    expect(result.score).toBe(80);
    expect(result.breakdown.reliability_modifier).toBe(1.0);
  });
});
