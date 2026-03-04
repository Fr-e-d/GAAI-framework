---
type: skill
id: build-skills-indices
name: build-skills-indices
description: Scan SKILL.md files in .gaai/core/skills/ and .gaai/project/skills/ separately, extract YAML frontmatter, and regenerate two independent indexes — one per scope. Core index stays clean for OSS sync.
layer: cross
category: governance
created_at: 2026-03-02
updated_at: 2026-03-03
---

# Skill: Build Skills Indices (Core + Project — Separate)

## Purpose

Scan SKILL.md files in `.gaai/core/skills/` and `.gaai/project/skills/` **separately**, extract YAML frontmatter, and regenerate **two independent indexes** — one per scope. This separation is critical: `.gaai/core/` is synced to the GAAI OSS repo via subtree, so project-specific skills must never appear in the core index.

> **Usage context:** After creating, modifying, or removing any skill (core or project). Maintains two indexes:
> - `.gaai/core/skills/skills-index.yaml` — core skills only (synced to OSS)
> - `.gaai/project/skills/skills-index.yaml` — project skills only (never synced)

---

## Input

No parameters required. This skill scans the local filesystem.

## Output

Returns summary of both index regenerations:

```json
{
  "core_index": {
    "path": ".gaai/core/skills/skills-index.yaml",
    "status": "regenerated",
    "total_skills": 47
  },
  "project_index": {
    "path": ".gaai/project/skills/skills-index.yaml",
    "status": "regenerated",
    "total_skills": 9
  },
  "generated_at": "2026-03-03T14:30:00Z",
  "errors": 0,
  "warnings": []
}
```

---

## Process

### Phase 1 — Scan Core Directory

Scan `.gaai/core/skills/` recursively. Collect every file named `SKILL.md`.
Ignore non-SKILL.md files, `README.*`, and `skills-index.yaml`.

For each `SKILL.md` found:
- Read YAML frontmatter block (between `---` delimiters)
- Extract: `id`, `name` (from directory path), `description`, `category`, `track`, `tags`, `updated_at`
- If required field missing, log warning but include entry for visibility
- Log any duplicate `id` values

### Phase 2 — Scan Project Directory

Scan `.gaai/project/skills/` recursively using the same logic as Phase 1.

### Phase 3 — Write Two Separate Indexes

**Core index** → `.gaai/core/skills/skills-index.yaml` (core skills ONLY):

```yaml
# GAAI Core Skills Index
# Source of truth: .gaai/core/skills/*/SKILL.md ONLY
# Does NOT include project skills — see .gaai/project/skills/skills-index.yaml
# Regenerate: invoke build-skills-indices skill
generated_at: YYYY-MM-DD
total: 47

discovery:
  - id: SKILL-DSC-001
    name: create-prd
    description: "..."
    # ... fields
```

**Project index** → `.gaai/project/skills/skills-index.yaml` (project skills ONLY):

```yaml
# GAAI Project Skills Index
# Source of truth: .gaai/project/skills/*/SKILL.md ONLY
# Does NOT include core skills — see .gaai/core/skills/skills-index.yaml
# Regenerate: invoke build-skills-indices skill
generated_at: YYYY-MM-DD
total: 9

discovery:
  - id: SKILL-CNT-011
    name: content-plan
    description: "..."
    # ... fields
```

> **CRITICAL:** No `source:` field needed — each index is scoped to its own directory. Project skills must NEVER appear in the core index (it is synced to the OSS repo).

### Phase 4 — Report Results

Return summary:
- Core skills scanned and written
- Project skills scanned and written
- Any missing required fields (names + fields)
- Any duplicate IDs across both indexes (cross-index collision warning)
- Confirmation both files were written

---

## Acceptance Criteria

- [ ] **AC1:** Scans all SKILL.md files in `.gaai/core/skills/` without skipping
- [ ] **AC2:** Scans all SKILL.md files in `.gaai/project/skills/` without skipping
- [ ] **AC3:** Extracts frontmatter fields (id, name, description, category, track, tags, updated_at)
- [ ] **AC4:** Core index contains ONLY core skills — zero project skills
- [ ] **AC5:** Project index contains ONLY project skills — zero core skills
- [ ] **AC6:** Groups skills by track (discovery, delivery, cross), sorts by category then name
- [ ] **AC7:** Generates valid YAML for both indexes
- [ ] **AC8:** Writes core index to `.gaai/core/skills/skills-index.yaml`
- [ ] **AC9:** Writes project index to `.gaai/project/skills/skills-index.yaml`
- [ ] **AC10:** Each index includes metadata: total, generated_at
- [ ] **AC11:** Reports warnings (missing fields) and cross-index duplicate ID detection
- [ ] **AC12:** Each index is independently regenerable (can delete and re-run)

---

## Usage Examples

**After creating or modifying any skill:**
```
Invoke: build-skills-indices
Result: Unified index regenerated in single operation
```

**To verify index freshness:**
```
Check: .gaai/core/skills/skills-index.yaml generated_at field
If stale, invoke build-skills-indices to refresh
```

---

## Non-Goals

This skill must NOT:
- Edit any SKILL.md file
- Make decisions about which skills are valid
- Merge duplicate skills or resolve conflicts (only report them)
- Be invoked as a dependency of other skills (only agents call this)

**This skill reads and aggregates — it does not evaluate or decide.**

---

## Integration with Skill Lifecycle

Activate `build-skills-indices` when:
1. A new skill is created (core or project)
2. A skill's frontmatter is modified
3. A skill is removed or deprecated
4. Either index file is absent or suspected stale

Recommendation: Add to pre-commit hook to ensure indices stay in sync:

```bash
# .git/hooks/pre-commit
if git diff --cached --name-only | grep -q '.gaai/.*/skills/.*SKILL.md'; then
  invoke build-skills-indices
  git add .gaai/core/skills/skills-index.yaml .gaai/project/skills/skills-index.yaml
fi
```

---

## Known Constraints

- **Frontmatter parsing:** Only YAML frontmatter blocks are processed (between `---`)
- **Description extraction:** Attempts to extract from frontmatter; falls back to first line of SKILL.md if unavailable
- **Category flexibility:** Project skills may have domain-specific categories (not limited to core's discovery/delivery/cross)
- **Duplicate detection:** Reports duplicate IDs but does not auto-resolve (manual review required)

---

## Notes for Agents

- **Discovery Agent:** No typical usage (indices are read-only for discovery)
- **Delivery Agent:** No typical usage (indices are read-only for delivery)
- **Bootstrap Agent:** Run this skill during project initialization to seed both skill catalogues

This unified approach prevents duplication while maintaining independent indices for fast lookups.
