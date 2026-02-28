import { describe, it, expect } from 'vitest';
import { generateApiKey, hashApiKey } from './agentKey';

describe('generateApiKey', () => {
  it('returns a key and hash, both hex strings', async () => {
    const { key, hash } = await generateApiKey();
    expect(key).toMatch(/^[0-9a-f]{64}$/);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('returns a different key on each call', async () => {
    const first = await generateApiKey();
    const second = await generateApiKey();
    expect(first.key).not.toBe(second.key);
    expect(first.hash).not.toBe(second.hash);
  });

  it('hash is the SHA-256 of the key', async () => {
    const { key, hash } = await generateApiKey();
    const recomputed = await hashApiKey(key);
    expect(recomputed).toBe(hash);
  });
});

describe('hashApiKey', () => {
  it('produces the same hash for the same input', async () => {
    const key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 64 hex chars
    const hash1 = await hashApiKey(key);
    const hash2 = await hashApiKey(key);
    expect(hash1).toBe(hash2);
  });

  it('produces different hashes for different keys', async () => {
    const hash1 = await hashApiKey('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    const hash2 = await hashApiKey('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    expect(hash1).not.toBe(hash2);
  });

  it('returns a 64-char lowercase hex string', async () => {
    const hash = await hashApiKey('test-key');
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });
});
