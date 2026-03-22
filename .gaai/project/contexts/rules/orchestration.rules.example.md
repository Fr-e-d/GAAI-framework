---
type: rules
category: orchestration
id: RULES-ORCHESTRATION-OVERRIDE-EXAMPLE
example_for: orchestration.rules.md
override_scenario: Allow Discovery and Delivery in the same context window (lightweight mode)
tags:
  - orchestration
  - agents
  - solo-dev
  - context-isolation
created_at: 2026-03-22
updated_at: 2026-03-22
---

# Example Override: Lightweight Mode (Single-Context Discovery + Delivery)

> **This is an example file.** It does not override any core rule.
> To activate this override, copy this file to `project/contexts/rules/orchestration.rules.md`
> (removing the `.example` suffix). The `orchestration.rules.md` filename triggers the override.

---

## What This Overrides

Core rule: **Context Isolation (Non-Negotiable)** from `core/contexts/rules/orchestration.rules.md`:
> "Discovery and Delivery must never coexist in the same context window."

---

## Scenario

You are running GAAI **without the delivery daemon** — triggering deliveries manually in a single Claude session. You want to handle a full Discovery → Delivery cycle in one conversation without spawning isolated sub-agents. This is common for solo developers evaluating GAAI, running small one-off deliveries, or working in environments where sub-agent spawning is not available.

---

## The Override

```markdown
### Context Isolation (Relaxed for Manual Delivery)

For **manual delivery sessions** (no daemon, single-operator context), Discovery and Delivery
MAY operate in the same context window under these conditions:

1. The session begins with Discovery (reads backlog, validates story, confirms acceptance criteria)
2. Discovery explicitly signals completion before Delivery begins:
   `[DISCOVERY COMPLETE — switching to Delivery mode for story {id}]`
3. Delivery proceeds as pure execution from that point — no further Discovery reasoning
4. The transition is one-way: once Delivery begins, Discovery reasoning is frozen

This exception does NOT apply to:
- Multi-story sessions (each story must be isolated)
- Sessions involving memory ingestion (memory-ingest requires a clean Discovery context)
- Daemon-managed delivery (the daemon always enforces full isolation)
```

---

## Tradeoff

**What you gain:** A simpler operational model for solo developers. No daemon setup required. Discovery and Delivery happen sequentially in one conversation, which is easier to reason about and debug.

**What you lose:** The blast-radius protection that context isolation provides. In full isolation mode, Delivery cannot be influenced by Discovery-phase reasoning — stray thoughts, half-formed hypotheses, or discarded alternatives stay out of the implementation context. In lightweight mode, Discovery context is present and can subtly influence Delivery decisions in hard-to-detect ways.

**When this is appropriate:** Solo founders, personal projects, evaluation sessions, or any context where the agent is running a single story manually and the operator is present to catch any reasoning drift.

**When this is NOT appropriate:** Concurrent delivery (multiple stories running in parallel), team environments where Delivery must be reproducible and auditable, or any story where memory ingestion is required post-QA.
