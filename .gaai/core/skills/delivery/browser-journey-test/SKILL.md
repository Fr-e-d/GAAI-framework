---
name: browser-journey-test
description: Validate user stories by simulating real user journeys in a live browser against deployed application. Activate after implementation to verify actual user experience against acceptance criteria, not just code logic.
license: MIT
compatibility: Works with any filesystem-based AI coding agent (requires browser automation capability)
metadata:
  author: gaai-framework
  version: "1.1"
  category: delivery
  track: delivery
  id: SKILL-BROWSER-JOURNEY-TEST-001
  updated_at: 2026-02-26
  status: experimental
  required_capability: browser-automation
inputs:
  - contexts/artefacts/stories/**
  - deployed_application_url  # Provided by the invoking agent from the staging deploy output. Not supplied manually.
outputs:
  - contexts/artefacts/test-evidence/{story_id}/journey-test-report.md
---

# Browser Journey Test

## Purpose / When to Activate

Activate after implementation to validate real user experience — not just code logic.

Use when:
- Stories describe user-facing flows
- Acceptance criteria can only be verified through UI interaction
- Regression testing requires end-to-end validation

Complements (does not replace) `qa-review`.

---

## Process

**CRITICAL — Anti-Collision Guard (MUST execute before writing any output file):**
Before writing `contexts/artefacts/test-evidence/{story_id}/journey-test-report.md`, check if the target file already exists on disk:
- If it does NOT exist → proceed normally.
- If it DOES exist → **read the existing file first**. Then decide:
  - If the existing content is from a **different entity** (different story ID, different epic) → **STOP immediately**, surface the ID collision to the human, do not proceed.
  - If the existing content is from the **same entity** and an update is warranted (e.g., re-run after a fix) → proceed, but preserve any prior evidence or notes that remain relevant. Treat this as an **update**, not a replacement.
  - If the existing content is identical or still valid → skip writing, report "no changes needed".
This guard prevents the silent data loss incident of 2026-03-17 where concurrent sessions overwrote story files.

For each Story:

1. Read the Story's acceptance criteria. For each AC, extract the user action (verb + object) and the expected outcome. Produce a numbered action sequence.

2. Execute each action in the sequence using the browser automation capability available in the current environment (e.g., Playwright, Puppeteer, or the agent's built-in browser tool). Navigate to `deployed_application_url` before starting.

3. After each action, capture: (a) a screenshot saved to `contexts/artefacts/test-evidence/{story_id}/step-{N}.png`, (b) the HTTP status code, (c) any console errors, (d) whether the expected outcome from Step 1 is visually and functionally confirmed.

4. For each step, classify the result: PASS (outcome confirmed), FUNCTIONAL_FAILURE (expected outcome not met — blocks delivery), UX_FRICTION (outcome met but interaction is degraded — e.g., slow load, confusing layout, accessibility issue — does not block delivery).

5. Produce the test report using the output format below.

---

## Output Format

```
# Browser Journey Test — {Story ID}

> **Date:** {YYYY-MM-DD}
> **URL:** {deployed_application_url}
> **Overall verdict:** PASS | FAIL

## Step Results

| # | Action | Expected Outcome | Result | Evidence |
|---|--------|-----------------|--------|----------|
| 1 | {action} | {outcome} | PASS/FUNCTIONAL_FAILURE/UX_FRICTION | step-1.png |

## Functional Failures (blocking)
{list or "None"}

## UX Friction Points (non-blocking)
{list or "None"}
```

---

## Outputs

- `contexts/artefacts/test-evidence/{story_id}/journey-test-report.md`
- `contexts/artefacts/test-evidence/{story_id}/step-{N}.png` — one screenshot per action step

---

## Quality Checks

- Every acceptance criterion has a corresponding browser test
- Every step result has a screenshot as evidence
- Failures include reproduction steps
- Evidence is captured for audit trail
- FUNCTIONAL_FAILURE vs UX_FRICTION classification follows the rule: outcome not met = failure, outcome met but degraded = friction

---

## Non-Goals

This skill must NOT:
- Replace unit or integration tests
- Make product decisions about UX issues
- Run tests against non-deployed code

**Validates real user experience. Prevents regressions in production-like conditions.**
