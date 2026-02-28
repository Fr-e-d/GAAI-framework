import { describe, it, expect } from 'vitest';
import { signDirectLinkToken, verifyDirectLinkToken } from './directLinkToken';

const TEST_SECRET = 'test-secret-32bytes-padding-here';
const EXPERT_ID = 'expert-uuid-1234-5678-abcdef';
const NONCE = 'nonce-abc123';

describe('signDirectLinkToken', () => {
  it('returns a non-empty base64url string', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    expect(typeof token).toBe('string');
    expect(token.length).toBeGreaterThan(0);
    // base64url chars only
    expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it('is deterministic for the same inputs', async () => {
    const t1 = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const t2 = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    expect(t1).toBe(t2);
  });

  it('differs when nonce changes', async () => {
    const t1 = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const t2 = await signDirectLinkToken(EXPERT_ID, 'different-nonce', TEST_SECRET);
    expect(t1).not.toBe(t2);
  });

  it('differs when expertId changes', async () => {
    const t1 = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const t2 = await signDirectLinkToken('other-expert-id', NONCE, TEST_SECRET);
    expect(t1).not.toBe(t2);
  });

  it('differs when secret changes', async () => {
    const t1 = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const t2 = await signDirectLinkToken(EXPERT_ID, NONCE, 'different-secret-padding-here-x');
    expect(t1).not.toBe(t2);
  });
});

describe('verifyDirectLinkToken', () => {
  it('returns true for a valid token', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const valid = await verifyDirectLinkToken(token, EXPERT_ID, NONCE, TEST_SECRET);
    expect(valid).toBe(true);
  });

  it('returns false when token is tampered', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    // Flip a character at the end
    const tampered = token.slice(0, -1) + (token.endsWith('a') ? 'b' : 'a');
    const valid = await verifyDirectLinkToken(tampered, EXPERT_ID, NONCE, TEST_SECRET);
    expect(valid).toBe(false);
  });

  it('returns false when expertId does not match', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const valid = await verifyDirectLinkToken(token, 'other-expert', NONCE, TEST_SECRET);
    expect(valid).toBe(false);
  });

  it('returns false when nonce does not match', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const valid = await verifyDirectLinkToken(token, EXPERT_ID, 'wrong-nonce', TEST_SECRET);
    expect(valid).toBe(false);
  });

  it('returns false when secret does not match', async () => {
    const token = await signDirectLinkToken(EXPERT_ID, NONCE, TEST_SECRET);
    const valid = await verifyDirectLinkToken(token, EXPERT_ID, NONCE, 'wrong-secret-padding-x');
    expect(valid).toBe(false);
  });

  it('returns false for completely invalid (non-base64url) input', async () => {
    const valid = await verifyDirectLinkToken('!!!not-base64!!!', EXPERT_ID, NONCE, TEST_SECRET);
    expect(valid).toBe(false);
  });

  it('returns false for empty token', async () => {
    const valid = await verifyDirectLinkToken('', EXPERT_ID, NONCE, TEST_SECRET);
    expect(valid).toBe(false);
  });
});
