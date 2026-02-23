import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { syncExpertPoolToD1 } from '../../cron/syncExpertPool';
import type { BookingRow, ExpertRow } from '../../types/db';

// AC13: scheduled() handler dispatches to sync function (AC4)
export async function handleScheduled(controller: ScheduledController, env: Env): Promise<void> {
  const cron = controller.cron;

  if (cron === '*/5 * * * *') {
    // AC4: sync expert pool to D1 every 5 minutes
    await syncExpertPoolToD1(env);
    await cleanupExpiredHolds(env);
  } else if (cron === '*/15 * * * *') {
    await dispatchReminders(env);
  } else {
    console.warn('handleScheduled: unknown cron', cron);
  }
}

// AC9: Delete expired holds
async function cleanupExpiredHolds(env: Env): Promise<void> {
  const sql = createSql(env);
  const now = new Date().toISOString();

  const deleted = await sql`DELETE FROM bookings WHERE status = 'held' AND held_until < ${now} RETURNING id`;
  console.log(`cleanupExpiredHolds: deleted ${deleted.length} expired holds`);
}

// AC12: Send reminders for upcoming confirmed bookings
async function dispatchReminders(env: Env): Promise<void> {
  const sql = createSql(env);
  const now = new Date();

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
}
