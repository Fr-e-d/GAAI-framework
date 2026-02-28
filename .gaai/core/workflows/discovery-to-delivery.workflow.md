---
type: workflow
id: WORKFLOW-DISCOVERY-TO-DELIVERY-001
track: cross
updated_at: 2026-02-18
---

# Discovery to Delivery Handoff Workflow

## Purpose

Define the explicit handoff protocol between the Discovery Track and the Delivery Track.

Discovery ends. Delivery begins. This workflow governs the transition.

---

## Why This Workflow Exists

Without an explicit handoff gate:
- Delivery starts on ambiguous artefacts
- Acceptance criteria are missing or untestable
- Scope creep enters silently
- AI builds fast, wrong things

This workflow prevents all of the above.

---

## Handoff Gate Conditions

Discovery may hand off to Delivery **only when ALL of the following are true**:

| Condition | Check |
|---|---|
| All Stories have explicit acceptance criteria | ✅ |
| `validate-artefacts` returned PASS for all Stories | ✅ |
| Each Story maps to a parent Epic | ✅ |
| Backlog items are status: `refined` | ✅ |
| No open blocking questions remain | ✅ |
| No rule violations in artefacts | ✅ |

If any condition is not met → return to Discovery. Use `refine-scope` or `validate-artefacts` to resolve.

---

## Handoff Steps

### 1. Final Discovery Validation

1. Run `validate-artefacts` against all Stories targeted for Delivery
2. Confirm overall status is PASS — no BLOCKED items

### 2. Backlog Preparation

3. Set all passing Story backlog items to status: `refined`
4. Confirm dependencies are resolved
5. Confirm priorities are set

### 3. Context Transfer

6. Run `decision-extraction` on Discovery session to capture any decisions not yet in memory
7. Run `memory-ingest` if new knowledge was produced during Discovery
8. Verify `contexts/memory/memory/project/context.md` reflects current project state

### 4. Activate Delivery

9. Activate Delivery Agent
10. Hand off: point Delivery Agent to `contexts/backlog/active.backlog.yaml`
11. Start `delivery-loop.workflow.md`

---

## Handoff Contract

The Discovery Agent guarantees:
- Artefacts are outcome-driven and unambiguous
- Acceptance criteria are testable
- Scope is locked

The Delivery Agent commits to:
- Implementing exactly what the artefacts define
- Not reinterpreting product intent
- Escalating if anything is unclear

---

## If Delivery Discovers Ambiguity

If during Delivery, a Story is found to be ambiguous or incomplete:

1. STOP immediately
2. Escalate to Discovery Agent with specific question
3. Discovery refines the Story
4. Revalidate before resuming Delivery

**Delivery never guesses. Delivery never improvises.**
