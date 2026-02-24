import { Env } from '../types/env';
import { createSql } from './db';
import { decryptToken } from './gcalCrypto';
import { refreshGcalToken } from './gcalRefresh';
import type { ExpertRow } from '../types/db';

export class GcalApiError extends Error {
  constructor(public readonly gcalStatus: number, public readonly gcalMessage: string) {
    super(`GCal API error ${gcalStatus}: ${gcalMessage}`);
    this.name = 'GcalApiError';
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Gets the current access token — decrypts stored token, refreshes if expired
export async function getAccessToken(expertId: string, env: Env): Promise<string> {
  const sql = createSql(env);
  const [data] = await sql<Pick<ExpertRow, 'gcal_access_token' | 'gcal_token_expiry_at'>[]>`
    SELECT gcal_access_token, gcal_token_expiry_at FROM experts WHERE id = ${expertId}`;

  if (!data?.gcal_access_token) {
    throw new GcalApiError(0, 'Expert has no stored access token');
  }

  // Check expiry (with 60s buffer)
  const expiryAt = data.gcal_token_expiry_at ? new Date(data.gcal_token_expiry_at) : null;
  if (expiryAt && expiryAt.getTime() - Date.now() > 60_000) {
    // Token still valid — decrypt and return
    try {
      return await decryptToken(data.gcal_access_token, env.GCAL_TOKEN_ENCRYPTION_KEY);
    } catch {
      // Decryption failed — fall through to refresh
    }
  }

  // Token expired or decrypt failed — refresh
  return refreshGcalToken(expertId, env);
}

// Wraps a GCal API call with AC10 retry logic
// - 429: exponential backoff (1s, 4s, 16s), max 3 retries
// - 401: refreshGcalToken + retry once
// - Other non-2xx: throw GcalApiError
async function withGcalRetry<T>(
  fn: () => Promise<{ status: number; data: T }>,
  onTokenRefresh: () => Promise<string>,
  context: { expertId: string; env: Env },
  attempt = 0
): Promise<T> {
  const result = await fn();

  if (result.status >= 200 && result.status < 300) {
    return result.data;
  }

  if (result.status === 429 && attempt < 3) {
    const delay = [1000, 4000, 16000][attempt] ?? 16000;
    await sleep(delay);
    return withGcalRetry(fn, onTokenRefresh, context, attempt + 1);
  }

  if (result.status === 401 && attempt === 0) {
    await onTokenRefresh();
    return withGcalRetry(fn, onTokenRefresh, context, attempt + 1);
  }

  throw new GcalApiError(result.status, `GCal API returned ${result.status}`);
}

// Queries Google Calendar Freebusy API
// Returns array of busy intervals [{start, end}] in UTC ISO format
export async function gcalFreebusy(
  accessToken: string,
  calendarId: string,
  timeMin: string,
  timeMax: string,
  expertId: string,
  env: Env
): Promise<Array<{ start: string; end: string }>> {
  let currentToken = accessToken;

  const doRequest = async () => {
    const res = await fetch('https://www.googleapis.com/calendar/v3/freeBusy', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${currentToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        timeMin,
        timeMax,
        items: [{ id: calendarId }],
      }),
    });

    if (!res.ok) {
      return { status: res.status, data: [] as Array<{ start: string; end: string }> };
    }

    const json = await res.json() as { calendars: Record<string, { busy: Array<{ start: string; end: string }> }> };
    const busy = json.calendars?.[calendarId]?.busy ?? [];
    return { status: 200, data: busy };
  };

  const onTokenRefresh = async () => {
    currentToken = await refreshGcalToken(expertId, env);
    return currentToken;
  };

  return withGcalRetry(doRequest, onTokenRefresh, { expertId, env });
}

export interface GCalEventInput {
  summary: string;
  description?: string;
  start: { dateTime: string; timeZone: string };
  end: { dateTime: string; timeZone: string };
  attendees: Array<{ email: string }>;
  conferenceData?: {
    createRequest: { requestId: string; conferenceSolutionKey: { type: string } };
  };
}

export interface GCalEventResult {
  eventId: string;
  meetingUrl: string | null;
  htmlLink: string | null;
}

// Creates a Google Calendar event (with optional conference data)
export async function gcalInsertEvent(
  accessToken: string,
  calendarId: string,
  event: GCalEventInput,
  expertId: string,
  env: Env
): Promise<GCalEventResult> {
  let currentToken = accessToken;

  const doRequest = async () => {
    const params = new URLSearchParams({ conferenceDataVersion: '1' });
    const res = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events?${params}`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${currentToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(event),
      }
    );

    if (!res.ok) {
      return { status: res.status, data: { eventId: '', meetingUrl: null, htmlLink: null } };
    }

    const json = await res.json() as {
      id: string;
      htmlLink?: string;
      conferenceData?: { entryPoints?: Array<{ entryPointType: string; uri: string }> };
    };

    const meetLink = json.conferenceData?.entryPoints?.find(e => e.entryPointType === 'video')?.uri ?? null;

    return {
      status: 200,
      data: {
        eventId: json.id,
        meetingUrl: meetLink,
        htmlLink: json.htmlLink ?? null,
      },
    };
  };

  const onTokenRefresh = async () => {
    currentToken = await refreshGcalToken(expertId, env);
    return currentToken;
  };

  return withGcalRetry(doRequest, onTokenRefresh, { expertId, env });
}

// Deletes a Google Calendar event — treats 404 as success (AC10)
export async function gcalDeleteEvent(
  accessToken: string,
  calendarId: string,
  eventId: string,
  expertId: string,
  env: Env
): Promise<void> {
  let currentToken = accessToken;

  const doRequest = async () => {
    const res = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${currentToken}` },
      }
    );

    // 404 = already deleted = success (AC10)
    if (res.status === 404 || (res.status >= 200 && res.status < 300)) {
      return { status: 200, data: undefined as void };
    }

    return { status: res.status, data: undefined as void };
  };

  const onTokenRefresh = async () => {
    currentToken = await refreshGcalToken(expertId, env);
    return currentToken;
  };

  await withGcalRetry(doRequest, onTokenRefresh, { expertId, env });
}

// Patches a Google Calendar event (reschedule)
export async function gcalPatchEvent(
  accessToken: string,
  calendarId: string,
  eventId: string,
  patch: { start?: { dateTime: string; timeZone: string }; end?: { dateTime: string; timeZone: string } },
  expertId: string,
  env: Env
): Promise<GCalEventResult> {
  let currentToken = accessToken;

  const doRequest = async () => {
    const res = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(eventId)}`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${currentToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(patch),
      }
    );

    if (!res.ok) {
      return { status: res.status, data: { eventId: '', meetingUrl: null, htmlLink: null } };
    }

    const json = await res.json() as {
      id: string;
      htmlLink?: string;
      conferenceData?: { entryPoints?: Array<{ entryPointType: string; uri: string }> };
    };

    const meetLink = json.conferenceData?.entryPoints?.find(e => e.entryPointType === 'video')?.uri ?? null;

    return {
      status: 200,
      data: {
        eventId: json.id,
        meetingUrl: meetLink,
        htmlLink: json.htmlLink ?? null,
      },
    };
  };

  const onTokenRefresh = async () => {
    currentToken = await refreshGcalToken(expertId, env);
    return currentToken;
  };

  return withGcalRetry(doRequest, onTokenRefresh, { expertId, env });
}
