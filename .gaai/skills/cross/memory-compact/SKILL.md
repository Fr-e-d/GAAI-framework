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
  updated_at: 2026-01-27
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

1. Select memory by category or tags
2. Extract key decisions, constraints, priorities
3. Generate a single summary file replacing multiple entries
4. Archive detailed originals to `contexts/memory/archive/`
5. Update memory index

---

## Quality Checks

- One summary replaces many files
- Context remains precise and small
- No active constraints are lost
- Index reflects current state

---

## Non-Goals

This skill must NOT:
- Create new project knowledge
- Invent or reinterpret decisions
- Delete (only archive) source files

**One summary replaces many files. Context stays precise and small.**
