import { Env } from '../../types/env';
import { createSql } from '../../lib/db';

// ── Types ─────────────────────────────────────────────────────────────────────

interface LsEventMeta {
  event_name: string;
  custom_data?: {
    expert_id?: string;
  };
}

interface LsSubscriptionAttributes {
  status: string;
  customer_email?: string;
}

interface LsEventData {
  id: string;
  attributes: LsSubscriptionAttributes;
}

interface LsWebhookEvent {
  meta: LsEventMeta;
  data: LsEventData;
}

// ── HMAC-SHA256 signature verification (AC1) ─────────────────────────────────

export async function verifyLsSignature(
  request: Request,
  env: Env
): Promise<{ valid: boolean; bodyText: string }> {
  const rawBody = await request.arrayBuffer();
  const bodyText = new TextDecoder().decode(rawBody);
  const sigHeader = request.headers.get('X-Signature');
  if (!sigHeader) return { valid: false, bodyText: '' };

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(env.LEMON_SQUEEZY_WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify']
  );

  let sigBytes: Uint8Array;
  try {
    const hexPairs = sigHeader.match(/../g);
    if (!hexPairs) return { valid: false, bodyText: '' };
    sigBytes = Uint8Array.from(hexPairs.map(h => parseInt(h, 16)));
  } catch {
    return { valid: false, bodyText: '' };
  }

  const valid = await crypto.subtle.verify('HMAC', key, sigBytes, rawBody);
  return { valid, bodyText };
}

// ── Main webhook handler (AC1, AC5, AC9) ─────────────────────────────────────

