---
name: gaai-oss:status
description: Summarize current GAAI OSS project state, including backlog, memory, rules, skills, and framework health.
---

# GAAI OSS Status

Use this skill at the start of a session or before delivery to orient Codex in the governed project state.

## Procedure

1. Read `.gaai/core/GAAI.md`.
2. Read `.gaai/core/contexts/rules/base.rules.md`.
3. Inspect `.gaai/project/contexts/backlog/active.backlog.yaml`.
4. Inspect `.gaai/project/contexts/backlog/blocked.backlog.yaml` if present.
5. Inspect `.gaai/project/contexts/backlog/done/` if present.
6. Inspect `.gaai/project/contexts/memory/index.md` and `.gaai/project/contexts/memory/project/context.md` if present.
7. Count available internal GAAI skills under `.gaai/core/skills/`.
8. Count native Codex wrappers under `.agents/skills/gaai-oss-*` when present.
9. Run `.gaai/core/scripts/health-check.sh` when available and practical.

Present a concise status with ready work, blocked work, memory health, framework health, and any missing setup.
