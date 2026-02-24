import { describe, it, expect } from 'vitest';
import {
  applyAdmissibilityFilters,
  parseTimelineDays,
} from './admissibilityFilter';
import type { AdmissibilityCriteria, ProspectContext } from './admissibilityFilter';

// ── Test helpers ──────────────────────────────────────────────────────────────

function expert(id: string, skills: string[] = []): { id: string; profile: Record<string, unknown> } {
  return { id, profile: { skills } };
}

function criteria(overrides: Partial<AdmissibilityCriteria> = {}): AdmissibilityCriteria {
  return { ...overrides };
}

function prospect(overrides: Partial<ProspectContext> = {}): ProspectContext {
  return {
    industry: 'saas',
    vertical: null,
    timeline: '3 months',
    budget_max: 50000,
    skills_needed: ['python', 'n8n'],
    methodology: [],
    ...overrides,
  };
}

// ── parseTimelineDays ─────────────────────────────────────────────────────────

describe('parseTimelineDays', () => {
  it('null → null', () => {
    expect(parseTimelineDays(null)).toBeNull();
  });

  it('undefined → null', () => {
    expect(parseTimelineDays(undefined)).toBeNull();
  });

  it('"3 months" → 90', () => {
    expect(parseTimelineDays('3 months')).toBe(90);
  });

  it('"1-3 months" → upper bound → 90', () => {
    expect(parseTimelineDays('1-3 months')).toBe(90);
  });

  it('"6 months" → 180', () => {
    expect(parseTimelineDays('6 months')).toBe(180);
  });

  it('"2 weeks" → 14', () => {
    expect(parseTimelineDays('2 weeks')).toBe(14);
  });

  it('"1-4 weeks" → upper bound → 28', () => {
    expect(parseTimelineDays('1-4 weeks')).toBe(28);
  });

  it('"1 year" → 365', () => {
    expect(parseTimelineDays('1 year')).toBe(365);
  });

  it('"ongoing" → 365', () => {
    expect(parseTimelineDays('ongoing')).toBe(365);
  });

  it('"long-term" → 365', () => {
    expect(parseTimelineDays('long-term')).toBe(365);
  });

  it('"asap" → 14', () => {
    expect(parseTimelineDays('asap')).toBe(14);
  });

  it('"unknown value" → null (unrecognised → pass)', () => {
    expect(parseTimelineDays('unknown value')).toBeNull();
  });
});

// ── Empty criteria = backward compatible (AC8) ────────────────────────────────

describe('applyAdmissibilityFilters — empty criteria (AC8)', () => {
  it('empty map → all experts eligible', () => {
    const experts = [expert('e1'), expert('e2')];
    const { eligible, excluded } = applyAdmissibilityFilters(experts, new Map(), prospect());
    expect(eligible).toHaveLength(2);
    expect(excluded).toHaveLength(0);
  });

  it('criteria={} → expert passes all filters', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', {}]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect());
    expect(eligible).toHaveLength(1);
  });
});

// ── min_project_duration_days (AC5.1) ─────────────────────────────────────────

describe('applyAdmissibilityFilters — min_project_duration_days', () => {
  it('prospect duration >= min → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_project_duration_days: 30 })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(experts, map, prospect({ timeline: '3 months' }));
    expect(eligible).toHaveLength(1);
    expect(excluded).toHaveLength(0);
  });

  it('prospect duration exactly equals min → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_project_duration_days: 90 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ timeline: '3 months' }));
    expect(eligible).toHaveLength(1);
  });

  it('prospect duration < min → excluded', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_project_duration_days: 180 })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(experts, map, prospect({ timeline: '3 months' }));
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'duration_too_short' });
  });

  it('no prospect timeline (null) → pass (AC8)', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_project_duration_days: 180 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ timeline: null }));
    expect(eligible).toHaveLength(1);
  });

  it('unrecognised timeline string → pass (AC8)', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_project_duration_days: 180 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ timeline: 'flexible' }));
    expect(eligible).toHaveLength(1);
  });
});

// ── required_methodology (AC5.2) ──────────────────────────────────────────────

