// ── Input pre-validation — E06S40 (AC1) ───────────────────────────────────────
// Pure synchronous function. No I/O. Cost: ~0ms CPU.
// Called by POST /api/extract BEFORE any LLM invocation to reject garbage cheaply.

export interface ValidationResult {
  valid: boolean;
  reason?: string;
}

// ── validateFreetext ──────────────────────────────────────────────────────────
// AC1 checks (in order):
//   1. Minimum 30 characters
//   2. Minimum 3 distinct words
//   3. No keyboard mashing (4+ consecutive identical chars: aaaa, !!!!)
//   4. No character repetition patterns (asdfasdf-style)
//   5. No lorem ipsum placeholder text

export function validateFreetext(text: string): ValidationResult {
  // Check 1: minimum length
  if (text.length < 30) {
    return {
      valid: false,
      reason: 'Your description is too short. Please provide at least 30 characters describing your project.',
    };
  }

  // Check 2: minimum 3 distinct words
  const words = text.trim().split(/\s+/).filter(Boolean);
  const distinctWords = new Set(words.map((w) => w.toLowerCase().replace(/[^a-z0-9]/g, '')).filter(Boolean));
  if (distinctWords.size < 3) {
    return {
      valid: false,
      reason: 'Please describe your project with more detail — at least a few different words.',
    };
  }

  // Check 3: keyboard mashing — 4+ consecutive identical characters
  if (/(.)\1{3,}/.test(text)) {
    return {
      valid: false,
      reason: 'Your description appears to contain repeated characters. Please describe your project in plain text.',
    };
  }

  // Check 4: character repetition patterns (asdfasdf — same sequence of 3+ chars repeated)
  if (/(.{3,})\1/.test(text)) {
    return {
      valid: false,
      reason: 'Your description appears to contain repeated sequences. Please describe your project in plain text.',
    };
  }

  // Check 5: lorem ipsum placeholder text
  if (/lorem\s+ipsum/i.test(text)) {
    return {
      valid: false,
      reason: 'Please replace the placeholder text with your actual project description.',
    };
  }

  return { valid: true };
}
