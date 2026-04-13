#!/usr/bin/env bash
# Regression guard — E63S01: Canonical memory-delta schema enforcement
# AC9: Verifies literal phrases are present in target skill files after Story delivery.
#
# Usage: bash .gaai/core/scripts/test-e63s01-schema-enforcement.sh
# Exit code: 0 = PASS, 1 = FAIL

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
QA_SKILL="$PROJECT_DIR/.gaai/core/skills/delivery/qa-review/SKILL.md"
HANDOFFS_SKILL="$PROJECT_DIR/.gaai/core/skills/delivery/coordinate-handoffs/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

echo "[TEST] E63S01 Regression Guard"
echo "[TEST] Project root: $PROJECT_DIR"

# ── TEST 1: qa-review/SKILL.md contains literal phrase (AC9a) ────────────────
echo ""
echo "[TEST 1] qa-review/SKILL.md contains 'invoke \`memory-alignment-check\`'..."
if grep -qF "invoke \`memory-alignment-check\`" "$QA_SKILL" 2>/dev/null; then
  echo "[PASS] Phrase found in qa-review/SKILL.md"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Phrase NOT found in qa-review/SKILL.md"
  (( FAIL_COUNT++ ))
fi

# ── TEST 2: qa-review/SKILL.md has Step 6 heading ────────────────────────────
echo ""
echo "[TEST 2] qa-review/SKILL.md has '### 6. Memory Alignment' heading..."
if grep -qF "### 6. Memory Alignment" "$QA_SKILL" 2>/dev/null; then
  echo "[PASS] Step 6 heading found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Step 6 heading NOT found"
  (( FAIL_COUNT++ ))
fi

# ── TEST 3: qa-review/SKILL.md has Hard Rule bullet (AC9 / AC2) ──────────────
echo ""
echo "[TEST 3] qa-review/SKILL.md has Hard Rule 'MUST NOT write or modify'..."
if grep -qF "MUST NOT write or modify" "$QA_SKILL" 2>/dev/null; then
  echo "[PASS] Hard Rule bullet found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Hard Rule bullet NOT found"
  (( FAIL_COUNT++ ))
fi

# ── TEST 4: coordinate-handoffs/SKILL.md Step 9 has canonical sections (AC9b) ─
echo ""
echo "[TEST 4] coordinate-handoffs/SKILL.md Step 9 contains '## Confirmed Entries'..."
if grep -qF "## Confirmed Entries" "$HANDOFFS_SKILL" 2>/dev/null; then
  echo "[PASS] '## Confirmed Entries' found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] '## Confirmed Entries' NOT found"
  (( FAIL_COUNT++ ))
fi

echo ""
echo "[TEST 4b] coordinate-handoffs/SKILL.md Step 9 contains '## Contradicted Entries'..."
if grep -qF "## Contradicted Entries" "$HANDOFFS_SKILL" 2>/dev/null; then
  echo "[PASS] '## Contradicted Entries' found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] '## Contradicted Entries' NOT found"
  (( FAIL_COUNT++ ))
fi

echo ""
echo "[TEST 4c] coordinate-handoffs/SKILL.md Step 9 contains '## New Knowledge Candidates'..."
if grep -qF "## New Knowledge Candidates" "$HANDOFFS_SKILL" 2>/dev/null; then
  echo "[PASS] '## New Knowledge Candidates' found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] '## New Knowledge Candidates' NOT found"
  (( FAIL_COUNT++ ))
fi

# ── TEST 5: coordinate-handoffs/SKILL.md has SCHEMA_INVALID gate (AC3) ────────
echo ""
echo "[TEST 5] coordinate-handoffs/SKILL.md contains 'SCHEMA_INVALID'..."
if grep -qF "SCHEMA_INVALID" "$HANDOFFS_SKILL" 2>/dev/null; then
  echo "[PASS] SCHEMA_INVALID gate found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] SCHEMA_INVALID gate NOT found"
  (( FAIL_COUNT++ ))
fi

# ── TEST 6: Step 9b preserved (autonomous triage daemon wrapper) ───────────────
echo ""
echo "[TEST 6] coordinate-handoffs/SKILL.md Step 9b (autonomous triage) preserved..."
if grep -qF "Autonomous triage — daemon wrapper" "$HANDOFFS_SKILL" 2>/dev/null; then
  echo "[PASS] Step 9b preserved"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Step 9b NOT found — autonomous triage block may have been overwritten"
  (( FAIL_COUNT++ ))
fi

# ── TEST 7: OSS-generic check — no project-specific refs in either file ────────
echo ""
echo "[TEST 7] OSS-generic: no project-specific refs in modified files (AC7)..."
PROJECT_REF_VIOLATIONS=0
for file in "$QA_SKILL" "$HANDOFFS_SKILL"; do
  if grep -qE "(callibrate|gaai-cloud|gaai\.cloud|DEC-[0-9])" "$file" 2>/dev/null; then
    echo "[FAIL] Project-specific reference found in: $file"
    grep -nE "(callibrate|gaai-cloud|gaai\.cloud|DEC-[0-9])" "$file" || true
    (( PROJECT_REF_VIOLATIONS++ ))
    (( FAIL_COUNT++ ))
  fi
done
if [[ "$PROJECT_REF_VIOLATIONS" -eq 0 ]]; then
  echo "[PASS] No project-specific references in modified skill files"
  (( PASS_COUNT++ ))
fi

# ── TEST 8: ### heading count unchanged in coordinate-handoffs (AC6) ───────────
echo ""
echo "[TEST 8] coordinate-handoffs/SKILL.md has exactly 4 ### headings (AC6)..."
HEADING_COUNT=$(grep -c "^### " "$HANDOFFS_SKILL" 2>/dev/null || echo "0")
if [[ "$HEADING_COUNT" -eq 4 ]]; then
  echo "[PASS] 4 ### headings found (unchanged)"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Expected 4 ### headings, found: $HEADING_COUNT"
  (( FAIL_COUNT++ ))
fi

# ── TEST 9: qa-review Process step count (AC6 — steps not renumbered) ─────────
echo ""
echo "[TEST 9] qa-review/SKILL.md has exactly 6 Process steps (### 1 through ### 6)..."
STEP_COUNT=$(grep -cE "^### [0-9]+\." "$QA_SKILL" 2>/dev/null || echo "0")
if [[ "$STEP_COUNT" -eq 6 ]]; then
  echo "[PASS] 6 numbered Process steps found"
  (( PASS_COUNT++ ))
else
  echo "[FAIL] Expected 6 numbered Process steps, found: $STEP_COUNT"
  (( FAIL_COUNT++ ))
fi

# ── SUMMARY ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  E63S01 Schema Enforcement Regression Guard"
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo "================================================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "[RESULT] FAIL"
  exit 1
else
  echo "[RESULT] PASS"
  exit 0
fi
