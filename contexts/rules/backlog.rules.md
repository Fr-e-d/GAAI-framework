---
type: rules
category: backlog
id: RULES-BACKLOG-001
tags:
  - backlog
  - orchestration
  - governance
  - execution
  - source_of_truth
created_at: 2026-02-09
updated_at: 2026-02-09
---

# 🗂️ GAAI Backlog Rules

This document defines the **mandatory rules governing the backlog**
inside the GAAI (Governed Agentic AI Infrastructure) system.

The backlog is the **single source of truth for work and execution state**.
Any behavior violating these rules is **invalid by design**.

## 🧠 Core Principle

> **If it is not in the backlog, it must not be executed.**

## 👥 Authority Model

### R1 — Discovery Owns the Backlog

Only the **Discovery Agent** may:
- create backlog items
- modify scope or acceptance criteria
- validate and refine items
- move items to `refined`

No other agent or skill has this authority.

### R2 — Delivery Executes the Backlog

The **Delivery Agent** may:
- consume items marked `refined`
- update execution status (`in_progress`, `done`, `failed`)
- attach execution artefacts or notes

Delivery MUST NOT:
- change scope or acceptance criteria
- validate items
- create new backlog entries

## 🔁 Backlog Lifecycle (Mandatory)

Every backlog item MUST follow this lifecycle:

```
draft → refined → in_progress → done | failed
```

No state may be skipped.

| State | Description |
|---|---|
| `draft` | Item is being shaped by Discovery; acceptance criteria incomplete |
| `refined` | Story is validated, acceptance criteria present and unambiguous, ready for Delivery |
| `in_progress` | Delivery is actively executing |
| `done` | Acceptance criteria PASS; moved to `done/` archive |
| `failed` | Execution failed; requires human intervention |

## 🧭 Orchestration Rules

### R3 — Backlog Is the Only Orchestration Signal

- Cron jobs MAY poll the backlog
- Delivery MAY consume only `refined` items
- No artefact, memory file, or skill output may trigger execution

If execution occurs, it MUST be traceable to a backlog item.

### R4 — No Parallel Sources of Truth

The backlog MUST NOT be duplicated.
- Artefacts may reference backlog IDs
- Memory may summarize backlog outcomes
- No other file may represent execution state

## 📑 Backlog Item Structure

Each backlog item MUST declare:
- unique ID
- type (`story`, `task`, `fix`)
- description
- acceptance criteria
- current status
- timestamps
- links to related artefacts (optional)

## 🚫 Forbidden Backlog Behaviors

The following are **explicitly forbidden**:
- execution without a backlog item
- skills modifying backlog state
- cron creating or validating backlog items
- Delivery redefining scope or criteria
- artefacts acting as backlog state
- implicit backlog state transitions

## 🧠 Final Rule

**If execution cannot be traced to a backlog item,**
**the system is out of compliance.**

The backlog is the **spine of GAAI execution governance**.
