---
name: memory-index-lint
description: Validate discoverability invariants of memory `index.md` and `archive/superseded-decisions.archive.md`. Tool-agnostic L3 prompt + capability-dependent L4 script. Detects table corruption, dangling/orphan supersession pointers, frontmatter inconsistencies, missing affordance signals.
license: ELv2
compatibility: L3 prompt = any filesystem-based AI coding agent ; L4 script requires Python 3.9+ + Bash access
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-INDEX-LINT-001
  updated_at: 2026-05-08
  status: stable
inputs:
  - contexts/memory/index.md
  - contexts/memory/archive/superseded-decisions.archive.md
  - contexts/memory/decisions/DEC-*.md  (frontmatters only)
outputs:
  - lint_report  (inline summary of violations + soft warnings)
---

# Memory Index Lint

## Purpose / When to Activate

Validate that `index.md` and `archive/superseded-decisions.archive.md` satisfy the discoverability invariants required for AI agents to reliably navigate the memory corpus without missing context.

**Activate when:**
- Pre-commit (via git hook)
- Post-merge (via CI)
- Before invoking `memory-archive-superseded` (precondition check)
- After invoking `memory-archive-superseded` (post-condition check)
- After manual edits to `index.md` or archive files
- As part of `memory-index-sync` post-step

---

## Two execution paths

### L4 — Capability-dependent script (preferred when shell available)

When the agent has Bash/shell access (Claude Code, Cursor with terminal, daemon `claude -p`) :

```bash
python3 scripts/validate-memory-index.py
# Exit 0 = CLEAN
# Exit 1 = VIOLATIONS (printed to stderr/stdout)
# Exit 2 = USAGE / IO error

# Strict mode: treat soft warnings as failures (use post-migration)
python3 scripts/validate-memory-index.py --strict

# Quiet mode: print only final summary line
python3 scripts/validate-memory-index.py --quiet
```

Pre-commit hook invokes the script automatically — no manual invocation needed in most flows.

### L3 — Tool-agnostic in-session prompt (fallback when no shell)

When the agent is on a surface without shell access, or when invoking the script is not appropriate, perform these checks manually by reading the files :

#### Invariant checks (mandatory)

1. **Table column consistency.** For every Markdown table in `index.md` and the archive, every row has the same number of `|`-delimited cells. If a row has different cell count → format corruption, FAIL. (This catches the kind of manual-edit corruption where two table rows get concatenated into one — empirically observed in earlier index revisions.)

2. **Active ↔ archive symmetry.** Every DEC ID in the "Superseded (archived)" pointer table of `index.md` MUST have exactly one matching row (column 1) in `archive/superseded-decisions.archive.md` § "Superseded DEC entries", and vice versa. Dangling pointer (active claims archived but no archive row) = FAIL. Orphan archive row (archive has DEC but active doesn't reference it) = FAIL.

3. **DEC frontmatter source-of-truth.** For every DEC referenced in the archive index, read `decisions/DEC-XX.md` frontmatter and verify :
   - `status: superseded` (not `active`, not `candidate`, not `draft`)
   - `superseded_by:` is set (DEC-X or [DEC-X, ...] — non-empty, non-null)
   - `archived_to: archive/superseded-decisions.archive.md`
   - `archived_at:` is a date string

4. **Path stability.** Every DEC referenced in active index OR archive index has its file at `decisions/DEC-XX.md` on disk. Exception: a DEC ID may be reserved-no-file (declared in the index as such — e.g. a contingency pivot reservation that intentionally holds a slot without a body file).

5. **Supersedeur backlink (V2 — soft check V1).** For every supersession edge `DEC-X → DEC-Y`, the supersedeur DEC-Y's frontmatter should declare `supersedes: [DEC-X, ...]`. Missing or asymmetric backlink = WARN (not FAIL in V1 ; promotes to FAIL in V2).

#### Affordance signal check (soft)

6. **"How agents read" section present.** If `index.md` references "Superseded" or has a "Superseded (archived)" section, it MUST contain an affordance block telling agents :
   - Files are still readable at original path
   - Read both endpoints for "why" questions
   - Follow chains end-to-end
   - Use the archive skill to archive new supersedeses

   Missing this block = soft warning (non-blocking) in V1. Promotes to hard fail post full-migration.

#### Reporting

After running all checks, produce an inline report :

```
# Memory Index Lint — {date}

## Hard violations
- [<category>] <description> ... (or "none")

## Soft warnings
- [<category>] <description> ... (or "none")

## Result: CLEAN | VIOLATIONS_FOUND | SOFT_ONLY
```

If hard violations found, the operation that triggered the lint should be reverted or escalated. Soft warnings are informational and do not block.

---

## Worktree + parallel safety

- Linter is **stateless** — reads filesystem snapshot at invocation time, produces report, exits
- **Idempotent** — running twice in succession gives identical result (no side effects)
- **Safe in parallel** — multiple worktrees can run the linter concurrently ; each sees its own working tree state
- **Cross-worktree backstop** — pre-commit catches per-worktree commits ; CI catches merged-state anomalies (when WT-A and WT-B independently commit valid changes that produce invalid merge)

---

## Quality Checks

- Linter is read-only — never modifies any file
- Zero external dependencies (Python stdlib only — no PyYAML, no markdown parser)
- Fast — full validation completes in <2s on a corpus of ~100 DECs
- Returns structured exit codes for hook integration (0 = clean, 1 = violations, 2 = usage error)
- Both modes (`--strict` and default) coexist — pre-commit uses default tolerant mode during in-flight migration ; post-migration switch to `--strict` for hard enforcement of affordance signals

---

## Non-Goals

This skill must NOT :
- Modify any file
- Auto-fix violations (would mask integrity issues)
- Validate semantic correctness of decisions or rationales
- Replace `memory-index-sync` (which heals drift) or `memory-archive-superseded` (which migrates rows)
- Run on `decisions/DEC-XX.md` content beyond frontmatter
- Validate `_log.md` or other auxiliary files

**memory-index-lint validates structural invariants. It does not enforce policy.**

---

## Related skills

- `memory-archive-superseded` — invokes lint as pre + post condition
- `memory-index-sync` — heals drift between disk and registry ; runs lint as final step
- `memory-compact` — compaction operations should run lint before commit
