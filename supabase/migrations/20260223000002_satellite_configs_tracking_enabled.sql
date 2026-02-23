-- E07S02: add tracking_enabled column to satellite_configs
ALTER TABLE satellite_configs
  ADD COLUMN tracking_enabled BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN satellite_configs.tracking_enabled IS
  'When false, PostHog SDK is not injected into the satellite landing page (GDPR opt-out or debug mode).';
