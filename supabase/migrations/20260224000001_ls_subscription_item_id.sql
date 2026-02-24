-- E06S33: Add LS subscription billing columns to experts table
-- and usage tracking columns to leads table.
-- NOTE: This migration was already applied to Supabase staging.
-- This file exists for repo tracking only.

-- Add billing columns to experts
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS credit_balance integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ls_subscription_id text,
  ADD COLUMN IF NOT EXISTS ls_subscription_status text,
  ADD COLUMN IF NOT EXISTS ls_subscription_item_id text;

-- Add usage tracking columns to leads
ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS usage_reported_at timestamptz,
  ADD COLUMN IF NOT EXISTS flag_reason text,
  ADD COLUMN IF NOT EXISTS flagged_at timestamptz;

-- Create credit_transactions table (if not already present from E06S31)
CREATE TABLE IF NOT EXISTS credit_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expert_id uuid NOT NULL REFERENCES experts(id) ON DELETE CASCADE,
  type text NOT NULL,
  amount integer NOT NULL,
  balance_after integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS credit_transactions_expert_id_idx ON credit_transactions(expert_id);
CREATE INDEX IF NOT EXISTS credit_transactions_type_idx ON credit_transactions(type);
