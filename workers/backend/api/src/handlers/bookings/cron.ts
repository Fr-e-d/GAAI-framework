import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { syncExpertPoolToD1 } from '../../cron/syncExpertPool';
import { handleLsBillingCron } from '../../cron/lsBillingCron';
import type { BookingRow, ExpertRow } from '../../types/db';
import { captureEvent } from '../../lib/posthog';

// AC13: scheduled() handler dispatches to sync function (AC4)
export async function handleScheduled(controller: ScheduledController, env: Env): Promise<void> {
  const cron = controller.cron;

  if (cron === '*/5 * * * *') {
    // AC4: sync expert pool to D1 every 5 minutes
    await syncExpertPoolToD1(env);
    await cleanupExpiredHolds(env);
    await cleanupExpiredConfirmations(env);
    await autoConfirmPendingExpertApproval(env);
  } else if (cron === '*/15 * * * *') {
    await dispatchReminders(env);
  } else if (cron === '0 * * * *') {
    // E06S33: hourly LS billing cron — auto-confirm leads + report usage
    await handleLsBillingCron(env);
  } else if (cron === '0 0 1 * *') {
    // E02S12 AC13: reset monthly direct submission quotas on the 1st of each month
    await resetDirectSubmissions(env);
  } else {
    console.warn('handleScheduled: unknown cron', cron);
  }
}

// AC9: Delete expired holds
async function cleanupExpiredHolds(env: Env): Promise<void> {
  const sql = createSql(env);
  const now = new Date().toISOString();
  try {
    const deleted = await sql`DELETE FROM bookings WHERE status = 'held' AND held_until < ${now} RETURNING id`;
    console.log(`cleanupExpiredHolds: deleted ${deleted.length} expired holds`);
  } finally {
    await sql.end();
  }
}

// AC12: Send reminders for upcoming confirmed bookings
async function dispatchReminders(env: Env): Promise<void> {
  const sql = createSql(env);
  const now = new Date();
  try {

  // J-1: 23h to 25h before start
  const j1Start = new Date(now.getTime() + 23 * 60 * 60 * 1000).toISOString();
  const j1End = new Date(now.getTime() + 25 * 60 * 60 * 1000).toISOString();

  const j1Bookings = await sql<Pick<BookingRow, 'id' | 'expert_id'>[]>`
    SELECT id, expert_id FROM bookings WHERE status = 'confirmed'
    AND start_at >= ${j1Start} AND start_at <= ${j1End} AND reminder_j1_sent_at IS NULL`;

  for (const booking of j1Bookings) {
    try {
      // Always send prospect reminder
      await env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.reminder_prospect',
        booking_id: booking.id,
      });

      // Expert reminder only if reminder_settings.enabled = true
      const [expert] = await sql<Pick<ExpertRow, 'reminder_settings'>[]>`
        SELECT reminder_settings FROM experts WHERE id = ${booking.expert_id!}`;

      const reminderEnabled = (expert?.reminder_settings as Record<string, unknown> | null)?.enabled !== false;
      if (reminderEnabled) {
        await env.EMAIL_NOTIFICATIONS.send({
          type: 'booking.reminder_expert',
          booking_id: booking.id,
        });
      }

      // Mark J-1 sent
      await sql`UPDATE bookings SET reminder_j1_sent_at = ${new Date().toISOString()} WHERE id = ${booking.id}`;
    } catch (err) {
      console.error('dispatchReminders J-1 error for booking', booking.id, err);
    }
  }

  // H-1: 50min to 70min before start
  const h1Start = new Date(now.getTime() + 50 * 60 * 1000).toISOString();
  const h1End = new Date(now.getTime() + 70 * 60 * 1000).toISOString();

  const h1Bookings = await sql<Pick<BookingRow, 'id' | 'expert_id'>[]>`
    SELECT id, expert_id FROM bookings WHERE status = 'confirmed'
    AND start_at >= ${h1Start} AND start_at <= ${h1End} AND reminder_h1_sent_at IS NULL`;

  for (const booking of h1Bookings) {
    try {
      await env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.reminder_prospect',
        booking_id: booking.id,
      });

      const [expert] = await sql<Pick<ExpertRow, 'reminder_settings'>[]>`
        SELECT reminder_settings FROM experts WHERE id = ${booking.expert_id!}`;

      const reminderEnabled = (expert?.reminder_settings as Record<string, unknown> | null)?.enabled !== false;
      if (reminderEnabled) {
        await env.EMAIL_NOTIFICATIONS.send({
          type: 'booking.reminder_expert',
          booking_id: booking.id,
        });
      }

      await sql`UPDATE bookings SET reminder_h1_sent_at = ${new Date().toISOString()} WHERE id = ${booking.id}`;
    } catch (err) {
      console.error('dispatchReminders H-1 error for booking', booking.id, err);
    }
  }

  } finally {
    await sql.end();
  }
}

