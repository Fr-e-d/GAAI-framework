// ── Direct Link Token — raw HMAC-SHA256 (no JWT structure) ───────────────────
// E02S12: Signs a direct booking link token for an expert.
// Token = base64url(HMAC-SHA256(secret, "{expertId}:{nonce}"))
// Unlike bookingToken.ts (which is a full JWT), this is a simple HMAC MAC
// over a fixed message string. Constant-time comparison via SubtleCrypto.verify.

function toBase64Url(data: ArrayBuffer): string {
  const bytes = new Uint8Array(data);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
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

// Sign: returns base64url(HMAC-SHA256(secret, "{expertId}:{nonce}"))
export async function signDirectLinkToken(
  expertId: string,
  nonce: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const message = `${expertId}:${nonce}`;
  const key = await importHmacKey(secret, 'sign');
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(message));
  return toBase64Url(signature);
}

// Verify: constant-time comparison using SubtleCrypto.verify
// Returns true if token is a valid HMAC of "{expertId}:{nonce}" under secret.
export async function verifyDirectLinkToken(
  token: string,
  expertId: string,
  nonce: string,
  secret: string,
): Promise<boolean> {
  // Decode the provided token from base64url to bytes
  let sigBytes: Uint8Array;
  try {
    const base64 = token.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(base64);
    sigBytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      sigBytes[i] = binary.charCodeAt(i);
    }
  } catch {
    return false;
  }

  const encoder = new TextEncoder();
  const message = `${expertId}:${nonce}`;

  let key: CryptoKey;
  try {
    key = await importHmacKey(secret, 'verify');
  } catch {
    return false;
  }

  return crypto.subtle.verify('HMAC', key, sigBytes, encoder.encode(message));
}
