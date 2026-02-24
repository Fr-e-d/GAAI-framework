import { Env } from '../types/env';
import { createSql } from '../lib/db';

// ── Types ─────────────────────────────────────────────────────────────────────

interface LeadForUsage {
  id: string;
  amount: number;
  expert_id: string;
  ls_subscription_item_id: string;
}

// ── Main cron handler (AC6–AC8, AC11) ────────────────────────────────────────

export async function handleLsBillingCron(env: Env): Promise<void> {
  await autoConfirmLeads(env);
  await reportUsage(env);
}

// ── AC6: Auto-confirm pending leads past the flag window ─────────────────────

async function autoConfirmLeads(env: Env): Promise<void> {
  const sql = createSql(env);

  // FLAG_WINDOW_MS: staging acceleration via env var, defaults to 7 days in production
  const windowMs = parseInt(env.FLAG_WINDOW_MS ?? String(7 * 24 * 60 * 60 * 1000));
  const cutoff = new Date(Date.now() - windowMs).toISOString();

  const confirmed = await sql<{ id: string }[]>`
    UPDATE leads
    SET status = 'confirmed', confirmed_at = now()
    WHERE status = 'pending' AND created_at < ${cutoff}
    RETURNING id`;

  if (confirmed.length > 0) {
    console.log(`autoConfirmLeads: confirmed ${confirmed.length} leads`, confirmed.map(r => r.id));
  }
}

// ── AC7–AC8: Report confirmed leads to LS usage API ──────────────────────────

async function reportUsage(env: Env): Promise<void> {
  const sql = createSql(env);

  // Find leads with status='confirmed' AND usage_reported_at IS NULL
  // Join with experts to get ls_subscription_item_id
  const leads = await sql<LeadForUsage[]>`
    SELECT
      l.id,
      l.amount,
      l.expert_id,
      e.ls_subscription_item_id
    FROM leads l
    JOIN experts e ON e.id = l.expert_id
    WHERE l.status = 'confirmed'
      AND l.usage_reported_at IS NULL
      AND e.ls_subscription_item_id IS NOT NULL`;

  for (const lead of leads) {
    try {
      await reportLeadUsage(lead, env);
      // AC7: On success — UPDATE lead SET status='usage_reported', usage_reported_at=now()
      await sql`
        UPDATE leads
        SET status = 'usage_reported', usage_reported_at = now()
        WHERE id = ${lead.id}`;
      console.log('reportUsage: reported usage for lead', lead.id);
    } catch (err) {
      // AC8: On failure — leave status='confirmed', log error. Retry on next cron run.
      console.error('reportUsage: failed to report usage for lead', lead.id, err);
    }
  }
}

async function reportLeadUsage(lead: LeadForUsage, env: Env): Promise<void> {
  const body = {
    data: {
      type: 'usage-records',
      attributes: {
        quantity: lead.amount,
        action: 'increment',
      },
      relationships: {
        'subscription-item': {
          data: {
            type: 'subscription-items',
            id: lead.ls_subscription_item_id,
          },
        },
      },
    },
  };

  const res = await fetch('https://api.lemonsqueezy.com/v1/usage-records', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.LEMON_SQUEEZY_API_KEY}`,
      'Content-Type': 'application/vnd.api+json',
      Accept: 'application/vnd.api+json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`LS usage API error ${res.status}: ${text}`);
  }
}
