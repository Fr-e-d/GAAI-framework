---
name: build-skills-index
description: Scan SKILL.md files in .gaai/core/skills/ and .gaai/project/skills/, extract YAML frontmatter, and regenerate separate skills indices for each layer. Core index ships with the OSS framework; project index is project-specific.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "2.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-017
  tags:
    - governance
    - index
    - discoverability
  updated_at: 2026-03-17
  status: stable
inputs:
  - .gaai/core/skills/**/SKILL.md       (core framework skills)
  - .gaai/project/skills/**/SKILL.md    (project-specific skills, if present)
outputs:
  - .gaai/core/skills/skills-index.yaml     (core skills only — ships with OSS)
  - .gaai/project/skills/skills-index.yaml  (project skills only — if project dir exists)
---

# Build Skills Index

## Purpose / When to Activate

Activate when:
- A new skill is created (invoked automatically by `create-skill` Step 6)
- A skill's frontmatter is modified (description, tags, category, id)
- A skill is removed or deprecated
- Either `skills-index.yaml` is absent or suspected stale (e.g. after a git pull or framework update)

This skill generates the derived catalogs used by agents for fast skill discovery.
It does not replace frontmatter — it aggregates it.

**`skills-index.yaml` files are caches. Frontmatter is the source of truth.**

---

## Process

### Step 1 — Scan both skill directories

Scan `.gaai/core/skills/` recursively. Collect every file named `SKILL.md`.
If `.gaai/project/skills/` exists, scan it too.
Ignore non-SKILL.md files. Ignore `README.*`, `skills-index.yaml`.

### Step 2 — Extract frontmatter from each SKILL.md

For each `SKILL.md` found, read the YAML frontmatter block (between `---` delimiters).
Extract the following fields:

| Field | Source | Notes |
|---|---|---|
| `name` | frontmatter `name` | Required |
| `description` | frontmatter `description` | Required |
| `id` | frontmatter `id` or `metadata.id` | Required |
| `category` | frontmatter `category` or `metadata.category` | Required |
| `track` | frontmatter `track` or `metadata.track` | Required |
| `tags` | frontmatter `tags` or `metadata.tags` | May be absent — default to `[]` |
| `updated_at` | frontmatter `updated_at` or `metadata.updated_at` | May be absent |
| `path` | derived — relative path from `.gaai/` to SKILL.md | e.g. `core/skills/cross/memory-ingest/SKILL.md` |

If a required field is missing, log a warning inline in the entry but do not skip — include for visibility.
Log any duplicate `id` values across both layers.

### Step 3 — Group entries by track

Organize entries into three groups: `discovery`, `delivery`, `cross`.
Within each group, sort alphabetically by `name`.

### Step 4 — Write separate index files

**Core index** → `.gaai/core/skills/skills-index.yaml` (core skills only):
```yaml
# GAAI Core Skills Index
# Source of truth: .gaai/core/skills/*/SKILL.md — core framework skills only
# Regenerate: invoke build-skills-index skill
generated_at: YYYY-MM-DD
total: N

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
```

**Project index** → `.gaai/project/skills/skills-index.yaml` (project skills only, if project dir exists):
```yaml
# GAAI Project Skills Index
# Source of truth: .gaai/project/skills/*/SKILL.md — project-specific skills only
# Regenerate: invoke build-skills-index skill
generated_at: YYYY-MM-DD
total: N

discovery:
  - id: SKILL-CNT-011
    name: content-plan
    source: project
    description: "..."
    # ... fields
```

Agents read **both** indices to get the full skill catalogue.

### Step 5 — Report

Return to the invoking agent:
- Core skills count + project skills count
- Any entries with missing required fields (names + fields)
- Any duplicate IDs across both layers
- Confirmation both files were written

---

## Automation

The `check-and-update-skills-index.cjs` script performs the same work automatically via the post-commit Git hook. This skill exists for manual invocation when the hook doesn't trigger (fresh clone, worktree, CI).

---

## Quality Checks

- Every SKILL.md in both directories is represented in the correct index (no silently skipped files)
- No manually written entries — all entries derived from frontmatter
- Duplicate `id` values flagged across both layers (do not silently deduplicate)
- `generated_at` reflects the date of this run
- Core index contains zero `source: project` entries
- Project index contains zero `source: core` entries

---

## Non-Goals

This skill must NOT:
- Edit any SKILL.md file
- Make decisions about which skills are valid or relevant
- Merge duplicate skills or resolve conflicts — only report them
- Be invoked as a dependency of other skills (only agents call this)

**This skill reads and aggregates — it does not evaluate or decide.**
