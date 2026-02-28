-- E06S39: Add verified_at column to prospects table
-- Set when OTP verification completes (via POST /api/prospects/:id/otp/verify success).
-- Used by handleProspectIdentify to record that the email was verified before revealing profiles.
ALTER TABLE prospects
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
