// E06S43: API key generation and hashing for agent authentication

const encoder = new TextEncoder();

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Generate a new random 32-byte API key and its SHA-256 hash.
 * Returns { key: hexString, hash: hexString }.
 * Store only the hash. Return the key ONCE to the prospect.
 */
export async function generateApiKey(): Promise<{ key: string; hash: string }> {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const key = toHex(bytes.buffer);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(key));
  const hash = toHex(hashBuffer);
  return { key, hash };
}

/**
 * Hash an API key for lookup. Used in agentAuth middleware.
 */
export async function hashApiKey(key: string): Promise<string> {
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(key));
  return toHex(hashBuffer);
}
