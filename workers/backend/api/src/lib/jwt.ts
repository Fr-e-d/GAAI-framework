// ── Prospect JWT — sign / verify using Web Crypto API (HMAC-SHA256) ───────────
// Used by the satellite funnel: POST /api/prospects/submit signs a token,
// GET /api/prospects/:id/matches and POST /api/prospects/:id/identify verify it.
// No external library — CF Workers provides crypto.subtle natively.
//
// Also used for survey token sign/verify (E06S17):
//   signSurveyToken / verifySurveyToken — uses SURVEY_TOKEN_SECRET (distinct from
//   PROSPECT_TOKEN_SECRET). Payload: { booking_id, prospect_id, exp, iss, aud } (7d TTL).
//
// Also used for flow token sign/verify (E06S40 AC11):
//   signFlowToken / verifyFlowToken — uses PROSPECT_TOKEN_SECRET.
//   Payload: { extraction_id, exp, iss, aud: 'extract:flow' }. TTL: 30 minutes.
//   isValidProspectToken — verifies any prospect JWT without matching prospect_id (for AC9).

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
  aud: 'prospect:submit' | 'prospect:matches' | 'prospect:identify',
): Promise<{ token: string; expiresAt: string }> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + 86400; // 24h

  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(encoder.encode(JSON.stringify({ prospect_id: prospectId, exp, iss: 'callibrate', aud })));
  const signingInput = `${header}.${payload}`;

  const key = await importHmacKey(secret, 'sign');
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
  const token = `${signingInput}.${toBase64Url(signatureBuffer)}`;

  return {
    token,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}

// ── verifyProspectToken ────────────────────────────────────────────────────────
// Returns true only if: signature valid + not expired + prospect_id matches + aud matches.

export async function verifyProspectToken(
  token: string,
  prospectId: string,
  secret: string,
  expectedAud: string,
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

  let claims: { prospect_id?: string; exp?: number; aud?: string; iss?: string };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return false;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return false;
  if (claims.aud !== expectedAud) return false;
  if (claims.prospect_id !== prospectId) return false;

  return true;
}

// ── Survey JWT — sign / verify (E06S17) ───────────────────────────────────────
// Used by E06S16 (sign — in survey emails) and E06S17 (verify — in survey endpoints).
// Secret: SURVEY_TOKEN_SECRET (separate from PROSPECT_TOKEN_SECRET).
// Payload: { booking_id, prospect_id, exp, iss, aud }. TTL: 7 days (reduced from 30 in E08S05).

export type SurveyTokenClaims = {
  booking_id: string;
  prospect_id: string;
};

// ── signSurveyToken ──────────────────────────────────────────────────────────
// Returns a signed JWT with 7-day TTL for survey links.

export async function signSurveyToken(
  bookingId: string,
  prospectId: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + 7 * 86400; // 7 days

  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(
    encoder.encode(JSON.stringify({ booking_id: bookingId, prospect_id: prospectId, exp, iss: 'callibrate', aud: 'survey' })),
  );
  const signingInput = `${header}.${payload}`;

  const key = await importHmacKey(secret, 'sign');
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));

  return `${signingInput}.${toBase64Url(signatureBuffer)}`;
}

// ── verifySurveyToken ──────────────────────────────────────────────────────────
// Returns SurveyTokenClaims if valid, null otherwise.

export async function verifySurveyToken(
  token: string,
  secret: string,
): Promise<SurveyTokenClaims | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, sig] = parts as [string, string, string];
  const signingInput = `${header}.${payload}`;

  let signatureBytes: Uint8Array;
  try {
    signatureBytes = fromBase64Url(sig);
  } catch {
    return null;
  }

  const key = await importHmacKey(secret, 'verify');
  const encoder = new TextEncoder();

  const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(signingInput));
  if (!valid) return null;

  let claims: { booking_id?: string; prospect_id?: string; exp?: number };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return null;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return null;
  if (typeof claims.booking_id !== 'string' || typeof claims.prospect_id !== 'string') return null;

  return { booking_id: claims.booking_id, prospect_id: claims.prospect_id };
}

// ── Flow token — sign / verify (E06S40 AC11) ──────────────────────────────────
// Proves client went through a legitimate extraction → confirmation → submit flow.
// Secret: PROSPECT_TOKEN_SECRET (reused — distinct audiences prevent cross-token use).
// Payload: { extraction_id, exp, iss, aud: 'extract:flow' }. TTL: 30 minutes (1800s).

export async function signFlowToken(extractionId: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const exp = Math.floor(Date.now() / 1000) + 1800; // 30 minutes

  const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const payload = toBase64Url(
    encoder.encode(JSON.stringify({ extraction_id: extractionId, exp, iss: 'callibrate', aud: 'extract:flow' })),
  );
  const signingInput = `${header}.${payload}`;

  const key = await importHmacKey(secret, 'sign');
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));

  return `${signingInput}.${toBase64Url(signatureBuffer)}`;
}

// Returns the extraction_id if valid, null otherwise.
export async function verifyFlowToken(token: string, secret: string): Promise<{ extraction_id: string } | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, sig] = parts as [string, string, string];
  const signingInput = `${header}.${payload}`;

  let signatureBytes: Uint8Array;
  try {
    signatureBytes = fromBase64Url(sig);
  } catch {
    return null;
  }

  const key = await importHmacKey(secret, 'verify');
  const encoder = new TextEncoder();

  const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(signingInput));
  if (!valid) return null;

  let claims: { extraction_id?: string; exp?: number; aud?: string };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return null;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return null;
  if (claims.aud !== 'extract:flow') return null;
  if (typeof claims.extraction_id !== 'string') return null;

  return { extraction_id: claims.extraction_id };
}

// ── E06S41: Verify prospect JWT and return claims ──────────────────────────────
// Used by identified fast-track path (project 2+). Returns { prospect_id } on
// success, null on any failure (invalid signature, expired, wrong audience).

export async function verifyProspectTokenGetClaims(
  token: string,
  secret: string,
  expectedAud: 'prospect:submit',
): Promise<{ prospect_id: string } | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [header, payload, sig] = parts as [string, string, string];
  const signingInput = `${header}.${payload}`;

  let signatureBytes: Uint8Array;
  try {
    signatureBytes = fromBase64Url(sig);
  } catch {
    return null;
  }

  const key = await importHmacKey(secret, 'verify');
  const encoder = new TextEncoder();

  const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, encoder.encode(signingInput));
  if (!valid) return null;

  let claims: { prospect_id?: string; exp?: number; aud?: string };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return null;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return null;
  if (claims.aud !== expectedAud) return null;
  if (typeof claims.prospect_id !== 'string' || !claims.prospect_id) return null;

  return { prospect_id: claims.prospect_id };
}

// ── isValidProspectToken ───────────────────────────────────────────────────────
// Verifies any prospect JWT (signature + TTL only — no prospect_id matching).
// Used by AC9: if the caller holds a valid session token, they are identified and exempt
// from the extraction count limit.

export async function isValidProspectToken(token: string, secret: string): Promise<boolean> {
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

  let claims: { exp?: number };
  try {
    claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
  } catch {
    return false;
  }

  if (claims.exp === undefined || claims.exp < Math.floor(Date.now() / 1000)) return false;

  return true;
}
