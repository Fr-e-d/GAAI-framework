---
name: memory-index-compact
description: Compact verbose memory index / registry files to pointer-only form. Activate when an index file (index.md, index-decisions.md, or any sibling registry table) breaches the file-size budget OR shows substance-duplication drift. Distinct from memory-compact (which targets content categories) and memory-archive-superseded (which migrates superseded rows to archive).
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-INDEX-COMPACT-001
  updated_at: 2026-05-28
  status: stable
inputs:
  - contexts/memory/index.md
  - contexts/memory/index-*.md
  - any sibling registry table (archive/*.archive.md indexes)
outputs:
  - contexts/memory/index.md (updated — pointer-only rows)
  - contexts/memory/index-*.md (updated)
related_skills:
  - memory-compact
  - memory-archive-superseded
  - memory-index-sync
  - memory-index-lint
---

# Memory Index Compact

## Purpose / When to Activate

Activate when:
- A registry file (`index.md`, `index-*.md`, archive index) breaches its file-size budget (typically 40k chars). The `post-commit` hook surfaces this.
- An index row has accreted substance that duplicates the target file body (Tier 2 cycle trails, commit SHAs, §-numbered substance dumps, validation ceremony, drift-heal forensic prose). Detection : any row > 200 chars in a registry table is suspect.
- Scheduled hygiene pass during `memory-index-sync` or post-DEC-activation cleanup.

**Distinct from other memory skills:**
- `memory-compact` — compacts memory CONTENT (sessions, domains) into summaries. NOT for index files.
- `memory-archive-superseded` — migrates superseded DEC rows to archive. Adjacent but separate.
- `memory-index-sync` — heals drift between filesystem and registry (missing rows). Detects bloat ; compaction is THIS skill's job.

## Core principle — index = pointer

Every row in a registry must answer one question : *« Does an agent reading this row for relevance assessment need this word? »*

- **Keep** : file path, ID, category, level, status, ≤30-word topic essence, relation to other entities (amends, supersedes, related).
- **Dégage** : Tier 2 cycle trails, finding counts (F-C1, REFINE 2C+7H+4M+4L), commit SHAs, validation ceremony ("Fred ratified post Tier 2 + Compliance 11/11 PASS"), §-numbered substance dumps duplicating DEC body, drift-heal forensic prose, self-referential pointers without payload.

**Substance lives in:**
- DEC body (`decisions/DEC-XX.md`) — for substantive design rationale
- `_log.md` — for forensic governance trail (cycle history, status flips, drift heals)
- `git log` — for commit history
- artefact files (`contexts/artefacts/research/*.md`) — for deep dives

Index rows duplicating any of these are anti-pattern.

---

## Process

1. **Identify target file.** Read the registry. Confirm it is an index (rows = pointers, not content). Skip if file is substantive content with embedded tables (those follow `memory-compact` flow).

2. **Measure baseline.** Record current size in chars. Note the budget (typically 40k for memory index files — check `hooks/post-commit.d/03-memory-size-budget.sh` `BUDGETS` array). Calculate target reduction.

3. **Triage rows.** For each row > 200 chars, classify content per the « keep / dégage » heuristic:
   - Keep : metadata (path, ID, status, date) + ≤30-word topic + key relations (amends/supersedes).
   - Dégage : everything else, mapping each cut to its source-of-truth file (DEC body / `_log.md` / git / artefact).

4. **Compact the row.** Rewrite in the target form:
   - **Active Files table row:** `| path | category | ID | YYYY-MM-DD (status) |`
   - **Decision registry row:** `| DEC-XX | domain | level | ≤30-word topic. Amends/supersedes X. | status YYYY-MM-DD |`
   - **Changelog row:** `| YYYY-MM-DD | ≤15-word event. Detail → _log.md / DEC-XX. |`
   - **External artefacts row:** `| path | ≤15-word topic | referenced-by IDs |`

5. **Compact narrative sections.** Same principle for non-table prose:
   - **Navigation / TL;DR blocks:** keep only actionable pointers, no philosophy.
   - **Section preambles** ("How agents read this section") : ≤2 sentences max.
   - **Cascade summaries** (paragraphs duplicating registry data) : delete outright.
   - **Frontmatter `updated_at`** with embedded change history : reduce to date only.

6. **Verify no information loss.** Before any cut, confirm the dropped content lives in another source-of-truth file. If a row's content does NOT live elsewhere, the substance must move TO the appropriate target file FIRST (then cut from index).

7. **Update budget tracking.** If the post-commit hook flagged the breach, verify new size is ≤ budget. Re-run the hook locally if available.

---

## Outputs

- Updated index file(s) — pointer-only rows, all substance preserved in source-of-truth files
- No new files (this skill compacts in place ; for extract-to-sibling pattern, see precedent §7.4 in `strategy/strategic-frame.md`)
- No deletions of source-of-truth files

---

## Quality Checks

- Every row is ≤200 chars unless an explicit relation chain justifies more (e.g. multi-DEC amends)
- No row contains : commit SHAs, Tier 2 finding counts, §-numbered substance dumps, validation ceremony prose
- All metadata fields preserved : path, ID, category, level, status, date
- Target file size ≤ budget (per hook `BUDGETS` array)
- `memory-index-lint` passes post-compaction (no broken row symmetry vs filesystem)
- Spot-check : pick 3 random compacted rows ; can an agent decide relevance from them ? If yes, PASS.

---

## Non-Goals

This skill must NOT:
- Move or delete source-of-truth files (`decisions/DEC-XX.md`, `_log.md`, artefacts)
- Extract content into sibling files (that is the §7.4 file-extraction pattern, separate concern)
- Archive superseded rows (use `memory-archive-superseded`)
- Compact memory CONTENT — sessions, domains, patterns body (use `memory-compact`)
- Add new metadata to rows (drift-heal new fields belongs in `memory-index-sync`)
- Modify DEC bodies, `_log.md`, or any source-of-truth file as part of compaction (substance must already live there before the cut — verify in step 6)

---

## Relationship with other skills

```
file-size budget breach → memory-index-compact (this skill)
filesystem-vs-registry drift → memory-index-sync
DEC superseded → memory-archive-superseded
content categories oversized → memory-compact
validation invariants → memory-index-lint
```

If unsure which skill applies, the failure mode of each is well-bounded :
- `memory-index-compact` cuts text but never moves files. Reverse via `git revert`.
- `memory-compact` archives ephemeral content. Reverse via archive restore.
- `memory-archive-superseded` migrates rows + sets `archived_to:` frontmatter. Reverse via `git revert`.

**Pointer principle is invariant.** Even if other skills create or amend rows, those new rows MUST be in pointer-only form per this skill's heuristic. Substance-duplication in any row is a defect.
