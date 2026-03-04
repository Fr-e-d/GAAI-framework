# GAAI Backlog System

The backlog is the **live execution state** — a controlled execution queue for AI-assisted delivery.

---

## Folder Structure

```
contexts/backlog/
├── README.backlog.md         ← you are here
├── active.backlog.yaml       ← executable queue (small & clean)
├── blocked.backlog.yaml      ← waiting for clarification or Discovery
├── _template.backlog.yaml    ← template for new items
├── done/                     ← archived history (compressed by period)
├── .delivery-locks/          ← cross-device execution coordination
└── .delivery-logs/           ← per-story delivery session logs
```

## Rules

- One item = one Story (no Epics, no vague tasks)
- Must have acceptance criteria in a corresponding artefact
- Only Discovery may add items; only Delivery may update status
- Keep `active.backlog.yaml` under ~20 items
- Archive completed items to `done/` periodically

## Lifecycle

```
Discovery Agent → produces Stories
  → Validation gates
  → Story added to active.backlog.yaml (status: refined)
  → Delivery loop executes automatically
  → PASS → moved to done/
  → FAIL → remediation loop
  → BLOCKED → moved to blocked.backlog.yaml
```
