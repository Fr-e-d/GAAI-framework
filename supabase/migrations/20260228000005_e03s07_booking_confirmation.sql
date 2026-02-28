-- E03S07: Booking Confirmation Email + Reminders + No-Show Tracking

-- 1. Drop existing CHECK constraint on bookings.status safely
DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'bookings'::regclass
    AND contype = 'c'
    AND conname LIKE '%status%';
  IF constraint_name IS NOT NULL THEN
    EXECUTE 'ALTER TABLE bookings DROP CONSTRAINT ' || quote_ident(constraint_name);
  END IF;
END $$;

-- 2. Add updated CHECK constraint with all valid statuses
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check
  CHECK (status IN (
    'held',
    'confirmed',
    'cancelled',
    'completed',
    'no_show',
    'pending_confirmation',
    'expired_no_confirmation',
    'cancelled_by_prospect',
    'pending_expert_approval'
  ));

-- 3. Add confirmation_token column to bookings
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS confirmation_token TEXT;

-- 4. Add booking_auto_confirm to experts
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS booking_auto_confirm BOOLEAN NOT NULL DEFAULT true;

-- 5. Add no_show_count to prospects
ALTER TABLE prospects
  ADD COLUMN IF NOT EXISTS no_show_count INTEGER NOT NULL DEFAULT 0;

-- 6. Index for expiry cron query performance
CREATE INDEX IF NOT EXISTS bookings_status_created_at_idx
  ON bookings (status, created_at)
  WHERE status IN ('pending_confirmation', 'pending_expert_approval');
