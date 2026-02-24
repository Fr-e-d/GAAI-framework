import { Env } from '../types/env';
import { createSql } from './db';
import { decryptToken, encryptToken } from './gcalCrypto';
import type { ExpertRow } from '../types/db';

export class GcalNotConnectedError extends Error {
  constructor(expertId: string) {
    super(`Expert ${expertId} has no stored Google Calendar refresh token`);
    this.name = 'GcalNotConnectedError';
  }
}

export class GcalRefreshError extends Error {
  constructor(status: number, body: string) {
    super(`Google token refresh failed: ${status} — ${body}`);
    this.name = 'GcalRefreshError';
  }
}

/**
 * Refreshes the Google Calendar access token for an expert.
 * Retrieves the stored refresh token, calls Google Token endpoint,
 * updates gcal_access_token + gcal_token_expiry_at in DB.
 * Returns the fresh (unencrypted) access token for immediate use.
 *
 * AC6 caller contract (for E06S11 implementors):
 * If Google Calendar API returns 401/403, call this utility once and retry.
 * If still 401/403 after refresh, set gcal_connected = false and return { error: "gcal_disconnected" }.
 */
export async function refreshGcalToken(expertId: string, env: Env): Promise<string> {
  const sql = createSql(env);

  const [data] = await sql<Pick<ExpertRow, 'gcal_refresh_token'>[]>`
    SELECT gcal_refresh_token FROM experts WHERE id = ${expertId}`;

  if (!data || !data.gcal_refresh_token) {
    throw new GcalNotConnectedError(expertId);
  }

  const refreshToken = await decryptToken(data.gcal_refresh_token, env.GCAL_TOKEN_ENCRYPTION_KEY);

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      grant_type: 'refresh_token',
    }).toString(),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new GcalRefreshError(response.status, body);
  }

  const tokens = await response.json() as { access_token: string; expires_in?: number };
  const { access_token, expires_in } = tokens;

  const newExpiryAt = new Date(Date.now() + (expires_in ?? 3600) * 1000).toISOString();
  const encryptedAccessToken = await encryptToken(access_token, env.GCAL_TOKEN_ENCRYPTION_KEY);

  // Best-effort DB update — if it fails, return the fresh token anyway (in-flight use succeeds)
  await sql`UPDATE experts SET gcal_access_token = ${encryptedAccessToken}, gcal_token_expiry_at = ${newExpiryAt} WHERE id = ${expertId}`;

  return access_token;
}
