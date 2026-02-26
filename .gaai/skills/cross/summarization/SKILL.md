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
  status: stable
inputs:
  - contexts/memory/index.md        (registry — read first to discover all active categories)
  - contexts/memory/**              (any category registered in index.md — resolved at runtime)
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

**Step 0: Enumerate categories.** Read `contexts/memory/index.md`. List all registered categories. For each category, assess whether summarization is warranted: trigger if >5 files in the category OR estimated token count >5000 tokens OR memory-retrieve is returning too many results for this category. Skip categories that do not meet any threshold.

For each category that meets the threshold:

1. **Identify durable information** — extract confirmed decisions, stable constraints, validated assumptions, current priorities, key outcomes, known risks. Ignore brainstorming noise, intermediate reasoning, abandoned ideas.

2. **Compress into structured summary** — use the template below. Prefer bullets over prose.

3. **Archive raw memory** — move original files to `contexts/memory/archive/{category}-{YYYY-MM-DD}.archive.md`. Concatenate multiple files from the same category into a single archive file. Only summaries remain active.

4. **Update memory index** — record new summary files, archived sources, affected categories.

---

## Summary File Template

```markdown
# {Category} — Summary
> Summarized from {N} files on {YYYY-MM-DD}
> Compression: ~{original_tokens} → ~{summary_tokens} ({percentage}%)

## Decisions
- {bullet per confirmed decision}

## Constraints
- {bullet per active constraint}

## Priorities
- {bullet per current priority}

## Open Questions
- {bullet per unresolved question, if still relevant}
```

---

## Outputs

- `contexts/memory/summaries/{category}.summary.md` — compressed, structured summary for each processed category
- `contexts/memory/archive/{category}-{YYYY-MM-DD}.archive.md` — concatenated originals, retained for audit
- `contexts/memory/index.md` — updated to reflect new summaries and archived sources

---

## Quality Checks

A good summary:
- Summary token count is ≤20% of original — verify before replacing active memory
- Every summarized category has its archive file created before the summary replaces it
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
