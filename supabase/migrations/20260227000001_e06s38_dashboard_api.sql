-- E06S38: Add evaluation columns to leads table
ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS evaluation_score    INTEGER,
  ADD COLUMN IF NOT EXISTS evaluation_notes    TEXT,
  ADD COLUMN IF NOT EXISTS conversion_declared BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS evaluated_at        TIMESTAMPTZ;

-- E06S38: Add cancel_reason to bookings table
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT;
