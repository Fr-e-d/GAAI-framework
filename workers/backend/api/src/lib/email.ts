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
