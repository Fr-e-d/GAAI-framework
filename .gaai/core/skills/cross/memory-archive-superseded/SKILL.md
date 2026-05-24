---
name: memory-archive-superseded
description: Migrate a superseded DEC's index rows from active `index.md` to `archive/superseded-decisions.archive.md`. Idempotent. Discovery-only — never invoked by daemon delivery. Updates DEC frontmatter as canonical source of truth.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent (filesystem-only operation, no network or shell required for the prompt-only path)
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-ARCHIVE-SUPERSEDED-001
  updated_at: 2026-05-08
  status: stable
inputs:
  - contexts/memory/decisions/DEC-XX.md  (frontmatter to update)
  - contexts/memory/index.md  (rows to remove from Active Files + Decision Registry)
  - contexts/memory/archive/superseded-decisions.archive.md  (rows to add)
outputs:
  - contexts/memory/decisions/DEC-XX.md  (frontmatter updated)
  - contexts/memory/index.md  (rows removed, pointer added)
  - contexts/memory/archive/superseded-decisions.archive.md  (row appended)
  - migration_report  (inline summary)
---

# Memory Archive Superseded

## Purpose / When to Activate

Activate when a DEC has been **formally superseded** by another DEC and you want to migrate its row out of the active index eager-load surface, while preserving full traceability and path stability.

**Discovery-only.** This skill must NEVER be invoked by daemon delivery. Per base.rules.md, Delivery may only write memory via `decision-extraction` after QA PASS. Archive operations are a strategic memory governance act and belong to Discovery (or Bootstrap during initialization).

**When NOT to activate:**
- DEC is still active or candidate (no formal supersession)
- DEC is `deferred` or `cancelled` (different lifecycle, different archive pattern)
- The supersedeur DEC is not yet `active` (premature archival risk)
- Pattern, ARCH, or strategy file supersession (V2 — out of scope this skill)

## Preconditions (must hold before execution)

1. Supersedee DEC has frontmatter `status: superseded` and `superseded_by: DEC-X` (or `[DEC-X, ...]`)
2. Supersedeur DEC file exists at `decisions/DEC-X.md`
3. Supersedeur frontmatter declares `supersedes: [DEC-Y, ...]` mentioning the supersedee
4. The supersedee is currently in active `index.md` (Active Files table and/or Decision Registry)
5. No active or in-progress backlog story is amending the supersedee DEC

If any precondition fails: STOP and escalate. Do not partial-apply.

---

## Process

### Step 1 — Verify preconditions

Read the supersedee DEC frontmatter. Read the supersedeur DEC frontmatter. Read `index.md`. Read `archive/superseded-decisions.archive.md`. Verify all 5 preconditions above.

