# GAAI Backlog System

The GAAI backlog represents the **live execution state** of the product.

It contains only governed, ready-to-execute work — not ideas, not drafts, not noise.

The backlog is designed to be:
- small
- explicit
- automation-friendly
- safe for AI execution

---

## Why the Backlog Exists

In AI-assisted delivery, unlimited speed creates a new risk:

> Executing too much — too fast — without product control.

The GAAI backlog acts as a **controlled execution queue**.

It ensures:
- ✅ only validated Stories are executed
- ✅ scope does not drift
- ✅ automation remains safe
- ✅ context stays minimal
- ✅ history is compressed

---

## Folder Structure

```
contexts/backlog/
├── README.backlog.md         ← you are here
├── active.backlog.yaml       ← executable queue (small & clean)
├── blocked.backlog.yaml      ← waiting for clarification or Discovery
└── done/
    ├── 2026-01.done.yaml     ← archived history (compressed by period)
    └── 2026-02.done.yaml
```

---

## active.backlog.yaml — Execution Queue

Contains only Stories that are:
- validated
- ready for Delivery
- dependency-free (or dependencies resolved)

**Rules:**
- ✔ One item = one Story
- ✔ Must exist as governed artefact
- ✔ Must have acceptance criteria
- ❌ No drafts
- ❌ No vague tasks

---

## blocked.backlog.yaml — Waiting State

Stories that cannot proceed due to:
- missing context
- unclear acceptance criteria
- unresolved decisions

---

## done/ — Compressed History

Completed Stories are moved here periodically by period (`YYYY-MM.done.yaml`).

This keeps:
- active backlog small
- memory cheap
- history preserved

---

## Backlog Lifecycle

```
Discovery Agent → produces Stories
  ↓
Validation gates
  ↓
Story added to active.backlog.yaml
  ↓
Delivery loop executes automatically
  ↓
PASS → moved to done/
FAIL → remediation loop
BLOCKED → moved to blocked.backlog.yaml
```

---

## Governance Rules

The backlog must never contain:
- ❌ Epics
- ❌ vague tasks
- ❌ partial ideas
- ❌ technical todos
- ❌ unvalidated scope

Only governed Stories are allowed.

---

## Best Practices

- ✔ keep `active.backlog.yaml` under ~20 items
- ✔ archive frequently
- ✔ block aggressively when unclear
- ✔ never bypass Discovery
- ✔ treat backlog as production state

---

## Final Principle

The backlog is not a wish list.
It is a governed execution queue.

> If it's not safe to automate — it doesn't belong in `active.backlog.yaml`.

---

→ [active.backlog.yaml](active.backlog.yaml) — the live execution queue
→ [blocked.backlog.yaml](blocked.backlog.yaml) — items waiting for clarification
→ [_template.backlog.yaml](_template.backlog.yaml) — backlog item template
→ [Back to README.contexts.md](../README.contexts.md)
→ [Back to GAAI.md](../../GAAI.md)
