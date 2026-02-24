// ── Shared types for the callibrate-matching Worker ───────────────────────────

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

// Expert pool entry (subset of experts table used for scoring)
export interface ExpertPoolEntry {
  id: string;
  profile: Json | null;
  preferences: Json | null;
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number;
}

// ── Matching domain types (mirrors core src/types/matching.ts) ─────────────────

export interface ExpertProfile {
  industries?: string[];
  skills?: string[];
  project_types?: string[];
  languages?: string[];
  rate_min?: number | null;
  rate_max?: number | null;
}

export interface ExpertPreferences {
  excluded_industries?: string[];
  languages?: string[];
  accepted_timelines?: string[];
}

export interface BudgetRange {
  min?: number;
  max: number;
}

export interface ProspectRequirements {
  challenge?: string;
  skills_needed?: string[];
  industry?: string;
  budget_range?: BudgetRange;
  timeline?: string;
  company_size?: string;
  languages?: string[];
}

export interface MatchingWeights {
  skills_overlap: number;
  industry_match: number;
  budget_compatibility: number;
  timeline_match: number;
  language_match: number;
  budget_conversion_factor?: number;
}

export const DEFAULT_WEIGHTS: MatchingWeights = {
  skills_overlap: 40,
  industry_match: 20,
  budget_compatibility: 20,
  timeline_match: 10,
  language_match: 10,
  budget_conversion_factor: 20,
};

export interface ScoreBreakdown {
  skills_overlap: number;
  industry_match: number;
  budget_compatibility: number;
  timeline_match: number;
  language_match: number;
  deal_breaker?: boolean;
  reliability_modifier?: number;
  semantic_similarity?: number;
}

export interface MatchScore {
  score: number;
  breakdown: ScoreBreakdown;
}

export type QualityTier = 'new' | 'rising' | 'established' | 'top';

export interface MatchResult {
  match_id: string;
  expert_id: string;
  score: number;
  score_breakdown: ScoreBreakdown;
  quality_tier: QualityTier;
  skills: string[];
  industries: string[];
  project_types: string[];
  languages: string[];
  rate_min: number | null;
  rate_max: number | null;
}

// ── DB row types (subset used by matching pipeline) ───────────────────────────

export interface ProspectRow {
  id: string;
  requirements: Json | null;
  satellite_id: string | null;
}

export interface SatelliteConfigRow {
  matching_weights: Json;
}

export interface ExpertRow {
  id: string;
  profile: Json | null;
  rate_min: number | null;
  rate_max: number | null;
  availability: string | null;
}

// Billing exclusion result (returned in handleMatch response)
export interface BillingExclusion {
  expert_id: string;
  reason: 'insufficient_balance' | 'max_lead_price_exceeded' | 'spending_limit_reached';
}
