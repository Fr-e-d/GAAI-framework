-- E08S05 AC9: webhook_events table for persistent LemonSqueezy webhook idempotency
-- L2 check (KV is L1). INSERT ON CONFLICT DO NOTHING prevents double-processing.

CREATE TABLE IF NOT EXISTS webhook_events (
  event_id     TEXT PRIMARY KEY,
  event_name   TEXT NOT NULL DEFAULT '',
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_processed_at
  ON webhook_events (processed_at);

ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
-- Service role bypasses RLS — no policies needed for Worker access
