import { describe, it, expect } from 'vitest';
import { signProspectToken, verifyProspectToken, signSurveyToken, verifySurveyToken, signRevealConfirmToken, verifyRevealConfirmToken } from './jwt';

const SECRET = 'test-secret-at-least-32-characters-long';
const PROSPECT_ID = 'prospect-uuid-abc123';

describe('signProspectToken', () => {
  it('produces a 3-part JWT string', async () => {
    const { token, expiresAt } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:submit');
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
    const { token } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:submit');
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET, 'prospect:submit');
    expect(result).toBe(true);
  });

  it('returns false for a token with wrong prospect_id', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:submit');
    const result = await verifyProspectToken(token, 'other-prospect-id', SECRET, 'prospect:submit');
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
    const payload = toBase64Url(encoder.encode(JSON.stringify({ prospect_id: PROSPECT_ID, exp: pastExp, iss: 'callibrate', aud: 'prospect:submit' })));
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

    const result = await verifyProspectToken(expiredToken, PROSPECT_ID, SECRET, 'prospect:submit');
    expect(result).toBe(false);
  });

  it('returns false for a token signed with a different secret', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, 'different-secret-value-here-xyz', 'prospect:submit');
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET, 'prospect:submit');
    expect(result).toBe(false);
  });

  it('returns false for a tampered payload', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:submit');
    const parts = token.split('.');
    // Replace payload with tampered content (different prospect_id)
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array): string => {
      let binary = '';
      for (const byte of data) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };
    const tamperedPayload = toBase64Url(
      encoder.encode(JSON.stringify({ prospect_id: 'attacker-id', exp: Math.floor(Date.now() / 1000) + 86400, iss: 'callibrate', aud: 'prospect:submit' }))
    );
    const tamperedToken = `${parts[0]}.${tamperedPayload}.${parts[2]}`;
    const result = await verifyProspectToken(tamperedToken, 'attacker-id', SECRET, 'prospect:submit');
    expect(result).toBe(false);
  });

  it('returns false for a malformed token (fewer than 3 parts)', async () => {
    const result = await verifyProspectToken('not.a.jwt.with.toomanyparts', PROSPECT_ID, SECRET, 'prospect:submit');
    expect(result).toBe(false);
  });

  // AC11(a): wrong aud → returns false
  it('returns false for a token with wrong aud (AC11)', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:submit');
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET, 'prospect:matches');
    expect(result).toBe(false);
  });

  // AC11(b): correct aud → returns true
  it('returns true for a token with matching aud (AC11)', async () => {
    const { token } = await signProspectToken(PROSPECT_ID, SECRET, 'prospect:matches');
    const result = await verifyProspectToken(token, PROSPECT_ID, SECRET, 'prospect:matches');
    expect(result).toBe(true);
  });
});

describe('signSurveyToken', () => {
  // AC11(c): signSurveyToken produces token with exp between 6-8 days from now
  it('produces a token with exp between 6 and 8 days from now (AC11)', async () => {
    const token = await signSurveyToken('booking-uuid-1', 'prospect-uuid-1', SECRET);
    const parts = token.split('.');
    expect(parts).toHaveLength(3);

    const payloadJson = atob(parts[1]!.replace(/-/g, '+').replace(/_/g, '/'));
    const claims = JSON.parse(payloadJson) as { exp?: number };
    expect(claims.exp).toBeDefined();

    const now = Math.floor(Date.now() / 1000);
    expect(claims.exp!).toBeGreaterThan(now + 6 * 86400); // more than 6 days
    expect(claims.exp!).toBeLessThan(now + 8 * 86400);    // less than 8 days
  });
});

describe('verifySurveyToken', () => {
  // AC11(d): verifySurveyToken rejects token with past exp
  it('returns null for a survey token with past exp (AC11)', async () => {
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array | ArrayBuffer): string => {
      const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };

    const pastExp = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
    const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const payload = toBase64Url(encoder.encode(JSON.stringify({ booking_id: 'booking-1', prospect_id: 'prospect-1', exp: pastExp, iss: 'callibrate', aud: 'survey' })));
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

    const result = await verifySurveyToken(expiredToken, SECRET);
    expect(result).toBeNull();
  });
});

