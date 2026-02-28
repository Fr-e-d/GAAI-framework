-- E03S09: Add locale column to satellite_configs
-- Allows per-satellite language configuration for hint text and UI strings
ALTER TABLE satellite_configs
  ADD COLUMN IF NOT EXISTS locale TEXT;

COMMENT ON COLUMN satellite_configs.locale IS 'BCP 47 locale code, e.g. "fr", "en". NULL = default to "en".';
