import { Env } from '../types/env';
import { LeadBillingMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createServiceClient } from '../lib/supabase';

// TODO: move to env secrets once Lemon Squeezy account is configured
const LS_STORE_ID = 'YOUR_LS_STORE_ID';
const LS_VARIANT_ID = 'YOUR_LS_VARIANT_ID';

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

  // Step 1: Insert lead with status 'pending', handle partial-failure retries
  let leadId: string;

  const { data: insertedLead, error: insertErr } = await supabase
    .from('leads')
    .insert({
      booking_id: body.booking_id,
      expert_id: body.expert_id,
      prospect_id: body.prospect_id,
      status: 'pending',
    })
    .select('id')
    .single();

  if (insertErr) {
    if (insertErr.code === '23505') {
      // Unique constraint violation — lead already exists from a previous partial attempt
      const { data: existingLead, error: fetchErr } = await supabase
        .from('leads')
        .select('id')
        .eq('booking_id', body.booking_id)
        .single();
      if (fetchErr || !existingLead) {
        throw new Error(`Failed to fetch existing lead for booking ${body.booking_id}: ${fetchErr?.message}`);
      }
      leadId = existingLead.id;
    } else {
      throw new Error(`Failed to insert lead: ${insertErr.message}`);
    }
  } else {
    leadId = insertedLead.id;
  }

  // Step 2: Fetch expert gcal_email for Lemon Squeezy checkout attribution
  const { data: expert, error: expertErr } = await supabase
    .from('experts')
    .select('gcal_email')
    .eq('id', body.expert_id)
    .single();

  const expertEmail = expert?.gcal_email ?? '';
  if (expertErr) {
    throw new Error(`Failed to fetch expert ${body.expert_id}: ${expertErr.message}`);
  }

  // Step 3: Create Lemon Squeezy checkout
  const lsRes = await fetch('https://api.lemonsqueezy.com/v1/checkouts', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.LEMON_SQUEEZY_API_KEY}`,
      'Content-Type': 'application/vnd.api+json',
      Accept: 'application/vnd.api+json',
    },
    body: JSON.stringify({
      data: {
        type: 'checkouts',
        attributes: {
          checkout_data: {
            email: expertEmail,
            custom: {
              lead_id: leadId,
              booking_id: body.booking_id,
              expert_id: body.expert_id,
            },
          },
        },
        relationships: {
          store: { data: { type: 'stores', id: LS_STORE_ID } },
          variant: { data: { type: 'variants', id: LS_VARIANT_ID } },
        },
      },
    }),
  });

  if (!lsRes.ok) {
    const text = await lsRes.text();
    throw new Error(`Lemon Squeezy checkout error ${lsRes.status}: ${text}`);
  }

  const lsData = await lsRes.json() as { data: { id: string } };
  const lsCheckoutId = lsData.data.id;

  // Step 4: Update lead with checkout ID and 'billed' status
  // 'billed' at MVP = checkout link created (payment is manual via expert clicking the link)
  const { error: updateErr } = await supabase
    .from('leads')
    .update({ ls_checkout_id: lsCheckoutId, status: 'billed' })
    .eq('id', leadId);

  if (updateErr) {
    throw new Error(`Failed to update lead ${leadId}: ${updateErr.message}`);
  }
}
