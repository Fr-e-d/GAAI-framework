---
type: rules
category: artefacts
id: RULES-ARTEFACTS-001
tags:
  - artefacts
  - governance
  - traceability
  - execution
  - non_authoritative
created_at: 2026-02-09
updated_at: 2026-02-20
---

# 📦 GAAI Artefacts Rules

This document defines the **mandatory rules governing artefacts**
inside the GAAI (Governed Agentic AI Infrastructure) system.

These rules are **non-negotiable**.
Any artefact violating these rules is **invalid by design**.

## 🎯 Purpose of Artefacts

Artefacts exist to provide:
- execution evidence
- rationale and explanation
- traceability
- auditability
- support for agent reasoning

Artefacts do **not** exist to:
- drive orchestration
- decide actions
- control workflow
- replace backlog or memory

## 🧠 Core Principles

**Backlog is canonical.**
**Artefacts are informational.**
**Agents decide.**

Artefacts never hold authority.

## 🗂️ Artefact Authority Model

### R1 — Artefacts Never Decide

An artefact MUST NOT:
- decide priorities or scope
- approve or reject execution
- override agent decisions

All authority belongs to **agents**.

### R2 — Artefacts Never Orchestrate

An artefact MUST NOT:
- trigger execution
- change backlog state
- be used by cron or automation as a signal
- act as a workflow controller

Only the **backlog** may be used for orchestration.

## 📑 Structure Rules

### R3 — Mandatory Frontmatter

Every artefact MUST contain YAML frontmatter declaring at minimum:
- `gaai.type: artefact`
- `artefact_type` — must be one of: `epic | story | plan | report | prd | marketing | strategy | evaluation`
- `track`
- `id`
- `related_backlog_id`
- timestamps

Frontmatter is **machine-readable**. Markdown body is **explanatory only**.

### R4 — Descriptive Status Only

Artefacts MAY include local status fields (e.g. `draft`, `final`).
Such statuses are:
- informational only
- non-canonical
- never consumed by automation
- never used for orchestration

## 🔁 Artefacts vs Backlog

### R5 — Backlog Is the Single Source of Truth

- Execution state lives in the backlog
- Artefacts may reference backlog IDs
- Artefacts MUST NOT duplicate or override backlog state

## 🧠 Artefacts & Memory

### R6 — Artefacts Are Not Memory

Artefacts MUST NOT:
- be treated as long-term memory
- be auto-ingested into memory
- bypass memory governance rules

Only agents may decide if an artefact should be summarized into memory.

## 🗂️ Artefact Routing Table (Canonical)

Every artefact type has **one and only one** target directory. This table is the single source of truth for artefact placement. Agents MUST write to these paths — no exceptions.

| Artefact type | Directory | Written by |
|---|---|---|
| `{id}.execution-plan.md` | `contexts/artefacts/plans/` | Planning Sub-Agent |
| `{id}.plan-blocked.md` | `contexts/artefacts/plans/` | Planning Sub-Agent |
| `{id}.approach-evaluation.md` | `contexts/artefacts/evaluations/` | Planning Sub-Agent |
| `{id}.impl-report.md` | `contexts/artefacts/impl-reports/` | Implementation Sub-Agent |
| `{id}.specialist-{domain}.md` | `contexts/artefacts/impl-reports/` | Specialist Sub-Agent |
| `{id}.qa-report.md` | `contexts/artefacts/qa-reports/` | QA Sub-Agent |
| `{id}.memory-delta.md` | `contexts/artefacts/memory-deltas/` | QA Sub-Agent (PASS only) |
| `{id}.micro-delivery-report.md` | `contexts/artefacts/delivery/` | MicroDelivery Sub-Agent |
| `{id}.story.md` | `contexts/artefacts/stories/` | Discovery Agent |
| `{id}.epic.md` | `contexts/artefacts/epics/` | Discovery Agent |
| `{id}-thread.md` | `contexts/artefacts/content/drafts/` | Delivery Orchestrator (via `generate-build-in-public-content`) |
| `{id}-blog.md` | `contexts/artefacts/content/drafts/` | Delivery Orchestrator (milestone stories only) |
| `week-{N}-metrics.md` | `contexts/artefacts/content/drafts/` | Delivery Orchestrator (weekly cadence) |

**R7 — No artefact may be written to the root of `contexts/artefacts/`.** Every artefact must be placed in its designated subdirectory.

---

## 🚫 Forbidden Artefact Behaviors (Hard Fail)

The following behaviors are **explicitly forbidden**:
- triggering execution
- updating backlog state
- ingesting memory directly
- auto-loading themselves into context
- containing hidden orchestration logic
- communicating with humans as authority

Any artefact exhibiting these behaviors is **invalid**.

## 🧠 Final Rule

**If an artefact influences execution without an agent decision,**
**it violates GAAI design principles.**

Artefacts exist to **support clarity and traceability** —
never to control behavior.
