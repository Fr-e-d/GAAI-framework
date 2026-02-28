# Scripts Reference

Bash utilities for automation, validation, and maintenance.

**Location:** `.gaai/core/scripts/`

All scripts are self-contained. They require bash 3.2+ and no external dependencies (except `backlog-scheduler.sh` which uses Python 3 for YAML parsing).

---

## health-check.sh

**Purpose:** Validate `.gaai/` folder integrity. Use in CI or before any session.

```bash
bash .gaai/core/scripts/health-check.sh
```

**Checks:**
- Required directories exist (agents/, skills/, contexts/, workflows/)
- VERSION file present and valid
- All `SKILL.md` files have `name` and `description` fields
- All required rule files are present
- `active.backlog.yaml` is parseable YAML
- `memory/project/context.md` exists

**Exit codes:**
- `0` — all checks pass
- `1` — one or more checks failed (failures listed in output)

**Use in CI:**
```yaml
- name: Validate GAAI structure
  run: bash .gaai/core/scripts/health-check.sh
```

---

## backlog-scheduler.sh

**Purpose:** Backlog management utility — select next ready Story, list all ready items, visualize dependencies, detect priority conflicts.

```bash
# Select next ready item (default)
bash .gaai/core/scripts/backlog-scheduler.sh .gaai/project/contexts/backlog/active.backlog.yaml

# List all ready items sorted by priority
bash .gaai/core/scripts/backlog-scheduler.sh --list .gaai/project/contexts/backlog/active.backlog.yaml

# Show dependency graph for all active items
bash .gaai/core/scripts/backlog-scheduler.sh --graph .gaai/project/contexts/backlog/active.backlog.yaml

# Detect priority conflicts (high-priority items blocked by low-priority dependencies)
bash .gaai/core/scripts/backlog-scheduler.sh --conflicts .gaai/project/contexts/backlog/active.backlog.yaml
```

**Modes:**

| Flag | Output |
|---|---|
| `--next` (default) | ID of next ready item, or `NO_ITEM_READY` |
| `--list` | All ready items: `[PRIORITY] ID — title (complexity: N)` |
| `--graph` | Dependency tree with status indicators (✅🔄🔒⏳) |
| `--conflicts` | Priority inversions and missing dependency references |

**Logic (--next):**
1. Parse `active.backlog.yaml`
2. Filter for `status: refined`
3. Skip items with unresolved `depends_on`
4. Sort by priority (high → medium → low), then complexity (ascending)
5. Output first item id, or `NO_ITEM_READY`

**Requires:** Python 3 (for YAML parsing)

---

## context-bootstrap.sh

**Purpose:** Print a formatted context summary at session start.

```bash
bash .gaai/core/scripts/context-bootstrap.sh
```

**Output:**
- Project name and description (from `memory/project/context.md`)
- Active backlog: total items, ready count, in-progress count
- Memory index: files present and last updated
- Skill count

Used by `/gaai-status` to generate the status report.

---

## artefact-sync.sh

**Purpose:** Validate that all backlog artefact references point to real files.

```bash
bash .gaai/core/scripts/artefact-sync.sh
```

**Checks:**
- Every backlog item with an `artefact` field references an existing file
- Artefact frontmatter has required fields (`type`, `id`)
- Story artefacts have non-empty acceptance criteria

**Exit codes:**
- `0` — all references valid
- `1` — broken references listed

**Use in CI for traceability:**
```yaml
- name: Validate artefact references
  run: bash .gaai/core/scripts/artefact-sync.sh
```

---

## memory-snapshot.sh

**Purpose:** Export current memory state to a timestamped archive.

```bash
bash .gaai/core/scripts/memory-snapshot.sh
```

**Output:** Creates `.gaai/project/contexts/memory/snapshots/YYYY-MM-DD_{timestamp}/` with copies of all memory files.

**When to use:**
- Before risky architectural work
- Before running `memory-compact`
- Before onboarding a new team member (snapshot = documented baseline)

Snapshots are not committed to git by default (add `snapshots/` to `.gitignore`).

---

→ [Workflows Reference](workflows.md)
→ [Senior Engineer Guide](../guides/senior-engineer-guide.md#ci-integration)
