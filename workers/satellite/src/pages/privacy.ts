export function renderPrivacyPolicy(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Privacy Policy — Callibrate</title>
  <meta name="description" content="Callibrate Privacy Policy — how we collect, use, and protect your data.">
  <meta name="robots" content="index, follow">
  <link rel="canonical" href="https://callibrate.io/privacy">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      color: #1a1a2e;
      background: #fafafa;
      line-height: 1.7;
    }
    .container {
      max-width: 720px;
      margin: 0 auto;
      padding: 3rem 1.5rem 5rem;
    }
    .logo-row {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 2.5rem;
      text-decoration: none;
    }
    .logo-name {
      font-size: 1.125rem;
      font-weight: 700;
      color: #4F46E5;
    }
    h1 {
      font-size: 2rem;
      font-weight: 700;
      color: #1a1a2e;
      margin-bottom: 0.5rem;
    }
    .updated {
      font-size: 0.875rem;
      color: #888;
      margin-bottom: 2.5rem;
    }
    h2 {
      font-size: 1.125rem;
      font-weight: 600;
      color: #1a1a2e;
      margin-top: 2rem;
      margin-bottom: 0.75rem;
    }
    p { margin-bottom: 1rem; color: #333; }
    ul {
      margin: 0.5rem 0 1rem 1.5rem;
      color: #333;
    }
    li { margin-bottom: 0.4rem; }
    a { color: #4F46E5; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .divider {
      border: none;
      border-top: 1px solid #e5e7eb;
      margin: 2.5rem 0;
    }
    @media (max-width: 640px) {
      h1 { font-size: 1.5rem; }
      .container { padding: 2rem 1rem 4rem; }
    }
  </style>
</head>
<body>
  <div class="container">
    <a href="https://callibrate.io" class="logo-row">
      <span class="logo-name">Callibrate</span>
    </a>

    <h1>Privacy Policy</h1>
    <p class="updated">Last updated: 23 February 2026</p>

    <p>
      Callibrate (&ldquo;we&rdquo;, &ldquo;our&rdquo;, &ldquo;us&rdquo;) operates the platform at
      <a href="https://callibrate.io">callibrate.io</a> and its satellite sites. This Privacy Policy
      explains what personal data we collect, why we collect it, how we use it, and your rights
      regarding that data.
    </p>

    <h2>1. What Data We Collect</h2>
    <p>We collect the following personal data, depending on how you use the platform:</p>
    <ul>
      <li>
        <strong>Email address</strong> — collected during expert registration and used as your
        login identifier and for transactional communications (booking confirmations, reminders,
        survey invitations).
      </li>
      <li>
        <strong>Profile information</strong> — for expert accounts: name, professional headline,
        biography, skills, hourly rate, and availability preferences that you provide.
      </li>
      <li>
        <strong>Google Calendar data</strong> — if you connect your Google Calendar as an expert,
        we request access to the
        <code>https://www.googleapis.com/auth/calendar.events</code> scope. This allows us to:
        <ul>
          <li>Read your free/busy availability to display open booking slots to prospects</li>
          <li>Create calendar events on your behalf when a booking is confirmed</li>
          <li>Add Google Meet conference links to those events</li>
        </ul>
        We do not read, store, or process the title or details of your existing calendar events.
        We only access event data in the context of creating or managing booking events initiated
        through Callibrate.
      </li>
      <li>
        <strong>Project requirements</strong> — for prospect accounts: the project description
        you submit via the intake form, which is processed by an AI service to extract structured
        requirements for matching purposes.
      </li>
      <li>
        <strong>Usage data</strong> — anonymised analytics events (page views, funnel steps)
        collected via PostHog. No cross-site tracking. No advertising cookies.
      </li>
    </ul>

    <h2>2. How We Use Your Data</h2>
    <ul>
      <li>To match prospects with the most relevant experts based on skills and availability</li>
      <li>To display expert availability and enable booking of consultation calls</li>
      <li>To create Google Calendar events with Google Meet links when a booking is confirmed</li>
      <li>To send transactional emails: booking confirmations, reminders, and follow-up surveys</li>
      <li>To compute and update an expert&rsquo;s composite score for ranking purposes</li>
      <li>To improve matching quality and platform performance via aggregated analytics</li>
    </ul>
    <p>
      We do not use your data for advertising, profiling for third-party purposes, or any purpose
      beyond operating the Callibrate platform.
    </p>

    <h2>3. Google Calendar OAuth</h2>
    <p>
      Callibrate&rsquo;s use of the <code>calendar.events</code> scope is limited to:
    </p>
    <ul>
      <li>Querying free/busy data to display availability to prospects</li>
      <li>
        Creating booking events (with Google Meet links) on behalf of an expert who has
        explicitly granted OAuth access
      </li>
      <li>Cancelling or rescheduling those booking events when requested</li>
    </ul>
    <p>
      We store only the OAuth refresh token, encrypted at rest (AES-256-GCM), to maintain the
      connection between sessions. We do not store calendar event content beyond what is required
      to manage bookings created through Callibrate.
    </p>
    <p>
      Callibrate&rsquo;s use and transfer of information received from Google APIs adheres to
      the <a href="https://developers.google.com/terms/api-services-user-data-policy" target="_blank" rel="noopener">
      Google API Services User Data Policy</a>, including the Limited Use requirements.
    </p>

    <h2>4. Data Sharing</h2>
    <p>
      We do not sell, rent, or share your personal data with third parties for their own purposes.
    </p>
    <p>We share minimal data with the following sub-processors solely to operate the platform:</p>
    <ul>
      <li><strong>Supabase</strong> — database hosting (EU region)</li>
      <li><strong>Cloudflare</strong> — edge computing and CDN (EU-based edge nodes)</li>
      <li><strong>Resend</strong> — transactional email delivery (your email address only)</li>
      <li>
        <strong>OpenAI</strong> — AI extraction of project requirements from prospect descriptions
        (no personal identifying information is sent)
      </li>
      <li><strong>PostHog EU</strong> — anonymised product analytics</li>
    </ul>
    <p>All sub-processors operate under data processing agreements consistent with GDPR.</p>

    <h2>5. Data Retention</h2>
    <ul>
      <li>Account data is retained for as long as your account is active.</li>
      <li>
        If you disconnect your Google Calendar, your OAuth refresh token is deleted immediately
        from our database.
      </li>
      <li>
        If you request account deletion, all personal data is deleted within 30 days, except
        where retention is required by law.
      </li>
      <li>Anonymised analytics data may be retained indefinitely.</li>
    </ul>

    <h2>6. Your Rights</h2>
    <p>
      Under GDPR and applicable data protection law, you have the right to:
    </p>
    <ul>
      <li><strong>Access</strong> the personal data we hold about you</li>
      <li><strong>Rectify</strong> inaccurate data</li>
      <li><strong>Delete</strong> your account and all associated personal data</li>
      <li>
        <strong>Disconnect</strong> your Google Calendar at any time via your expert profile
        settings — this immediately revokes our access to your calendar
      </li>
      <li><strong>Object</strong> to processing in certain circumstances</li>
      <li><strong>Data portability</strong> — request a copy of your data in machine-readable format</li>
    </ul>
    <p>
      To exercise any of these rights, email us at
      <a href="mailto:support@callibrate.io">support@callibrate.io</a>.
    </p>

    <h2>7. Cookies &amp; Tracking</h2>
    <p>
      We use PostHog EU for anonymised product analytics. PostHog is configured in
      memory-only persistence mode — no cookies are stored on your device for analytics purposes.
      We do not use any advertising or cross-site tracking cookies.
    </p>

    <h2>8. Data Controller</h2>
    <p>
      The data controller responsible for your personal data is:
    </p>
    <p>
      Callibrate<br>
      Email: <a href="mailto:support@callibrate.io">support@callibrate.io</a>
    </p>

    <h2>9. Changes to This Policy</h2>
    <p>
      We may update this Privacy Policy from time to time. Material changes will be communicated
      by email or via a notice on the platform. Continued use of the platform after such notice
      constitutes acceptance of the updated policy.
    </p>

    <hr class="divider">
    <p style="font-size: 0.875rem; color: #888;">
      Questions? Email <a href="mailto:support@callibrate.io">support@callibrate.io</a>
    </p>
  </div>
</body>
</html>`;
}
