-- E02S12: Expert Public Profile Page — SEO & Direct Booking Link
-- AC11: direct_link_nonce, direct_submissions_this_month, direct_submissions_reset_at on experts
-- AC12: lead_source on bookings

-- 1. Add direct link columns to experts
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS direct_link_nonce TEXT NOT NULL DEFAULT gen_random_uuid()::text,
  ADD COLUMN IF NOT EXISTS direct_submissions_this_month INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS direct_submissions_reset_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 2. Add lead_source to bookings (nullable — pre-existing bookings have no source)
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS lead_source TEXT;

-- 3. Index for quota check queries (direct booking handler)
CREATE INDEX IF NOT EXISTS experts_direct_link_nonce_idx
  ON experts (direct_link_nonce);

-- 4. Index for cron reset query
CREATE INDEX IF NOT EXISTS experts_direct_submissions_reset_at_idx
  ON experts (direct_submissions_reset_at);
