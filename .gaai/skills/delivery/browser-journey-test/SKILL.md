---
name: browser-journey-test
description: Validate user stories by simulating real user journeys in a live browser against deployed application. Activate after implementation to verify actual user experience against acceptance criteria, not just code logic.
license: MIT
compatibility: Works with any filesystem-based AI coding agent (requires browser automation capability)
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-BROWSER-JOURNEY-TEST-001
  updated_at: 2026-02-18
  status: experimental
  required_capability: browser-automation
inputs:
  - contexts/artefacts/stories/**
  - acceptance_criteria
  - deployed_application_url
outputs:
  - story_test_results
  - execution_logs
  - detected_failures
  - ux_friction_points
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

For each Story:
1. Interpret acceptance criteria as user actions
2. Simulate real user actions in a live browser
3. Validate expected outcomes at each step
4. Capture evidence (screenshots, logs)
5. Report pass/fail per acceptance criterion

---

## Output

- Story-by-story pass/fail report
- Screenshots or recordings of each journey
- Execution logs linked to backlog items
- Failure reproduction steps
- UX friction points identified

---

## Quality Checks

- Every acceptance criterion has a corresponding browser test
- Failures include reproduction steps
- Evidence is captured for audit trail
- UX friction is distinguished from functional failures

---

## Non-Goals

This skill must NOT:
- Replace unit or integration tests
- Make product decisions about UX issues
- Run tests against non-deployed code

**Validates real user experience. Prevents regressions in production-like conditions.**
