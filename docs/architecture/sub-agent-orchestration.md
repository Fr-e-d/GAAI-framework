# Sub-Agent Orchestration — Architecture Design

**Status:** v3.0 design target. Not adopted in v2.0.0.0.

This document defines the target architecture for sub-agent orchestration in the Delivery track. It is the authoritative design reference for when implementation begins.

---

## Design Principles (Validated)

Four principles drive every decision in this document:

1. **Delivery Agent is orchestrator-only.** It never implements, never tests, never writes a plan. It evaluates, composes, coordinates, and escalates.
2. **Sub-agents are ephemeral.** Lifecycle: spawn → execute → handoff-artefact → die. No runtime communication between agents. All handoffs via files.
3. **Right tool for the task.** Complexity determines team composition. A typo fix does not spawn three agents. A multi-module migration does.
4. **Discovery is out of scope.** Discovery Agent is a conversational human interface. Sub-agents would break the conversational continuity that is its core value. Discovery remains sequential and single-context, permanently.

---

## Why Delivery Agent Must Be Orchestrator-Only

The current v2.0 model gives the Delivery Agent both orchestration skills and execution skills. This creates ambiguity: the agent decides at runtime whether to orchestrate or execute directly. That decision is a source of drift — and it means the agent's available skill set is the union of two roles, making its context larger than necessary for either.

**If Delivery can both orchestrate and execute:**
- Its skills are the superset of orchestrator + executor roles
- Its prompt context carries rules for both roles simultaneously
- The question "when does it orchestrate vs execute?" must be answered at runtime, case by case
- Sub-agents become an optimization layer bolted on top, not a design principle

**If Delivery is orchestrator-only:**
- Its skills: evaluate-story, compose-team, spawn-sub-agents, collect-artefacts, escalate
- It never touches code, never writes tests, never builds a detailed plan
- Each sub-agent has a precise, limited skill set matching its role exactly
- The question "who does what" is answered by the topology, not at runtime

This is the single-responsibility principle applied to agents. The clarity is permanent — it does not erode over time as the framework grows.

---

## Why Discovery Does Not Use Sub-Agents

Discovery Agent and Delivery Agent have fundamentally different operating profiles:

| Dimension | Discovery Agent | Delivery Agent |
|-----------|----------------|----------------|
| Primary interlocutor | The human | The backlog |
| Nature of work | Conversation + clarification + artefact generation | Deterministic execution against a plan |
| Output volume | Short artefacts (PRD, Epics, Stories — ~3K tokens) | Code, tests, reports — can grow large |
| Expected interruptions | Frequent (human questions) | Rare (escalation only) |
| Session structure | One conversation thread | Multi-phase loop with checkpoints |
| Inter-artefact coherence | Critical — PRD must inform Epics must inform Stories | Enforced by acceptance criteria |
| Context accumulation risk | Low | High for complex, multi-phase Stories |

The conversational continuity constraint is decisive. A Planning sub-agent isolated from the conversation thread cannot access the nuance the human expressed two messages earlier. Fragmenting Discovery across sub-agents would produce incoherent artefacts — exactly what `consistency-check` and `validate-artefacts` are designed to catch.

For Discovery, a single coherent context is a feature, not a constraint.

---

## Team Composition Model

The orchestrator composes the delivery team based on Story complexity. Three tiers:

### Tier 1 — MicroDelivery (complexity ≤ 2)

A single sub-agent handles plan + implement + verify in one context window. Minimal context bundle. No specialists.

```
Delivery Orchestrator
    └── MicroDelivery Sub-Agent
            skills: implement, qa-review
            context: Story + acceptance criteria + relevant patterns
```

Use cases: bug fixes, typo corrections, single-line changes, dependency updates, rename operations.

### Tier 2 — Core Team (complexity 3–7)

Three specialized sub-agents, sequentially coordinated.

