/**
 * E07S04 — PostHog Funnel Dashboards Setup
 *
 * Creates 3 dashboards via PostHog API:
 *   1. Prospect Conversion Funnel
 *   2. Expert Activation Funnel
 *   3. Business Overview
 *
 * Idempotent — safe to run multiple times (checks by name before creating).
 *
 * Usage:
 *   POSTHOG_PERSONAL_API_KEY=xxx POSTHOG_PROJECT_ID=yyy npx tsx scripts/posthog-setup-dashboards.ts
 *
 * Requires:
 *   - POSTHOG_PERSONAL_API_KEY: Personal API Key (Settings → Personal API Keys in PostHog)
 *   - POSTHOG_PROJECT_ID: Project numeric ID (visible in PostHog project URL)
 */

const BASE_URL = "https://eu.posthog.com";

interface DashboardSummary {
  id: number;
  name: string;
}

interface DashboardListResponse {
  results: DashboardSummary[];
  next: string | null;
}

interface DashboardCreateResponse {
  id: number;
  name: string;
}

interface InsightCreateResponse {
  id: number;
  name: string;
  short_id: string;
}

type InsightFilters = Record<string, unknown>;

interface InsightPayload {
  name: string;
  filters: InsightFilters;
  dashboards: number[];
}

async function phFetch(
  path: string,
  apiKey: string,
  options: RequestInit = {}
): Promise<unknown> {
  const url = `${BASE_URL}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      ...(options.headers as Record<string, string> | undefined),
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `PostHog API error ${response.status} at ${path}: ${body}`
    );
  }

  return response.json();
}

async function listAllDashboards(
  apiKey: string,
  projectId: string
): Promise<DashboardSummary[]> {
  const path = `/api/projects/${projectId}/dashboards/?limit=100`;
  const data = (await phFetch(path, apiKey)) as DashboardListResponse;
  return data.results;
}

async function createDashboard(
  apiKey: string,
  projectId: string,
  name: string,
  description: string
): Promise<DashboardCreateResponse> {
  const path = `/api/projects/${projectId}/dashboards/`;
  const data = await phFetch(path, apiKey, {
    method: "POST",
    body: JSON.stringify({ name, description }),
  });
  return data as DashboardCreateResponse;
}

async function createInsight(
  apiKey: string,
  projectId: string,
  payload: InsightPayload
): Promise<InsightCreateResponse> {
  const path = `/api/projects/${projectId}/insights/`;
  const data = await phFetch(path, apiKey, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  return data as InsightCreateResponse;
}

async function ensureDashboard(
  apiKey: string,
  projectId: string,
  name: string,
  description: string,
  existing: DashboardSummary[]
): Promise<{ id: number; created: boolean }> {
  const found = existing.find((d) => d.name === name);
  if (found !== undefined) {
    console.log(`  ↳ Dashboard "${name}" already exists (id=${found.id}) — skipping`);
    return { id: found.id, created: false };
  }

  const dashboard = await createDashboard(apiKey, projectId, name, description);
  console.log(`  ↳ Dashboard "${name}" created (id=${dashboard.id})`);
  return { id: dashboard.id, created: true };
}

async function main(): Promise<void> {
  // AC5: Read env vars
  const apiKey = process.env["POSTHOG_PERSONAL_API_KEY"];
  const projectId = process.env["POSTHOG_PROJECT_ID"];

  if (!apiKey) {
    console.error(
      "Error: POSTHOG_PERSONAL_API_KEY is required.\n" +
        "Generate one at: https://eu.posthog.com/settings/user-api-keys"
    );
    process.exit(1);
  }

  if (!projectId) {
    console.error(
      "Error: POSTHOG_PROJECT_ID is required.\n" +
        "Find it in your PostHog project URL: https://eu.posthog.com/project/{id}/..."
    );
    process.exit(1);
  }

  console.log(`PostHog Dashboard Setup — Project ID: ${projectId}`);
  console.log("─────────────────────────────────────────");

  // AC6: Load existing dashboards once — used for idempotency checks
  console.log("\nFetching existing dashboards...");
  const existing = await listAllDashboards(apiKey, projectId);
  console.log(`Found ${existing.length} existing dashboard(s).`);

  const createdUrls: Array<{ name: string; url: string }> = [];

  // ── Dashboard 1: Prospect Conversion Funnel (AC2) ──────────────────────────
  console.log("\n[1/3] Prospect Conversion Funnel");
  const { id: prospectDashId, created: prospectCreated } = await ensureDashboard(
    apiKey,
    projectId,
    "Prospect Conversion Funnel",
    "Prospect journey from form submission to confirmed booking, broken down by satellite.",
    existing
  );

  if (prospectCreated) {
    await createInsight(apiKey, projectId, {
      name: "Prospect Conversion Funnel",
      filters: {
        insight: "FUNNELS",
        events: [
          { id: "prospect.form_submitted", name: "prospect.form_submitted", order: 0, type: "events" },
          { id: "prospect.matches_viewed", name: "prospect.matches_viewed", order: 1, type: "events" },
          { id: "prospect.identified", name: "prospect.identified", order: 2, type: "events" },
          { id: "booking.held", name: "booking.held", order: 3, type: "events" },
          { id: "booking.confirmed", name: "booking.confirmed", order: 4, type: "events" },
        ],
        breakdown: "satellite_id",
        breakdown_type: "event",
        date_from: "-30d",
        funnel_window_interval: 14,
        funnel_window_interval_unit: "day",
      },
      dashboards: [prospectDashId],
    });
    console.log(`  ↳ Insight "Prospect Conversion Funnel" created`);
  }

  const prospectUrl = `${BASE_URL}/project/${projectId}/dashboard/${prospectDashId}`;
  createdUrls.push({ name: "Prospect Conversion Funnel", url: prospectUrl });

  // ── Dashboard 2: Expert Activation Funnel (AC3) ────────────────────────────
  console.log("\n[2/3] Expert Activation Funnel");
  const { id: expertDashId, created: expertCreated } = await ensureDashboard(
    apiKey,
    projectId,
    "Expert Activation Funnel",
    "Expert journey from registration to first confirmed booking.",
    existing
  );

  if (expertCreated) {
    await createInsight(apiKey, projectId, {
      name: "Expert Activation Funnel",
      filters: {
        insight: "FUNNELS",
        events: [
          { id: "expert.registered", name: "expert.registered", order: 0, type: "events" },
          { id: "expert.profile_updated", name: "expert.profile_updated", order: 1, type: "events" },
          { id: "expert.gcal_connected", name: "expert.gcal_connected", order: 2, type: "events" },
          { id: "booking.confirmed", name: "booking.confirmed", order: 3, type: "events" },
        ],
        date_from: "-30d",
        funnel_window_interval: 30,
        funnel_window_interval_unit: "day",
      },
      dashboards: [expertDashId],
    });
    console.log(`  ↳ Insight "Expert Activation Funnel" created`);
  }

  const expertUrl = `${BASE_URL}/project/${projectId}/dashboard/${expertDashId}`;
  createdUrls.push({ name: "Expert Activation Funnel", url: expertUrl });

  // ── Dashboard 3: Business Overview (AC4) ──────────────────────────────────
  console.log("\n[3/3] Business Overview");
  const { id: overviewDashId, created: overviewCreated } = await ensureDashboard(
    apiKey,
    projectId,
    "Business Overview",
    "Daily activity trends and overall prospect-to-booking conversion rate.",
    existing
  );

  if (overviewCreated) {
    // Insight A: Daily prospect.form_submitted
    await createInsight(apiKey, projectId, {
      name: "Daily prospect.form_submitted",
      filters: {
        insight: "TRENDS",
        events: [{ id: "prospect.form_submitted", name: "prospect.form_submitted", order: 0, type: "events" }],
        date_from: "-30d",
        interval: "day",
      },
      dashboards: [overviewDashId],
    });
    console.log(`  ↳ Insight "Daily prospect.form_submitted" created`);

    // Insight B: Daily booking.confirmed
    await createInsight(apiKey, projectId, {
      name: "Daily booking.confirmed",
      filters: {
        insight: "TRENDS",
        events: [{ id: "booking.confirmed", name: "booking.confirmed", order: 0, type: "events" }],
        date_from: "-30d",
        interval: "day",
      },
      dashboards: [overviewDashId],
    });
    console.log(`  ↳ Insight "Daily booking.confirmed" created`);

    // Insight C: Daily expert.registered
    await createInsight(apiKey, projectId, {
      name: "Daily expert.registered",
      filters: {
        insight: "TRENDS",
        events: [{ id: "expert.registered", name: "expert.registered", order: 0, type: "events" }],
        date_from: "-30d",
        interval: "day",
      },
      dashboards: [overviewDashId],
    });
    console.log(`  ↳ Insight "Daily expert.registered" created`);

    // Insight D: Form to Booking Conversion Rate (formula: B/A)
    await createInsight(apiKey, projectId, {
      name: "Form to Booking Conversion Rate",
      filters: {
        insight: "TRENDS",
        events: [
          { id: "prospect.form_submitted", name: "prospect.form_submitted", order: 0, type: "events", math: "total" },
          { id: "booking.confirmed", name: "booking.confirmed", order: 1, type: "events", math: "total" },
        ],
        formula: "B/A*100",
        date_from: "-30d",
        interval: "day",
        display: "ActionsLineGraph",
      },
      dashboards: [overviewDashId],
    });
    console.log(`  ↳ Insight "Form to Booking Conversion Rate" created`);
  }

  const overviewUrl = `${BASE_URL}/project/${projectId}/dashboard/${overviewDashId}`;
  createdUrls.push({ name: "Business Overview", url: overviewUrl });

  // AC7: Output dashboard URLs on success
  console.log("\n─────────────────────────────────────────");
  console.log("✓ Setup complete. Dashboard URLs:");
  for (const { name, url } of createdUrls) {
    console.log(`  • ${name}: ${url}`);
  }
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  console.error(`\nError: ${message}`);
  process.exit(1);
});
