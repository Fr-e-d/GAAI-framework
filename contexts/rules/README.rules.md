# Rules (GAAI)

This folder contains the **canonical, tool-agnostic source of truth** for all governance rules used by the GAAI framework.

Rules define **what must be respected** when using AI —
they protect direction, quality, and alignment across Discovery and Delivery.

> If rules are unclear, missing, or contradictory, the system must stop and ask.

---

## What Are Rules?

Rules are **explicit constraints**, not prompts.

They:
- define what is allowed or forbidden
- apply to specific phases and artefacts
- are versioned and auditable
- are readable by humans and usable by any AI tool

Rules do **not**:
- contain workflows (belongs in `workflows/`)
- contain personas or reasoning (belongs in `agents/`)
- implement tool-specific logic

---

## Canonical Location

The **only authoritative location** for rules is `.gaai/core/contexts/rules/`.

Rules live inside Contexts because governance is part of the decision environment,
not a technical configuration layer.

---

## Loading Priority

Rules are loaded selectively by agents — never all at once.

Each rule file declares its own `category` and `tags` in its YAML frontmatter — use these to determine relevance and load order. The source of truth for available rules is this directory. Read each `.rules.md` file directly for its purpose and activation conditions.

---

## Rule File Format

Every rule file uses YAML frontmatter + markdown:

```yaml
---
type: rules
category: orchestration|skills|backlog|artefacts|memory
id: RULES-{CATEGORY}-001
tags: []
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---
# Title
## Content...
```

---

## Adding a New Rule

Before creating a new rule file:
1. Read this index — verify no existing rule already covers the intent
2. Identify the correct `category` (orchestration, skills, backlog, artefacts, memory)
3. Use the file format above with a new `id` following the sequence
4. Add an entry to this index

A rule must define constraints, not workflows or reasoning. If it contains a process, it belongs in `workflows/`. If it defines agent behavior, it belongs in `agents/`.

---

**Start customizing here:**
→ [orchestration.rules.md](orchestration.rules.md) — agent authority and execution flows (edit this first)
→ [skills.rules.md](skills.rules.md) — skill invocation and isolation (execution)
→ [skills-design.rules.md](skills-design.rules.md) — skill authoring constraints: modularity, no hardcoded project values
→ [backlog.rules.md](backlog.rules.md) — backlog lifecycle and state transitions
→ [artefacts.rules.md](artefacts.rules.md) — artefact authority and structure
→ [memory.rules.md](memory.rules.md) — memory retrieval and ingestion
→ [context-discovery.rules.md](context-discovery.rules.md) — Discovery track activation
→ [Back to README.contexts.md](../README.contexts.md)
→ [Back to GAAI.md](../../GAAI.md)
