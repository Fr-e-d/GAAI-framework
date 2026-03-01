---
name: memory-search
description: Search memory by frontmatter fields, full-text keywords, or cross-reference graph. Returns ranked file list — never loads full content. Use when the agent needs to find relevant memory without knowing exact paths.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-024
  updated_at: 2026-03-01
  status: stable
  tags:
    - memory
    - search
    - retrieval
    - cross-reference
inputs:
  - search_mode: A | B | C
  - query: mode-specific (see Process)
  - contexts/memory/**  (read-only scan)
outputs:
  - search_results: list of {file_path, id, title, relevance, excerpt} (~2,000 tokens max)
---

# Memory Search

## Purpose / When to Activate

Activate when an agent needs to **find** relevant memory but does not know the exact file path, domain, or DEC ID.

This skill **locates** memory — it does not **load** it. After results are returned, the agent invokes `memory-retrieve` to load the specific files.

Use cases:
- "Which decisions relate to Hyperdrive?" → Mode A (frontmatter: domain=infrastructure, tags contains hyperdrive)
- "Where did we discuss pool exhaustion?" → Mode B (full-text keyword: "pool exhaustion")
- "What decisions are related to DEC-132?" → Mode C (cross-reference: DEC-132 → related_to + mentions)

---

## Process

### Mode A — Frontmatter Search

Search YAML frontmatter fields across `decisions/DEC-*.md` files.

1. Accept query as field-value pairs: `{domain: "infrastructure", level: "operational"}` and/or `{tags: ["hyperdrive"]}` and/or `{related_to: ["DEC-66"]}` and/or `{status: "active"}`
2. Grep frontmatter blocks (between `---` delimiters) of all `decisions/DEC-*.md` files
3. Match files where ALL specified fields match (AND logic)
4. Extract `id`, `title`, and matched field values from each hit
5. Rank by: exact tag match > domain match > level match
6. Return top 10 results

### Mode B — Content Search

Full-text keyword search across ALL memory files.

1. Accept query as 1-3 keywords (e.g., `"pool exhaustion"`, `"scoring formula"`)
2. Grep all files under `contexts/memory/` for keyword matches
3. For each hit, extract:
   - `file_path` (relative to `contexts/memory/`)
   - `id` from frontmatter (if present)
   - `title` from first `#` heading
   - `excerpt` — the matching line ± 1 line of context (~50 tokens)
4. Rank by: number of keyword matches > file recency (`updated_at`)
5. Return top 10 results
6. Never return more than ~2,000 tokens total

### Mode C — Cross-Reference Search

For a given DEC ID, find all files that reference it + traverse `related_to` (depth 1).

1. Accept query as a single DEC ID (e.g., `DEC-132`)
2. **Direct mentions:** grep all files under `contexts/memory/` for the literal string `DEC-132`
3. **Frontmatter `related_to`:** grep `related_to:` lines in `decisions/DEC-*.md` for the target ID
4. **Outbound relations:** read the target file's own `related_to` field → list those DEC IDs
5. Deduplicate and merge results into a single list
6. For each result, extract: `file_path`, `id`, `title`, `relevance` (direct_mention | related_to_inbound | related_to_outbound)
7. Rank: related_to_inbound > related_to_outbound > direct_mention
8. Return all results (typically <15 files)

---

## Quality Checks

- Never loads full file content — only returns paths, IDs, titles, and short excerpts
- Total output stays under ~2,000 tokens
- Mode A searches frontmatter only (fast, structured)
- Mode B searches content (slower, broader — use sparingly)
- Mode C is bounded to depth 1 (no recursive graph traversal)
- Results are always ranked by relevance
- Never modifies any file

---

## Outputs

**`search_results`** — ranked list of memory file references:

```yaml
- file_path: decisions/DEC-132.md
  id: DEC-132
  title: "Centralized SQL connection cleanup"
  relevance: related_to_inbound  # or: frontmatter_match | content_match | direct_mention | related_to_outbound
  excerpt: "safety net for Hyperdrive pool exhaustion"  # ~50 tokens max, absent in Mode A
```

Agent receives this list and decides which files to load via `memory-retrieve`.

---

## Non-Goals

This skill must NOT:
- Load full file contents (that is `memory-retrieve`)
- Modify any memory files (that is `memory-ingest`)
- Make decisions about which results to act on (that is the agent's job)
- Perform recursive graph traversal beyond depth 1
- Search outside `contexts/memory/`

**Memory-search finds. Memory-retrieve loads. The agent decides.**
