// Row types for all 9 tables (derived from Database['public']['Tables'][X]['Row'])
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export interface ExpertRow {
  id: string;
  admissibility_criteria: Json;
  availability: string | null;
  availability_rules: Json | null;
  avatar_url: string | null;
  bio: string | null;
  cal_username: string | null;
  composite_score: number | null;
  created_at: string | null;
  credit_balance: number;
  max_lead_price: number | null;
  spending_limit: number | null;
  display_name: string | null;
  gcal_access_token: string | null;
  gcal_connected: boolean | null;
  gcal_connected_at: string | null;
  gcal_email: string | null;
  gcal_refresh_token: string | null;
  gcal_token_expiry_at: string | null;
  headline: string | null;
  ls_subscription_id: string | null;
  ls_subscription_item_id: string | null;
  ls_subscription_status: string | null;
  // E02S10: milestone timestamps (immutable once set, DEC-116/DEC-117)
  milestone_matchable_at: string | null;
  milestone_bookable_at: string | null;
  milestone_trust_at: string | null;
  normalized_email: string | null;
  preferences: Json | null;
  profile: Json | null;
  rate_max: number | null;
  rate_min: number | null;
  reminder_settings: Json | null;
  score_updated_at: string | null;
  verified_at: string | null;
  outcome_tags: string[] | null; // E06S37: outcome-based profile tags
  timezone: string; // E02S11: IANA timezone, NOT NULL DEFAULT 'UTC' at DB level
  booking_auto_confirm: boolean;  // E03S07: if false, requires expert approval
  // E02S12: direct link token
  direct_link_nonce: string;
  direct_submissions_this_month: number;
  direct_submissions_reset_at: string;
}

export interface ExpertAvailabilityRuleRow {
  id: string;
  expert_id: string;
  day_of_week: number;
  start_time: string; // 'HH:MM:SS' from postgres.js
  end_time: string;   // 'HH:MM:SS' from postgres.js
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface BookingRow {
  id: string;
  cancel_reason: string | null; // E06S38
  confirmed_at: string | null;
  created_at: string | null;
  description: string | null;
  duration_min: number | null;
  end_at: string | null;
  expert_id: string | null;
  gcal_event_id: string | null;
  held_until: string | null;
  match_id: string | null;
  meeting_url: string | null;
  prep_token: string | null;
  prospect_email: string | null;
  prospect_id: string | null;
  prospect_name: string | null;
  reminder_h1_sent_at: string | null;
  reminder_j1_sent_at: string | null;
  scheduled_at: string | null;
  start_at: string | null;
  status: string | null;
  confirmation_token: string | null;  // E03S07
  lead_source: string | null;  // E02S12: 'direct' | 'callibrate' | null
}

export interface ProspectRow {
  id: string;
  created_at: string | null;
  email: string | null;
  quiz_answers: Json | null;
  requirements: Json | null;
  satellite_id: string | null;
  status: string | null;
  utm_campaign: string | null;
  utm_content: string | null;
  utm_source: string | null;
  verified_at: string | null; // E06S39: set when OTP verification completes
  no_show_count: number;  // E03S07
}

export interface MatchRow {
  id: string;
  created_at: string | null;
  expert_id: string | null;
  expires_at: string | null;
  prospect_id: string | null;
  score: number | null;
  score_breakdown: Json | null;
  status: string | null;
}

export interface SatelliteConfigRow {
  id: string;
  active: boolean;
  brand: Json | null;
  content: Json | null;
  created_at: string | null;
  domain: string | null;
  label: string | null;
  matching_weights: Json;
  quiz_schema: Json;
  structured_data: Json | null;
  theme: Json | null;
  updated_at: string | null;
  vertical: string | null;
}

export interface LeadRow {
  id: string;
  amount: number | null;
  billed_at: string | null;
  booking_id: string | null;
  confirmed_at: string | null;
  conversion_declared: boolean; // E06S38
  created_at: string | null;
  evaluated_at: string | null; // E06S38
  evaluation_notes: string | null; // E06S38
  evaluation_score: number | null; // E06S38
  expert_id: string | null;
  flag_reason: string | null;
  flagged_at: string | null;
  ls_checkout_id: string | null;
  ls_order_id: string | null;
  prospect_id: string | null;
  status: string | null;
  usage_reported_at: string | null;
}

export interface CallExperienceSurveyRow {
  id: string;
  booking_id: string | null;
  prospect_id: string | null;
  score: number | null;
  submitted_at: string | null;
}

export interface ProjectSatisfactionSurveyRow {
  id: string;
  booking_id: string | null;
  prospect_id: string | null;
  score: number | null;
  submitted_at: string | null;
}

export interface LeadEvaluationRow {
  id: string;
  conversion_declared: boolean | null;
  conversion_declared_at: string | null;
  expert_id: string | null;
  lead_id: string | null;
  lead_quality_score: number | null;
  notes: string | null;
  submitted_at: string | null;
}

export interface CreditTransactionRow {
  id: string;
  expert_id: string;
  type: string;
  amount: number;
  lead_id: string | null;
  description: string | null;
  balance_after: number;
  created_at: string | null;
  available_at: string | null; // E02S10: 72h delay for milestone credits (AC6)
}
