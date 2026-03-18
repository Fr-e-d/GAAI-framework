---
name: memory-refresh
description: Periodic memory maintenance — archive session files, convert recurring knowledge into summaries, update the memory index. Activate at end of a major phase (Discovery complete, sprint done) or when memory spans many sessions. For emergency context-window pressure mid-task, use memory-compact instead.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-REFRESH-001
  updated_at: 2026-03-03
  status: stable
inputs:
  - contexts/memory/index.md        (registry — read first to discover all active categories)
  - contexts/memory/**              (any category registered in index.md — resolved at runtime)
outputs:
  - contexts/memory/summaries/*.summary.md
  - contexts/memory/archive/**
  - contexts/memory/index.md  (updated)
---

# Memory Refresh

## Purpose / When to Activate

Activate:
- After major discovery or delivery phases
- When memory exceeds comfortable context size
- Periodically on active projects (weekly or per sprint)

This skill governs and optimizes **existing memory only** — it does not create new knowledge.

---

## Process

1. Read memory index
2. Extract durable knowledge from session memory
3. Convert recurring or validated information into summary memory
4. Archive raw session files to `contexts/memory/archive/`
5. **Compact with R7 category-aware rules:**
   - **Durable memory** (decisions, patterns, project, ops, contacts, domains): only entries with explicit supersession markers (`> SUPERSEDED by DEC-XX`, `> RETRACTED`, `> OBSOLETE — {reason}`) may be archived. All other entries are ACTIVE and MUST NOT be archived. Decisions are already individual ADR files (`decisions/DEC-{N}.md`) — no compaction needed. For other oversized durable files → domain-split, not archive.
   - **Ephemeral memory** (sessions): standard compaction — summarize and archive.
5b. **Summary lifecycle — mandatory when extending summary coverage:** When creating or extending a decisions summary file that supersedes an existing one (e.g., `decisions-90-145.summary.md` → `decisions-90-155.summary.md`):
   a. Write the new summary file with updated frontmatter (`id`, `updated_at`, source range).
   b. Update `index.md` Summaries section: replace the old filename with the new one.
   c. Delete the old summary file from disk (it is now superseded; do not leave orphan files).
   d. Verify: confirm old filename is gone from disk AND `index.md` pointer is updated before proceeding.
   Also check `decisions/_log.md` for any `⚠️ PENDING: extend summary range` notes — process them and remove the notes once handled.
6. **Update memory index:** update `index.md` frontmatter `updated_at` to reflect this refresh run.

---

## Quality Checks

- Active memory remains minimal and high-signal
- Summaries become the primary long-term context source
- Raw exploration is archived, not deleted
- No uncontrolled memory growth
- Index always reflects current active memory
- **No active durable memory entry archived** — only superseded/retracted entries may be archived (R7/R7b)

---

## Non-Goals

This skill must NOT:
- Create new project memory
- Record new decisions (use `memory-ingest` or `decision-extraction`)
- Generate architecture context

**Governs existing memory. Keeps it clean, cheap, and precise.**