If `status` is anything other than `superseded`, STOP — do not flip the status as part of the archive op (that's a separate decision that requires Discovery validation).

### Step 2 — Update DEC frontmatter (canonical source of truth)

For the supersedee DEC, ensure these fields are present in YAML frontmatter :
- `status: superseded`
- `superseded_by: DEC-X` (or `[DEC-X, ...]`)
- `archived_at: YYYY-MM-DD` (today's date)
- `archived_to: archive/superseded-decisions.archive.md`

If `archived_at` already exists with an earlier date, leave it (idempotent — first archival date wins). If `archived_to` already points elsewhere, STOP — conflict requires escalation.

### Step 3 — Append row to archive index

Append a row to the table under `## Superseded DEC entries` in `archive/superseded-decisions.archive.md`. Columns :

`| Supersedee | Supersedeur | Chain (if any) | Date | Original rationale | What changed | Notes |`

For chains : if the supersedee was itself a supersedeur of an earlier DEC (e.g. <DEC-id> supersedes <DEC-earlier> and is itself superseded by <DEC-later>), render the full chain `<DEC-earlier> → <DEC-id> → <DEC-later>`.

### Step 4 — Remove rows from active index.md

Remove the supersedee row from :
- Active Files table (the global file list)
- Decision Registry (the per-domain DEC tables)

If a row carries an inline supersession notation like `~~...~~ — superseded by DEC-X` or `(superseded by DEC-X)`, remove the entire row.

### Step 5 — Add pointer row to active index "Superseded (archived)" section

If the section does not yet exist, create it after the last Decision Registry sub-table with the affordance block from the template (see "Affordance template" below).

Append a row to the pointer table :

`| <supersedee> | <supersedeur> | <chain or —> | <date> | <one-line summary> |`

The one-line summary should give an agent enough context to decide whether to load full files. Keep ≤120 chars.

### Step 6 — Update file count metadata

Update the "Total decisions" line and `Shared Categories` decisions row to reflect the new active/archive split.

### Step 7 — Append migration history entry

Append a row to the "Migration history" table at the bottom of `archive/superseded-decisions.archive.md` :

`| YYYY-MM-DD | Migrate <DEC-ID> | 1 | <source> | Discovery |`

### Step 8 — Run linter

Run `validate-memory-index.py` (if shell available) OR ask another agent to run it. Linter must return CLEAN. If violations: revert the migration and escalate.

If linter is not invokable (no shell access), perform manual checks per the L3 prompt instructions in `memory-index-lint/SKILL.md` § "L3 In-session validation prompt".

### Step 9 — Update changelog

Add an entry to `index.md` § Changelog summarizing the operation : DEC archived, source files touched, today's date.

---

## Affordance template (used in Step 5 if section does not yet exist)

```markdown
### Superseded (archived)

> **How agents read this section.** Files are NOT moved — every supersedee DEC remains readable at `decisions/DEC-XX.md` (path stable). Supersession changes the file's *status*, not its *location*. For "why was X decided" questions, **read both endpoints** (supersedee + supersedeur) ; for chains, read every intermediate DEC. Use skill `memory-archive-superseded` to archive new supersedeses ; full archive rows in `archive/superseded-decisions.archive.md`.

| Supersedee | Supersedeur | Chain (if any) | Date | One-line summary |
|---|---|---|---|---|
```

---

## Idempotence & failure recovery

This skill is **idempotent** — running it twice on the same DEC produces no change after the first successful run. If a run fails partway :

- Frontmatter updated but archive row missing → next run detects via linter symmetry check, completes
- Archive row added but active row not removed → linter symmetry check fails, next run detects + completes
- All steps committed but linter still fails → escalate (likely upstream invariant violation)

Order of operations (frontmatter → archive → active) is chosen so that partial failure leaves a recoverable state ; rerun completes the migration.

---

## Migration report (inline, after completion)

```
# Memory Archive Superseded — {date}

## Operation
- Archived: DEC-{N} → DEC-{M}
- Chain: {chain or "—"}

## Files touched
- decisions/DEC-{N}.md (frontmatter: archived_at + archived_to added)
- index.md (rows removed from Active Files + Decision Registry, pointer appended)
- archive/superseded-decisions.archive.md (row appended)

## Linter result
- CLEAN | VIOLATIONS: ...

## Result: SUCCESS | RECOVERED | FAILED
```

---

## Quality Checks

- Idempotent — running twice on the same DEC = no-op after first successful run
- Atomicity-friendly — order frontmatter → archive index → active index so partial failures are recoverable
- Single-DEC operation by default (batch mode: invoke once per DEC sequentially, not parallel — table writes are not concurrency-safe within a single worktree)
- Skill is read-only on supersedeur DEC (only modifies supersedee + index files)
- Always validates with `memory-index-lint` after operation

---

## Non-Goals

This skill must NOT:
- Flip a DEC's `status` from `candidate` or `active` to `superseded` (that's a separate Discovery decision requiring `/gaai:review-input`)
- Archive patterns, ARCH files, or strategy files (V2 scope)
- Move the supersedee DEC file (path stability is hard invariant)
- Be invoked by daemon delivery
- Operate without preconditions check

**memory-archive-superseded migrates an already-decided supersession. It does not make supersession decisions.**

---

## Worktree + parallel safety

- Skill is Discovery-only — no daemon invocation paths
- Table writes are append-style → merge-friendly across worktrees
- If two parallel Discovery sessions both archive different DECs : git merge resolves cleanly (different rows)
- If two parallel sessions both archive the SAME DEC : second run is no-op (idempotent)
- No file locks required (git is the synchronization mechanism)

---

## Related skills

- `memory-index-sync` (V2 amended) — checks `archived_to:` field before re-adding to active registry, to prevent undo of archive
- `memory-index-lint` — discoverability invariants validator (L3 prompt + L4 script)
- `decision-extraction` — DEC creation, including supersedeur frontmatter `supersedes: [...]` writing
