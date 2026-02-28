---
name: coordinate-handoffs
description: Validate sub-agent handoff artefacts, sequence phase transitions, and manage retry and escalation logic. Activate after each sub-agent terminates to determine next action.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DEL-009
  updated_at: 2026-02-18
  status: stable
inputs:
  - contexts/artefacts/plans/{id}.execution-plan.md       (after Planning phase)
  - contexts/artefacts/impl-reports/{id}.impl-report.md   (after Implementation phase)
  - contexts/artefacts/qa-reports/{id}.qa-report.md       (after QA phase)
  - contexts/artefacts/delivery/{id}.micro-delivery-report.md  (Tier 1)
  - contexts/artefacts/plans/{id}.plan-blocked.md         (on Planning failure)
outputs:
  - next-action decision (inline — to Orchestrator)
---

# Coordinate Handoffs

## Purpose / When to Activate

Activate after each sub-agent writes its handoff artefact and terminates.

The Orchestrator cannot proceed to the next phase until it has validated the current phase's output. This skill validates artefact structure, interprets verdicts, and returns a clear next-action decision.

---

## Process

### After Planning Sub-Agent terminates

1. Check: does `{id}.execution-plan.md` exist?
   - No → check for `{id}.plan-blocked.md`
     - If blocked artefact exists: **ESCALATE** with block reason
     - If neither exists: **RE-SPAWN** Planning Sub-Agent (attempt 2)
2. Check: does the execution plan contain required sections? (Implementation Sequence, Edge Cases, Test Checkpoints, Risk Register)
   - No → **RE-SPAWN** Planning Sub-Agent with validation failure noted (attempt 2)
   - After 2 failed attempts: **ESCALATE**
3. Valid artefact: → **PROCEED to Implementation phase**

### After Implementation Sub-Agent terminates

1. Check: does `{id}.impl-report.md` exist?
   - No: **RE-SPAWN** (attempt 2), then **ESCALATE**
2. Check: does impl-report contain required sections? (changes made, criteria mapping, rules applied)
   - No: **RE-SPAWN** with validation failure noted
3. Check: impl-report notes any blocking failures?
   - Yes: **RE-SPAWN** with enriched context (add failure details to bundle)
   - Note: implementation self-reported blocking failures (from impl-report) count as the first attempt. A single RE-SPAWN with enriched context is allowed. If the second attempt also reports blocking failures, escalate — do not enter QA.
4. Valid artefact: → **PROCEED to QA phase**

### After QA Sub-Agent terminates

1. Read verdict from `{id}.qa-report.md`:
   - **PASS**: → **INTEGRATE, MERGE & COMPLETE Story**:
     1. **Rebase on staging** (in worktree): `git merge staging` into story branch
     2. **Verify build**: `npx tsc --noEmit` in worktree
        - If fails with errors **introduced by this story** → fix and re-commit
        - If fails with **pre-existing errors only** → proceed (not this story's problem)
        - If unclear → **ESCALATE** with error list
     3. **Verify tests**: `npx vitest run` in worktree
        - Same triage: story-introduced failures → fix; pre-existing → proceed; unclear → **ESCALATE**
     4. Push story branch to origin
     5. `gh pr create --base staging --head story/{id}`
     6. Wait for PR CI check to reach a terminal state (`gh run watch`)
        - If CI fails → diagnose: same triage as steps 2–3 (fix story issues, ignore pre-existing)
        - If CI fails on infra (missing secrets, missing bindings) → **ESCALATE** with logs
     7. `gh pr merge --squash` — immediate merge to staging (DEC-71)
        - If merge fails (conflict): merge staging into branch, resolve, push, retry merge
        - If merge still fails after 2 attempts: **ESCALATE** with conflict details
        - If merge rejected (branch protection / checks required): wait for checks, then retry
     8. After successful merge: verify staging deploy CI (`gh run list --branch staging --limit 1`)
        - If staging deploy fails → **ESCALATE** with deploy logs (do not attempt infra fixes)
     9. If `{id}.memory-delta.md` exists in `contexts/artefacts/memory-deltas/`, flag it in the completion report for Discovery to action via `memory-ingest`.
    10. Update backlog (status=done, pr_url, pr_number, pr_status, completed_at), commit artefacts, cleanup worktree
     **NEVER leave a PR open. NEVER merge to production (staging only).**
   - **FAIL**: spawn count < 2? → **RE-SPAWN** Implementation Sub-Agent with qa-report, then re-spawn QA Sub-Agent
   - **FAIL** after 2 cycles: → **ESCALATE**
   - **ESCALATE**: → **ESCALATE** (pass QA's escalation reason to human)

### After MicroDelivery Sub-Agent terminates (Tier 1)

1. Read verdict from `{id}.micro-delivery-report.md`:
   - **PASS**: → **COMPLETE Story**
   - **FAIL** (attempt 1): → **RE-SPAWN** MicroDelivery Sub-Agent (max 1 retry)
   - **FAIL** (attempt 2): → **ESCALATE**
   - **ESCALATE** (complexity escalation): → **RE-EVALUATE** Story as Tier 2 and re-run with Core Team

---

## Retry Limits

| Phase | Max re-spawns |
|-------|--------------|
| Planning Sub-Agent | 1 retry (2 total) |
| Implementation Sub-Agent | 1 retry per QA cycle (2 total) |
| QA Sub-Agent | Re-runs after each Implementation retry |
| QA FAIL cycles | 2 (before ESCALATE) |
| MicroDelivery Sub-Agent | 1 retry (2 total) |

---

## Escalation Package

When escalating, the Orchestrator surfaces to the human:
- Story ID and title
- Phase where escalation occurred
- Handoff artefact path (for full context)
- Specific failure reason
- Recommended next action (back to Discovery / manual fix / scope clarification)

---

## Non-Goals

This skill must NOT:
- Make product decisions about what to implement
- Modify acceptance criteria
- Skip QA validation even under time pressure
- Delete worktrees containing uncommitted work without confirmation

---

## Quality Checks

- No phase transition occurs without a validated handoff artefact
- Retry counts are tracked across the full Story lifecycle (not reset between phases)
- Escalation always includes a specific, actionable failure reason
- PASS is never issued unless `{id}.qa-report.md` contains explicit PASS verdict
