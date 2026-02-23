import { Env } from '../types/env';
import { EmailNotificationMessage } from '../types/queues';
import { isAlreadyProcessed, markProcessed } from '../lib/idempotency';
import { handleMessageFailure } from '../lib/retryQueue';
import { createServiceClient } from '../lib/supabase';
import { signSurveyToken } from '../lib/jwt';

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
          await env.BOOKING_CONFIRMED_WORKFLOW.create({ params: body });
          break;
        case 'booking.confirmed.enriched':
          await sendBookingConfirmedEnrichedEmail(body, env);
          break;
        case 'booking.completed':
          await env.BOOKING_COMPLETED_WORKFLOW.create({ params: body });
          break;
        case 'survey.call_experience':
          await sendSurveyEmail('call_experience', body, env);
          break;
        case 'survey.project_satisfaction':
          await sendSurveyEmail('project_satisfaction', body, env);
          break;
        case 'booking.cancelled':
        case 'booking.rescheduled':
        case 'booking.reminder_prospect':
        case 'booking.reminder_expert':
          // TODO(E06S16+): implement notification — stub acks for now
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

async function sendBookingConfirmedEnrichedEmail(
  body: Extract<EmailNotificationMessage, { type: 'booking.confirmed.enriched' }>,
  env: Env
): Promise<void> {
  const supabase = createServiceClient(env);

  // Fetch expert gcal_email and display_name
  const { data: expert, error: expertErr } = await supabase
    .from('experts')
    .select('gcal_email, display_name')
    .eq('id', body.expert_id)
    .single();

  if (expertErr || !expert?.gcal_email) {
    throw new Error(`Expert not found or no email for ${body.expert_id}: ${expertErr?.message}`);
  }

  // Fetch prospect name from bookings (denormalized)
  const { data: booking, error: bookingErr } = await supabase
    .from('bookings')
    .select('prospect_name')
    .eq('id', body.booking_id)
    .single();

  if (bookingErr) {
    throw new Error(`Booking not found for ${body.booking_id}: ${bookingErr.message}`);
  }

  // Fetch prospect requirements
  const { data: prospect } = await supabase
    .from('prospects')
    .select('requirements')
    .eq('id', body.prospect_id)
    .single();

  const prospectName = booking?.prospect_name ?? 'A prospect';
  const requirements = (prospect?.requirements && typeof prospect.requirements === 'object')
    ? prospect.requirements as Record<string, unknown>
    : null;

  const requirementsSummary = requirements
    ? [
        requirements['challenge'] ? `Challenge: ${String(requirements['challenge'])}` : null,
        Array.isArray(requirements['skills_needed']) && (requirements['skills_needed'] as unknown[]).length > 0
          ? `Skills needed: ${(requirements['skills_needed'] as string[]).join(', ')}`
          : null,
        requirements['industry'] ? `Industry: ${String(requirements['industry'])}` : null,
        requirements['timeline'] ? `Timeline: ${String(requirements['timeline'])}` : null,
      ].filter((line): line is string => line !== null).join('\n')
    : '';

  const bodyLines = [
    `Hi ${expert.display_name ?? 'Expert'},`,
    '',
    `${prospectName} has booked a call with you.`,
    '',
    ...(requirementsSummary ? ['Prospect context:', requirementsSummary, ''] : []),
    `Meeting link: ${body.meeting_url}`,
    `Scheduled: ${body.scheduled_at}`,
    '',
    'Good luck with the call!',
  ];
  const textBody = bodyLines.join('\n');

  await sendResendEmail(
    env.RESEND_API_KEY,
    expert.gcal_email,
    'New booking — prospect context',
    `<p>${textBody.replace(/\n/g, '<br>')}</p>`,
    textBody,
    env.EMAIL_FROM_DOMAIN || 'callibrate.io',
    env.EMAIL_REPLY_TO || 'support@callibrate.io'
  );
}

async function sendSurveyEmail(
  surveyType: 'call_experience' | 'project_satisfaction',
  body: Extract<EmailNotificationMessage, { type: 'survey.call_experience' | 'survey.project_satisfaction' }>,
  env: Env
): Promise<void> {
  const supabase = createServiceClient(env);

  // Fetch prospect email from bookings (denormalized)
  const { data: booking, error: bookingErr } = await supabase
    .from('bookings')
    .select('prospect_email')
    .eq('id', body.booking_id)
    .single();

  let prospectEmail: string;

  if (!bookingErr && booking?.prospect_email) {
    prospectEmail = booking.prospect_email;
  } else {
    // Fallback: query prospects table directly
    const { data: prospect, error: prospectErr } = await supabase
      .from('prospects')
      .select('email')
      .eq('id', body.prospect_id)
      .single();

    if (prospectErr || !prospect?.email) {
      throw new Error(`No email found for booking ${body.booking_id} / prospect ${body.prospect_id}`);
    }
    prospectEmail = prospect.email;
  }

  const token = await signSurveyToken(body.booking_id, body.prospect_id, env.PROSPECT_TOKEN_SECRET);
  const surveyPath = surveyType === 'call_experience' ? 'call-experience' : 'project-satisfaction';
  const surveyUrl = `${env.WORKER_BASE_URL}/api/surveys/${surveyPath}?token=${token}`;

  const isCallExperience = surveyType === 'call_experience';
  const subject = isCallExperience
    ? 'How was your call? (quick survey)'
    : 'How did the project go? (quick survey)';
  const textBody = isCallExperience
    ? `Hi,\n\nWe hope your call went well!\n\nWe'd love to hear how it went. It takes less than a minute:\n\n${surveyUrl}\n\nThank you for your feedback.`
    : `Hi,\n\nWe hope your project is progressing well!\n\nWe'd love to hear how things went with the expert. It takes less than a minute:\n\n${surveyUrl}\n\nThank you for your feedback.`;

  await sendResendEmail(
    env.RESEND_API_KEY,
    prospectEmail,
    subject,
    `<p>${textBody.replace(/\n/g, '<br>')}</p>`,
    textBody,
    env.EMAIL_FROM_DOMAIN || 'callibrate.io',
    env.EMAIL_REPLY_TO || 'support@callibrate.io'
  );
}
