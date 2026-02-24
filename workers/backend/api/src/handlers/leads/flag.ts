import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createServiceClient } from '../../lib/supabase';

const FLAG_WINDOW_DAYS = 7;

function unprocessableEntity(message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 422,
    headers: { 'Content-Type': 'application/json' },
  });
}

// POST /api/leads/:id/flag
// Expert flags a lead as non-qualified within the 7-day window.
// Atomically restores credit balance via restore_lead_credit RPC (AC4).
export async function handleFlagLead(
  request: Request,
  env: Env,
  user: AuthUser,
  leadId: string,
): Promise<Response> {
  let body: { reason?: string } = {};
  try {
    body = await request.json() as { reason?: string };
  } catch {
    // reason is optional — empty body is fine
  }

  const supabase = createServiceClient(env);

  // Fetch lead with fields needed for validation
  const { data: lead, error: fetchErr } = await supabase
    .from('leads')
    .select('id, expert_id, status, created_at, amount')
    .eq('id', leadId)
    .single();

  if (fetchErr || !lead) {
    return new Response(JSON.stringify({ error: 'Lead not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Ownership check (AC4)
  if (lead.expert_id !== user.id) {
    return new Response(JSON.stringify({ error: 'Forbidden' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Status check — only pending leads can be flagged (AC4)
  if (lead.status !== 'pending') {
    return unprocessableEntity('Lead status must be pending');
  }

  // 7-day flag window check (AC4)
  const createdAt = new Date(lead.created_at!);
  const flagDeadline = new Date(createdAt.getTime() + FLAG_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  if (new Date() > flagDeadline) {
    return unprocessableEntity('Flag window expired');
  }

  // Atomic credit restore via PostgreSQL RPC (AC4)
  // restore_lead_credit: locks expert row, restores credit_balance,
  // records credit_transaction, and updates lead.status='flagged' — all in one SQL transaction.
  const { data: result, error: rpcErr } = await supabase
    .rpc('restore_lead_credit', {
      p_expert_id:   user.id,
      p_lead_id:     leadId,
      p_amount:      lead.amount ?? 0,
      p_flag_reason: body.reason ?? '',
    });

  if (rpcErr) {
    return new Response(JSON.stringify({ error: 'Failed to process flag' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const rpcResult = result as { success: boolean; balance_after?: number };

  if (!rpcResult.success) {
    return new Response(JSON.stringify({ error: 'Flag processing failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
