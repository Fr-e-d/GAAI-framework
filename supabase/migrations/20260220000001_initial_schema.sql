-- E06S02: Initial schema — 9 tables + GIN indexes + RLS
-- Applied via Supabase MCP on callibrate-staging

-- ── 1. experts ──────────────────────────────────────────────────────────────
-- FK to auth.users: experts are created through Supabase Auth.
CREATE TABLE experts (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name     TEXT,
  headline         TEXT,
  bio              TEXT,
  avatar_url       TEXT,
  rate_min         INTEGER,
  rate_max         INTEGER,
  availability     TEXT CHECK (availability IN ('available', 'limited', 'unavailable')),
  cal_username     TEXT,
  profile          JSONB,
  preferences      JSONB,
  verified_at      TIMESTAMPTZ,
  composite_score  NUMERIC(5,2) DEFAULT 0,
  score_updated_at TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- ── 2. prospects ─────────────────────────────────────────────────────────────
CREATE TABLE prospects (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  satellite_id TEXT,
  email        TEXT,
  utm_source   TEXT,
  utm_campaign TEXT,
  quiz_answers JSONB,
  requirements JSONB,
  status       TEXT CHECK (status IN ('anonymous', 'identified', 'matched', 'booked')),
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- ── 3. matches ───────────────────────────────────────────────────────────────
CREATE TABLE matches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expert_id       UUID REFERENCES experts(id) ON DELETE CASCADE,
  prospect_id     UUID REFERENCES prospects(id) ON DELETE CASCADE,
  score           NUMERIC(5,2),
  score_breakdown JSONB,
  status          TEXT CHECK (status IN ('pending', 'revealed', 'booked', 'expired')),
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 4. bookings ──────────────────────────────────────────────────────────────
CREATE TABLE bookings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id        UUID REFERENCES matches(id) ON DELETE CASCADE,
  cal_booking_id  TEXT UNIQUE,
  cal_meeting_url TEXT,
  scheduled_at    TIMESTAMPTZ,
  duration_min    INTEGER DEFAULT 20,
  status          TEXT CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show')),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 5. leads ─────────────────────────────────────────────────────────────────
CREATE TABLE leads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id      UUID REFERENCES bookings(id) ON DELETE CASCADE,
  expert_id       UUID REFERENCES experts(id) ON DELETE CASCADE,
  prospect_id     UUID REFERENCES prospects(id) ON DELETE CASCADE,
  amount          INTEGER,
  ls_checkout_id  TEXT,
  ls_order_id     TEXT,
  status          TEXT CHECK (status IN ('pending', 'billed', 'disputed', 'refunded')),
  billed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 6. satellite_configs ─────────────────────────────────────────────────────
CREATE TABLE satellite_configs (
  id               TEXT PRIMARY KEY,
  label            TEXT,
  domain           TEXT,
  vertical         TEXT,
  quiz_schema      JSONB NOT NULL,
  matching_weights JSONB NOT NULL,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- ── 7. call_experience_surveys ───────────────────────────────────────────────
CREATE TABLE call_experience_surveys (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   UUID REFERENCES bookings(id) ON DELETE CASCADE,
  prospect_id  UUID REFERENCES prospects(id) ON DELETE CASCADE,
  score        INTEGER CHECK (score BETWEEN 1 AND 5),
  submitted_at TIMESTAMPTZ DEFAULT now()
);

-- ── 8. project_satisfaction_surveys ─────────────────────────────────────────
CREATE TABLE project_satisfaction_surveys (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   UUID REFERENCES bookings(id) ON DELETE CASCADE,
  prospect_id  UUID REFERENCES prospects(id) ON DELETE CASCADE,
  score        INTEGER CHECK (score BETWEEN 1 AND 10),
  submitted_at TIMESTAMPTZ DEFAULT now()
);

-- ── 9. lead_evaluations ──────────────────────────────────────────────────────
CREATE TABLE lead_evaluations (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id                UUID REFERENCES leads(id) ON DELETE CASCADE,
  expert_id              UUID REFERENCES experts(id) ON DELETE CASCADE,
  lead_quality_score     INTEGER CHECK (lead_quality_score BETWEEN 1 AND 10),
  conversion_declared    BOOLEAN DEFAULT false,
  conversion_declared_at TIMESTAMPTZ,
  notes                  TEXT,
  submitted_at           TIMESTAMPTZ DEFAULT now()
);

-- ── GIN indexes (AC8) ────────────────────────────────────────────────────────
CREATE INDEX experts_profile_gin      ON experts  USING GIN (profile);
CREATE INDEX experts_preferences_gin  ON experts  USING GIN (preferences);
CREATE INDEX prospects_requirements_gin ON prospects USING GIN (requirements);
CREATE INDEX matches_score_breakdown_gin ON matches USING GIN (score_breakdown);

-- ── RLS (AC9) ────────────────────────────────────────────────────────────────
ALTER TABLE experts                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE prospects                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE satellite_configs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_experience_surveys    ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_satisfaction_surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_evaluations           ENABLE ROW LEVEL SECURITY;

-- Experts: authenticated user can SELECT / UPDATE only their own row.
-- Service role bypasses RLS by default (no explicit policy needed).
CREATE POLICY "experts_select_own" ON experts
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "experts_update_own" ON experts
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- prospects, matches, bookings, leads, satellite_configs,
-- call_experience_surveys, project_satisfaction_surveys, lead_evaluations:
-- No user-facing policies → accessible by service role only (RLS blocks all other roles).
