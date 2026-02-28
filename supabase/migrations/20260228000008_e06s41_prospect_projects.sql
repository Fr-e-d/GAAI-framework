-- E06S41: Multi-project support — prospect_projects table + matches.project_id
-- DEC-124

-- ── AC1: Create prospect_projects table ───────────────────────────────────────
CREATE TABLE prospect_projects (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prospect_id           UUID REFERENCES prospects(id) ON DELETE CASCADE,
  satellite_id          TEXT,
  freetext              TEXT DEFAULT '',
  requirements          JSONB,
  extraction_confidence NUMERIC(4,2),
  status                TEXT CHECK (status IN ('active', 'matched', 'archived')) DEFAULT 'active',
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON prospect_projects(prospect_id);

-- ── AC2: Add project_id FK to matches (prospect_id kept for backwards compat) ──
ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES prospect_projects(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS matches_project_id_idx ON matches(project_id);

-- ── AC3: Data migration — one project per existing prospect ────────────────────
-- Insert one prospect_projects row for each existing prospect.
INSERT INTO prospect_projects (prospect_id, satellite_id, requirements, freetext, status, created_at)
SELECT
  id,
  satellite_id,
  requirements,
  '',
  CASE WHEN status IN ('matched', 'booked') THEN 'matched' ELSE 'active' END,
  COALESCE(created_at, now())
FROM prospects;

-- Link existing matches to the newly-created project rows.
UPDATE matches m
SET project_id = pp.id
FROM prospect_projects pp
WHERE pp.prospect_id = m.prospect_id;
