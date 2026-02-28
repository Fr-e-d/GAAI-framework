-- E02S10: Expert profile mandatory fields + credit milestones (DEC-116/DEC-117)

-- ── 1. Milestone timestamps on experts ────────────────────────────────────────
-- Immutable once set: application enforces IF IS NULL THEN SET (no DB constraint to
-- allow SET if null, never reset).
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS milestone_matchable_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS milestone_bookable_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS milestone_trust_at     TIMESTAMPTZ;

-- ── 2. Normalized email (anti-gaming, AC4) ────────────────────────────────────
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS normalized_email TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS experts_normalized_email_idx ON experts(normalized_email)
  WHERE normalized_email IS NOT NULL;

-- ── 3. available_at on credit_transactions (72h delay, AC6) ──────────────────
ALTER TABLE credit_transactions
  ADD COLUMN IF NOT EXISTS available_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- lead_id and description already in TS types — add them if absent
ALTER TABLE credit_transactions
  ADD COLUMN IF NOT EXISTS lead_id     UUID REFERENCES leads(id),
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Index for billingFilter query (available_at filter on expert_id)
CREATE INDEX IF NOT EXISTS credit_transactions_available_at_idx
  ON credit_transactions(expert_id, available_at);

-- ── 4. Backfill existing records ──────────────────────────────────────────────
-- All existing credit_transactions are immediately available (legacy data).
-- DEFAULT NOW() already handles new rows; existing rows already have now() from insert time.
-- No backfill needed — available_at defaults to NOW() on ADD COLUMN.
