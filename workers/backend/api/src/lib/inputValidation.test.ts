import { describe, it, expect } from 'vitest';
import { validateFreetext } from './inputValidation';

// ── validateFreetext — unit tests (E06S40 AC1, AC12) ─────────────────────────

describe('validateFreetext', () => {
  // ── Valid input ──────────────────────────────────────────────────────────────

  it('accepts a valid 150-word project description', () => {
    const text = [
      'We are a mid-size e-commerce company with around 80 employees based in France.',
      'We want to automate customer support using AI integrated with Zendesk.',
      'Budget is between 5000 and 15000 euros for the initial implementation.',
    ].join(' ');
    expect(validateFreetext(text)).toEqual({ valid: true });
  });

  it('accepts exactly 30 characters', () => {
    const text = 'I need help with my AI project'; // 30 chars
    expect(validateFreetext(text).valid).toBe(true);
  });

  it('accepts minimum 3 distinct words', () => {
    const text = 'I need help with my automation project for the company today'; // 11 distinct words, no patterns
    expect(validateFreetext(text).valid).toBe(true);
  });

  // ── Too short ────────────────────────────────────────────────────────────────

  it('rejects text shorter than 30 characters', () => {
    const result = validateFreetext('Help me build AI');
    expect(result.valid).toBe(false);
    expect(result.reason).toBeDefined();
    expect(result.reason).toMatch(/30/);
  });

  it('rejects empty string', () => {
    const result = validateFreetext('');
    expect(result.valid).toBe(false);
  });

  it('rejects whitespace-only text under 30 chars', () => {
    const result = validateFreetext('   ');
    expect(result.valid).toBe(false);
  });

  // ── Too few distinct words ───────────────────────────────────────────────────

  it('rejects text with fewer than 3 distinct words (repetition)', () => {
    const result = validateFreetext('help help help help help help help help help help help help help help');
    expect(result.valid).toBe(false);
    expect(result.reason).toBeDefined();
  });

  it('rejects text with only 2 distinct words', () => {
    const result = validateFreetext('automation automation automation automation automation automation automation');
    expect(result.valid).toBe(false);
  });

  // ── Keyboard mashing ─────────────────────────────────────────────────────────

  it('rejects 4+ consecutive identical characters (aaaa)', () => {
    const result = validateFreetext('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa I need help with projects');
    expect(result.valid).toBe(false);
    expect(result.reason).toMatch(/repeated characters/i);
  });

  it('rejects keyboard mashing with punctuation (!!!!)', () => {
    const result = validateFreetext('I need help with my project!!!!!!!!!!!!!!!!!! right now asap');
    expect(result.valid).toBe(false);
  });

  it('accepts 3 consecutive identical chars (below threshold)', () => {
    const result = validateFreetext('I need help with my project!!! right now for automation please');
    expect(result.valid).toBe(true);
  });

  // ── Character repetition patterns (asdfasdf) ──────────────────────────────────

  it('rejects repeated 3+ char sequences (asdfasdf)', () => {
    const result = validateFreetext('asdfasdfasdfasdfasdfasdfasdfasdfasdfasdfasdfasdf and more');
    expect(result.valid).toBe(false);
    expect(result.reason).toMatch(/repeated sequences/i);
  });

  it('rejects abcabc-style repetition', () => {
    const result = validateFreetext('abcabcabcabcabcabcabcabcabcabcabcabcabcabc I want help now');
    expect(result.valid).toBe(false);
  });

  // ── Lorem ipsum ───────────────────────────────────────────────────────────────

  it('rejects "Lorem ipsum" (exact case)', () => {
    const result = validateFreetext('Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod');
    expect(result.valid).toBe(false);
    expect(result.reason).toMatch(/placeholder/i);
  });

  it('rejects "lorem ipsum" (lowercase)', () => {
    const result = validateFreetext('lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod');
    expect(result.valid).toBe(false);
  });

  it('rejects "LOREM IPSUM" (uppercase)', () => {
    const result = validateFreetext('LOREM IPSUM DOLOR SIT AMET CONSECTETUR ADIPISCING ELIT SED DO EIUSMOD');
    expect(result.valid).toBe(false);
  });

  it('accepts text containing "lorem" without "ipsum"', () => {
    const text = 'My company name is Lorem Technologies and we need help with automation processes for accounting';
    expect(validateFreetext(text).valid).toBe(true);
  });
});
