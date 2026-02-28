// ── Email — provider-agnostic send interface ───────────────────────────────────
// AC2: Resend API integration with a provider-agnostic interface.
// The interface uses SendEmailOptions so callers are decoupled from Resend details.
// Graceful error handling: throws on non-2xx so callers can catch and handle.

export interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text: string;
  from?: string;        // defaults to notifications@{fromDomain}
  replyTo?: string;
}

export interface EmailProviderConfig {
  apiKey: string;
  fromDomain: string;
  replyTo: string;
}

export async function sendEmail(options: SendEmailOptions, config: EmailProviderConfig): Promise<void> {
  const from = options.from ?? `Callibrate <notifications@${config.fromDomain}>`;
  const replyTo = options.replyTo ?? config.replyTo;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [options.to],
      subject: options.subject,
      html: options.html,
      text: options.text,
      reply_to: replyTo,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Email send failed (${res.status}): ${body}`);
  }
}

// Build the OTP email HTML and text bodies (AC9: plain HTML, all-client compatible).
export function buildOtpEmail(code: string): { html: string; text: string } {
  const text = [
    'Your Callibrate verification code:',
    '',
    code,
    '',
    'This code expires in 10 minutes. Do not share it with anyone.',
    '',
    'If you did not request this code, you can ignore this email.',
  ].join('\n');

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Your Callibrate code</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Your Callibrate verification code:</p>
  <p style="font-size:32px;font-weight:bold;letter-spacing:8px;text-align:center;padding:16px;background:#f4f4f4;border-radius:4px;">${code}</p>
  <p>This code expires in <strong>10 minutes</strong>. Do not share it with anyone.</p>
  <p style="color:#888;font-size:12px;">If you did not request this code, you can ignore this email.</p>
</body>
</html>`;

  return { html, text };
}

export function buildConfirmationEmail(opts: {
  expertName: string;
  confirmUrl: string;
  cancelUrl: string;
  startAt: string;
  expiryMinutes: number;
}): { html: string; text: string } {
  const dateStr = new Date(opts.startAt).toLocaleString('fr-FR', {
    timeZone: 'UTC',
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit'
  });

  const text = [
    `Bonjour,`,
    ``,
    `Vous avez demandé un appel découverte avec ${opts.expertName}.`,
    ``,
    `Date : ${dateStr} (UTC)`,
    ``,
    `Confirmez votre réservation en cliquant sur ce lien :`,
    opts.confirmUrl,
    ``,
    `Pour annuler : ${opts.cancelUrl}`,
    ``,
    `Ce lien expire dans ${opts.expiryMinutes} minutes. Sans confirmation, le créneau sera libéré.`,
    ``,
    `Si vous n'avez pas effectué cette réservation, ignorez cet email.`,
    ``,
    `— Callibrate`,
  ].join('\n');

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>Confirmez votre appel</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Bonjour,</p>
  <p>Vous avez demandé un appel découverte avec <strong>${opts.expertName}</strong>.</p>
  <p><strong>Date :</strong> ${dateStr} (UTC)</p>
  <p>Cliquez sur le bouton ci-dessous pour confirmer votre réservation :</p>
  <p style="text-align:center;margin:24px 0;">
    <a href="${opts.confirmUrl}" style="background:#4F46E5;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;">
      Confirmer mon appel
    </a>
  </p>
  <p>Si vous souhaitez annuler, <a href="${opts.cancelUrl}" style="color:#4F46E5;">cliquez ici</a>.</p>
  <p style="color:#888;font-size:12px;">Ce lien expire dans ${opts.expiryMinutes} minutes. Sans confirmation, le créneau sera libéré.</p>
  <p style="color:#888;font-size:12px;">Si vous n'avez pas effectué cette réservation, ignorez cet email.</p>
  <p style="margin-top:24px;font-size:12px;color:#888;">— Callibrate</p>
</body>
</html>`;
  return { html, text };
}

export function buildReminderEmail(opts: {
  recipientType: 'prospect' | 'expert';
  expertName: string;
  prospectName: string | null;
  startAt: string;
  meetingUrl: string | null;
  reminderType: 'j1' | 'h1';
}): { html: string; text: string } {
  const dateStr = new Date(opts.startAt).toLocaleString('fr-FR', {
    timeZone: 'UTC',
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit'
  });
  const urgency = opts.reminderType === 'h1' ? ' (dans 1 heure !)' : ' (demain)';
  const recipient = opts.recipientType === 'prospect' ? opts.expertName : (opts.prospectName ?? 'votre prospect');

  const lines = [
    `Bonjour,`,
    ``,
    `Rappel : vous avez un appel${urgency} avec ${recipient}.`,
    ``,
    `Date : ${dateStr} (UTC)`,
  ];
  if (opts.meetingUrl) {
    lines.push(``, `Lien de réunion : ${opts.meetingUrl}`);
  }
  lines.push(``, `— Callibrate`);
  const text = lines.join('\n');

  const meetHtml = opts.meetingUrl
    ? `<p><a href="${opts.meetingUrl}" style="background:#059669;color:#fff;padding:10px 20px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;">Rejoindre Google Meet</a></p>`
    : '';

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>Rappel — votre appel</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Bonjour,</p>
  <p>Rappel : vous avez un appel<strong>${urgency}</strong> avec <strong>${recipient}</strong>.</p>
  <p><strong>Date :</strong> ${dateStr} (UTC)</p>
  ${meetHtml}
  <p style="margin-top:24px;font-size:12px;color:#888;">— Callibrate</p>
</body>
</html>`;
  return { html, text };
}

