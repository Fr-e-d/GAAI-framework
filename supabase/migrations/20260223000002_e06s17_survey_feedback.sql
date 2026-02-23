-- E06S17: Survey submission endpoints — schema additions
-- Adds comment columns (AC1/AC2) and unique constraints for idempotency (AC1/AC2/AC3)

-- ── comment columns ───────────────────────────────────────────────────────────
ALTER TABLE call_experience_surveys ADD COLUMN IF NOT EXISTS comment TEXT;
ALTER TABLE project_satisfaction_surveys ADD COLUMN IF NOT EXISTS comment TEXT;

-- ── unique constraints (idempotency — 409 on duplicate submission) ────────────
ALTER TABLE call_experience_surveys
  ADD CONSTRAINT call_experience_surveys_booking_prospect_unique
  UNIQUE (booking_id, prospect_id);

ALTER TABLE project_satisfaction_surveys
  ADD CONSTRAINT project_satisfaction_surveys_booking_prospect_unique
  UNIQUE (booking_id, prospect_id);

ALTER TABLE lead_evaluations
  ADD CONSTRAINT lead_evaluations_lead_id_unique
  UNIQUE (lead_id);