// AC4 (E03S07): Expire pending_confirmation bookings older than 30 minutes.
// E02S12 CRITICAL: Direct bookings (lead_source = 'direct') use a 24h magic link TTL.
//   They must NOT be purged after 30 minutes — only after 24 hours.
async function cleanupExpiredConfirmations(env: Env): Promise<void> {
  const sql = createSql(env);
  const cutoff30m = new Date(Date.now() - 30 * 60 * 1000).toISOString();
  const cutoff24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  try {
    const expired = await sql<{ id: string; expert_id: string | null; prospect_id: string | null }[]>`
      UPDATE bookings SET status = 'expired_no_confirmation', confirmation_token = NULL
      WHERE status = 'pending_confirmation'
        AND (
          (lead_source IS DISTINCT FROM 'direct' AND created_at < ${cutoff30m})
          OR (lead_source = 'direct' AND created_at < ${cutoff24h})
        )
      RETURNING id, expert_id, prospect_id`;

    for (const b of expired) {
      captureEvent(env.POSTHOG_API_KEY, {
        distinctId: `system`,
        event: 'booking.expired_no_confirmation',
        properties: { booking_id: b.id, expert_id: b.expert_id, prospect_id: b.prospect_id },
      }).catch(() => {});
    }

    if (expired.length > 0) {
      console.log(`cleanupExpiredConfirmations: expired ${expired.length} pending_confirmation bookings`);
    }
  } finally {
    await sql.end();
  }
}

// E02S12 AC13: Reset monthly direct submission quotas on the 1st of each month
async function resetDirectSubmissions(env: Env): Promise<void> {
  const sql = createSql(env);
  try {
    await sql`
      UPDATE experts
      SET direct_submissions_this_month = 0,
          direct_submissions_reset_at = now()
    `;
    console.log('resetDirectSubmissions: reset monthly direct submission quotas for all experts');
  } finally {
    await sql.end();
  }
}

// AC5 (E03S07): Auto-confirm pending_expert_approval bookings older than 24h
async function autoConfirmPendingExpertApproval(env: Env): Promise<void> {
  const sql = createSql(env);
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  try {
    const confirmed = await sql<{ id: string; expert_id: string | null; prospect_id: string | null }[]>`
      UPDATE bookings SET status = 'confirmed', confirmed_at = ${new Date().toISOString()}
      WHERE status = 'pending_expert_approval' AND created_at < ${cutoff}
      RETURNING id, expert_id, prospect_id`;

    for (const b of confirmed) {
      try {
        await env.LEAD_BILLING.send({
          type: 'booking.created',
          booking_id: b.id,
          expert_id: b.expert_id!,
          prospect_id: b.prospect_id!,
        });
        await env.EMAIL_NOTIFICATIONS.send({
          type: 'booking.confirmed',
          booking_id: b.id,
          expert_id: b.expert_id!,
          prospect_id: b.prospect_id!,
          meeting_url: '',
          scheduled_at: '',
        });
      } catch (err) {
        console.error('autoConfirmPendingExpertApproval: queue error for booking', b.id, err);
      }
    }

    if (confirmed.length > 0) {
      console.log(`autoConfirmPendingExpertApproval: confirmed ${confirmed.length} pending_expert_approval bookings`);
    }
  } finally {
    await sql.end();
  }
}
