export function renderTermsOfService(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Terms of Service — Callibrate</title>
  <meta name="description" content="Callibrate Terms of Service — the rules governing use of the platform.">
  <meta name="robots" content="index, follow">
  <link rel="canonical" href="https://callibrate.io/terms">
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

    <h1>Terms of Service</h1>
    <p class="updated">Last updated: 23 February 2026</p>

    <p>
      These Terms of Service (&ldquo;Terms&rdquo;) govern your use of the Callibrate platform
      (&ldquo;Platform&rdquo;) operated by Callibrate (&ldquo;we&rdquo;, &ldquo;our&rdquo;,
      &ldquo;us&rdquo;). By accessing or using the Platform, you agree to be bound by these Terms.
    </p>

    <h2>1. Service Description</h2>
    <p>
      Callibrate is a B2B marketplace that connects businesses (&ldquo;Prospects&rdquo;) with
      AI automation and integration experts (&ldquo;Experts&rdquo;) for paid consultation calls.
      The Platform facilitates matching, scheduling, and billing. It does not employ Experts and
      is not a party to any service agreement between an Expert and a Prospect.
    </p>

    <h2>2. Eligibility</h2>
    <p>
      You must be at least 18 years old and legally capable of entering into a binding contract
      to use the Platform. By creating an account, you represent that these conditions are met.
    </p>

    <h2>3. Expert Accounts</h2>
    <p>Experts using the Platform agree to:</p>
    <ul>
      <li>Provide accurate, complete, and up-to-date profile information</li>
      <li>Maintain calendar availability that accurately reflects their actual availability</li>
      <li>Honour confirmed bookings or cancel with reasonable notice (minimum 24 hours)</li>
      <li>
        Grant Callibrate access to their Google Calendar solely for availability display and
        booking creation, as described in the <a href="/privacy">Privacy Policy</a>
      </li>
      <li>Not engage in deceptive, misleading, or fraudulent conduct toward Prospects</li>
      <li>
        Comply with all applicable laws when providing services to Prospects
      </li>
    </ul>

    <h2>4. Prospect Accounts</h2>
    <p>Prospects using the Platform agree to:</p>
    <ul>
      <li>Provide accurate information about their project and requirements</li>
      <li>Attend booked sessions or cancel at least 24 hours in advance</li>
      <li>Not use the Platform to solicit Experts outside the Platform for unpaid engagements</li>
      <li>
        Use expert contact information and project insights shared through the Platform only
        for legitimate business purposes
      </li>
    </ul>

    <h2>5. Bookings and Payments</h2>
    <p>
      Consultation calls are billed through the Callibrate credit system. Rates are set by
      Experts and displayed before booking. Credits are deducted when a booking is confirmed.
      Credits may be restored if a lead is disputed within the 7-day flag window and the
      dispute is upheld, as described in the Platform documentation.
    </p>
    <p>
      Callibrate is not responsible for the quality, outcome, or results of any consultation
      call between an Expert and a Prospect.
    </p>

    <h2>6. Acceptable Use</h2>
    <p>You agree not to:</p>
    <ul>
      <li>Use the Platform for any unlawful purpose or in violation of any applicable law</li>
      <li>Attempt to gain unauthorised access to any part of the Platform or its infrastructure</li>
      <li>Scrape, crawl, or systematically extract data from the Platform</li>
      <li>Use automated tools to interact with the Platform without prior written consent</li>
      <li>
        Circumvent any matching, billing, or anti-abuse mechanisms of the Platform
      </li>
      <li>Post false, misleading, or defamatory content</li>
    </ul>

    <h2>7. Intellectual Property</h2>
    <p>
      All Platform content, design, code, and branding are owned by Callibrate or its licensors.
      You are granted a limited, non-exclusive, non-transferable licence to use the Platform
      for its intended purpose. You retain ownership of any content you submit (profile
      information, project descriptions) and grant Callibrate a licence to use it to operate
      the Platform.
    </p>

    <h2>8. Limitation of Liability</h2>
    <p>
      To the fullest extent permitted by applicable law, Callibrate shall not be liable for
      any indirect, incidental, special, consequential, or punitive damages arising out of or
      related to your use of the Platform, including but not limited to loss of profits, loss
      of data, or failure to find a suitable Expert or Prospect.
    </p>
    <p>
      Our total liability to you for any claim arising under these Terms shall not exceed the
      amount you paid to Callibrate in the twelve months preceding the claim.
    </p>

    <h2>9. Disclaimers</h2>
    <p>
      The Platform is provided &ldquo;as is&rdquo; and &ldquo;as available&rdquo; without
      warranties of any kind, express or implied. We do not warrant that the Platform will
      be uninterrupted, error-free, or free of harmful components. Expert matching is
      algorithmic and we make no guarantee of match quality or session outcomes.
    </p>

    <h2>10. Termination</h2>
    <p>
      We reserve the right to suspend or terminate your account if you violate these Terms,
      engage in fraudulent activity, or for any other reason at our sole discretion, with
      or without notice. You may close your account at any time by contacting
      <a href="mailto:support@callibrate.io">support@callibrate.io</a>.
    </p>

    <h2>11. Changes to These Terms</h2>
    <p>
      We may update these Terms from time to time. We will notify you of material changes
      by email or via a notice on the Platform. Continued use of the Platform after such
      notice constitutes acceptance of the updated Terms.
    </p>

    <h2>12. Governing Law</h2>
    <p>
      These Terms are governed by the laws of France, without regard to conflict of law
      principles. Any disputes shall be subject to the exclusive jurisdiction of the courts
      of France, except where mandatory local law provides otherwise.
    </p>

    <h2>13. Contact</h2>
    <p>
      For questions about these Terms, contact us at
      <a href="mailto:support@callibrate.io">support@callibrate.io</a>.
    </p>

    <hr class="divider">
    <p style="font-size: 0.875rem; color: #888;">
      Also see our <a href="/privacy">Privacy Policy</a>
    </p>
  </div>
</body>
</html>`;
}
