# GAAI Artefacts

This document defines what **artefacts are**, how they are used, and their **strict role**
inside the GAAI (Governed Agentic AI Infrastructure) system.

Artefacts provide **evidence, structure, and traceability** —
they never drive orchestration or decision-making.

---

## Purpose of Artefacts

Artefacts exist to:
- document intent, execution, and outcomes
- support agent reasoning
- provide auditability and traceability
- persist execution evidence
- enable human and agent review

Artefacts do **not**:
- decide what to do
- trigger execution
- manage workflow state
- replace backlog or memory

> Artefacts inform decisions. Agents decide.

---

## Core Principles

> Backlog is canonical.
> Artefacts are informational.
> Agents interpret artefacts.

---

## Artefact Types & Folders

```
contexts/artefacts/
├── README.artefacts.md     ← you are here
├── prd/                    ← Product Requirements Documents
├── epics/                  ← Epic artefacts
├── stories/                ← Story artefacts (mirrors backlog items)
├── plans/                  ← Delivery execution plans
└── reports/                ← QA reports, post-mortems, findings
```

---

## Artefact Structure

All artefacts follow the same structural convention:
- YAML frontmatter → **machine-readable contract**
- Markdown body → **human-readable explanation**

### YAML Frontmatter (Mandatory)

```yaml
---
type: artefact
artefact_type: epic | story | plan | report | prd
id: UNIQUE-ID
track: discovery | delivery
related_backlog_id: BACKLOG-ID   # null if no backlog item yet
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---
```

---

## Artefact Types

### Epic Artefacts (`epics/`)

- capture high-level product intent
- structure large initiatives
- describe **what and why** — never execution steps
- any progress indicators are **descriptive only**

### Story Artefacts (`stories/`)

- explain the intent behind a backlog story
- clarify acceptance criteria
- document rationale
- **story status lives in the backlog — not in artefacts**

### Plan Artefacts (`plans/`)

- describe **how** Delivery intends to execute a validated story
- procedural, contain no product decisions or scope changes
- may be iterated freely
- **execution notes, not strategy**

### Reports (`reports/`)

- capture results, findings, or observations
- record execution outcomes
- document failures or anomalies
- never update backlog state or memory directly

### PRD (`prd/`)

- high-level product requirements documents
- produced by Discovery for major initiatives
- optional; not required for every story

---

## Artefacts vs Backlog

| Concern | Backlog | Artefacts |
|---|---|---|
| Execution state | ✅ Canonical | ❌ Never |
| Orchestration | ✅ Yes | ❌ No |
| Evidence & rationale | ❌ | ✅ |
| Execution details | ❌ | ✅ |

---

## Final Principle

**Artefacts describe.**
**Backlog governs.**
**Agents decide.**

---

→ [_template.story.md](_template.story.md) — Story template
→ [_template.epic.md](_template.epic.md) — Epic template
→ [_template.plan.md](_template.plan.md) — Plan template
→ [_template.prd.md](_template.prd.md) — PRD template
→ [Back to README.contexts.md](../README.contexts.md)
→ [Back to GAAI.md](../../GAAI.md)
