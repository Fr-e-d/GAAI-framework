---
name: memory-compact
description: Emergency single-pass memory compression when context window pressure is high mid-task. Activate when approaching token limits during active work. For scheduled end-of-phase cleanup, use memory-refresh instead.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-COMPACT-001
  updated_at: 2026-03-01
  status: stable
inputs:
  - contexts/memory/index.md
  - contexts/memory/**/*
outputs:
  - contexts/memory/summaries/*.summary.md
  - contexts/memory/archive/**
  - contexts/memory/index.md  (updated)
---

# Memory Compact

## Purpose / When to Activate

Activate when:
- Context window pressure is high
- Memory has grown across many sessions
- A single targeted compression pass is needed

More focused than `memory-refresh` — this is a single-pass compression operation.

---

## Process

1. **Select memory by category or tags.** Read `contexts/memory/index.md`. Prioritize categories by: (a) largest file count first, (b) oldest entries first, (c) categories not referenced by the current task last. Under extreme pressure, compact the single largest category only.

2. **Classify entries by durability (R7 gate).** Before compacting, classify each entry:
   - **Durable** (decisions, patterns, project, ops, contacts, domains): only entries with explicit supersession markers (`> SUPERSEDED by DEC-XX`, `> RETRACTED`, `> OBSOLETE — {reason}`) may be archived. All other entries are ACTIVE and MUST NOT be archived regardless of file size. Note: decisions are already individual ADR files (`decisions/DEC-{N}.md`). For other oversized durable files → domain-split, not archive.
   - **Ephemeral** (sessions): standard compaction applies — summarize and archive.

3. Extract key decisions, constraints, priorities

4. **Generate a single summary file replacing multiple entries.** Produce one summary file per compacted category using bullet format: one bullet per decision, constraint, or durable fact. Target ≤20% of the original token count. Use the format:

```markdown
# {Category} — Compact Summary
> Compacted from {N} files on {YYYY-MM-DD}
> Original token estimate: ~{X} | Summary: ~{Y}

## Key Decisions
- {decision 1}
- {decision 2}

## Active Constraints
- {constraint 1}

## Current State
- {fact 1}
```

5. **Archive detailed originals (ephemeral and superseded only).** Archive originals to `contexts/memory/archive/{category}-{YYYY-MM-DD}.archive.md`. If multiple compactions happen on the same day for the same category, append a sequence number: `{category}-{YYYY-MM-DD}-02.archive.md`.

6. Update memory index

---

## Outputs

- `contexts/memory/summaries/{category}.summary.md`
- `contexts/memory/archive/{category}-{YYYY-MM-DD}.archive.md`
- `contexts/memory/index.md` (updated — mandatory)

---

## Quality Checks

- One summary replaces many files
- Context remains precise and small
- No active constraints are lost
- Index reflects current state
- Summary preserves all active decisions and constraints from the originals
- Archive files are never deleted — only moved
- **No active durable memory entry archived** — only superseded/retracted entries may be archived (R7/R7b)

---

## Non-Goals

This skill must NOT:
- Create new project knowledge
- Invent or reinterpret decisions
- Delete (only archive) source files

**One summary replaces many files. Context stays precise and small.**
