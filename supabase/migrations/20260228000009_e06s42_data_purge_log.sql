-- E06S42: GDPR audit trail — one row per automated purge run
CREATE TABLE IF NOT EXISTS data_purge_log (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purge_type       TEXT NOT NULL,          -- 'abandoned_funnel' | 'otp_kv_cleanup'
  records_affected INTEGER NOT NULL DEFAULT 0,
  purged_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE data_purge_log ENABLE ROW LEVEL SECURITY;
-- No policies = service_role bypasses RLS; anon/authenticated cannot read/write
