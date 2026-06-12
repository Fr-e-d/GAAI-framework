---
description: Show local GAAI OSS backlog, memory state, and delivery readiness
---

# /gaai-oss:status

Show current local GAAI OSS project state: backlog, memory, and health.

## Instructions for Claude Code

1. Read `.gaai/project/contexts/backlog/active.backlog.yaml` and summarize items by status.
2. Read `.gaai/project/contexts/backlog/blocked.backlog.yaml` if present.
3. Read `.gaai/project/contexts/backlog/done/` if present.
4. Read `.gaai/project/contexts/memory/index.md` and `.gaai/project/contexts/memory/project/context.md` if present.
5. Count active internal GAAI skills under `.gaai/core/skills/`.
6. Run `.gaai/core/scripts/health-check.sh` when available and practical.

Present a concise local OSS status. Do not report GAAI Cloud subscription state from this OSS command.

