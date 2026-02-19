---
name: summarization
description: Transform large, noisy, or short-term memory into compact, durable, high-signal summaries. Activate when session memory grows large, decisions accumulate, or memory retrieval starts returning too many files.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-SUMMARIZATION-001
  updated_at: 2026-01-30
inputs:
  - contexts/memory/project/**
  - contexts/memory/decisions/**
  - contexts/memory/patterns/**
  - contexts/memory/sessions/**
  - contexts/memory/summaries/**  (for consolidation)
outputs:
  - contexts/memory/summaries/*.summary.md
  - contexts/memory/archive/**
  - contexts/memory/index.md  (updated)
---

# Summarization

## Purpose / When to Activate

Activate when:
- Session memory grows large
- Decisions accumulate across sessions
- Project context becomes fragmented
- Memory retrieval returns too many files
- Token usage increases noticeably

This skill is both preventive and corrective.

---

## Process

For each memory group:

1. **Identify durable information** — extract confirmed decisions, stable constraints, validated assumptions, current priorities, key outcomes, known risks. Ignore brainstorming noise, intermediate reasoning, abandoned ideas.

2. **Compress into structured summary** — key decisions, scope boundaries, architectural/product constraints, current focus, risks and open questions (if still relevant). Prefer bullets over prose.

3. **Archive raw memory** — move original files to `contexts/memory/archive/`. Only summaries remain active.

4. **Update memory index** — record new summary files, archived sources, affected categories.

---

## Quality Checks

A good summary:
- Is under ~10–20% of original token size
- Preserves all actionable knowledge
- Removes all conversational fluff
- Supports future decisions without rereading history

---

## Non-Goals

This skill must NOT:
- Invent new knowledge
- Reinterpret decisions
- Remove active constraints
- Keep long narrative text

**Distill knowledge. Delete noise. Small, sharp context always beats full history.**
