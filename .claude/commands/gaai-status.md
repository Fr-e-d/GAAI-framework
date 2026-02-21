# /gaai-status

Show current GAAI project state: backlog, memory, and health.

## What This Does

Runs a complete status report:
1. Active backlog summary (total items by status, next ready items)
2. Memory evaluation (structure discovery, staleness, accuracy, optimization)
3. Recent decisions
4. Framework health check

## When to Use

- At the start of a session to orient yourself
- To check what's ready to deliver
- To verify the framework is correctly set up

## Instructions for Claude Code

### Step 0 — Discover memory structure first

Read `.gaai/contexts/memory/index.md`. This is the authoritative registry of all active memory files. Do not assume any specific files or categories exist — derive everything from what the index declares.

From the index, extract:
- The list of active memory files (path, category, id, last updated)
- The list of declared-but-empty categories (summaries/, sessions/, archive/ if noted)

Then read `.gaai/contexts/backlog/active.backlog.yaml` and the discovered memory files **in parallel**.

---

### Section 1 — Backlog

Summarize `active.backlog.yaml`:
- Count items by status: `done`, `in_progress`, `refined`, `deferred`, `superseded`
- List all items with status `refined` and no unresolved dependencies → **ready to deliver**, ordered by priority
- Flag any item marked `in_progress` (should normally be empty between sessions)

---

### Section 2 — Memory Evaluation

This section must be thorough. Work entirely from what `index.md` declares — never assume a file exists unless the index lists it.

**2a. Structure inventory**

From `index.md`, produce a table of all registered memory files:
- Path, category, last `updated_at` per frontmatter, approximate line count
- Flag any category declared in the index but whose file does not exist on disk
- Flag any directory visible under `contexts/memory/` that is NOT registered in the index (invisible to all memory skills — this is a critical gap)

**2b. Staleness check — for each registered file**

For each file listed in the index:
- Read its frontmatter `updated_at`
- Read its content and identify the most recent decision or event it references
- If the most recent referenced decision is more recent than `updated_at`, flag as stale
- If any field describes a tool, provider, or architecture that a more recent decision (from the decisions log) has superseded, name it explicitly and state the correct current value

**2c. Accuracy check — decisions log cross-reference**

Read the decisions log (whichever file the index registers as the decisions category):
- Identify any decision marked `⚠️ SUPERSEDED` — confirm the original decision entry carries that marker
- Identify the last 5 decisions — check if the most recent architectural changes are reflected in other memory files (especially the project context file)

**2d. Completeness check**

- Are all active memory categories populated (non-empty)?
- Are declared-but-empty categories (summaries, sessions, archive) expected to be empty at this stage, or overdue?
- Is the index itself up to date with what's on disk?

**2e. Compaction assessment**

For each registered file, report line count:
- Files > 400 lines → flag as `COMPACT_CANDIDATE`
- Decisions log > 500 lines with clusters of superseded entries → flag as `ARCHIVE_CANDIDATE`
- Overall memory is manageable if total active lines < 2000

**2f. Optimization verdict**

Score each file on: Staleness / Accuracy / Size. Give an overall memory verdict:
- `HEALTHY` — all files accurate, updated, well-sized
- `NEEDS_UPDATE` — one or more stale or inaccurate fields identified
- `NEEDS_COMPACTION` — one or more files exceeding size thresholds
- `CRITICAL` — stale fields in files loaded every session (project context) OR unregistered categories on disk

---

### Section 3 — Recent Decisions

From the decisions log file discovered via `index.md`, list the 5 most recent entries: ID, one-line summary, date. Flag any that carry a `⚠️ SUPERSEDED` marker.

---

### Section 4 — Framework Health

- Count of active skills (glob `.gaai/skills/**/*.md`)
- Confirm `index.md` was updated recently (within the last active session)
- Note any open pre-go-live blockers visible in backlog notes
- Flag any `in_progress` backlog item that may represent a stale lock

---

Present as a concise, human-readable report. Use tables where helpful. Flag issues with ⚠️ or ❌. Do not pad — if everything is healthy, say so briefly.
