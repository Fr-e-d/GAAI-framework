---
name: remediate-failures
description: Correct failures, rule violations, and acceptance criteria gaps detected during QA review. Activate when qa-review returns FAIL. Fixes without redefining scope — loops until all quality gates pass.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-REMEDIATE-FAILURES-001
  updated_at: 2026-01-27
  status: stable
inputs:
  - qa_report  (failing)
  - contexts/artefacts/stories/**
  - contexts/artefacts/plans/**
  - contexts/rules/**
  - memory_context_bundle  (optional)
outputs:
  - updated_code_changes
  - remediation_notes
  - updated_qa_inputs  (for re-validation)
---

# Remediate Failures

## Purpose / When to Activate

Activate when:
- QA review returns FAIL
- Acceptance criteria are unmet
- Rules are violated
- Regressions are detected
- Implementation deviates from governed artefacts

---

## Process

1. Identify all failures precisely from the QA report
2. Map each failure to: acceptance criteria / rule violated / implementation section
3. Determine minimal corrective changes
4. Apply fixes without expanding scope
5. Re-validate against Story criteria and rules
6. Prepare updated inputs for QA re-run

**Loop: Detect → Correct → Re-validate → repeat until PASS.**

**Convergence / Escalation:** If re-validation does not pass after 3 attempts, or if a fix requires changing acceptance criteria or product intent, STOP. Mark the story as `failed` and escalate to Discovery with a remediation report listing: what was attempted, what failed, and why convergence was not possible.

---

## Remediation Principles

- Fix the cause, not the symptom
- Minimal change preferred
- Never broaden scope
- Never reinterpret requirements
- Respect architecture constraints
- Preserve maintainability

---

## Output

- Corrected implementation
- Remediation notes:
  - What failed
  - What was fixed
  - Why it now passes
- Updated inputs for QA re-validation

---

## Quality Checks

- All acceptance criteria satisfied
- No rule violations remain
- QA review will pass
- Scope unchanged
- Code remains clean

---

## Non-Goals

This skill must NOT:
- Add new features
- Reinterpret product intent
- Weaken rules
- Bypass quality gates
- Silently ignore failures

**If a fix requires changing product intent or scope: STOP. Escalate back to Discovery. Remediation is correction — not redesign.**
