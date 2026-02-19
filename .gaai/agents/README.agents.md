# Agents (GAAI)

Agents are the **thinking units** of the GAAI framework.
They encapsulate **decision-making logic and domain reasoning** that would normally live in human roles.

Agents:
- reason
- make trade-offs
- produce governed artefacts
- invoke skills when needed

Agents do **not**:
- orchestrate process (belongs to workflows)
- define governance (belongs to rules)
- manage execution loops
- bypass artefacts

**Agents think.**
**Workflows coordinate.**
**Rules govern.**

---

## What Is an Agent?

An agent is:
- a focused cognitive role
- responsible for one track of the system
- constrained by explicit rules
- operating through artefacts

Agents exist to make AI behavior:
- predictable
- explainable
- auditable
- aligned with product intent

---

## Core Principle

GAAI intentionally limits the number of agents.

> More agents = more coordination overhead + more context pollution.

GAAI uses **two primary agents** aligned with the Dual-Track model, one Bootstrap agent, and four Delivery Sub-Agents spawned by the Delivery Orchestrator.

---

## Primary Agents

### 🧠 Discovery Agent (`discovery.agent.md`)

**Purpose:** Decide what should be built — and why.

- the **only human-facing agent**
- interprets human intent
- produces PRD, Epics, Stories with acceptance criteria
- validates artefact coherence before handoff to Delivery

Constraints: never writes code, never defines technical implementation. Never uses sub-agents — conversational continuity with the human is its core value.

### 🛠️ Delivery Agent (`delivery.agent.md`) — Orchestrator

**Purpose:** Coordinate the delivery team to turn validated Stories into working software.

- a **pure orchestration agent** — it does not write code, tests, or plans
- evaluates Story complexity, composes the team, spawns sub-agents
- collects handoff artefacts, manages phase transitions
- escalates to human when blocked

Constraints: never redefines product intent, never adds unvalidated scope, never executes directly.

### 🏗️ Bootstrap Agent (`bootstrap.agent.md`)

**Purpose:** Initialize and converge project context at the start of a project or onboarding.

- runs once (at project start or on major onboarding)
- builds durable project memory
- normalizes rules
- maps system structure

Constraints: never implements features, never runs in the delivery loop.

---

## Delivery Sub-Agents (`sub-agents/`)

Sub-agents are spawned by the Delivery Orchestrator. They are ephemeral: spawn → execute → handoff-artefact → die. No runtime communication between sub-agents.

Each sub-agent spec lives in `sub-agents/` — read the individual files for tier, purpose, and constraints.

Specialist sub-agents are defined in `contexts/specialists.registry.yaml` and spawned by the Implementation Sub-Agent on domain trigger matches.

---

## Agent Responsibilities Matrix

| Concern | Discovery | Delivery Orchestrator | Sub-Agents | Bootstrap |
|---------|-----------|----------------------|------------|-----------|
| Product value | ✅ | ❌ | ❌ | ❌ |
| Scope decisions | ✅ | ❌ | ❌ | ❌ |
| Team composition | ❌ | ✅ | ❌ | ❌ |
| Implementation | ❌ | ❌ | ✅ (Impl/Micro) | ❌ |
| Testing / QA | ❌ | ❌ | ✅ (QA/Micro) | ❌ |
| Planning | ❌ | ❌ | ✅ (Planning/Micro) | ❌ |
| Memory ingestion | ✅ | ⚠️ (post-Story only) | ❌ | ✅ |
| Rule normalization | ❌ | ❌ | ❌ | ✅ |
| Project context init | ❌ | ❌ | ❌ | ✅ |

---

## Mental Model

```
Idea
  ↓
Discovery Agent → clarity & decisions
  ↓
Artefacts (PRD → Epics → Stories)
  ↓
Delivery Orchestrator → evaluates → composes team → coordinates
  ↓
Sub-Agents (Planning, Implementation, QA) → handoff artefacts
  ↓
Working software
```

Everything else in GAAI exists to support this flow.

---

## Final Principle

Agents are not meant to be clever.
They are meant to be reliable.

> Clarity beats intelligence.
> Governance beats creativity.
> Artefacts beat memory.

---

→ [discovery.agent.md](discovery.agent.md) — Discovery Agent spec
→ [delivery.agent.md](delivery.agent.md) — Delivery Orchestrator spec
→ [bootstrap.agent.md](bootstrap.agent.md) — Bootstrap Agent spec
→ [sub-agents/](sub-agents/) — Delivery sub-agent specs (Planning, Implementation, QA, MicroDelivery)
→ [Back to GAAI.md](../GAAI.md)
