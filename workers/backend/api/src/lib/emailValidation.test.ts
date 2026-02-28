import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  validateEmailSyntax,
  normalizeEmail,
  isDisposableDomain,
  checkMxRecord,
  preCheckEmail,
} from './emailValidation';

// ── validateEmailSyntax ───────────────────────────────────────────────────────

describe('validateEmailSyntax', () => {
  it('accepts valid emails (AC3)', () => {
    expect(validateEmailSyntax('user@example.com')).toBe(true);
    expect(validateEmailSyntax('user.name+tag@subdomain.example.co.uk')).toBe(true);
    expect(validateEmailSyntax('a@b.io')).toBe(true);
  });

  it('rejects emails without @ (AC3)', () => {
    expect(validateEmailSyntax('notanemail')).toBe(false);
  });

  it('rejects emails without domain (AC3)', () => {
    expect(validateEmailSyntax('user@')).toBe(false);
  });

  it('rejects emails without TLD (AC3)', () => {
    expect(validateEmailSyntax('user@domain')).toBe(false);
  });

  it('rejects emails with spaces (AC3)', () => {
    expect(validateEmailSyntax('user @example.com')).toBe(false);
  });

  it('rejects empty string (AC3)', () => {
    expect(validateEmailSyntax('')).toBe(false);
  });

  it('rejects email over 254 chars (AC3)', () => {
    const longEmail = 'a'.repeat(250) + '@b.com';
    expect(validateEmailSyntax(longEmail)).toBe(false);
  });
});

// ── normalizeEmail ────────────────────────────────────────────────────────────

describe('normalizeEmail', () => {
  it('lowercases the email (AC3)', () => {
    expect(normalizeEmail('User@Example.COM')).toBe('user@example.com');
  });

  it('strips +tags for all providers (AC3)', () => {
    expect(normalizeEmail('user+tag@example.com')).toBe('user@example.com');
    expect(normalizeEmail('user+newsletter@company.org')).toBe('user@company.org');
  });

  it('strips dots from Gmail local part (AC3)', () => {
    expect(normalizeEmail('first.last@gmail.com')).toBe('firstlast@gmail.com');
    expect(normalizeEmail('f.i.r.s.t@gmail.com')).toBe('first@gmail.com');
  });

  it('strips dots from googlemail.com (AC3)', () => {
    expect(normalizeEmail('first.last@googlemail.com')).toBe('firstlast@googlemail.com');
  });

  it('does NOT strip dots from non-Gmail providers (AC3)', () => {
    expect(normalizeEmail('first.last@outlook.com')).toBe('first.last@outlook.com');
  });

  it('strips +tags AND dots for Gmail (AC3)', () => {
    expect(normalizeEmail('first.last+tag@gmail.com')).toBe('firstlast@gmail.com');
  });

  it('trims whitespace (AC3)', () => {
    expect(normalizeEmail('  user@example.com  ')).toBe('user@example.com');
  });
});

// ── isDisposableDomain ────────────────────────────────────────────────────────

describe('isDisposableDomain', () => {
  it('identifies known disposable domains (AC3)', () => {
    expect(isDisposableDomain('mailinator.com')).toBe(true);
    expect(isDisposableDomain('guerrillamail.com')).toBe(true);
    expect(isDisposableDomain('yopmail.com')).toBe(true);
    expect(isDisposableDomain('10minutemail.com')).toBe(true);
    expect(isDisposableDomain('sharklasers.com')).toBe(true);
    expect(isDisposableDomain('trashmail.com')).toBe(true);
  });

  it('does not flag legitimate providers (AC3)', () => {
    expect(isDisposableDomain('gmail.com')).toBe(false);
    expect(isDisposableDomain('outlook.com')).toBe(false);
    expect(isDisposableDomain('yahoo.com')).toBe(false);
    expect(isDisposableDomain('company.io')).toBe(false);
  });

  it('is case-insensitive (AC3)', () => {
    expect(isDisposableDomain('MAILINATOR.COM')).toBe(true);
    expect(isDisposableDomain('Yopmail.com')).toBe(true);
  });
});

// ── checkMxRecord ─────────────────────────────────────────────────────────────

describe('checkMxRecord', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns true when Google DNS returns MX records (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({
        Status: 0,
        Answer: [{ type: 15, data: '10 mx.example.com.' }],
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    );
    const result = await checkMxRecord('example.com');
    expect(result).toBe(true);
  });

  it('returns false when Google DNS returns NXDOMAIN (Status 3) (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ Status: 3, Answer: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    );
    const result = await checkMxRecord('nonexistent-xyz-123.com');
    expect(result).toBe(false);
  });

  it('returns false when Answer is empty (no MX records) (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ Status: 0, Answer: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    );
    const result = await checkMxRecord('nomx.example.com');
    expect(result).toBe(false);
  });

  it('returns true (fail-open) when DNS fetch throws a network error (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValueOnce(new Error('Network failure'));
    const result = await checkMxRecord('flaky-domain.com');
    expect(result).toBe(true); // fail-open
  });

  it('returns true (fail-open) when DNS API returns non-OK status (AC3)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response('Server Error', { status: 500 })
    );
    const result = await checkMxRecord('example.com');
    expect(result).toBe(true); // fail-open
  });
});

// ── preCheckEmail (pipeline) ──────────────────────────────────────────────────

describe('preCheckEmail — pipeline (AC4)', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  function mockMxSuccess() {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({
        Status: 0,
        Answer: [{ type: 15, data: '10 mx.example.com.' }],
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    );
  }

  it('returns ok=true with normalizedEmail for a valid email (AC4)', async () => {
    mockMxSuccess();
    const result = await preCheckEmail('User.Name+tag@gmail.com');
    expect(result.ok).toBe(true);
    expect(result.normalizedEmail).toBe('username@gmail.com');
    expect(result.error).toBeUndefined();
  });

  it('returns ok=false with invalid_syntax for a malformed email (AC4)', async () => {
    const result = await preCheckEmail('notanemail');
    expect(result.ok).toBe(false);
    expect(result.error).toBe('invalid_syntax');
  });

  it('returns ok=false with no_mx_record when MX check fails (AC4)', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
      new Response(JSON.stringify({ Status: 3, Answer: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    );
    const result = await preCheckEmail('user@nonexistent-xyz-9999.com');
    expect(result.ok).toBe(false);
    expect(result.error).toBe('no_mx_record');
  });

  it('returns ok=false with disposable_domain for a disposable email (AC4)', async () => {
    mockMxSuccess();
    const result = await preCheckEmail('user@mailinator.com');
    expect(result.ok).toBe(false);
    expect(result.error).toBe('disposable_domain');
  });
});