export async function handleLsWebhook(request: Request, env: Env): Promise<Response> {
  // AC1: verify HMAC-SHA256 signature
  const { valid, bodyText } = await verifyLsSignature(request, env);
  if (!valid) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let event: LsWebhookEvent;
  try {
    event = JSON.parse(bodyText) as LsWebhookEvent;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const eventName = event.meta?.event_name;
  const eventId = event.data?.id;

  if (!eventId) {
    return new Response(JSON.stringify({ error: 'Missing event ID' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // AC5: idempotency — KV dedup via idem:ls-webhook:{event_id}, TTL 86400s
  const idemKey = `idem:ls-webhook:${eventId}:${eventName}`;
  const alreadyProcessed = await env.SESSIONS.get(idemKey);
  if (alreadyProcessed !== null) {
    return new Response(JSON.stringify({ ok: true, deduplicated: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    switch (eventName) {
      case 'subscription_created':
        await handleSubscriptionCreated(event, env);
        break;
      case 'subscription_updated':
        await handleSubscriptionUpdated(event, env);
        break;
      case 'subscription_payment_failed':
        await handleSubscriptionPaymentFailed(event, env);
        break;
      default:
        // Unhandled event — ack silently
        console.log('handleLsWebhook: unhandled event_name', eventName);
    }

    // Mark as processed (AC5)
    await env.SESSIONS.put(idemKey, '1', { expirationTtl: 86400 });
  } catch (err) {
    console.error('handleLsWebhook: error processing event', eventName, eventId, err);
    return new Response(JSON.stringify({ error: 'Internal error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// ── subscription_created (AC2) ────────────────────────────────────────────────

async function handleSubscriptionCreated(event: LsWebhookEvent, env: Env): Promise<void> {
  const sql = createSql(env);

  // Identify expert: primary = custom_data.expert_id, fallback = gcal_email
  let expertId: string | null = null;
  const customExpertId = event.meta?.custom_data?.expert_id;
  if (customExpertId) {
    const rows = await sql<{ id: string }[]>`SELECT id FROM experts WHERE id = ${customExpertId}`;
    expertId = rows[0]?.id ?? null;
  }
  if (!expertId) {
    const email = event.data?.attributes?.customer_email;
    if (email) {
      const rows = await sql<{ id: string }[]>`SELECT id FROM experts WHERE gcal_email = ${email}`;
      expertId = rows[0]?.id ?? null;
    }
  }
  if (!expertId) {
    console.warn('handleSubscriptionCreated: expert not found for event', event.data?.id);
    return;
  }

  const subscriptionId = event.data?.id;

  // Fetch subscription item ID from LS API
  let subscriptionItemId: string | null = null;
  try {
    const siRes = await fetch(
      `https://api.lemonsqueezy.com/v1/subscription-items?filter[subscription_id]=${subscriptionId}`,
      {
        headers: {
          Authorization: `Bearer ${env.LEMON_SQUEEZY_API_KEY}`,
          Accept: 'application/vnd.api+json',
        },
      }
    );
    const siJson = await siRes.json() as { data?: Array<{ id: string }> };
    subscriptionItemId = siJson.data?.[0]?.id ?? null;
    if (!subscriptionItemId) {
      console.warn('handleSubscriptionCreated: no subscription item found for subscription', subscriptionId);
    }
  } catch (e) {
    console.warn('handleSubscriptionCreated: failed to fetch subscription items', e);
  }

  // UPDATE experts: set LS subscription fields + credit_balance += 10000
  const updated = await sql<{ credit_balance: number }[]>`
    UPDATE experts SET
      ls_subscription_id = ${subscriptionId},
      ls_subscription_status = 'active',
      ls_subscription_item_id = ${subscriptionItemId},
      credit_balance = credit_balance + 10000
    WHERE id = ${expertId}
    RETURNING credit_balance`;
  const balanceAfter = updated[0]?.credit_balance ?? 0;

  // INSERT credit_transaction — idempotent (WHERE NOT EXISTS)
  await sql`
    INSERT INTO credit_transactions (expert_id, type, amount, balance_after)
    SELECT ${expertId}, 'welcome_credit', 10000, ${balanceAfter}
    WHERE NOT EXISTS (
      SELECT 1 FROM credit_transactions WHERE expert_id = ${expertId} AND type = 'welcome_credit'
    )`;

  console.log('handleSubscriptionCreated: processed for expert', expertId, 'balance_after', balanceAfter);
}

// ── subscription_updated (AC3) ────────────────────────────────────────────────

// Maps LS statuses to our internal statuses
function mapLsStatus(lsStatus: string): string {
  switch (lsStatus) {
    case 'active':
      return 'active';
    case 'past_due':
      return 'past_due';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'unpaid':
      return 'unpaid';
    default:
      return lsStatus;
  }
}

async function handleSubscriptionUpdated(event: LsWebhookEvent, env: Env): Promise<void> {
  const sql = createSql(env);
  const subscriptionId = event.data?.id;
  const lsStatus = event.data?.attributes?.status;
  const mappedStatus = mapLsStatus(lsStatus ?? '');

  await sql`
    UPDATE experts SET ls_subscription_status = ${mappedStatus}
    WHERE ls_subscription_id = ${subscriptionId}`;

  console.log('handleSubscriptionUpdated: subscription', subscriptionId, 'status ->', mappedStatus);
}

// ── subscription_payment_failed (AC4) ────────────────────────────────────────

async function handleSubscriptionPaymentFailed(event: LsWebhookEvent, env: Env): Promise<void> {
  const sql = createSql(env);
  const subscriptionId = event.data?.id;

  // UPDATE experts SET ls_subscription_status = 'past_due'
  const rows = await sql<{ id: string }[]>`
    UPDATE experts SET ls_subscription_status = 'past_due'
    WHERE ls_subscription_id = ${subscriptionId}
    RETURNING id`;

  const expertId = rows[0]?.id;
  if (!expertId) {
    console.warn('handleSubscriptionPaymentFailed: no expert found for subscription', subscriptionId);
    return;
  }

  // Queue EMAIL_NOTIFICATIONS with payment_failed type
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'expert.billing.payment_failed',
    expert_id: expertId,
  });

  console.log('handleSubscriptionPaymentFailed: queued notification for expert', expertId);
}
