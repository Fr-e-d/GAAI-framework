// ── Admissibility filter — pre-scoring exclusion (E06S36, DEC-80) ────────────
// Applied AFTER billing filters, BEFORE scoring in the matching pipeline.
// Pure function applyAdmissibilityFilters + Hyperdrive query helper loadAdmissibilityData.

import { createSql } from './db';
import type { Env } from '../types/env';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface AdmissibilityCriteria {
  min_project_duration_days?: number;
  required_methodology?: string[];
  excluded_verticals?: string[];
  min_budget?: number;
  required_stack_overlap_min?: number;
  custom_rules?: string[]; // stored but not evaluated (AI interpretation out of scope)
}

export interface AdmissibilityExclusion {
  expert_id: string;
  reason:
    | 'duration_too_short'
    | 'methodology_mismatch'
    | 'vertical_excluded'
    | 'budget_below_minimum'
    | 'stack_overlap_insufficient';
}

export interface ProspectContext {
  industry?: string | null;
  vertical?: string | null;  // satellite vertical (satellite_configs.vertical)
  timeline?: string | null;
  budget_max?: number | null;
  skills_needed?: string[];
  methodology?: string[];    // populated when quiz includes methodology question
}

// ── Timeline parser ───────────────────────────────────────────────────────────
// Maps prospect timeline strings to approximate days.
// Returns null when timeline is absent or unrecognised (→ filter passes, AC8).

export function parseTimelineDays(timeline: string | null | undefined): number | null {
  if (!timeline) return null;
  const t = timeline.toLowerCase().trim();

  if (t.includes('year')) {
    const m = t.match(/(\d+)/);
    return m ? parseInt(m[1] ?? '1', 10) * 365 : 365;
  }
  if (t.includes('month')) {
    // "1-3 months" → use the upper bound (most permissive interpretation for the expert)
    const m = t.match(/(\d+)\s*[-–]\s*(\d+)/);
    if (m) return parseInt(m[2] ?? '1', 10) * 30;
    const single = t.match(/(\d+)/);
    return single ? parseInt(single[1] ?? '1', 10) * 30 : 30;
  }
  if (t.includes('week')) {
    const m = t.match(/(\d+)\s*[-–]\s*(\d+)/);
    if (m) return parseInt(m[2] ?? '1', 10) * 7;
    const single = t.match(/(\d+)/);
    return single ? parseInt(single[1] ?? '1', 10) * 7 : 7;
  }
  if (t.includes('ongoing') || t.includes('long-term') || t.includes('long term')) return 365;
  if (t.includes('short') || t.includes('quick') || t.includes('asap')) return 14;

  return null; // unrecognised → pass
}

// ── Pure filter function ──────────────────────────────────────────────────────

export function applyAdmissibilityFilters<
  T extends { id: string; profile: Record<string, unknown> | null | unknown },
>(
  experts: T[],
  admissibilityMap: Map<string, AdmissibilityCriteria>,
  prospect: ProspectContext,
): { eligible: T[]; excluded: AdmissibilityExclusion[] } {
  const eligible: T[] = [];
  const excluded: AdmissibilityExclusion[] = [];

  for (const expert of experts) {
    const criteria = admissibilityMap.get(expert.id) ?? {};

    // Empty criteria = backward compatible — pass all filters (AC8)
    if (Object.keys(criteria).length === 0) {
      eligible.push(expert);
      continue;
    }

    let exclusionReason: AdmissibilityExclusion['reason'] | null = null;

    // ── AC5.1: min_project_duration_days ──────────────────────────────────────
    if (
      exclusionReason === null &&
      criteria.min_project_duration_days !== undefined &&
      criteria.min_project_duration_days > 0
    ) {
      const durationDays = parseTimelineDays(prospect.timeline);
      // Only exclude if prospect duration is known AND below the minimum
      if (durationDays !== null && durationDays < criteria.min_project_duration_days) {
        exclusionReason = 'duration_too_short';
      }
    }

    // ── AC5.2: required_methodology ───────────────────────────────────────────
    if (
      exclusionReason === null &&
      criteria.required_methodology &&
      criteria.required_methodology.length > 0
    ) {
      const prospectMethodology = prospect.methodology ?? [];
      // Only exclude when prospect has declared a methodology AND there is no overlap
      if (prospectMethodology.length > 0) {
        const prospectLower = prospectMethodology.map((m) => m.toLowerCase());
        const hasOverlap = criteria.required_methodology.some((m) =>
          prospectLower.includes(m.toLowerCase()),
        );
        if (!hasOverlap) {
          exclusionReason = 'methodology_mismatch';
        }
      }
      // Prospect with no methodology declared → pass (AC8)
    }

    // ── AC5.3: excluded_verticals ─────────────────────────────────────────────
    if (
      exclusionReason === null &&
      criteria.excluded_verticals &&
      criteria.excluded_verticals.length > 0
    ) {
      const prospectVertical = (prospect.vertical ?? prospect.industry ?? '').toLowerCase().trim();
      if (prospectVertical) {
        const isExcluded = criteria.excluded_verticals.some(
          (v) =>
            prospectVertical === v.toLowerCase() ||
            prospectVertical.includes(v.toLowerCase()) ||
            v.toLowerCase().includes(prospectVertical),
        );
        if (isExcluded) {
          exclusionReason = 'vertical_excluded';
        }
      }
      // No prospect vertical → pass
    }

    // ── AC5.4: min_budget ─────────────────────────────────────────────────────
    if (
      exclusionReason === null &&
      criteria.min_budget !== undefined &&
      criteria.min_budget > 0
    ) {
      if (prospect.budget_max !== null && prospect.budget_max !== undefined) {
        if (prospect.budget_max < criteria.min_budget) {
          exclusionReason = 'budget_below_minimum';
        }
      }
      // No prospect budget → pass
    }

    // ── AC5.5: required_stack_overlap_min ─────────────────────────────────────
    if (
      exclusionReason === null &&
      criteria.required_stack_overlap_min !== undefined &&
      criteria.required_stack_overlap_min > 0
    ) {
      const profile = expert.profile as Record<string, unknown> | null;
      const expertSkills = (profile?.['skills'] as string[] | undefined) ?? [];
      const prospectSkills = prospect.skills_needed ?? [];

      if (expertSkills.length > 0 && prospectSkills.length > 0) {
        const prospectLower = prospectSkills.map((s) => s.toLowerCase());
        const overlapCount = expertSkills.filter((s) =>
          prospectLower.includes(s.toLowerCase()),
        ).length;
        const overlapFraction = overlapCount / expertSkills.length;
        if (overlapFraction < criteria.required_stack_overlap_min) {
          exclusionReason = 'stack_overlap_insufficient';
        }
      }
      // No expert or prospect skills → pass
    }

    if (exclusionReason === null) {
      eligible.push(expert);
    } else {
      excluded.push({ expert_id: expert.id, reason: exclusionReason });
    }
  }

  return { eligible, excluded };
}

// ── Hyperdrive query helper ───────────────────────────────────────────────────

export async function loadAdmissibilityData(
  env: Env,
  expertIds: string[],
): Promise<Map<string, AdmissibilityCriteria>> {
  if (expertIds.length === 0) return new Map();

  const sql = createSql(env);

  const rows = await sql<{ id: string; admissibility_criteria: unknown }[]>`
    SELECT id, admissibility_criteria FROM experts WHERE id = ANY(${expertIds})`;

  const result = new Map<string, AdmissibilityCriteria>();
  for (const row of rows) {
    result.set(row.id, (row.admissibility_criteria ?? {}) as AdmissibilityCriteria);
  }

  return result;
}
