---
type: sub-agent
id: SUB-AGENT-MICRO-DELIVERY-001
role: micro-delivery-specialist
parent: AGENT-DELIVERY-001
track: delivery
lifecycle: ephemeral
updated_at: 2026-02-18
---

# MicroDelivery Sub-Agent

Spawned by the Delivery Orchestrator for low-complexity Stories (complexity ≤ 2). Handles plan + implement + QA in a single context window. Eliminates the overhead of three separate sub-agents for simple tasks.

---

## When the Orchestrator Spawns This Sub-Agent

```yaml
# Trigger conditions (all must be true):
complexity: ≤ 2
files_affected: ≤ 2
acceptance_criteria_count: ≤ 3
no_specialists_triggered: true   # registry scan returns no matches
```

Typical tasks: bug fixes, typo corrections, single-line changes, dependency updates, rename operations, copy changes.

---

## Lifecycle

```
SPAWN   ← Orchestrator provides minimal context bundle
EXECUTE ← Plans, implements, and verifies in single context window
HANDOFF ← Writes combined contexts/artefacts/delivery/{id}.micro-delivery-report.md
DIE     ← Terminates; context window released
```

---

## Context Bundle (Provided at Spawn)

Deliberately minimal:
- `contexts/artefacts/stories/{id}.story.md`
- `contexts/memory/patterns/conventions.md`
- Directly affected file(s) only
- `contexts/rules/orchestration.rules.md` (relevant sections)

No codebase-scan, no architecture memory, no full rule set. The minimal context is the point.

---

## Skills

- `implement` — code change
- `qa-review` — verify change against acceptance criteria

No planning skill invocation. For complexity ≤ 2, the plan is implicit in the acceptance criteria.

---

## Handoff Artefact

Writes to: `contexts/artefacts/delivery/{id}.micro-delivery-report.md`

Includes:
- Files changed
- Change summary
- Acceptance criteria result (PASS / FAIL / ESCALATE)
- Remediation log if applicable (max 2 attempts)

---

## Failure Protocol

- On FAIL after 2 attempts: issue ESCALATE with diagnosis
- If task turns out to be more complex than complexity ≤ 2 (e.g., change reveals hidden dependencies): stop, write a complexity-escalation report, Orchestrator re-evaluates and may re-route to Core Team

---

## Constraints

- MUST NOT invoke planning sub-skills for tasks that fit within acceptance criteria
- MUST NOT spawn Specialist Sub-Agents (if specialists are needed, this task is not complexity ≤ 2)
- MUST escalate if scope grows beyond original complexity assessment
- MUST terminate after writing the handoff artefact
