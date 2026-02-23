import { Env } from '../types/env';
import { LeadBillingMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createServiceClient } from '../lib/supabase';
import { calculateLeadPrice } from '../lib/pricing';
import { ProspectRequirements } from '../types/matching';

export async function consumeLeadBilling(
  batch: MessageBatch<LeadBillingMessage>,
  env: Env
): Promise<void> {
  for (const message of batch.messages) {
    try {
      if (await isAlreadyProcessed(env.SESSIONS, 'lead-billing', message.id)) {
        message.ack();
        continue;
      }

      const body = message.body;

      if (body.type !== 'booking.created') {
        console.warn('lead-billing: unknown message type', (body as unknown as { type: string }).type);
        message.ack();
        continue;
      }

      await processLeadBilling(body, env);

      await markProcessed(env.SESSIONS, 'lead-billing', message.id);
      message.ack();
    } catch (err) {
      handleMessageFailure(message, err, 'lead-billing');
    }
  }
}

async function processLeadBilling(
  body: LeadBillingMessage,
  env: Env
): Promise<void> {
  const supabase = createServiceClient(env);

  // Step 1: Fetch prospect requirements for lead price calculation (AC1)
  const { data: prospect, error: prospectErr } = await supabase
    .from('prospects')
    .select('requirements')
    .eq('id', body.prospect_id)
    .single();

  if (prospectErr || !prospect) {
    throw new Error(`Failed to fetch prospect ${body.prospect_id}: ${prospectErr?.message ?? 'not found'}`);
  }

  // Step 2: Calculate lead price via DEC-67 grid (AC1)
  const requirements = prospect.requirements as ProspectRequirements | null;
  const budgetMax = requirements?.budget_range?.max ?? null;
  const price = calculateLeadPrice(budgetMax, {
    budget_max: budgetMax,
    // Any non-null timeline string signals the prospect provided a timeline (premium eligibility)
    timeline_days: requirements?.timeline != null ? 30 : null,
    ...(requirements?.skills_needed ? { skills: requirements.skills_needed } : {}),
  });

  // Step 3: Atomic credit debit via PostgreSQL RPC function (AC1, AC3)
  // debit_lead_credit locks the expert row (FOR UPDATE), inserts the lead, and
  // debits credit_balance + inserts credit_transactions — all in one SQL transaction.
  const { data: result, error: rpcErr } = await supabase
    .rpc('debit_lead_credit', {
      p_expert_id:   body.expert_id,
      p_booking_id:  body.booking_id,
      p_prospect_id: body.prospect_id,
      p_amount:      price.amount,
    });

  if (rpcErr) {
    throw new Error(`debit_lead_credit RPC failed: ${rpcErr.message}`);
  }

  const rpcResult = result as { success: boolean; reason?: string; lead_id: string };

  // Step 4: AC2 — insufficient balance path
  // Lead inserted with status='insufficient_balance'; notify expert to top up
  if (!rpcResult.success && rpcResult.reason === 'insufficient_balance') {
    await env.EMAIL_NOTIFICATIONS.send({
      type: 'expert.billing.insufficient_balance',
      expert_id: body.expert_id,
    });
    return;
  }

  if (!rpcResult.success) {
    throw new Error(`debit_lead_credit failed: ${JSON.stringify(rpcResult)}`);
  }
}
