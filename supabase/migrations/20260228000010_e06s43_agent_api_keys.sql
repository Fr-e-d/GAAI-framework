-- E06S43: Prospect API keys for agent authentication
CREATE TABLE IF NOT EXISTS prospect_api_keys (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prospect_id   UUID NOT NULL REFERENCES prospects(id) ON DELETE CASCADE,
  key_hash      TEXT NOT NULL,
  name          TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at  TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS prospect_api_keys_key_hash_idx ON prospect_api_keys(key_hash);
CREATE INDEX IF NOT EXISTS prospect_api_keys_prospect_id_idx ON prospect_api_keys(prospect_id);

ALTER TABLE prospect_api_keys ENABLE ROW LEVEL SECURITY;
-- No RLS policies: service role bypasses RLS; auth at Worker level via API key middleware
