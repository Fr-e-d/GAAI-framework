---
name: memory-retrieve
description: Load only the minimum relevant memory for a task using 3-level progressive disclosure. Activate before context-building — never load full memory dumps. Never substitute summaries for durable memory.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "2.2"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-RETRIEVE-001
  updated_at: 2026-04-05
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
  Optionally traverse `related_to` in loaded files to discover adjacent decisions
  Or invoke `memory-search` Mode C for systematic cross-reference discovery

Level 3 — CROSS-DOMAIN SCAN (only for Decision Consistency Gate)
  Grep frontmatter across all DEC-*.md files for conflicts
  Only triggered when recording a new decision (see Decision Consistency Gate in decision-extraction skill)
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

4. **For Decision Consistency Gate:**
   → Scan the Decision Registry in index.md for ALL entries in the relevant domain
   → Load the specific `DEC-{ID}.md` files to check for conflicts
   → If uncertain about boundaries, also load decisions from adjacent domains

5. **Freshness Check (Tier 2 files only)**

   Pre-condition: verify that `git` is available on the PATH (`git --version`). If `git` is unavailable, append the following note to the `freshness_warnings` section and skip the remainder of this step — proceed to Step 6 normally:
   > Freshness check skipped: git not available

   For each file in the `memory_context_bundle`:

   a. If the file's frontmatter has no `refresh_tier` field, or `refresh_tier` ≠ 2 → **skip** (Tier 1 files are proactively refreshed via the post-delivery hook; Tier 3-4 are not checked at read time).

   b. If `depends_on` is absent or `depends_on.code_paths` is empty → **skip** (treat as Tier 4 — no check, no warning).

   c. If `updated_at` is absent or unparseable → append to `freshness_warnings`:
   > Freshness check skipped: no valid updated_at — {file_path}
   Then **skip** this file.

   d. For each path in `depends_on.code_paths`:
      - If the path does not exist on disk, append to `freshness_warnings`:
        > Freshness check skipped: {path} not found — depends_on may be stale
        Then skip this path.
      - Run: `git log --oneline --since="{updated_at}" -- "{path}"` (where `{updated_at}` is the file's frontmatter value, quoted exactly as-is).
      - Count the lines returned. If the count > 0, the file is `POTENTIALLY_STALE` for this path.

   e. If any path produced a non-zero commit count for this file, append one `freshness_warnings` entry per changed path in the format below (AC2):

   ```
   ⚠ FRESHNESS WARNING — {file_path}
     refresh_tier: 2
     updated_at: {date}
     changed_dependency: {code_path} ({N} commits since updated_at)
     action: verify content is still accurate before relying on it
   ```

   If no warnings are produced, the `freshness_warnings` section is omitted from the output (0 tokens).

6. **Return `memory_context_bundle`** — curated, minimal set of memory files relevant to the current task, plus any `freshness_warnings` produced in Step 5.

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
- Token budget: index (~1,500) + 3-10 individual decision files (~300 each) = ~4,500 tokens typical; `freshness_warnings` section adds ~100-200 tokens when Tier 2 staleness is detected, 0 tokens when all files are clean
- Only memory directly relevant to the task is included
- Freshness warnings are emitted for Tier 2 files with changed code dependencies — never silently suppressed.

---

## Non-Goals

This skill must NOT:
- Load all memory files
- Decide what to do with retrieved memory
- Modify memory files
- Substitute summary one-liners for full decision text

**Selective retrieval via progressive disclosure. Memory is never auto-loaded. Durable memory is never summarized away.**
