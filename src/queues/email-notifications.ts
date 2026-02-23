import { Env } from '../types/env';
import { EmailNotificationMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createServiceClient } from '../lib/supabase';

export async function consumeEmailNotifications(
  batch: MessageBatch<EmailNotificationMessage>,
  env: Env
): Promise<void> {
  for (const message of batch.messages) {
    try {
      if (await isAlreadyProcessed(env.SESSIONS, 'email-notifications', message.id)) {
        message.ack();
        continue;
      }

      const body = message.body;

      switch (body.type) {
        case 'expert.registered':
          await sendExpertRegisteredEmail(body, env);
          break;
        case 'booking.confirmed':
          await sendBookingConfirmedEmails(body, env);
          await triggerN8nBookingConfirmed(body, env);
          break;
        case 'booking.completed':
          await triggerN8nBookingCompleted(body, env);
          break;
        case 'booking.cancelled':
        case 'booking.rescheduled':
        case 'booking.reminder_prospect':
        case 'booking.reminder_expert':
          // TODO(E06S15/E06S16): implement notification — stub acks for now
          break;
        case 'expert.billing.insufficient_balance':
          // TODO(E06S33+): implement insufficient balance email — stub acks for now
          break;
        default: {
          const exhaustiveCheck: never = body;
          console.warn('email-notifications: unknown message type', (exhaustiveCheck as EmailNotificationMessage & { type: string }).type);
          message.ack();
          continue;
        }
      }

      await markProcessed(env.SESSIONS, 'email-notifications', message.id);
      message.ack();
    } catch (err) {
      handleMessageFailure(message, err, 'email-notifications');
    }
  }
}

async function sendResendEmail(
  apiKey: string,
  to: string,
  subject: string,
  html: string,
  text: string,
  fromDomain: string,
  replyTo: string
): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: `Callibrate <notifications@${fromDomain}>`,
      to: [to],
      subject,
      html,
      text,
      reply_to: replyTo,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Resend error ${res.status}: ${text}`);
  }
}

async function sendExpertRegisteredEmail(
  body: Extract<EmailNotificationMessage, { type: 'expert.registered' }>,
  env: Env
): Promise<void> {
  await sendResendEmail(
    env.RESEND_API_KEY,
    body.email,
    'Welcome to Callibrate',
    `<p>Hi ${body.name}, welcome to the Callibrate expert network.</p><p>Your profile is now active. Pre-qualified leads will be booked directly to your calendar.</p>`,
    `Hi ${body.name}, welcome to the Callibrate expert network.\n\nYour profile is now active. Pre-qualified leads will be booked directly to your calendar.`,
    env.EMAIL_FROM_DOMAIN || 'callibrate.io',
    env.EMAIL_REPLY_TO || 'support@callibrate.io'
  );
}

async function sendBookingConfirmedEmails(
  body: Extract<EmailNotificationMessage, { type: 'booking.confirmed' }>,
  env: Env
): Promise<void> {
  const supabase = createServiceClient(env);

  // Fetch expert gcal_email
  const { data: expert, error: expertErr } = await supabase
    .from('experts')
    .select('gcal_email, display_name')
    .eq('id', body.expert_id)
    .single();

  if (expertErr || !expert?.gcal_email) {
    throw new Error(`Expert not found or no email for ${body.expert_id}: ${expertErr?.message}`);
  }

  // Fetch prospect email
  const { data: prospect, error: prospectErr } = await supabase
    .from('prospects')
    .select('email')
    .eq('id', body.prospect_id)
    .single();

  if (prospectErr || !prospect?.email) {
    throw new Error(`Prospect not found or no email for ${body.prospect_id}: ${prospectErr?.message}`);
  }

  // Email to expert
  await sendResendEmail(
    env.RESEND_API_KEY,
    expert.gcal_email,
    'New booking confirmed',
    `<p>Hi ${expert.display_name ?? 'Expert'},</p><p>A new call has been booked with a prospect.</p><p>Meeting link: <a href="${body.meeting_url}">${body.meeting_url}</a></p><p>Scheduled: ${body.scheduled_at}</p>`,
    `Hi ${expert.display_name ?? 'Expert'},\n\nA new call has been booked with a prospect.\n\nMeeting link: ${body.meeting_url}\n\nScheduled: ${body.scheduled_at}`,
    env.EMAIL_FROM_DOMAIN || 'callibrate.io',
    env.EMAIL_REPLY_TO || 'support@callibrate.io'
  );

  // Email to prospect
  await sendResendEmail(
    env.RESEND_API_KEY,
    prospect.email,
    'Your booking is confirmed',
    `<p>Your call has been confirmed.</p><p>Meeting link: <a href="${body.meeting_url}">${body.meeting_url}</a></p><p>Scheduled: ${body.scheduled_at}</p>`,
    `Your call has been confirmed.\n\nMeeting link: ${body.meeting_url}\n\nScheduled: ${body.scheduled_at}`,
    env.EMAIL_FROM_DOMAIN || 'callibrate.io',
    env.EMAIL_REPLY_TO || 'support@callibrate.io'
  );
}

async function triggerN8nBookingConfirmed(
  body: Extract<EmailNotificationMessage, { type: 'booking.confirmed' }>,
  env: Env
): Promise<void> {
  const res = await fetch(`${env.N8N_WEBHOOK_URL}/booking-confirmed`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      booking_id: body.booking_id,
      expert_id: body.expert_id,
      prospect_id: body.prospect_id,
      meeting_url: body.meeting_url,
      scheduled_at: body.scheduled_at,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`n8n booking-confirmed webhook error ${res.status}: ${text}`);
  }
}

async function triggerN8nBookingCompleted(
  body: Extract<EmailNotificationMessage, { type: 'booking.completed' }>,
  env: Env
): Promise<void> {
  const res = await fetch(`${env.N8N_WEBHOOK_URL}/booking-completed`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      booking_id: body.booking_id,
      expert_id: body.expert_id,
      prospect_id: body.prospect_id,
      scheduled_at: body.scheduled_at,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`n8n booking-completed webhook error ${res.status}: ${text}`);
  }
}
