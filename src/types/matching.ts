// ── Matching domain types ─────────────────────────────────────────────────────
// These types map to the JSONB fields in the database (experts.profile,
// experts.preferences, prospects.requirements) and are intentionally flexible
// to support domain-agnostic matching across verticals (DEC-18/22/27).

// ExpertProfile represents all expert-side data relevant to scoring.
// Fields map to both the experts.profile JSONB column (skills, industries, etc.)
// and the experts table direct columns (rate_min, rate_max).
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

// ── AI Extraction types (E06S08) ───────────────────────────────────────────────

export type ExtractionField = 'challenge' | 'skills_needed' | 'industry' | 'budget_range' | 'timeline' | 'company_size' | 'languages';

export type FieldConfidence = Partial<Record<ExtractionField, number>>;

export interface ExtractionQuestion {
  field: string;
  question: string;
  options?: string[];
}

export interface ExtractionResponse {
  requirements: ProspectRequirements;
  confidence: FieldConfidence;
  needs_confirmation: string[];
  ready_to_match: boolean;
  confirmation_questions?: ExtractionQuestion[];
}

export interface MatchingWeights {
  skills_overlap: number;       // max points for skills component (default 40)
  industry_match: number;       // max points for industry component (default 20)
  budget_compatibility: number; // max points for budget component (default 20)
  timeline_match: number;       // max points for timeline component (default 10)
  language_match: number;       // max points for language component (default 10)
}

export const DEFAULT_WEIGHTS: MatchingWeights = {
  skills_overlap: 40,
  industry_match: 20,
  budget_compatibility: 20,
  timeline_match: 10,
  language_match: 10,
};

export interface ScoreBreakdown {
  skills_overlap: number;
  industry_match: number;
  budget_compatibility: number;
  timeline_match: number;
  language_match: number;
  deal_breaker?: boolean;
}

export interface MatchScore {
  score: number;
  breakdown: ScoreBreakdown;
}

export type QualityTier = 'new' | 'rising' | 'established' | 'top';

// Returned to prospects — anonymized (no display_name, avatar_url, cal_username)
export interface MatchResult {
  match_id: string;
  expert_id: string;
  score: number;
  score_breakdown: ScoreBreakdown;
  quality_tier: QualityTier;
  skills: string[];
  industries: string[];
  project_types: string[];
}