// E02S12 AC16: Direct booking email confirmation (sent to prospect to confirm their email)
export function buildDirectConfirmationEmail(opts: {
  confirmUrl: string;
  expiryHours: number;
}): { html: string; text: string } {
  const text = [
    `Hello,`,
    ``,
    `You have submitted a booking request via an expert's direct link on Callibrate.`,
    ``,
    `Please confirm your email address by clicking the link below:`,
    opts.confirmUrl,
    ``,
    `This link expires in ${opts.expiryHours} hours.`,
    ``,
    `If you did not submit this request, you can ignore this email.`,
    ``,
    `Powered by Callibrate`,
  ].join('\n');

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Confirm your booking request</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Hello,</p>
  <p>You have submitted a booking request via an expert&rsquo;s direct link on Callibrate.</p>
  <p>Please confirm your email address to proceed:</p>
  <p style="text-align:center;margin:24px 0;">
    <a href="${opts.confirmUrl}" style="background:#4F46E5;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;">
      Confirm my booking request
    </a>
  </p>
  <p style="color:#888;font-size:12px;">This link expires in ${opts.expiryHours} hours.</p>
  <p style="color:#888;font-size:12px;">If you did not submit this request, you can ignore this email.</p>
  <p style="margin-top:24px;font-size:12px;color:#888;">Powered by <a href="https://callibrate.io" style="color:#4F46E5;">Callibrate</a></p>
</body>
</html>`;

  return { html, text };
}

// E02S12 AC17: Expert prep email for confirmed direct bookings
export function buildDirectPrepEmail(opts: {
  expertName: string;
  requirementsBrief: string;
  startAt: string;
  prepUrl: string;
}): { html: string; text: string } {
  const dateStr = new Date(opts.startAt).toLocaleString('en-GB', {
    timeZone: 'UTC',
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit'
  });

  const text = [
    `Hello ${opts.expertName},`,
    ``,
    `A prospect has confirmed a booking via your direct link on Callibrate.`,
    ``,
    `Date: ${dateStr} (UTC)`,
    ``,
    `Requirements summary:`,
    opts.requirementsBrief,
    ``,
    `View the full prep sheet: ${opts.prepUrl}`,
    ``,
    `Powered by Callibrate`,
  ].join('\n');

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Direct booking confirmed</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Hello ${opts.expertName},</p>
  <p>A prospect has confirmed a booking via your <strong>direct link</strong> on Callibrate.</p>
  <p><strong>Date:</strong> ${dateStr} (UTC)</p>
  <p><strong>Requirements summary:</strong></p>
  <blockquote style="border-left:4px solid #4F46E5;padding:8px 16px;color:#444;background:#f9fafb;border-radius:0 4px 4px 0;">
    ${opts.requirementsBrief.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}
  </blockquote>
  <p style="text-align:center;margin:24px 0;">
    <a href="${opts.prepUrl}" style="background:#059669;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;">
      View full prep sheet
    </a>
  </p>
  <p style="margin-top:24px;font-size:12px;color:#888;">Powered by <a href="https://callibrate.io" style="color:#4F46E5;">Callibrate</a></p>
</body>
</html>`;

  return { html, text };
}

export function buildExpertApprovalEmail(opts: {
  expertName: string;
  prospectName: string;
  startAt: string;
  approveUrl: string;
  rejectUrl: string;
  expiryHours: number;
}): { html: string; text: string } {
  const dateStr = new Date(opts.startAt).toLocaleString('fr-FR', {
    timeZone: 'UTC',
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit'
  });

  const text = [
    `Bonjour ${opts.expertName},`,
    ``,
    `${opts.prospectName} souhaite réserver un appel avec vous.`,
    ``,
    `Date proposée : ${dateStr} (UTC)`,
    ``,
    `Accepter : ${opts.approveUrl}`,
    `Refuser : ${opts.rejectUrl}`,
    ``,
    `Ce lien expire dans ${opts.expiryHours}h. Sans réponse, la réservation sera automatiquement confirmée.`,
    ``,
    `— Callibrate`,
  ].join('\n');

  const html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>Nouvelle demande de réservation</title></head>
<body style="font-family:sans-serif;color:#111;max-width:480px;margin:0 auto;padding:24px;">
  <p>Bonjour ${opts.expertName},</p>
  <p><strong>${opts.prospectName}</strong> souhaite réserver un appel avec vous.</p>
  <p><strong>Date proposée :</strong> ${dateStr} (UTC)</p>
  <p style="text-align:center;margin:24px 0;">
    <a href="${opts.approveUrl}" style="background:#059669;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;margin-right:8px;">Accepter</a>
    <a href="${opts.rejectUrl}" style="background:#DC2626;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;display:inline-block;">Refuser</a>
  </p>
  <p style="color:#888;font-size:12px;">Sans réponse dans ${opts.expiryHours}h, la réservation sera automatiquement confirmée.</p>
  <p style="margin-top:24px;font-size:12px;color:#888;">— Callibrate</p>
</body>
</html>`;
  return { html, text };
}
