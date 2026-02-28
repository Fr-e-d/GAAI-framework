---
name: prepare-execution-plan
description: Decompose a high-level delivery plan into a precise, file-level execution sequence with explicit ordering, edge cases, and test checkpoints. Activate after delivery-high-level-plan for complex or multi-phase Stories before implementation begins.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DEL-006
  updated_at: 2026-02-26
  status: stable
inputs:
  - contexts/artefacts/plans/*.plan.md        (from delivery-high-level-plan)
  - contexts/artefacts/stories/**             (validated)
  - contexts/rules/**
  - memory_context_bundle
  - codebase_map                              (optional, from codebase-scan)
outputs:
  - contexts/artefacts/plans/{id}.execution-plan.md
---

# Prepare Execution Plan

## Purpose / When to Activate

Activate after `delivery-high-level-plan` when the Story meets at least one of:
- Touches more than 3 files or modules
- Has cross-cutting concerns (shared state, API contracts, migrations)
- Requires a specific implementation order to avoid breakage
- Contains edge cases or error paths that are non-trivial to sequence
- Has a history of QA failures on similar work

For simple Stories (1-2 files, clear criteria, no order constraints), `delivery-high-level-plan` output is sufficient — skip this skill.

---

## Process

### Phase 1 — Codebase Mapping

1. Identify all files that will be created or modified
2. Map dependencies between those files (who imports whom)
3. Identify shared state, interfaces, or contracts that must remain stable across changes
4. Flag any files with existing tests that may be affected

### Phase 2 — Implementation Sequence

4. Order changes to minimize broken states at each intermediate step:
   - Define interfaces/types first (if applicable)
   - Implement lowest-dependency modules first
   - Update consumers after providers are stable
   - Database/schema changes before logic changes
5. Mark explicit checkpoints: points where partial work is testable and safe to commit
6. Identify rollback boundaries: the last safe state before each risky change

### Phase 3 — Edge Cases and Error Paths

7. For each acceptance criterion, enumerate:
   - Happy path behavior (must pass QA)
   - Boundary conditions (empty, null, max values)
   - Error paths (what should fail and how)
   - Concurrency or timing concerns (if applicable)
8. Map each edge case to an explicit test checkpoint

### Phase 4 — Test Sequence

9. Define test order aligned with implementation order:
   - Unit tests for each module (written alongside implementation)
   - Integration checkpoints where cross-module behavior is verified
   - Acceptance criteria tests (the QA gate inputs)
10. Flag which tests must pass before proceeding to the next implementation step

### Phase 5 — Risk Register

11. Surface any remaining ambiguities or risks:
    - Acceptance criteria that are still partially ambiguous
    - Files where blast radius is uncertain
    - External dependencies or APIs that cannot be tested locally
12. For each risk: proposed mitigation or escalation condition

### Phase 6 — Consistency Gate

13. Before finalizing: if the Story references multiple artefacts (Epic, PRD, prior decisions), flag any contradictions found between the plan and those artefacts. Record them in the Risk Register. **Do not write the plan artefact if contradictions exist** — write a `{id}.plan-blocked.md` instead with the specific inconsistencies listed. The Planning Sub-Agent (not this skill) is responsible for invoking `consistency-check` before this skill runs.

---

## Outputs

```markdown
# Execution Plan — {Story ID}: {Story Title}

## Implementation Sequence

| Step | Action | Files | Checkpoint |
|------|--------|-------|------------|
| 1 | {action} | {files} | {test or review gate} |
| 2 | {action} | {files} | {test or review gate} |

## Edge Cases

### {Acceptance Criterion 1}
- Happy path: {behavior}
- Boundary: {condition → expected behavior}
- Error path: {condition → expected behavior}

## Test Checkpoints

1. After step N: {what must pass}
2. After step M: {what must pass}
3. Final QA gate: all acceptance criteria pass

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| {risk} | high/medium/low | {action} |

## Rollback Boundaries

- Safe state after step N: {what is stable}
- Full rollback point: {last known good state}
```

Saves to `contexts/artefacts/plans/{id}.execution-plan.md`.

---

## Quality Checks

- Every acceptance criterion maps to at least one implementation step and one test checkpoint
- Implementation sequence has no circular dependencies
- Every risky step has an explicit rollback boundary
- Edge cases cover: happy path, at least one boundary, at least one error path
- No ambiguity remains in the implementation sequence — all files are named

---

## Non-Goals

This skill must NOT:
- Write any code
- Modify the Story's acceptance criteria or scope
- Make architectural decisions not already implied by the high-level plan
- Produce test code (only test checkpoints and assertions to verify)

**A precise execution plan makes implementation mechanical. Mechanical is auditable. Auditable is governed.**
