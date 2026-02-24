import { PostHog } from 'posthog-node';

const POSTHOG_HOST = 'https://eu.i.posthog.com';

export interface CapturePayload {
  distinctId: string;
  event: string;
  properties?: Record<string, unknown>;
}

export function captureEvent(
  apiKey: string | undefined,
  payload: CapturePayload,
): Promise<void> {
  if (!apiKey) return Promise.resolve();

  const ph = new PostHog(apiKey, {
    host: POSTHOG_HOST,
    flushAt: 1,
    flushInterval: 0,
  });

  return ph
    .captureImmediate({
      distinctId: payload.distinctId,
      event: payload.event,
      properties: payload.properties ?? {},
    })
    .catch(() => {
      // AC9: swallow all PostHog errors — never surface to API caller
    });
}
