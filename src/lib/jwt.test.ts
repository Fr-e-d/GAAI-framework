import { describe, it, expect } from 'vitest';
import { signProspectToken, verifyProspectToken } from './jwt';

const SECRET = 'test-secret-at-least-32-characters-long';
const PROSPECT_ID = 'prospect-uuid-abc123';

describe('signProspectToken', () => {
  it('produces a 3-part JWT string', async () => {
    const { token, expiresAt } = await signProspectToken(PROSPECT_ID, SECRET);
    const parts = token.split('.');
    expect(parts).toHaveLength(3);
    expect(expiresAt).toBeTruthy();
    // expiresAt should be ~24h from now
    const exp = new Date(expiresAt).getTime();
    const now = Date.now();
    expect(exp).toBeGreaterThan(now + 23 * 60 * 60 * 1000); // at least 23h away
    expect(exp).toBeLessThan(now + 25 * 60 * 60 * 1000);   // no more than 25h away
  });
});

describe('verifyProspectToken', () => {
  it('returns true for a freshly signed token with correct prospect_id', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET);
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET);
    expect(result).toBe(true);
  });

  it('returns false for a token with wrong prospect_id', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET);
    const result = await verifyProspectToken(token, 'other-prospect-id', SECRET);
    expect(result).toBe(false);
  });

  it('returns false for an expired token', async () => {
    // Build a token with exp in the past by manually crafting the payload
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array | ArrayBuffer): string => {
      const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };

    const pastExp = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
    const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const payload = toBase64Url(encoder.encode(JSON.stringify({ prospect_id: PROSPECT_ID, exp: pastExp })));
    const signingInput = `${header}.${payload}`;

    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(SECRET),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const sigBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
    const expiredToken = `${signingInput}.${toBase64Url(sigBuffer)}`;

    const result = await verifyProspectToken(expiredToken, PROSPECT_ID, SECRET);
    expect(result).toBe(false);
  });

  it('returns false for a token signed with a different secret', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, 'different-secret-value-here-xyz');
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET);
    expect(result).toBe(false);
  });

  it('returns false for a tampered payload', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET);
    const parts = token.split('.');
    // Replace payload with tampered content (different prospect_id)
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array): string => {
      let binary = '';
      for (const byte of data) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };
    const tamperedPayload = toBase64Url(
      encoder.encode(JSON.stringify({ prospect_id: 'attacker-id', exp: Math.floor(Date.now() / 1000) + 86400 }))
    );
    const tamperedToken = `${parts[0]}.${tamperedPayload}.${parts[2]}`;
    const result = await verifyProspectToken(tamperedToken, 'attacker-id', SECRET);
    expect(result).toBe(false);
  });

  it('returns false for a malformed token (fewer than 3 parts)', async () => {
    const result = await verifyProspectToken('not.a.jwt.with.toomanyparts', PROSPECT_ID, SECRET);
    expect(result).toBe(false);
  });
});
