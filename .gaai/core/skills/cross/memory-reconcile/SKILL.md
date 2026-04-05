---
name: memory-reconcile
description: Scan all memory files for drift, contradictions, and stale references. Produce a reconciliation report for Discovery to action. Activate on demand or via cron.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-RECONCILE-001
  updated_at: 2026-04-05
  status: stable
inputs:
  - contexts/memory/index.md  (entry registry)
  - contexts/memory/**  (all files registered in index.md)
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

This skill **MAY be triggered by cron** per `orchestration.rules.md`.

This skill **reports issues** — it does not fix them. See Non-Goals.

---

## Process

**1. Read index — build scan manifest**
Read `contexts/memory/index.md`. Extract the list of all active registered entries: file paths, categories, topic labels, and `updated_at` timestamps. This list is the scan manifest for all subsequent steps. Do not scan files that are not registered in the index.

**2. Extract DEC references from overview, strategy, and architecture files**
For each file in the manifest whose category is `project`, `decisions`, `patterns`, or any strategy/architecture category: scan the file content for all occurrences of the pattern `DEC-\d+`. Record every reference found along with the source file path and the approximate line number where the reference appears.

**3. Validate each DEC reference — classify as ACTIVE, SUPERSEDED, or MISSING**
For each DEC reference collected in Step 2: check whether the corresponding decision file (`contexts/memory/decisions/DEC-{N}.md`) exists and is active (not marked `SUPERSEDED`, `RETRACTED`, or `OBSOLETE`). Classify each reference as:
- `ACTIVE` — decision file exists and is active
- `SUPERSEDED` — decision file exists but carries a supersession marker
- `MISSING` — decision file does not exist on disk

**4. Freshness check — detect stale files**
For each overview, strategy, or architecture file in the manifest: compare its `updated_at` against the `updated_at` of every DEC it references. If any referenced DEC has an `updated_at` newer than the file's own `updated_at`, flag the file as `STALE`. This indicates the file was written before the referenced decision changed and may no longer reflect current governance.

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
files_scanned: N
findings_count: N
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
