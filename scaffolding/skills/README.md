# Project Skills

Custom skill definitions specific to this project.

Framework skills live in `.gaai/core/skills/`. This directory extends them with project-specific skills organized by category.

## Directory Structure

```
skills/
├── cross/              ← cross-cutting project skills
│   ├── analytics-query/
│   ├── cost-analysis/
│   └── domain-knowledge-research/
└── domains/            ← domain-specific skill packs
    └── content-production/
```

## When to Add a Custom Skill

- When the project needs a capability not provided by the framework
- When a domain (e.g., content, analytics) has enough complexity to warrant its own skill pack
- When a reusable pattern emerges across multiple stories

## Naming Convention

Each skill lives in its own directory with a `SKILL.md` file:

```
skills/{category}/{skill-name}/SKILL.md
```

## Resolution Order

`build-skills-index` scans `core/skills/` first, then `project/skills/`. The generated index marks each skill with `source: core` or `source: project`.

## Template

See `.gaai/core/skills/cross/create-skill/SKILL.md` for the meta-skill that creates new skills.
