// ── Booking confirmation tokens ──────────────────────────────────────────────
// HMAC-SHA256 signed JWT, same pattern as lib/jwt.ts.
// Uses BOOKING_CONFIRM_SECRET (separate from PROSPECT_TOKEN_SECRET).

export type BookingTokenAction =
  | 'confirm'         // prospect email-confirms — 30min TTL
  | 'cancel'          // prospect email-cancels — 30min TTL
  | 'expert-approve'  // expert approves — 24h TTL
  | 'expert-reject';  // expert rejects — 24h TTL

export type BookingTokenResult = 'valid' | 'expired' | 'invalid';

function toBase64Url(data: Uint8Array | ArrayBuffer): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function fromBase64Url(str: string): Uint8Array {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function importHmacKey(secret: string, usage: 'sign' | 'verify'): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    [usage],
  );
}

export async function signBookingToken(
  bookingId: string,
  action: BookingTokenAction,
  secret: string,
  ttlSeconds = 1800,
): Promise<string> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(
    encoder.encode(JSON.stringify({ booking_id: bookingId, action, exp, iss: 'callibrate', aud: `booking:${action}` })),
  );
  const signingInput = `${header}.${payload}`;
  const key = await importHmacKey(secret, 'sign');
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
  return `${signingInput}.${toBase64Url(signature)}`;
}

export async function verifyBookingToken(
  token: string,
  bookingId: string,
  action: BookingTokenAction,
  secret: string,
): Promise<BookingTokenResult> {
  const parts = token.split('.');
  if (parts.length !== 3) return 'invalid';

  const [header, payloadB64, sigB64] = parts;
  const signingInput = `${header}.${payloadB64}`;

  let sigBytes: Uint8Array;
  try {
    sigBytes = fromBase64Url(sigB64!);
  } catch {
    return 'invalid';
  }

  const encoder = new TextEncoder();
  let key: CryptoKey;
  try {
    key = await importHmacKey(secret, 'verify');
  } catch {
    return 'invalid';
  }

  const valid = await crypto.subtle.verify('HMAC', key, sigBytes, encoder.encode(signingInput));
  if (!valid) return 'invalid';

  let claims: Record<string, unknown>;
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payloadB64!)));
  } catch {
    return 'invalid';
  }

  if (claims['booking_id'] !== bookingId || claims['aud'] !== `booking:${action}`) return 'invalid';

  if (typeof claims['exp'] !== 'number' || claims['exp'] < Math.floor(Date.now() / 1000)) {
    return 'expired';
  }

  return 'valid';
}