```
Delivery Orchestrator
    ├── Planning Sub-Agent
    │       skills: delivery-high-level-plan, prepare-execution-plan
    │       context: Story + rules + architecture memory
    │
    ├── Implementation Sub-Agent
    │       skills: implement, codebase-scan, context-building
    │       context: Story + execution plan + coding patterns
    │
    └── QA Sub-Agent
            skills: qa-review, remediate-failures
            context: Story + acceptance criteria + implementation artefact
```

Use cases: standard features, refactors touching 3–7 files, API changes with tests.

### Tier 3 — Core Team + Specialists (complexity ≥ 8)

Core team augmented with specialist sub-agents invoked per-phase when the Implementation sub-agent identifies domain-specific work.

```
Delivery Orchestrator
    ├── Planning Sub-Agent          (same as Tier 2)
    │
    ├── Implementation Sub-Agent
    │       ├── [db-migration specialist]   if schema changes required
    │       ├── [api-integration specialist] if external service involved
    │       └── [ui-component specialist]   if frontend work required
    │
    └── QA Sub-Agent               (same as Tier 2)
```

Specialists are not spawned by the Planning sub-agent or the QA sub-agent — only by Implementation. The orchestrator does not decide which specialists are needed; that determination belongs to the Implementation sub-agent, which reads the execution plan and matches against the specialist registry.

---

## Specialist Registry

Specialists are declared in a file-based registry. The registry is part of the GAAI framework — not dynamic configuration, not code.

```yaml
# .gaai/core/contexts/specialists.registry.yaml
- id: db-migration
  triggers: [schema change, migration, ALTER TABLE, database]
  skills: [implement]
  context_bundle:
    - contexts/memory/patterns/db-conventions.md
    - contexts/rules/artefacts.rules.md

- id: api-integration
  triggers: [webhook, external API, OAuth, HTTP client, third-party]
  skills: [implement]
  context_bundle:
    - contexts/memory/patterns/api-conventions.md

- id: ui-component
  triggers: [component, frontend, CSS, template, layout]
  skills: [implement]
  context_bundle:
    - contexts/memory/patterns/ui-conventions.md

- id: security-audit
  triggers: [authentication, authorization, secrets, credentials, encryption]
  skills: [implement, security-audit]
  context_bundle:
    - contexts/rules/orchestration.rules.md
```

The Implementation sub-agent reads the execution plan, scans for trigger keywords, and invokes matching specialists. No specialist is spawned without a trigger match. This is explicit, auditable, and file-based — consistent with the GAAI design philosophy.

Users can extend the registry for their project's specialist needs.

---

## Sub-Agent Lifecycle

Every sub-agent, without exception, follows this four-step lifecycle:

```
1. SPAWN
   Orchestrator creates sub-agent with an explicit context bundle.
   Context bundle = a set of files, not a live context.
   Sub-agent has no access to the orchestrator's context window.

2. EXECUTE
   Sub-agent runs its task autonomously.
   No communication with orchestrator during execution.
   No communication with sibling sub-agents.
   All inputs come from the context bundle provided at spawn.

3. HANDOFF
   Sub-agent writes a structured artefact to a known file path.
   Sub-agent signals completion (exit 0 or structured output).
   Sub-agent terminates — its context window is released.

4. COLLECT
   Orchestrator reads the artefact.
   Validates structure and completeness.
   Decides: proceed to next phase, re-spawn with enriched context, or escalate.
```

**No exceptions to this lifecycle.** Sub-agents do not call back to the orchestrator. They do not read each other's outputs at runtime. They do not share state. The only communication channel is the artefact file written at step 3 and read at step 4.

### Handoff artefacts

Each phase produces a typed artefact:

```
.gaai/project/contexts/artefacts/plans/{id}.execution-plan.md     ← Planning handoff
.gaai/project/contexts/artefacts/reports/{id}.impl-report.md       ← Implementation handoff
.gaai/project/contexts/artefacts/reports/{id}.qa-report.md         ← QA handoff
```

