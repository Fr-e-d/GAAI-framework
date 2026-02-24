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
4. Valid artefact: → **PROCEED to QA phase**

### After QA Sub-Agent terminates

1. Read verdict from `{id}.qa-report.md`:
   - **PASS**: → **MERGE & COMPLETE Story**:
     1. Push story branch to origin
     2. `gh pr create --base staging --head story/{id}`
     3. `gh pr merge --squash` — immediate merge to staging (DEC-71)
     4. If merge fails (conflict): merge staging into branch, resolve, push, retry merge
     5. If merge still fails after 2 attempts: **ESCALATE** with conflict details
     6. After successful merge: update backlog, commit artefacts, cleanup worktree + remote branch
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

## Quality Checks

- No phase transition occurs without a validated handoff artefact
- Retry counts are tracked across the full Story lifecycle (not reset between phases)
- Escalation always includes a specific, actionable failure reason
- PASS is never issued unless `{id}.qa-report.md` contains explicit PASS verdict
