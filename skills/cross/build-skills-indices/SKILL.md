---
type: skill
id: build-skills-indices
name: build-skills-indices
description: Scan SKILL.md files in .gaai/core/skills/ and .gaai/project/skills/, extract YAML frontmatter, and regenerate a single unified skills index for fast discovery across all skill repositories.
layer: cross
category: governance
created_at: 2026-03-02
updated_at: 2026-03-02
---

# Skill: Build Skills Index (Core + Project Unified)

## Purpose

Scan SKILL.md files in **both** `.gaai/core/skills/` and `.gaai/project/skills/`, extract YAML frontmatter, and regenerate a **single unified index** containing all skills. No separate indices — one source for fast discovery across all skill repositories.

> **Usage context:** After creating, modifying, or removing any skill (core or project). Maintains a single merged index at `.gaai/core/skills/skills-index.yaml`.

---

## Input

No parameters required. This skill scans the local filesystem.

## Output

Returns summary of unified index regeneration:

```json
{
  "path": ".gaai/core/skills/skills-index.yaml",
  "status": "regenerated",
  "total_skills": 52,
  "core_skills": 44,
  "project_skills": 8,
  "generated_at": "2026-03-02T14:30:00Z",
  "errors": 0,
  "warnings": []
}
```

---

## Process

### Phase 1 — Scan Both Directories

Scan `.gaai/core/skills/` and `.gaai/project/skills/` recursively.
Collect every file named `SKILL.md`.
Ignore non-SKILL.md files, `README.*`, and `skills-index.yaml`.

For each `SKILL.md` found:
- Read YAML frontmatter block (between `---` delimiters)
- Extract: `id`, `name` (from directory path), `description`, `category`, `track`, `tags`, `updated_at`
- If required field missing, log warning but include entry for visibility
- Track which repository (core vs project) each skill came from
- Log any duplicate `id` values globally

### Phase 2 — Organize and Write Unified Index

Group all entries (core + project) by category and track:
- **By track:** `discovery`, `delivery`, `cross`
- **Within each track:** Sort by category, then alphabetically by name

Write **single unified index** to `.gaai/core/skills/skills-index.yaml`:

```yaml
# GAAI Skills Index (Unified)
# Source of truth: .gaai/core/skills/*/SKILL.md and .gaai/project/skills/*/SKILL.md
# Regenerate: invoke build-skills-indices skill
generated_at: YYYY-MM-DD
total: 52
core: 44
project: 8

discovery:
  - id: SKILL-DSC-001
    name: create-prd
    source: core
    description: "..."
    category: discovery
    track: discovery
    tags: []
    updated_at: YYYY-MM-DD
    path: core/skills/discovery/create-prd/SKILL.md

  # ... more discovery skills ...

  - id: SKILL-PROJECT-CONTENT-001
    name: content-plan
    source: project
    description: "..."
    category: content
    track: discovery
    tags: []
    updated_at: YYYY-MM-DD
    path: project/skills/domains/content-production/content-plan/SKILL.md

delivery:
  - id: SKILL-DEL-001
    name: evaluate-story
    source: core
    # ... fields

cross:
  - id: SKILL-CRS-001
    name: memory-ingest
    source: core
    # ... fields

  - id: SKILL-PROJECT-CROSS-001
    name: analytics-query
    source: project
    # ... fields
```

### Phase 3 — Report Results

Return summary:
- Total skills scanned (core + project)
- Breakdown (core count, project count)
- Any missing required fields (names + fields)
- Any duplicate IDs globally
- Confirmation file was written to `.gaai/core/skills/skills-index.yaml`

---

## Acceptance Criteria

- [ ] **AC1:** Scans all SKILL.md files in `.gaai/core/skills/` without skipping
- [ ] **AC2:** Scans all SKILL.md files in `.gaai/project/skills/` without skipping
- [ ] **AC3:** Extracts frontmatter fields (id, name, description, category, track, tags, updated_at)
- [ ] **AC4:** Tags each skill with its source (core or project)
- [ ] **AC5:** Groups all skills (core + project) by track (discovery, delivery, cross)
- [ ] **AC6:** Within each track, sorts by category then alphabetically by name
- [ ] **AC7:** Generates valid YAML for single unified index
- [ ] **AC8:** Writes to `.gaai/core/skills/skills-index.yaml` only
- [ ] **AC9:** Index includes metadata: total, core count, project count, generated_at
- [ ] **AC10:** Reports total skills scanned, warnings (missing fields), and duplicate ID detection
- [ ] **AC11:** Single index is independently regenerable (can delete and re-run)

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
  git add .gaai/*/skills/skills-index.yaml
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
