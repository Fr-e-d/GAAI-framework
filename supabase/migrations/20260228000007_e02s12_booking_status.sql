-- E02S12: Add 'pending_slot_selection' to bookings status CHECK constraint
-- Used by direct booking confirmation flow (AC16).
-- Same pattern as E03S07 migration: drop + re-add constraint.

-- 1. Drop existing CHECK constraint on bookings.status
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

-- 2. Re-add CHECK constraint with all valid statuses including 'pending_slot_selection'
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
    'pending_expert_approval',
    'pending_slot_selection'
  ));
