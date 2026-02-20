ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS gcal_connected       BOOLEAN      DEFAULT false,
  ADD COLUMN IF NOT EXISTS gcal_email           TEXT,
  ADD COLUMN IF NOT EXISTS gcal_access_token    TEXT,
  ADD COLUMN IF NOT EXISTS gcal_refresh_token   TEXT,
  ADD COLUMN IF NOT EXISTS gcal_token_expiry_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS gcal_connected_at    TIMESTAMPTZ;
