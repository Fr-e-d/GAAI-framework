import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';

export async function handleScheduled(controller: ScheduledController, env: Env): Promise<void> {
  const cron = controller.cron;

  if (cron === '*/5 * * * *') {
    await cleanupExpiredHolds(env);
  } else if (cron === '*/15 * * * *') {
    await dispatchReminders(env);
  } else {
    console.warn('handleScheduled: unknown cron', cron);
  }
}

// AC9: Delete expired holds
async function cleanupExpiredHolds(env: Env): Promise<void> {
  const supabase = createServiceClient(env);
  const now = new Date().toISOString();

  const { error, count } = await supabase
    .from('bookings')
    .delete({ count: 'exact' })
    .eq('status', 'held')
    .lt('held_until', now);

  if (error) {
    console.error('cleanupExpiredHolds error:', error.message);
  } else {
    console.log(`cleanupExpiredHolds: deleted ${count ?? 0} expired holds`);
  }
}

// AC12: Send reminders for upcoming confirmed bookings
async function dispatchReminders(env: Env): Promise<void> {
  const supabase = createServiceClient(env);
  const now = new Date();

  // J-1: 23h to 25h before start
  const j1Start = new Date(now.getTime() + 23 * 60 * 60 * 1000).toISOString();
  const j1End = new Date(now.getTime() + 25 * 60 * 60 * 1000).toISOString();

  const { data: j1Bookings } = await supabase
    .from('bookings')
    .select('id, expert_id')
    .eq('status', 'confirmed')
    .gte('start_at', j1Start)
    .lte('start_at', j1End)
    .is('reminder_j1_sent_at', null);

  for (const booking of j1Bookings ?? []) {
    try {
      // Always send prospect reminder
      await env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.reminder_prospect',
        booking_id: booking.id,
      });

      // Expert reminder only if reminder_settings.enabled = true
      const { data: expert } = await supabase
        .from('experts')
        .select('reminder_settings')
        .eq('id', booking.expert_id!)
        .single();

      const reminderEnabled = (expert?.reminder_settings as Record<string, unknown> | null)?.enabled !== false;
      if (reminderEnabled) {
        await env.EMAIL_NOTIFICATIONS.send({
          type: 'booking.reminder_expert',
          booking_id: booking.id,
        });
      }

      // Mark J-1 sent
      await supabase
        .from('bookings')
        .update({ reminder_j1_sent_at: new Date().toISOString() })
        .eq('id', booking.id);
    } catch (err) {
      console.error('dispatchReminders J-1 error for booking', booking.id, err);
    }
  }

  // H-1: 50min to 70min before start
  const h1Start = new Date(now.getTime() + 50 * 60 * 1000).toISOString();
  const h1End = new Date(now.getTime() + 70 * 60 * 1000).toISOString();

  const { data: h1Bookings } = await supabase
    .from('bookings')
    .select('id, expert_id')
    .eq('status', 'confirmed')
    .gte('start_at', h1Start)
    .lte('start_at', h1End)
    .is('reminder_h1_sent_at', null);

  for (const booking of h1Bookings ?? []) {
    try {
      await env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.reminder_prospect',
        booking_id: booking.id,
      });

      const { data: expert } = await supabase
        .from('experts')
        .select('reminder_settings')
        .eq('id', booking.expert_id!)
        .single();

      const reminderEnabled = (expert?.reminder_settings as Record<string, unknown> | null)?.enabled !== false;
      if (reminderEnabled) {
        await env.EMAIL_NOTIFICATIONS.send({
          type: 'booking.reminder_expert',
          booking_id: booking.id,
        });
      }

      await supabase
        .from('bookings')
        .update({ reminder_h1_sent_at: new Date().toISOString() })
        .eq('id', booking.id);
    } catch (err) {
      console.error('dispatchReminders H-1 error for booking', booking.id, err);
    }
  }
}
