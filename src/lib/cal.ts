/**
 * Cal.com v2 API client — Managed Users (Platform OAuth)
 *
 * Docs: https://cal.com/docs/api-reference/v2/managed-users
 *
 * Authentication:
 *   - Platform-level calls: x-cal-secret-key header (CAL_API_KEY)
 *   - Managed user calls: Authorization: Bearer {managedUserAccessToken}
 */

const CAL_API_BASE = 'https://api.cal.com/v2';
const CAL_API_VERSION = '2024-08-13';

export type CalManagedUser = {
  cal_user_id: string;
  cal_username: string;
  access_token: string;
  refresh_token: string;
};

type CalApiResponse<T> = {
  status: 'success' | 'error';
  data: T;
  error?: { message: string };
};

async function calRequest<T>(
  method: string,
  path: string,
  opts: {
    apiKey?: string;
    accessToken?: string;
    body?: unknown;
  } = {}
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'cal-api-version': CAL_API_VERSION,
  };

  if (opts.apiKey) {
    headers['x-cal-secret-key'] = opts.apiKey;
  }
  if (opts.accessToken) {
    headers['Authorization'] = `Bearer ${opts.accessToken}`;
  }

  const fetchInit: RequestInit = { method, headers };
  if (opts.body !== undefined) {
    fetchInit.body = JSON.stringify(opts.body);
  }

  const res = await fetch(`${CAL_API_BASE}${path}`, fetchInit);

  const json = (await res.json()) as CalApiResponse<T>;

  if (!res.ok || json.status === 'error') {
    throw new Error(
      `Cal.com API error ${res.status} on ${method} ${path}: ${json.error?.message ?? 'unknown error'}`
    );
  }

  return json.data;
}

/**
 * AC1: Create a Cal.com managed user for an expert.
 * Called synchronously at expert registration (DEC-34).
 */
export async function createManagedUser(
  apiKey: string,
  oauthClientId: string,
  opts: { email: string; name: string; timeZone?: string }
): Promise<CalManagedUser> {
  type CreateUserData = {
    user: { id: number; username: string };
    accessToken: string;
    refreshToken: string;
  };

  const data = await calRequest<CreateUserData>(
    'POST',
    `/oauth-clients/${oauthClientId}/users`,
    {
      apiKey,
      body: {
        email: opts.email,
        name: opts.name,
        timeZone: opts.timeZone ?? 'UTC',
      },
    }
  );

  return {
    cal_user_id: String(data.user.id),
    cal_username: data.user.username,
    access_token: data.accessToken,
    refresh_token: data.refreshToken,
  };
}

/**
 * AC2: Get Google Calendar OAuth authorization URL for a managed user.
 * Returns the URL the expert should visit to connect their Google Calendar.
 */
export async function getGoogleCalendarAuthUrl(
  accessToken: string,
  returnTo: string
): Promise<string> {
  type ConnectData = { url: string };

  const params = new URLSearchParams({ returnTo });
  const data = await calRequest<ConnectData>(
    'GET',
    `/conferencing/google-calendar/connect?${params.toString()}`,
    { accessToken }
  );

  return data.url;
}

/**
 * AC4: Auto-create "20-min Intro Call" event type on the managed user.
 * Called after Google Calendar is connected (OAuth callback).
 * Returns the Cal.com event type ID.
 */
export async function createIntroCallEventType(
  accessToken: string
): Promise<number> {
  type EventTypeData = { id: number };

  const data = await calRequest<EventTypeData>('POST', '/event-types', {
    accessToken,
    body: {
      title: '20-min Intro Call',
      slug: 'intro-call',
      length: 20,
      locations: [{ type: 'integrations:google:meet' }],
    },
  });

  return data.id;
}

/**
 * Refresh a managed user's access token using the refresh token.
 */
export async function refreshManagedUserToken(
  apiKey: string,
  oauthClientId: string,
  calUserId: string,
  refreshToken: string
): Promise<{ access_token: string; refresh_token: string }> {
  type RefreshData = { accessToken: string; refreshToken: string };

  const data = await calRequest<RefreshData>(
    'POST',
    `/oauth-clients/${oauthClientId}/users/${calUserId}/tokens`,
    {
      apiKey,
      body: { refreshToken },
    }
  );

  return {
    access_token: data.accessToken,
    refresh_token: data.refreshToken,
  };
}
