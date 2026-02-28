# Agent-Skills Spec

How GAAI implements the agentskills.io specification.

---

## What Is agentskills.io?

agentskills.io is a community specification for describing AI agent skills in a tool-agnostic, filesystem-based way.

The spec defines:
- A standard directory structure: `{skill-name}/SKILL.md`
- Required frontmatter fields: `name`, `description`
- Optional fields: `license`, `compatibility`, `metadata`, `inputs`, `outputs`, `allowed-tools`

GAAI uses this spec for all its skills. The result: any tool that supports agentskills.io auto-discovers GAAI skills.

---

## GAAI's Implementation

### Directory structure

```
.gaai/core/skills/
├── discovery/
│   ├── discovery-high-level-plan/
│   │   └── SKILL.md
│   └── ...
├── delivery/
│   ├── implement/
│   │   └── SKILL.md
│   └── ...
└── cross/
    ├── memory-retrieve/
    │   └── SKILL.md
    └── ...
```

Each skill lives in a named directory. The directory name matches the `name` field in the frontmatter. `SKILL.md` is always uppercase and exact — this is a spec requirement.

### SKILL.md format

```yaml
---
name: skill-name
description: One sentence: WHAT it does and WHEN to activate it.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery|delivery|cross
  track: discovery|delivery|cross-cutting
  id: SKILL-{CAT}-{NNN}
  updated_at: YYYY-MM-DD
inputs:
  - description of input 1
  - description of input 2
outputs:
  - description of output 1
  - description of output 2
---

# Skill Title

## Purpose
## When to Activate
## Process
## Quality Checks
## Outputs
```

### Key requirements

1. **`name` must match the directory name exactly.** Tool auto-discovery works by matching directory names to `name` fields.

2. **`description` must be one sentence.** It's what agents (and tools) see when scanning available skills. The format: "WHAT it does and WHEN to activate it."

3. **`SKILL.md` is uppercase.** The spec requires it. Lowercase `skill.md` will not be discovered by compliant tools.

4. **One skill per directory.** A directory may have optional `references/` and `assets/` subdirectories, but only one `SKILL.md`.

---

## Why This Matters

### Tool auto-discovery

Claude Code, Cursor, and other tools scan for `SKILL.md` files and surface them as available skills. GAAI's skills appear automatically in supported tools without manual configuration.

### Tool-agnostic skills

A skill written for GAAI works with any tool that supports the spec. If a better AI tool emerges tomorrow, the skills require no changes.

### Human readability

The spec prioritizes plain text. `SKILL.md` is readable by anyone — no code to parse, no format to learn.

---

## GAAI Extensions to the Spec

GAAI adds metadata fields beyond the base spec:

```yaml
metadata:
  category: discovery|delivery|cross    # GAAI-specific categorization
  track: discovery|delivery|cross-cutting
  id: SKILL-CRS-001                     # Stable identifier for cross-referencing
  updated_at: YYYY-MM-DD
```

These fields are GAAI-specific. The base spec only requires `name` and `description`. Compliant tools will ignore unknown fields.

---

## Adding a Skill

To add a skill to GAAI:

1. Create a directory: `.gaai/core/skills/{category}/{skill-name}/`
2. Create `SKILL.md` with required frontmatter
3. Add the skill to `README.skills.md` (the master index)
4. Reference the skill in the appropriate agent file (`agents/{agent}.agent.md`)

See the `create-skill` skill for a guided workflow (when available — see roadmap).

---

→ [Skills Index](../../.gaai/core/skills/README.skills.md)
→ [Design Decisions](design-decisions.md)
