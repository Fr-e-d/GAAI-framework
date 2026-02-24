-- E08S05 AC10: Ownership assertions for lead credit RPC functions
-- Prevents a rogue expert_id from debiting/restoring credits on another expert's bookings/leads.

-- ── debit_lead_credit ─────────────────────────────────────────────────────────
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
  -- Ownership assertion: reject if booking already associated with different expert
  IF EXISTS (
    SELECT 1 FROM leads
    WHERE booking_id = p_booking_id
      AND expert_id != p_expert_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'booking_expert_mismatch');
  END IF;

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
  v_balance        integer;
  v_lead_expert_id uuid;
BEGIN
  -- Ownership assertion: reject if lead does not belong to p_expert_id
  SELECT expert_id INTO v_lead_expert_id FROM leads WHERE id = p_lead_id;
  IF NOT FOUND OR v_lead_expert_id != p_expert_id THEN
    RETURN jsonb_build_object('success', false, 'reason', 'lead_not_owned');
  END IF;

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
