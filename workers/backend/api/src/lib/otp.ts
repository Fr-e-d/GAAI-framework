// ── OTP — 6-digit code generation and verification ────────────────────────────
// AC1: Cryptographic 6-digit OTP generation via Web Crypto API.
// Codes are never stored in plaintext — only their SHA-256 hash is persisted in KV.

// Generate a cryptographically random 6-digit code and its SHA-256 hash.
// Returns { code, hash } where code is the plaintext (sent to user)
// and hash is what gets stored in KV.
export async function generateOtp(): Promise<{ code: string; hash: string }> {
  // Use crypto.getRandomValues for secure randomness
  const buf = new Uint8Array(4);
  crypto.getRandomValues(buf);
  // Derive a number in [0, 1_000_000) — gives uniform distribution
  const raw = (new DataView(buf.buffer).getUint32(0) >>> 0) % 1_000_000;
  const code = raw.toString().padStart(6, '0');
  const hash = await hashOtp(code);
  return { code, hash };
}

// Hash an OTP code using SHA-256.
// Used both when generating (to store) and when verifying (to compare).
export async function hashOtp(code: string): Promise<string> {
  const encoder = new TextEncoder();
  const buffer = await crypto.subtle.digest('SHA-256', encoder.encode(code));
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// Verify a submitted code against a stored hash.
// Timing-safe: always hashes before comparing (no early exit on plaintext).
export async function verifyOtpHash(submittedCode: string, storedHash: string): Promise<boolean> {
  const submittedHash = await hashOtp(submittedCode);
  return submittedHash === storedHash;
}
