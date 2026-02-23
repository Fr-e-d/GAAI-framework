import { Env } from '../types/env';
import { LeadBillingMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createSql } from '../lib/db';
import type { LeadRow, ExpertRow } from '../types/db';

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
  const sql = createSql(env);

  // Step 1: Insert lead with status 'pending', handle partial-failure retries
  let leadId: string;

  try {
    const [inserted] = await sql<Pick<LeadRow, 'id'>[]>`
      INSERT INTO leads (booking_id, expert_id, prospect_id, status)
      VALUES (${body.booking_id}, ${body.expert_id}, ${body.prospect_id}, 'pending')
      RETURNING id`;
    if (!inserted) throw new Error('Insert failed');
    leadId = inserted.id;
  } catch (err) {
    if ((err as { code?: string }).code === '23505') {
      // Unique constraint violation — lead already exists from a previous partial attempt
      const [existing] = await sql<Pick<LeadRow, 'id'>[]>`
        SELECT id FROM leads WHERE booking_id = ${body.booking_id}`;
      if (!existing) {
        throw new Error(`Failed to fetch existing lead for booking ${body.booking_id}`);
      }
      leadId = existing.id;
    } else {
      throw new Error(`Failed to insert lead: ${String(err)}`);
    }
  }

  // Step 2: Fetch expert gcal_email for Lemon Squeezy checkout attribution
  const [expert] = await sql<Pick<ExpertRow, 'gcal_email'>[]>`
    SELECT gcal_email FROM experts WHERE id = ${body.expert_id}`;

  if (!expert) {
    throw new Error(`Failed to fetch expert ${body.expert_id}`);
  }

  const expertEmail = expert.gcal_email ?? '';

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
  await sql`UPDATE leads SET ls_checkout_id = ${lsCheckoutId}, status = 'billed' WHERE id = ${leadId}`;
}
