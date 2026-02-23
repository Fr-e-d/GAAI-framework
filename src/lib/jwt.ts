// ── Prospect JWT — sign / verify using Web Crypto API (HMAC-SHA256) ───────────
// Used by the satellite funnel: POST /api/prospects/submit signs a token,
// GET /api/prospects/:id/matches and POST /api/prospects/:id/identify verify it.
// No external library — CF Workers provides crypto.subtle natively.

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

// ── signProspectToken ──────────────────────────────────────────────────────────
// Returns a signed JWT with 24h TTL and the ISO expiry string.

export async function signProspectToken(
  prospectId: string,
  secret: string,
): Promise<{ token: string; expiresAt: string }> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + 86400; // 24h

  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(encoder.encode(JSON.stringify({ prospect_id: prospectId, exp })));
  const signingInput = `${header}.${payload}`;

  const key = await importHmacKey(secret, 'sign');
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
  const token = `${signingInput}.${toBase64Url(signatureBuffer)}`;

  return {
    token,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}

// ── signSurveyToken ────────────────────────────────────────────────────────────
// Returns a signed JWT with 30-day TTL for survey submission links.
// Payload: { booking_id, prospect_id, exp }.

export async function signSurveyToken(
  bookingId: string,
  prospectId: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + 30 * 86400; // 30 days

  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(encoder.encode(JSON.stringify({ booking_id: bookingId, prospect_id: prospectId, exp })));
  const signingInput = `${header}.${payload}`;

  const key = await importHmacKey(secret, 'sign');
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));

  return `${signingInput}.${toBase64Url(signatureBuffer)}`;
}

// ── verifyProspectToken ────────────────────────────────────────────────────────
// Returns true only if: signature valid + not expired + prospect_id matches.

export async function verifyProspectToken(
  token: string,
  prospectId: string,
  secret: string,
): Promise<boolean> {
  const parts = token.split('.');
  if (parts.length !== 3) return false;

  const [header, payload, sig] = parts as [string, string, string];
  const signingInput = `${header}.${payload}`;

  let signatureBytes: Uint8Array;
  try {
    signatureBytes = fromBase64Url(sig);
  } catch {
    return false;
  }

  const key = await importHmacKey(secret, 'verify');
  const encoder = new TextEncoder();

  const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(signingInput));
  if (!valid) return false;

  let claims: { prospect_id?: string; exp?: number };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return false;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return false;
  if (claims.prospect_id !== prospectId) return false;

  return true;
}
