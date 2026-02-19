# GAAI Workflows

Workflows define **how work progresses** — which agents activate, in what order, under which rules, and producing which artefacts.

Workflows do not think. They coordinate thinking (agents) under governance (rules).

---

## What a Workflow Does

A workflow answers one question:

> "What is the next step, and under what constraints?"

Workflows:
- Make the process explicit
- Prevent skipping steps
- Guarantee Discovery precedes Delivery
- Keep AI execution aligned with product intent

---

## Dual-Track Foundation

GAAI is built on a **Dual-Track** model:

```
Discovery Track  → Product clarity
Delivery Track   → Engineering execution
```

Each track has its own workflow, agents, rules, and artefacts.

---

## Workflow Index

| File | Purpose | Track |
|---|---|---|
| `context-bootstrap.workflow.md` | Initialize project context on an existing codebase | Cross |
| `delivery-loop.workflow.md` | Autopiloted delivery with QA gating | Delivery |
| `discovery-to-delivery.workflow.md` | Handoff protocol from Discovery to Delivery | Cross |
| `emergency-rollback.workflow.md` | What to do when delivery goes wrong | Cross |

---

## Usage Notes

- Workflows are **prose descriptions** of the process, not automation scripts
- Shell scripts are available in `scripts/` for automation hooks
- Workflows reference skills by name — skills are the execution units
- The Delivery Loop is the core GAAI execution pattern

---

## Best Practices

- Always orchestrate via governed artefacts — never free-form prompts
- Isolate execution contexts per skill invocation
- Human intervention points are explicit — never bypassed
- Workflows remain tool-agnostic (Claude Code, Cursor, Windsurf, etc.)

---

→ [context-bootstrap.workflow.md](context-bootstrap.workflow.md) — initialize a project (start here)
→ [delivery-loop.workflow.md](delivery-loop.workflow.md) — the core delivery execution pattern
→ [discovery-to-delivery.workflow.md](discovery-to-delivery.workflow.md) — handoff protocol
→ [emergency-rollback.workflow.md](emergency-rollback.workflow.md) — when things go wrong
→ [Back to GAAI.md](../GAAI.md)
