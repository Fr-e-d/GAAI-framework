# GAAI Context System

This document defines how **context is structured, governed, and consumed**
inside the GAAI (Governed Agentic AI Infrastructure) system.

The objective is to provide **durable, high-signal context** to AI agents
while keeping reasoning **deterministic, cheap in tokens, and auditable**.

Everything lives **inside the repository**.
There is no hidden state and no external context system.

---

## Design Goals

The GAAI context system is designed to be:
- **Simple** — no external services, no opaque infrastructure
- **Explicit** — no implicit context injection
- **Token-efficient** — selective loading only
- **Governance-friendly** — predictable, auditable behavior
- **Agent-first** — agents decide, skills execute
- **Scalable over long projects**

---

## Context Folder Structure

```
contexts/
├── README.contexts.md    ← you are here
├── rules/                ← governance constraints
├── memory/               ← durable structured knowledge
├── backlog/              ← execution queue
└── artefacts/            ← evidence and traceability
```

Each folder has a **single, well-defined responsibility**.

---

## Agents, Skills & Context Ownership

### Core Principles

> Agents own context.
> Skills never load context implicitly.
> Skills execute in isolated context windows.

- Agents decide **what context is needed**
- Agents explicitly pass context to skills
- Skills never share the agent's reasoning state
- Skills only see what is explicitly provided as input

This guarantees:
- deterministic reasoning
- predictable token usage
- no hidden context pollution
- clean debugging and governance

---

## Context Categories

### Rules (`contexts/rules/`)

Rules define **governance and orchestration**, including:
- agent responsibilities
- allowed and forbidden triggers
- lifecycle constraints
- orchestration flows

Rules are **read-only guidance** and never modified by skills.
See `contexts/rules/README.rules.md` for loading priority.

### Memory (`contexts/memory/`)

Memory stores **durable, structured knowledge** — not chat logs.

```
contexts/memory/
├── README.memory.md
├── index.md
├── project/
├── decisions/
├── summaries/
├── sessions/
└── archive/
```

Memory is always:
- agent-selected
- explicitly retrieved
- intentionally injected

### Backlog (`contexts/backlog/`)

The backlog is the **single source of truth for work**.

```
contexts/backlog/
├── README.backlog.md
├── active.backlog.yaml    ← executable queue
├── blocked.backlog.yaml   ← waiting for clarification
└── done/                  ← archived by period (YYYY-MM.done.yaml)
```

Only Discovery may validate items.
Only Delivery may execute `refined` items.

### Artefacts (`contexts/artefacts/`)

Artefacts are **execution outputs and evidence** — not memory, not authority.

```
contexts/artefacts/
├── README.artefacts.md
├── epics/
├── stories/
├── plans/
├── reports/
├── prd/
├── marketing/    ← posts, campaigns, observation logs, validated hypotheses
└── strategy/     ← GTM plans, positioning, go-to-market artefacts
```

Artefacts inform future reasoning but never trigger execution.

---

## Forbidden Patterns

The following are explicitly forbidden:
- auto-loading full memory
- skills accessing memory implicitly
- storing raw chat transcripts long-term
- Delivery ingesting memory
- bypassing backlog lifecycle states
- direct human → Delivery interaction
- shared context windows between skills

---

## Final Principle

> Context is not history.
> Context is curated knowledge for reasoning.

This context system is intentionally **boring, strict, and explicit**.
That is what makes it reliable.

---

→ [Rules](rules/README.rules.md) — governance constraints and loading priority
→ [Memory](memory/README.memory.md) — how durable knowledge is structured
→ [Backlog](backlog/README.backlog.md) — the execution queue and lifecycle
→ [Artefacts](artefacts/README.artefacts.md) — evidence and traceability
→ [Back to GAAI.md](../GAAI.md)
