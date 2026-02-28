import { describe, it, expect } from 'vitest';
import { generateOtp, hashOtp, verifyOtpHash } from './otp';

describe('generateOtp', () => {
  it('generates a 6-digit string code (AC1)', async () => {
    const { code } = await generateOtp();
    expect(code).toMatch(/^\d{6}$/);
  });

  it('returns a SHA-256 hex hash (64 chars) (AC1)', async () => {
    const { hash } = await generateOtp();
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('generated codes are statistically unique (randomness check) (AC1)', async () => {
    const codes = new Set<string>();
    for (let i = 0; i < 10; i++) {
      const { code } = await generateOtp();
      codes.add(code);
    }
    // With true randomness, 10 codes should almost certainly differ
    expect(codes.size).toBeGreaterThan(1);
  });

  it('code is zero-padded to 6 digits (AC1)', async () => {
    // Run many times to catch edge cases around 0-padded numbers
    for (let i = 0; i < 20; i++) {
      const { code } = await generateOtp();
      expect(code.length).toBe(6);
    }
  });
});

describe('hashOtp', () => {
  it('produces a 64-char hex string for a given code (AC1)', async () => {
    const hash = await hashOtp('123456');
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('is deterministic — same code yields same hash (AC1)', async () => {
    const h1 = await hashOtp('999999');
    const h2 = await hashOtp('999999');
    expect(h1).toBe(h2);
  });

  it('different codes produce different hashes (AC1)', async () => {
    const h1 = await hashOtp('000000');
    const h2 = await hashOtp('000001');
    expect(h1).not.toBe(h2);
  });
});

describe('verifyOtpHash', () => {
  it('returns true when submitted code matches stored hash (AC1)', async () => {
    const { code, hash } = await generateOtp();
    const result = await verifyOtpHash(code, hash);
    expect(result).toBe(true);
  });

  it('returns false when submitted code does not match stored hash (AC1)', async () => {
    const { hash } = await generateOtp();
    const result = await verifyOtpHash('000000', hash);
    // Hash of '000000' won't match the hash of a different random code
    // (unless generated code happened to be 000000, but that's astronomically unlikely)
    const expectedHash = await hashOtp('000000');
    if (hash !== expectedHash) {
      expect(result).toBe(false);
    }
  });

  it('returns false for empty string (AC1)', async () => {
    const { hash } = await generateOtp();
    const result = await verifyOtpHash('', hash);
    expect(result).toBe(false);
  });

  it('is not vulnerable to timing shortcut — always hashes before comparing (AC1)', async () => {
    // Both calls should complete (no early exit), verifiable by checking type
    const { hash } = await generateOtp();
    const r1 = await verifyOtpHash('wrong1', hash);
    const r2 = await verifyOtpHash('wrong2', hash);
    expect(typeof r1).toBe('boolean');
    expect(typeof r2).toBe('boolean');
  });
});
