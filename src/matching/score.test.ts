import { describe, expect, it } from 'vitest';
import { DEFAULT_WEIGHTS, type ExpertPreferences, type ExpertProfile, type ProspectRequirements } from '../types/matching';
import { scoreMatch } from './score';

// ── Helpers ───────────────────────────────────────────────────────────────────

const emptyProfile: ExpertProfile = {};
const emptyPrefs: ExpertPreferences = {};
const emptyRequirements: ProspectRequirements = {};

// ── Test cases (AC11) ─────────────────────────────────────────────────────────

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
