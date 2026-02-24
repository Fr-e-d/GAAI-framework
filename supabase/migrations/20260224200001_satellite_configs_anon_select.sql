-- E08S05 AC7: RLS policy for anon role on satellite_configs
-- Allows cors.ts to query satellite_configs.domain using anon key (least-privilege).

ALTER TABLE satellite_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_read_domain"
  ON satellite_configs
  FOR SELECT
  TO anon
  USING (true);
