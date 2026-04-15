---
name: memory-reconcile
description: Scan all memory files, documentation (**/docs/**/*.md), and README files (**/README.md) for drift, contradictions, and stale references. Produce a reconciliation report for Discovery to action. Activate on demand or via cron.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.1"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-RECONCILE-001
  updated_at: 2026-04-05
  status: stable
inputs:
  - contexts/memory/index.md  (entry registry)
  - contexts/memory/**  (all files registered in index.md)
  - "**/docs/**/*.md"  (documentation files — discovered via glob, not index)
  - "**/README.md"     (README files — discovered via glob, not index)
outputs:
  - contexts/artefacts/reconciliation-reports/{date}.reconciliation-report.md
---

# Memory Reconcile

> **Why this skill exists:** The OSS (file-based) GAAI runtime has no server-side enforcement. Drift between memory files and the decisions they reference accumulates silently between sessions. `memory-ingest` populates memory from validated outputs but does not cross-check existing entries for staleness or contradiction. `memory-reconcile` is the OSS counterpart of the Cloud `ReconciliationWorkflow` (E40S03) — it fills this gap by scanning existing memory for drift that `memory-ingest` misses. In Cloud, reconciliation is a server-side scheduled workflow. In OSS, the Discovery Agent triggers it manually (or via cron) by invoking this skill.
>
> **DEC-13** (LLM stays client-side): This skill executes locally in the OSS layer, consistent with DEC-13. No data leaves the local filesystem.
>
> **DEC-20** (three-layer governance enforcement): This skill feeds the soft and escalation governance layers by surfacing drift before it becomes a governance violation.

## Purpose / When to Activate

Activate:
- On demand by the Discovery Agent after a significant batch of `memory-ingest` operations.
- After a major refactor has landed and existing memory files may reference superseded decisions.
- After a decision has been superseded and files referencing the old DEC need to be identified.
- When memory files have not been reconciled in more than 30 days.
- After an epic completes that modifies code structure — code-path staleness check surfaces architecture files that may need refresh.

This skill **MAY be triggered by cron** per `orchestration.rules.md`.

This skill **reports issues** — it does not fix them. See Non-Goals.

---

## Process

**1. Build scan manifest (memory + documentation + README)**
The scan manifest has two sources:

**1a. Memory files** — read `contexts/memory/index.md`. Extract the list of all active registered entries: file paths, categories, topic labels, and `updated_at` timestamps.

**1b. Documentation and README files** — discover files via two glob patterns run from the project root:
- `**/docs/**/*.md` — all Markdown files in any `docs/` directory at any depth
- `**/README.md` — all README files at any depth

Exclude paths matching `node_modules/`, `.git/`, `dist/`, `build/`, or any other common vendored/generated directories. For each discovered file, extract `updated_at` from YAML frontmatter if present; if absent, use the file's `git log -1 --format='%aI'` (last commit date) as a proxy.

Tag each manifest entry with its source (`memory` or `documentation`) for reporting purposes. Do not register documentation files in `contexts/memory/index.md` — they remain outside the memory index.

**2. Extract DEC references from overview, strategy, and architecture files**
For each file in the manifest whose category is `project`, `decisions`, `patterns`, or any strategy/architecture category: scan the file content for all occurrences of the pattern `DEC-\d+`. Record every reference found along with the source file path and the approximate line number where the reference appears.

**3. Validate each DEC reference — classify as ACTIVE, SUPERSEDED, or MISSING**
For each DEC reference collected in Step 2: check whether the corresponding decision file (`contexts/memory/decisions/DEC-{N}.md`) exists and is active (not marked `SUPERSEDED`, `RETRACTED`, or `OBSOLETE`). Classify each reference as:
- `ACTIVE` — decision file exists and is active
- `SUPERSEDED` — decision file exists but carries a supersession marker
- `MISSING` — decision file does not exist on disk

**4. Freshness check — detect stale files**
For each overview, strategy, or architecture file in the manifest: compare its `updated_at` against the `updated_at` of every DEC it references. If any referenced DEC has an `updated_at` newer than the file's own `updated_at`, flag the file as `STALE`. This indicates the file was written before the referenced decision changed and may no longer reflect current governance.

**4b. Code-path freshness check**
Before proceeding to Step 5, run a supplementary check against `git` history for files that declare code-path dependencies.

Pre-condition: verify that `git` is available on the PATH (`git --version`). If `git` is unavailable, log the note "Code-path freshness check skipped: git not available." in the report and skip the remainder of this sub-step. The rest of reconciliation proceeds normally.

For each file in the scan manifest that has a non-empty `depends_on.code_paths` array:
1. Read the file's `updated_at` timestamp (from the index entry).
2. For each path listed in `code_paths`, run:
   ```
   git log --oneline --since="{updated_at}" -- "{path}"
   ```
3. If the command returns one or more lines (commits exist after `updated_at`), flag the memory file as a `CODE_PATH_CHANGED` finding. Record: the memory file path, the code path, the commit count, and the number of days elapsed since `updated_at`.

Files without `depends_on`, or with an empty `code_paths` array, are silently skipped — they do not produce a finding of any kind.

