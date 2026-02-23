-- ── E06S32: Lead credit debit + restore RPC functions ────────────────────────
-- These functions run in a PostgreSQL transaction (ACID), providing the
-- atomicity required by AC3/AC4. Called via supabase.rpc() from the
-- callibrate-core Worker (Supabase JS client, no postgres.js needed).

-- ── debit_lead_credit ─────────────────────────────────────────────────────────
-- Called by the lead-billing queue consumer on booking.created.
-- Atomically:
--   1. Locks expert row (SELECT FOR UPDATE)
--   2. Inserts lead with status='pending' or 'insufficient_balance'
--   3. If balance sufficient: deducts credit + records transaction
-- Returns jsonb: { success, reason?, lead_id, balance_after? }
CREATE OR REPLACE FUNCTION debit_lead_credit(
  p_expert_id   uuid,
  p_booking_id  uuid,
  p_prospect_id uuid,
  p_amount      integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_balance  integer;
  v_lead_id  uuid;
BEGIN
  -- Lock expert row for this transaction
  SELECT credit_balance INTO v_balance
  FROM   experts
  WHERE  id = p_expert_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'expert_not_found');
  END IF;

  -- Insert lead (ON CONFLICT handles partial-failure retries — AC9)
  INSERT INTO leads (booking_id, expert_id, prospect_id, amount, status)
  VALUES (
    p_booking_id, p_expert_id, p_prospect_id, p_amount,
    CASE WHEN v_balance >= p_amount THEN 'pending' ELSE 'insufficient_balance' END
  )
  ON CONFLICT (booking_id) DO UPDATE
    SET amount = EXCLUDED.amount,
        status = CASE
          WHEN leads.status IN ('flagged', 'confirmed') THEN leads.status
          WHEN v_balance >= p_amount               THEN 'pending'
          ELSE                                          'insufficient_balance'
        END
  RETURNING id INTO v_lead_id;

  -- Insufficient balance path (AC2)
  IF v_balance < p_amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason',  'insufficient_balance',
      'lead_id', v_lead_id
    );
  END IF;

  -- Idempotency: skip if credit_transaction already recorded for this lead
  IF EXISTS (
    SELECT 1 FROM credit_transactions
    WHERE  lead_id = v_lead_id AND type = 'lead_debit'
  ) THEN
    RETURN jsonb_build_object(
      'success',        true,
      'lead_id',        v_lead_id,
      'already_debited', true
    );
  END IF;

  -- Atomic debit (AC1, AC3)
  UPDATE experts
  SET    credit_balance = credit_balance - p_amount
  WHERE  id = p_expert_id;

  INSERT INTO credit_transactions (expert_id, lead_id, type, amount, balance_after)
  VALUES (p_expert_id, v_lead_id, 'lead_debit', -p_amount, v_balance - p_amount);

  RETURN jsonb_build_object(
    'success',      true,
    'lead_id',      v_lead_id,
    'balance_after', v_balance - p_amount
  );
END;
$$;

-- ── restore_lead_credit ───────────────────────────────────────────────────────
-- Called by POST /api/leads/:id/flag after HTTP-layer validation.
-- Atomically: restores credit + records credit transaction + flags lead.
-- Returns jsonb: { success, balance_after }
CREATE OR REPLACE FUNCTION restore_lead_credit(
  p_expert_id   uuid,
  p_lead_id     uuid,
  p_amount      integer,
  p_flag_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_balance integer;
BEGIN
  -- Lock expert row
  SELECT credit_balance INTO v_balance
  FROM   experts
  WHERE  id = p_expert_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'expert_not_found');
  END IF;

  -- Restore credit
  UPDATE experts
  SET    credit_balance = credit_balance + p_amount
  WHERE  id = p_expert_id;

  -- Record credit transaction (AC4)
  INSERT INTO credit_transactions (expert_id, lead_id, type, amount, balance_after)
  VALUES (p_expert_id, p_lead_id, 'lead_credit', p_amount, v_balance + p_amount);

  -- Flag the lead (AC4)
  UPDATE leads
  SET    status = 'flagged', flagged_at = NOW(), flag_reason = p_flag_reason
  WHERE  id = p_lead_id;

  RETURN jsonb_build_object(
    'success',      true,
    'balance_after', v_balance + p_amount
  );
END;
$$;