These are not temporary files. They are durable artefacts — traceable, reviewable, auditable. The QA sub-agent reads the impl-report as part of its context bundle. The orchestrator reads the qa-report to determine the next action.

### Artefact lifecycle

Handoff artefacts are created per Story and persist until the Story is archived:

| State | Artefacts present |
|-------|------------------|
| Story in-progress | execution-plan, impl-report (partial or complete), qa-report (if QA has run) |
| Story done | All three artefacts, plus QA pass record |
| Story archived | Artefacts move with the Story to `backlog/done/` |

Artefacts are never deleted during active delivery. They are the audit trail.

---

## Failure Handling

| Situation | Orchestrator action |
|-----------|-------------------|
| Sub-agent produces valid handoff artefact | Proceed to next phase |
| Sub-agent produces malformed artefact | Re-spawn same sub-agent with enriched context bundle (attempt 2) |
| Sub-agent fails twice | Escalate to human — same protocol as current delivery loop |
| Specialist sub-agent unavailable | Implementation sub-agent proceeds without specialist, notes limitation in impl-report |
| QA fails | Orchestrator re-spawns Implementation sub-agent with qa-report as additional context (remediation loop, max 3 attempts) |

The orchestrator never attempts to fix a failure itself. It coordinates, escalates, or retries. It does not execute.

---

## Tool Compatibility

Sub-agent orchestration requires the AI tool to support spawning isolated context windows programmatically.

| Tool | Support | Notes |
|------|---------|-------|
| Claude Code | Yes | Task agents provide isolated context windows |
| Cursor | No | No equivalent mechanism |
| Windsurf | No | No equivalent mechanism |
| Other tools | Varies | Depends on tool capabilities |

**Consequence:** In v3.0, sub-agent orchestration will be a Claude Code-first feature. On Cursor and Windsurf, the Delivery Agent falls back to the v2.0 sequential model. This is a deliberate trade-off — not a violation of the tool-agnostic principle, but an acknowledgment that the principle has a capability floor.

The fallback is explicit in `compat/COMPAT.md`.

---

## Orchestrator Skill Set (v3.0)

The Delivery Orchestrator's available skills are strictly limited to coordination:

**Keeps from v2.0:**
- `context-building` — assembles context bundles for sub-agents
- `memory-retrieve` — loads relevant memory before composing team

**New in v3.0:**
- `evaluate-story` — determines complexity tier and team composition
- `compose-team` — reads specialists.registry, selects appropriate sub-agents
- `coordinate-handoffs` — validates artefacts, sequences phases, manages retries

**Removed from Delivery Orchestrator's skill set:**
- `delivery-high-level-plan` → moves to Planning Sub-Agent
- `prepare-execution-plan` → moves to Planning Sub-Agent
- `implement` → moves to Implementation Sub-Agent and MicroDelivery Sub-Agent
- `qa-review` → moves to QA Sub-Agent
- `remediate-failures` → moves to QA Sub-Agent (remediation loop)

The orchestrator's context window stays small. It never needs to know how to write code — only how to coordinate agents that do.

---

## Current Position

**Not adopted in v2.0.0.** The sequential delivery model ships as-is.

**Designated v3.0 design target.** This document is the implementation specification. When the trigger conditions are met, implementation begins from this spec — not from a fresh design discussion.

**Trigger conditions for v3.0 adoption:**
1. Claude Code Task agents reach stable API (current status: available but evolving)
2. Real-world evidence that Stories consistently benefit from phase isolation (context pressure, QA failure rates)
3. The specialist registry pattern is validated against real project patterns

**What does NOT change between v2.0 and v3.0:**
- The backlog as sole authorization mechanism
- The file-based artefact model
- The ephemeral agent lifecycle
- The GAAI philosophy: boring, strict, explicit

The orchestration topology changes. The governance model does not.

---

→ [Design Decisions](design-decisions.md)
→ [Roadmap](../contributing/roadmap.md)
→ [Delivery Agent](../../.gaai/core/agents/delivery.agent.md)
