-- Drop residual Cal.com booking columns from the bookings table.
-- These were scaffolded during the Cal.com integration phase.
-- After the GCal pivot (E06S10), neither column has ever been written to or read from.
-- cal_username on the experts table is intentionally retained — actively used for booking URL fallback.

ALTER TABLE bookings DROP COLUMN IF EXISTS cal_booking_id;
ALTER TABLE bookings DROP COLUMN IF EXISTS cal_meeting_url;
