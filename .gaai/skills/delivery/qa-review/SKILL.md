---
name: qa-review
description: Validate that implemented code fully satisfies Story acceptance criteria, respects rules, and introduces no regressions. This is the hard quality gate — no pass means no delivery. Activate after implementation is complete.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-QA-REVIEW-001
  updated_at: 2026-01-28
inputs:
  - contexts/artefacts/stories/**
  - contexts/artefacts/plans/**
  - codebase  (working tree)
  - contexts/rules/**
  - contexts/memory/**  (optional — past bugs, regressions, risks)
outputs:
  - qa_report  (PASS | FAIL)
---

# QA Review

## Purpose / When to Activate

Activate after implementation is complete. This is a **hard quality gate**.

**No pass → no delivery.**

---

## Process

### 1. Story Compliance Check
- Parse Story YAML frontmatter
- Extract acceptance criteria
- Validate each criterion is demonstrably satisfied in code
- Any criterion unclear or unmet → FAIL immediately

### 2. Scope Integrity Check
- Only files within Story scope were modified
- No feature creep introduced
- No unrelated refactors included
- Unexpected changes → FAIL

### 3. Rule Enforcement
- Confirm compliance with each applicable rule
- Surface violations explicitly
- Any broken rule → FAIL

### 4. Regression Scan
- Broken tests → FAIL
- Behavior drift → FAIL
- Known risk patterns from memory → FAIL

### 5. Quality Checks
- Error-prone operations lack error handling → FAIL
- External input enters functions without validation → FAIL
- Identifiers are ambiguous or non-descriptive → FAIL
- A function or module handles more than one responsibility without decomposition → FAIL
- Dead code or unreachable branches present → FAIL
- Tests were disabled or skipped to make the suite pass → FAIL

---

## Output Format

**If PASS:**
```
status: PASS
validated_stories:
  - E01S01
notes:
  - All acceptance criteria satisfied
  - No rule violations
  - No regressions detected
```

**If FAIL:**
```
status: FAIL
blocking_issues:
  - Story E01S01: acceptance criterion #2 not satisfied
  - Rule code-style violated in services/api/user.ts
  - Unexpected file modified: services/payments/
recommended_actions:
  - Fix acceptance behavior
  - Revert out-of-scope change
  - Apply code rule formatting
```

---

## Hard Rules

This skill must NEVER:
- Modify code
- Reinterpret Stories
- Negotiate acceptance criteria
- Approve partial conformance

**If it's not explicitly validated → it's broken. If it's broken → it doesn't ship.**
