---
name: memory-retrieve
description: Load only the minimum relevant memory for a task using 3-level progressive disclosure. Activate before context-building — never load full memory dumps. Never substitute summaries for durable memory.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "2.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-RETRIEVE-001
  updated_at: 2026-03-01
  status: stable
inputs:
  - contexts/memory/index.md        (registry — always read first, contains Decision Registry + file map)
  - contexts/memory/**              (any category registered in index.md — resolved at runtime)
outputs:
  - memory_context_bundle
---

# Memory Retrieve

## Purpose / When to Activate

Activate before `context-building` whenever a task requires historical context.

**Never load full memory. Always filter by relevance.**
**Never substitute summaries for durable memory (decisions, patterns, project).**

---

## 3-Level Progressive Disclosure

```
Level 1 — INDEX SCAN (~5 tokens/entry)
  Read index.md → Decision Registry table (DEC | Domain | Level | Title)
  Agent identifies relevant decision(s) by domain and/or level

Level 2 — INDIVIDUAL ADR FILES (~300 tokens/file)
  Load specific decisions/DEC-{ID}.md files for full entry text
  Load other relevant category files (patterns, project, ops)

Level 3 — CROSS-DOMAIN SCAN (only for Decision Consistency Gate)
  Grep frontmatter across all DEC-*.md files for conflicts
  Only triggered when recording a new decision (DEC-130)
```

---

## Process

1. **Read memory index** (`contexts/memory/index.md`). This contains:
   - Shared categories table (paths + purpose)
   - Decision Registry: one row per DEC-ID with domain, level, and title
   If `index.md` is absent or empty, fall back to scanning `contexts/memory/` directory structure.

2. **Identify relevant decisions** for the current task:
   - Filter the Decision Registry by **domain** (e.g., `billing`, `matching`)
   - Filter by **level** if scope is known (e.g., only `architectural` for implementation tasks)
   - From story/epic tags or explicit instruction scope

3. **Load memory by durability class:**

   **Durable memory** (decisions, patterns, project, ops, contacts, domains):
   → Load individual `decisions/DEC-{ID}.md` files directly. Full text, never summaries.
   → Summaries exist as INDEX-ONLY aids — they list entries for scanning but MUST NOT substitute for the full decision text.
   → Load only the specific decisions relevant to the task (typically 3-10 files).

   **Ephemeral memory** (sessions):
   → Prefer summaries if available (lower token cost).

4. **For Decision Consistency Gate (DEC-130):**
   → Scan the Decision Registry in index.md for ALL entries in the relevant domain
   → Load the specific `DEC-{ID}.md` files to check for conflicts
   → If uncertain about boundaries, also load decisions from adjacent domains

5. **Return `memory_context_bundle`** — curated, minimal set of memory files relevant to the current task.

---

## Output

**`memory_context_bundle`** — curated set of memory files relevant to the current task, ready for `context-building`.

---

## Quality Checks

- No full memory injection
- Context is focused on the task
- Agent loads only the specific DEC-{ID}.md files relevant to the task (typically 3-10)
- **Summaries are NEVER substituted for durable memory** (decisions, patterns, project)
- Decision Registry enables decision identification WITHOUT opening individual files
- Token budget: index (~1,500) + 3-10 individual decision files (~300 each) = ~4,500 tokens typical
- Only memory directly relevant to the task is included

---

## Non-Goals

This skill must NOT:
- Load all memory files
- Decide what to do with retrieved memory
- Modify memory files
- Substitute summary one-liners for full decision text

**Selective retrieval via progressive disclosure. Memory is never auto-loaded. Durable memory is never summarized away.**
