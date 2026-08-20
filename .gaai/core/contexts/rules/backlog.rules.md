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

No primary state may be skipped.

`blocked`, `cancelled` and `superseded` sit outside this chain. Their edges are enumerated in
**Auxiliary State Transitions** below, which is their single authority — this diagram deliberately
does not draw them, because the same edges drawn in two places is how the contradiction recorded
there arose.

| State | Description |
|---|---|
| `draft` | Item is being shaped by Discovery; acceptance criteria incomplete |
| `refined` | Story is validated, acceptance criteria present and unambiguous, ready for Delivery |
| `in_progress` | Delivery is actively executing |
| `done` | Acceptance criteria PASS; moved to `done/` archive |
| `failed` | Execution failed; requires human intervention |
| `blocked` | The item is held out of the ready pool under a recorded reason — dependency unmet, skill missing, external blocker, an unmet precondition, or work in flight outside the loop. A holding state, not a terminal one: the item returns to the chain at the point matching its actual progress. |
| `cancelled` | Deliberately removed from backlog by Discovery. Terminal state. |
| `superseded` | Replaced by a newer backlog item. Must reference replacement ID. Terminal state. |

### Auxiliary State Transitions

**Governing principle.** `blocked` holds an item out of Delivery selection; it never advances it.
On leaving, the item returns to the chain **at the point matching its actual progress** — which is
why the exit edge differs by case and why none of them skips work that was not done.

| Transition | Who | Condition |
|---|---|---|
| `refined` → `blocked` | Discovery | A recorded precondition must clear before the item may be selected |
| `in_progress` → `blocked` | Delivery | Dependency unmet, required skill absent, or external blocker met mid-execution |
| `escalated` \| `failed` → `blocked` | Discovery | Triage established the item is held pending a decision, not abandoned |
| `blocked` → `refined` | Discovery | Blocker cleared, contract intact; item re-enters the ready pool |
| `blocked` → `draft` | Discovery | Blocker cleared but the contract needs reshaping first |
| `blocked` → `in_progress` | Discovery | Execution was already under way when the item was held, and resumes |
| `blocked` → `done` | Discovery | The item **was dispatched before being held** — its record carries a start timestamp — and its own work then passed acceptance and merged while it waited |
| any → `cancelled` | Discovery | Deliberate removal; must include rationale |
| any → `superseded` | Discovery | Replaced by newer item; must reference replacement ID |

`blocked` → `done` is the narrowest edge here and is **not** a way to close work that never ran.
It is a resumption, not a shortcut: the item must already have been dispatched — a start timestamp on
the record is the evidence — and closes because the work it was holding then completed. An item held
before it was ever dispatched has no such history and leaves through `refined`, whatever the state of
any change produced for it outside the loop.

Every `blocked` row MUST carry a `blocked_reason` naming what must clear and who clears it. This is a
review obligation, not a mechanically enforced one.

> **Amended.** The lifecycle diagram drew `blocked` rejoining the chain at `done`, while
> this table admitted only `in_progress → blocked` and the state description said it resolves to
> `refined`. Both readings had textual support, so the rule could not settle whether a held item may
> close, and two agents citing the same file could reach opposite conclusions.
>
> The edges above were recovered from the commit history of the backlog rather than from a snapshot
> of it — a status transition is an event, visible only in the log, and an earlier attempt at this
> amendment asserted history from current rows and got it backwards. Each edge listed was observed in
> at least one real transition. The prior table was not wrong so much as radically incomplete: it
> documented one entry edge and one exit, while the corpus used four entry states and five exits.
>
> Three defects are closed. The auxiliary edges were drawn in two places at once, so picture and
> table could drift apart silently and did — the diagram now stops drawing them and this table is
> their sole authority. The exit edge was under-specified rather than absent, so it is stated as a
> principle (return at the point matching actual progress) with the cases enumerated under it, rather
> than left to be inferred from a glyph. And the terminal edge is bounded by the evidence that
> justifies it: every observed use of it closed an item that had been dispatched before being held,
> so the rule requires that history rather than merely a landed change.
>
> One further use of `blocked` was found and is deliberately **not** blessed here: holding a row to
> keep an automated scheduler from claiming it while work proceeds by hand. That is a workaround for a
> selection defect, and codifying it in the lifecycle would make the status field disagree with
> reality by design. It is recorded so the defect is visible, and left for the scheduler to fix.
>
> Edges for `escalated` and `deferred` other than those above remain undocumented; that gap is
> recorded here, not closed by this amendment.

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
