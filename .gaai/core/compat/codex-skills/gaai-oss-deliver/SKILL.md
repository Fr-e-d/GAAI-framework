---
name: gaai-oss:deliver
description: Implement validated GAAI OSS backlog Stories by activating the Delivery Agent and applying backlog-first delivery rules.
---

# GAAI OSS Delivery

Use this skill when the user asks Codex to implement governed work from `.gaai/project/contexts/backlog/active.backlog.yaml`.

## Procedure

1. Read `.gaai/core/GAAI.md`.
2. Read `.gaai/core/contexts/rules/base.rules.md`.
3. Read `.gaai/core/contexts/rules/orchestration.rules.md`.
4. Read `.gaai/core/agents/delivery.agent.md`.
5. Read `.gaai/project/contexts/backlog/active.backlog.yaml`.
6. Select only validated, ready backlog work unless the user explicitly names a Story or authorizes a narrow direct change.
7. Load story-specific artefacts and relevant memory before editing.
8. Implement, verify, and report the exact validation performed.

For autonomous daemon execution, use `$gaai-oss:daemon`. This skill is for interactive Codex delivery.
