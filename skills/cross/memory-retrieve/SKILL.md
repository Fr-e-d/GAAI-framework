---
name: memory-retrieve
description: Load only the minimum relevant memory for a task by filtering the memory index by relevance. Activate before context-building — never load full memory dumps.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-RETRIEVE-001
  updated_at: 2026-01-27
  status: stable
inputs:
  - contexts/memory/index.md        (registry — read first to discover available categories)
  - contexts/memory/**              (any category registered in index.md — resolved at runtime)
outputs:
  - memory_context_bundle
---

# Memory Retrieve

## Purpose / When to Activate

Activate before `context-building` whenever a task requires historical context.

**Never load full memory. Always filter by relevance.**

---

## Process

1. Read memory index (`contexts/memory/index.md` — registry that maps categories to files). If `index.md` is absent or empty, fall back to scanning the `contexts/memory/` directory structure directly — enumerate subdirectories as categories.
2. Identify relevant categories for the current task. Filter first by category (coarse), then by tags within selected categories (fine-grained) in Step 4.
3. Prefer summaries when present (lower token cost)
4. Within the selected categories, filter by tags or scope to narrow to the minimum relevant files.
5. Load only selected files

---

## Output

**`memory_context_bundle`** — curated set of memory files relevant to the current task, ready for `context-building`.

---

## Quality Checks

- No full memory injection
- Context is focused on the task
- Summaries preferred over raw files
- Token usage remains low
- Only memory directly relevant to the task is included

---

## Non-Goals

This skill must NOT:
- Load all memory files
- Decide what to do with retrieved memory
- Modify memory files

**Selective retrieval is the golden rule. Memory is never auto-loaded.**
