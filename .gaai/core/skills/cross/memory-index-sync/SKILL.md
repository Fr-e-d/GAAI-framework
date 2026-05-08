---
name: memory-index-sync
description: Detect and heal index.md drift — finds memory files on disk not registered in index.md and registers them. Run when /gaai-status reports unregistered files, after batch memory operations, or as a post-delivery gate.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-INDEX-SYNC-001
  updated_at: 2026-05-08
  status: stable
inputs:
  - contexts/memory/  (full scan — read-only except index.md)
outputs:
  - contexts/memory/index.md  (registry updated if drift found)
  - sync_report  (inline summary of changes applied and anomalies flagged)
---

# Memory Index Sync

## Purpose / When to Activate

Activate when:
- `/gaai-status` reports files on disk not registered in `index.md`
- After a batch of DEC files were created outside the `decision-extraction` skill
- As a lightweight post-delivery gate to confirm index integrity
- Before running `memory-refresh` or `memory-compact` (ensures index accuracy first)

This skill **heals drift** — it does NOT create new knowledge. It only registers things that already exist on disk but are missing from `index.md`.

---

## Process

### Step 1 — Decision Registry Sync

1. Read all registry files at `contexts/memory/` root (`index.md` + any `index-*.md` siblings such as `index-decisions.md` when Decision Registry has been extracted per file-size budget) — extract all registered DEC IDs from any of them
2. Read `archive/superseded-decisions.archive.md` "Superseded DEC entries" table — extract all archived DEC IDs (column 1)
3. Glob `decisions/DEC-*.md` — list all files on disk, extract IDs from filenames
4. For each DEC file on disk:
   - Read its YAML frontmatter : `id`, `domain`, `level`, `title`, `status`, `superseded_by`, **`archived_to`** (coordinated with `memory-archive-superseded` skill)
   - **If `archived_to:` field is set** (e.g. `archive/superseded-decisions.archive.md`) AND the DEC ID is present in the archive index: SKIP active registration. The DEC's active home is the archive. Do NOT add a row to the active Decision Registry. (Prevents undo of archive operation by `memory-archive-superseded` skill.)
   - **If `archived_to:` is set BUT no matching archive row**: flag `⚠️ ARCHIVE INCONSISTENCY: DEC-{N} frontmatter declares archived_to but no row in archive index` — escalate, do NOT auto-add either way
   - **If `archived_to:` is NOT set AND DEC is not in any active registry**: add a row to the appropriate Decision Registry — prefer `index-decisions.md` if it exists (Decision Registry has been extracted there) ; otherwise add to `index.md` Decision Registry as before. Format : `| DEC-{N} | {domain} | {level} | {title} |`. If frontmatter `status: superseded` and `superseded_by` is set: append `⚠️ SUPERSEDED by DEC-{M}` to the description column AND flag in report : "consider invoking `memory-archive-superseded` for DEC-{N}"
5. For each registered DEC with **no file on disk**: flag `⚠️ MISSING FILE` in the sync report — do NOT delete registry rows (possible archive situation)

### Step 2 — File Count Update

Re-count all `DEC-*.md` files on disk. Update the Shared Categories table file count in `index.md` to match.

### Step 3 — Summary File Sync

1. Read `index.md` Summaries section — extract registered summary filenames
2. Glob `summaries/*.summary.md` — list all files on disk
3. For each summary on disk **not** registered in `index.md`: read its frontmatter, add entry to Summaries section
4. For each registered summary with **no file on disk**: flag `⚠️ MISSING FILE — update pointer or delete entry` in sync report

### Step 4 — Supersession Reconciliation

1. For each DEC file on disk with `status: superseded` in frontmatter:
   - Check if its registry row carries the `⚠️ SUPERSEDED by DEC-{M}` marker
   - If not: add the marker to the registry row
2. Verify the Superseded/Retracted table in `index.md` is consistent with the Decision Registry (no contradictions)

### Step 5 — Index Frontmatter Update

Update `index.md` frontmatter `updated_at` field:
- Format: `{YYYY-MM-DD} ({N} entries synced, {M} anomalies flagged)` — or `(no drift — confirmed clean)` if nothing changed

### Step 6 — Archive Index Symmetry Check

1. For every DEC ID in `archive/superseded-decisions.archive.md` "Superseded DEC entries" table : verify there is exactly one matching pointer row in `index.md` § "Superseded (archived)" pointer table. Dangling archive row (no active pointer) = anomaly.
2. For every pointer row in `index.md` § "Superseded (archived)" : verify there is exactly one matching archive row. Orphan pointer (no archive backing) = anomaly.
3. Hand off to `memory-index-lint` for full discoverability invariant validation. If `memory-index-lint` is invokable (shell available), run `python3 scripts/validate-memory-index.py` and require `CLEAN` exit before declaring `DRIFT_HEALED` ; otherwise perform the L3 prompt-based check from `memory-index-lint/SKILL.md`.

---

## Output: Sync Report (inline, after completion)

```
# Memory Index Sync — {date}

## Changes Applied
- Registered: DEC-{A}, DEC-{B}, ..., DEC-{Z} (10 entries added to registry)
- Supersession markers added: DEC-{X} (→ DEC-{Y})
- File count updated: N → M

## Anomalies Flagged (requires human review)
- ⚠️ MISSING FILE: DEC-{N} registered but no file on disk
- ⚠️ ORPHAN SUMMARY: decisions-80-89.summary.md on disk, not in index

## Result: CLEAN | DRIFT_HEALED | ANOMALIES_FOUND
```

---

## Quality Checks

- Only registers what exists on disk — never invents registry rows
- Never deletes existing registry rows (only flags anomalies)
- Sync report is always produced, even if no changes needed (`CLEAN`)
- Idempotent — running twice produces no additional changes
- Does not modify any file except `index.md`

---

## Non-Goals

This skill must NOT:
- Create new DEC files (use `decision-extraction`)
- Ingest new knowledge (use `memory-ingest`)
- Compact or archive memory (use `memory-compact` or `memory-refresh`)
- Modify DEC file content

**Memory-index-sync heals the registry. It does not create or delete knowledge.**
