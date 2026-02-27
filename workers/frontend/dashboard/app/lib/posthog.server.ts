/**
 * Server-side PostHog event capture for the dashboard Worker.
 * Uses direct fetch to PostHog EU API — no client-side proxy needed for server events.
 * No-op if POSTHOG_API_KEY is not configured.
 */

const POSTHOG_EU_ENDPOINT = "https://eu.i.posthog.com/capture/";

export async function captureEvent(
  env: Env,
  distinctId: string,
  event: string,
  properties: Record<string, unknown> = {},
): Promise<void> {
  if (!env.POSTHOG_API_KEY) return;

  try {
    await fetch(POSTHOG_EU_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: env.POSTHOG_API_KEY,
        event,
        distinct_id: distinctId,
        properties,
      }),
    });
  } catch {
    // Non-blocking — analytics must never break the action
  }
}