describe('applyAdmissibilityFilters — required_methodology', () => {
  it('prospect methodology overlaps → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ required_methodology: ['agile', 'scrum'] })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ methodology: ['agile', 'waterfall'] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('prospect methodology no overlap → excluded', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ required_methodology: ['modular'] })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ methodology: ['agile', 'waterfall'] }),
    );
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'methodology_mismatch' });
  });

  it('prospect methodology empty → pass (AC8 — backward compatible)', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ required_methodology: ['modular'] })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ methodology: [] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('methodology comparison is case-insensitive', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ required_methodology: ['SCRUM'] })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ methodology: ['scrum'] }),
    );
    expect(eligible).toHaveLength(1);
  });
});

// ── excluded_verticals (AC5.3) ────────────────────────────────────────────────

describe('applyAdmissibilityFilters — excluded_verticals', () => {
  it('prospect vertical not in excluded list → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ excluded_verticals: ['healthcare', 'finance'] })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ industry: 'saas' }));
    expect(eligible).toHaveLength(1);
  });

  it('prospect vertical in excluded list → excluded', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ excluded_verticals: ['healthcare'] })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ industry: 'healthcare' }),
    );
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'vertical_excluded' });
  });

  it('no prospect industry → pass (AC8)', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ excluded_verticals: ['healthcare'] })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ industry: null, vertical: null }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('satellite vertical takes priority when set', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ excluded_verticals: ['finance'] })]]);
    // vertical='finance' should exclude, regardless of industry='saas'
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ industry: 'saas', vertical: 'finance' }),
    );
    expect(excluded[0]?.reason).toBe('vertical_excluded');
  });

  it('vertical comparison is case-insensitive', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ excluded_verticals: ['Healthcare'] })]]);
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ industry: 'healthcare' }),
    );
    expect(excluded[0]?.reason).toBe('vertical_excluded');
  });
});

// ── min_budget (AC5.4) ────────────────────────────────────────────────────────

describe('applyAdmissibilityFilters — min_budget', () => {
  it('prospect budget >= min_budget → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_budget: 10000 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ budget_max: 50000 }));
    expect(eligible).toHaveLength(1);
  });

  it('prospect budget exactly equals min_budget → included', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_budget: 50000 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ budget_max: 50000 }));
    expect(eligible).toHaveLength(1);
  });

  it('prospect budget < min_budget → excluded', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_budget: 50001 })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ budget_max: 50000 }),
    );
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'budget_below_minimum' });
  });

  it('no prospect budget (null) → pass (AC8)', () => {
    const experts = [expert('e1')];
    const map = new Map([['e1', criteria({ min_budget: 100000 })]]);
    const { eligible } = applyAdmissibilityFilters(experts, map, prospect({ budget_max: null }));
    expect(eligible).toHaveLength(1);
  });
});

// ── required_stack_overlap_min (AC5.5) ────────────────────────────────────────

describe('applyAdmissibilityFilters — required_stack_overlap_min', () => {
  it('sufficient overlap → included', () => {
    // expert skills: [python, n8n, docker] → 2/3 overlap with prospect [python, n8n] = 0.67 >= 0.5
    const experts = [expert('e1', ['python', 'n8n', 'docker'])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.5 })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: ['python', 'n8n'] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('exact overlap fraction → included', () => {
    // expert skills: [python, n8n] → 2/2 = 1.0 >= 0.5
    const experts = [expert('e1', ['python', 'n8n'])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.5 })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: ['python', 'n8n', 'react'] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('insufficient overlap → excluded', () => {
    // expert skills: [ruby, rails, postgres] → 0/3 overlap with [python, n8n] = 0.0 < 0.5
    const experts = [expert('e1', ['ruby', 'rails', 'postgres'])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.5 })]]);
    const { eligible, excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: ['python', 'n8n'] }),
    );
    expect(eligible).toHaveLength(0);
    expect(excluded[0]).toMatchObject({ expert_id: 'e1', reason: 'stack_overlap_insufficient' });
  });

  it('no expert skills → pass (AC8)', () => {
    const experts = [expert('e1', [])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.8 })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: ['python'] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('no prospect skills_needed → pass (AC8)', () => {
    const experts = [expert('e1', ['python', 'n8n'])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.8 })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: [] }),
    );
    expect(eligible).toHaveLength(1);
  });

  it('overlap comparison is case-insensitive', () => {
    const experts = [expert('e1', ['Python', 'N8N'])];
    const map = new Map([['e1', criteria({ required_stack_overlap_min: 0.5 })]]);
    const { eligible } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ skills_needed: ['python', 'n8n'] }),
    );
    expect(eligible).toHaveLength(1);
  });
});

