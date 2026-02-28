-- E02S11: Expert Availability — Weekly Recurring Rules
-- Adds timezone to experts + creates expert_availability_rules table

-- Add timezone column to experts (Layer 1 of DEC-118 availability model)
ALTER TABLE experts ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';

-- Create expert_availability_rules table
CREATE TABLE expert_availability_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expert_id UUID NOT NULL REFERENCES experts(id) ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time TIME NOT NULL,
  end_time TIME NOT NULL CHECK (end_time > start_time),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient availability queries
CREATE INDEX expert_availability_rules_expert_day_active_idx
  ON expert_availability_rules (expert_id, day_of_week, is_active);

-- Enable RLS
ALTER TABLE expert_availability_rules ENABLE ROW LEVEL SECURITY;

-- RLS policies: experts can only read/write their own rules
CREATE POLICY "experts_select_own_availability_rules"
  ON expert_availability_rules FOR SELECT
  TO authenticated
  USING (expert_id = auth.uid());

CREATE POLICY "experts_insert_own_availability_rules"
  ON expert_availability_rules FOR INSERT
  TO authenticated
  WITH CHECK (expert_id = auth.uid());

CREATE POLICY "experts_update_own_availability_rules"
  ON expert_availability_rules FOR UPDATE
  TO authenticated
  USING (expert_id = auth.uid());
