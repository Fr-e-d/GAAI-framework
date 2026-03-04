# CLAUDE.md — Working ON the GAAI Framework Repo

This file is for contributors working **on this repository itself** (fixing bugs, updating docs, improving scripts).

If you are a **user** looking to use GAAI in your project, read `.gaai/GAAI.md` instead — or run `install.sh`.

---

## What This Repo Is

This repo contains:
- `.gaai/` — the GAAI framework (what users copy into their projects)
- `docs/` — full documentation
- `install.sh` / `install-check.sh` — installer scripts
- Standard repo files (README, LICENSE, CHANGELOG, CONTRIBUTING)

---

## Working on This Repo

### Key Constraints

- **Never break `.gaai/` integrity.** The health check script (`scripts/health-check.sh` inside `.gaai/`) must always pass.
- **Never rename skill directories.** Skill directory names are part of the agentskills.io spec and are referenced in agent files.
- **Never rename rule files.** Rule filenames are referenced in agent files and compat adapters.
- **Keep compat adapters thin.** Files in `.gaai/core/compat/` must reference canonical `.gaai/` files — never duplicate content.
- **Preserve naming conventions.** `README.{type}.md`, `{name}.{type}.md`, `{name}.{type}.yaml` — see plan for full convention table.

### File Structure

```
.gaai/
└── core/
    ├── GAAI.md                        ← Master orientation (entry point for users)
    ├── VERSION                        ← Semantic version string (2.0.0)
    ├── agents/
    │   ├── README.agents.md
    │   ├── discovery.agent.md
    │   ├── delivery.agent.md
    │   └── bootstrap.agent.md
    ├── skills/
    │   ├── README.skills.md
    │   ├── discovery/{skill-name}/SKILL.md  (6 skills)
    │   ├── delivery/{skill-name}/SKILL.md   (11 skills)
    │   └── cross/{skill-name}/SKILL.md      (30 skills)
    ├── contexts/
    │   └── rules/         ← 8 framework rule files
    ├── workflows/
    │   ├── README.workflows.md
    │   └── *.workflow.md  (4 workflow files)
    ├── scripts/
    │   ├── README.scripts.md
    │   └── *.sh           (5 bash scripts)
    └── compat/
        ├── COMPAT.md
        ├── claude-code/
        ├── cursor/
        └── windsurf/
```

### Running the Health Check

```bash
bash .gaai/core/scripts/health-check.sh
```

This validates:
- All skill directories contain a `SKILL.md`
- All `SKILL.md` files have valid YAML frontmatter
- `VERSION` file exists and is semver
- All agent files exist
- All rule files exist

### CI

Every PR runs `.github/workflows/validate-structure.yml` which calls `health-check.sh`.

---

## Commit Convention

```
fix: correct broken YAML in _template.story.md
docs: clarify memory ownership model in README.memory.md
scripts: fix exit code in health-check.sh
```

Prefixes: `fix`, `docs`, `scripts`, `compat`, `chore`

---

## What NOT to Do

- Do not add new skills to `.gaai/core/skills/` (this is a "Fork & Own" framework — users add skills in their own fork)
- Do not modify the philosophy or operating rules without a serious reason
- Do not add external dependencies to bash scripts
- Do not break backward compatibility of YAML frontmatter formats