// ── Filter ordering (first-failing reason wins) ───────────────────────────────

describe('applyAdmissibilityFilters — check ordering', () => {
  it('duration fails first → reason=duration_too_short', () => {
    const experts = [expert('e1', ['ruby'])];
    const map = new Map([
      [
        'e1',
        criteria({
          min_project_duration_days: 180,
          excluded_verticals: ['saas'],
          min_budget: 200000,
          required_stack_overlap_min: 0.9,
        }),
      ],
    ]);
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ timeline: '1 month' }),
    );
    expect(excluded[0]?.reason).toBe('duration_too_short');
  });

  it('methodology fails before vertical → reason=methodology_mismatch', () => {
    const experts = [expert('e1')];
    const map = new Map([
      [
        'e1',
        criteria({
          required_methodology: ['modular'],
          excluded_verticals: ['saas'],
        }),
      ],
    ]);
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ methodology: ['agile'], industry: 'saas' }),
    );
    expect(excluded[0]?.reason).toBe('methodology_mismatch');
  });

  it('vertical fails before budget → reason=vertical_excluded', () => {
    const experts = [expert('e1')];
    const map = new Map([
      [
        'e1',
        criteria({
          excluded_verticals: ['healthcare'],
          min_budget: 200000,
        }),
      ],
    ]);
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ industry: 'healthcare', budget_max: 10000 }),
    );
    expect(excluded[0]?.reason).toBe('vertical_excluded');
  });

  it('budget fails before stack → reason=budget_below_minimum', () => {
    const experts = [expert('e1', ['ruby'])];
    const map = new Map([
      [
        'e1',
        criteria({
          min_budget: 200000,
          required_stack_overlap_min: 0.9,
        }),
      ],
    ]);
    const { excluded } = applyAdmissibilityFilters(
      experts,
      map,
      prospect({ budget_max: 5000, skills_needed: ['python'] }),
    );
    expect(excluded[0]?.reason).toBe('budget_below_minimum');
  });
});

// ── Mixed pool scenarios (AC9) ────────────────────────────────────────────────

describe('applyAdmissibilityFilters — mixed pool', () => {
  it('all experts excluded → eligible=[], all reasons present', () => {
    const experts = [
      expert('e1', ['ruby']),  // stack_overlap_insufficient
      expert('e2'),            // vertical_excluded
      expert('e3'),            // budget_below_minimum
    ];
    const map = new Map<string, AdmissibilityCriteria>([
      ['e1', criteria({ required_stack_overlap_min: 1.0 })],
      ['e2', criteria({ excluded_verticals: ['saas'] })],
      ['e3', criteria({ min_budget: 200000 })],
    ]);
    const { eligible, excluded } = applyAdmissibilityFilters(experts, map, prospect());
    expect(eligible).toHaveLength(0);
    expect(excluded).toHaveLength(3);
    const reasons = excluded.map((e) => e.reason);
    expect(reasons).toContain('stack_overlap_insufficient');
    expect(reasons).toContain('vertical_excluded');
    expect(reasons).toContain('budget_below_minimum');
  });

  it('partial exclusion → correct split', () => {
    const experts = [expert('e1'), expert('e2'), expert('e3')];
    const map = new Map<string, AdmissibilityCriteria>([
      ['e1', {}],                                          // empty → eligible
      ['e2', criteria({ excluded_verticals: ['saas'] })], // excluded
      ['e3', criteria({ min_budget: 200000 })],           // excluded
    ]);
    const { eligible, excluded } = applyAdmissibilityFilters(experts, map, prospect());
    expect(eligible).toHaveLength(1);
    expect(eligible[0]?.id).toBe('e1');
    expect(excluded).toHaveLength(2);
  });

  it('empty pool → eligible=[], excluded=[]', () => {
    const { eligible, excluded } = applyAdmissibilityFilters([], new Map(), prospect());
    expect(eligible).toHaveLength(0);
    expect(excluded).toHaveLength(0);
  });
});
