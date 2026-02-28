# Agents Reference

Three agents. Each has a distinct role, authority level, and skill set.

---

## Overview

| Agent | Track | Authority | Human-facing? | File |
|---|---|---|---|---|
| Discovery | Discovery | Propose + validate | Yes | `.gaai/core/agents/discovery.agent.md` |
| Delivery | Delivery | Orchestrate | No | `.gaai/core/agents/delivery.agent.md` |
| Bootstrap | Cross | Initialize | Yes (first session only) | `.gaai/core/agents/bootstrap.agent.md` |

For the complete agent specification — skills, authority rules, activation conditions — read the agent file directly. The files are the source of truth.

---

## Discovery Agent

**File:** `.gaai/core/agents/discovery.agent.md`

**Role:** Decide what should be built and why.

**When to use:**
- New features or products
- Product changes and iteration
- Clarifying ambiguous ideas

**Do NOT use for:** bug fixes, refactors, pure technical maintenance.

**Activated by:**
- Claude Code: `/gaai-discover`
- Other tools: "Read `.gaai/core/agents/discovery.agent.md`. I want to build [idea]."

**Output:** Artefacts (Epics, Stories, PRDs) + backlog items with `status: refined`

---

## Delivery Agent (Orchestrator)

**File:** `.gaai/core/agents/delivery.agent.md`

**Role:** Orchestrate specialized sub-agents to turn validated Stories into working software. Does not implement, plan, or test directly.

**When to use:** When Stories in the backlog have `status: refined`.

**Activated by:**
- Claude Code: `/gaai-deliver`
- Other tools: "Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`. Execute the next ready backlog item."

**Sub-agents spawned:**

| Sub-Agent | Tier | Purpose |
|-----------|------|---------|
| MicroDelivery | 1 (complexity ≤ 2) | Plan + implement + QA in one context window |
| Planning | 2/3 | Produces file-level execution plan |
| Implementation | 2/3 | Implements code; spawns Specialists if needed |
| QA | 2/3 | Validates output; contains remediation loop |

Specialists are domain-specific sub-agents defined in `contexts/specialists.registry.yaml`. Add entries there to extend the specialist registry — no agent files need to change.

**Output:** Completed Stories with PASS QA verdict — code, tests, artefacts

**The orchestration loop:**

```
Select Story (status: refined)
↓
evaluate-story → tier (1/2/3)
↓
Tier 1: MicroDelivery → PASS/FAIL/ESCALATE
↓
Tier 2/3: Planning → Implementation → QA
          FAIL: re-spawn Impl + QA (max 3 cycles)
          PASS → done → next Story
          ESCALATE → stop, report to human
```

**Sub-agent lifecycle (invariant):** spawn → execute → handoff-artefact → die.

---

## Bootstrap Agent

**File:** `.gaai/core/agents/bootstrap.agent.md`

**Role:** Initialize GAAI on an existing codebase. Run once.

**When to use:** When adding GAAI to a project that already has code.

**Activated by:**
- Claude Code: `/gaai-bootstrap`
- Other tools: "Read `.gaai/core/agents/bootstrap.agent.md`, then follow `.gaai/core/workflows/context-bootstrap.workflow.md`."

**Output:** Populated `contexts/memory/` files, initial `contexts/rules/` structure

**Completes when:** `✅ Bootstrap PASS — context ready.`

---

## Agent Relationships

```
Bootstrap (one-time init)
    ↓
Discovery ←→ Human (ongoing: ideas, feedback, decisions)
    ↓
Backlog (authorization gate)
    ↓
Delivery (autonomous execution)
    ↓
Done items → Memory (decisions captured)
```

Agents do not communicate directly. The backlog is the interface between Discovery and Delivery. Memory is the interface across sessions.

### Why Discovery and Delivery are architecturally distinct

A common misconception is that Discovery and Delivery are two phases of the same agent. They are not. Their operating profiles are fundamentally different:

| Dimension | Discovery Agent | Delivery Agent |
|-----------|----------------|----------------|
| Primary interlocutor | The human | The backlog |
| Nature of work | Conversation + clarification + artefact generation | Deterministic execution against a plan |
| Output volume | Short artefacts (PRD, Epics, Stories) | Code, tests, QA reports — can grow large |
| Expected interruptions | Frequent (asks the human questions) | Rare (escalation only) |
| Context requirement | Conversational continuity is critical | Phase isolation improves quality |
| Authorization source | Human intent + project constraints | `status: refined` backlog item |
| Failure mode | Ambiguous artefacts → stop and ask | QA failure → remediate or escalate |

This is why Discovery never uses sub-agents (conversational continuity would break) and why Delivery is designed for phase isolation. The architecture reflects the work — not the other way around.

See [Sub-Agent Orchestration](../architecture/sub-agent-orchestration.md) for the full design.

---

→ [Skills Index](../../.gaai/core/skills/README.skills.md)
→ [Workflows Reference](workflows.md)
