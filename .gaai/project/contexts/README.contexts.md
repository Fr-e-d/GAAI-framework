# Project Contexts

Project-specific execution context — the state and knowledge that drives this project's GAAI instance.

## Directory Structure

```
contexts/
├── rules/          ← project rule overrides (extend core/contexts/rules/)
├── memory/         ← durable project knowledge (decisions, patterns, contacts, etc.)
├── backlog/        ← execution queue (active, blocked, done)
│   ├── .delivery-locks/   ← cross-device execution coordination
│   └── .delivery-logs/    ← per-story delivery session logs
└── artefacts/      ← delivery evidence and traceability
```

## What Goes Where

| Data | Location | Loaded by |
|------|----------|-----------|
| Governance overrides | `rules/` | Agents (after core rules) |
| Project knowledge | `memory/` | `memory-retrieve` skill |
| Work items | `backlog/active.backlog.yaml` | Delivery Agent, daemon |
| Story evidence | `artefacts/` | QA Sub-Agent, Orchestrator |

## Resolution Order

For rules: `core/contexts/rules/` loads first, then `project/contexts/rules/` as overrides. A project rule with the same filename overrides the core rule entirely.