// ── E06S43: Reveal confirmation token tests ────────────────────────────────────

describe('signRevealConfirmToken', () => {
  it('produces a 3-part JWT string', async () => {
    const token = await signRevealConfirmToken('match-uuid-1', 'prospect-uuid-1', SECRET);
    const parts = token.split('.');
    expect(parts).toHaveLength(3);
  });

  it('encodes match_id and prospect_id in payload', async () => {
    const token = await signRevealConfirmToken('match-abc', 'prospect-xyz', SECRET);
    const parts = token.split('.');
    const payloadJson = atob(parts[1]!.replace(/-/g, '+').replace(/_/g, '/'));
    const claims = JSON.parse(payloadJson) as Record<string, unknown>;
    expect(claims['match_id']).toBe('match-abc');
    expect(claims['prospect_id']).toBe('prospect-xyz');
    expect(claims['aud']).toBe('agent:reveal:confirm');
  });

  it('sets exp ~24h in the future', async () => {
    const token = await signRevealConfirmToken('match-1', 'prospect-1', SECRET);
    const parts = token.split('.');
    const payloadJson = atob(parts[1]!.replace(/-/g, '+').replace(/_/g, '/'));
    const claims = JSON.parse(payloadJson) as { exp: number };
    const now = Math.floor(Date.now() / 1000);
    expect(claims.exp).toBeGreaterThan(now + 23 * 3600);
    expect(claims.exp).toBeLessThan(now + 25 * 3600);
  });
});

describe('verifyRevealConfirmToken', () => {
  it('returns { match_id, prospect_id } for a valid token', async () => {
    const token = await signRevealConfirmToken('match-abc', 'prospect-xyz', SECRET);
    const result = await verifyRevealConfirmToken(token, SECRET);
    expect(result).not.toBeNull();
    expect(result?.match_id).toBe('match-abc');
    expect(result?.prospect_id).toBe('prospect-xyz');
  });

  it('returns null for a token signed with a different secret', async () => {
    const token = await signRevealConfirmToken('match-1', 'prospect-1', 'wrong-secret-xxxxxxxxxxxxxxxxxx');
    const result = await verifyRevealConfirmToken(token, SECRET);
    expect(result).toBeNull();
  });

  it('returns null for a malformed token', async () => {
    const result = await verifyRevealConfirmToken('not.a.valid.jwt', SECRET);
    expect(result).toBeNull();
  });

  it('returns null for an expired token', async () => {
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array | ArrayBuffer): string => {
      const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };

    const pastExp = Math.floor(Date.now() / 1000) - 3600;
    const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const payload = toBase64Url(encoder.encode(JSON.stringify({ match_id: 'match-1', prospect_id: 'prospect-1', exp: pastExp, iss: 'callibrate', aud: 'agent:reveal:confirm' })));
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

    const result = await verifyRevealConfirmToken(expiredToken, SECRET);
    expect(result).toBeNull();
  });

  it('returns null for wrong audience', async () => {
    // Build a token with wrong aud
    const encoder = new TextEncoder();
    const toBase64Url = (data: Uint8Array | ArrayBuffer): string => {
      const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
      let binary = '';
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    };

    const exp = Math.floor(Date.now() / 1000) + 86400;
    const header = toBase64Url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const payload = toBase64Url(encoder.encode(JSON.stringify({ match_id: 'match-1', prospect_id: 'prospect-1', exp, iss: 'callibrate', aud: 'wrong:audience' })));
    const signingInput = `${header}.${payload}`;

    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(SECRET),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const sigBuffer = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
    const wrongAudToken = `${signingInput}.${toBase64Url(sigBuffer)}`;

    const result = await verifyRevealConfirmToken(wrongAudToken, SECRET);
    expect(result).toBeNull();
  });
});