**4c. Documentation proximity check**
For documentation files (source = `documentation`) that do NOT declare `depends_on`, apply an automatic proximity heuristic:

1. Determine the parent directory of the documentation file.
2. Identify the nearest source code directory (sibling or parent `src/`, `lib/`, `api/`, or equivalent).
3. Run:
   ```
   git log --oneline --since="{updated_at}" -- "{nearest_source_dir}"
   ```
4. If the command returns commits, flag the documentation file as a `DOC_PROXIMITY_STALE` finding. Record: the doc file path, the source directory checked, the commit count, and the number of days since `updated_at`.

This heuristic catches the common case where code evolves but nearby documentation is not updated. It applies ONLY to documentation files without explicit `depends_on` — files with `depends_on` are handled by Step 4b.

For `**/README.md` files: the proximity directory is the README's own parent directory (a README describes its enclosing module/package).

**5. Produce reconciliation report**
Write the report to `contexts/artefacts/reconciliation-reports/{YYYY-MM-DD}.reconciliation-report.md` using the output format defined in the Output Format section. One file per scan run. If a file already exists for today's date, append a sequence suffix: `{YYYY-MM-DD}-02.reconciliation-report.md` (incrementing as needed).

**6. Handle unreadable or missing files**
If any file registered in `index.md` does not exist on disk or is unreadable (permission error, corrupt content): log it as a finding of type `MISSING_FILE` in the report's Missing Files section and continue scanning. **Do not abort the scan.** The report must record the exact path that was unreadable and the error class (`MISSING_FILE` for file-not-found, `UNREADABLE` for permission error or corrupt content).

---

## Output Format

Output path: `contexts/artefacts/reconciliation-reports/{YYYY-MM-DD}.reconciliation-report.md`

Report frontmatter:
```yaml
---
skill: memory-reconcile
generated_at: YYYY-MM-DD
scan_manifest_source: contexts/memory/index.md
files_scanned: N          # total (memory + documentation + README)
memory_files_scanned: N
doc_files_scanned: N      # docs + README combined
findings_count: N
code_path_findings_count: N
doc_staleness_findings_count: N
---
```

Report sections (in order):

**1. Stale Entries**
Files whose `updated_at` predates a referenced DEC's `updated_at`. Each entry: file path, stale DEC IDs, date delta (in days).

**2. Superseded References**
References to DECs that are now `SUPERSEDED` or `RETRACTED`. Each entry: source file path, line number, DEC ID, supersession marker text found in the decision file.

**3. Contradictions**
Cases where two memory files assert conflicting facts about the same entity or decision. Each entry: file A path, file B path, description of the conflict.

**4. New Knowledge Candidates**
Patterns or decisions referenced in memory files but not yet represented by a dedicated memory entry. Each entry: candidate description, suggested category, source file path.

**5. Missing Files**
Files registered in `index.md` that could not be read (see Process Step 6). Each entry: path, error class (`MISSING_FILE` | `UNREADABLE`).

**6. Code-Path Staleness**
Memory files whose `depends_on.code_paths` reference one or more code paths that have received commits since the file's `updated_at`. Each entry: memory file path, code path, commit count since `updated_at`, days stale.

Example:

| File | code_path | Commits since updated_at | Days stale |
|---|---|---|---|
| architecture/<binding-audit>.md | workers/<worker-dir>/<config-file> | 3 | 2 |

If the code-path freshness check was skipped (git unavailable), this section contains only the skip note: "Code-path freshness check skipped: git not available."

**7. Documentation & README Staleness**
Documentation files (`**/docs/**/*.md`) and README files (`**/README.md`) that are flagged by Step 4b (explicit `depends_on`) or Step 4c (proximity heuristic). Each entry: doc file path, source type (`depends_on` or `proximity`), reference checked (code_path or nearest source dir), commit count since `updated_at`, days stale.

Example:

| File | Source | Reference | Commits since updated_at | Days stale |
|---|---|---|---|---|
| api/docs/overview/what-is-gaai-cloud.md | proximity | api/src/ | 12 | 8 |
| README.md | depends_on | src/index.ts | 3 | 2 |

If no documentation files were discovered, this section contains: "No documentation or README files found in project."

---

## Quality Checks

- Report identifies specific file paths and line numbers, not vague references.
- Every DEC reference in every scanned file is checked — no silent skips.
- Stale entries include the exact date delta (days) between file `updated_at` and DEC `updated_at`.
- Superseded references include the supersession marker text found in the decision file (e.g., `> SUPERSEDED by DEC-XX`).
- Report frontmatter `files_scanned` matches the actual count of files processed (including those that produced no findings).
- Missing files are logged in the Missing Files section, not silently omitted.

---

## Non-Goals

This skill MUST NOT:
- Auto-modify any memory file — it produces a report for Discovery to action.
- Trigger `memory-ingest` directly.
- Delete or archive memory files.
- Auto-correct superseded references without human review.
- Run server-side — this skill is OSS, client-side only (DEC-13). The Cloud counterpart is E40S03.

**Identify drift. Never resolve it unilaterally. Discovery is the sole actor authorized to action the report.**
