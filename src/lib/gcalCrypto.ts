// AES-256-GCM token encryption/decryption for Google Calendar OAuth tokens.
// Storage format: base64(IV || ciphertext) where IV = 12 random bytes.

export class GcalDecryptionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GcalDecryptionError';
  }
}

function base64ToUint8Array(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

async function importKey(rawKey: string, usage: 'encrypt' | 'decrypt'): Promise<CryptoKey> {
  const keyBytes = base64ToUint8Array(rawKey);
  return crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    [usage]
  );
}

export async function encryptToken(plaintext: string, rawKey: string): Promise<string> {
  const key = await importKey(rawKey, 'encrypt');
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
  const combined = new Uint8Array(12 + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), 12);
  return uint8ArrayToBase64(combined);
}

export async function decryptToken(stored: string, rawKey: string): Promise<string> {
  try {
    const combined = base64ToUint8Array(stored);
    const iv = combined.slice(0, 12);
    const ciphertext = combined.slice(12);
    const key = await importKey(rawKey, 'decrypt');
    const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext);
    return new TextDecoder().decode(plaintext);
  } catch (e) {
    throw new GcalDecryptionError(`Failed to decrypt token: ${e instanceof Error ? e.message : String(e)}`);
  }
}
