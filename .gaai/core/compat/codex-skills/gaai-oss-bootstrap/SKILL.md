---
name: gaai-oss:bootstrap
description: Initialize or refresh a project's GAAI OSS memory by activating the Bootstrap Agent and context-bootstrap workflow.
---

# GAAI OSS Bootstrap

Use this skill when the user wants to initialize GAAI on a codebase, refresh stale memory, rebuild project context, or verify that `.gaai/project/contexts/memory/` reflects the current repository.

## Procedure

1. Read `.gaai/core/GAAI.md`.
2. Read `.gaai/core/contexts/rules/base.rules.md`.
3. Read `.gaai/core/agents/bootstrap.agent.md`.
4. Read `.gaai/core/workflows/context-bootstrap.workflow.md`.
5. Follow the workflow step by step.
6. Use the internal GAAI skills referenced by the Bootstrap Agent from `.gaai/core/skills/`; do not treat this Codex skill as a replacement for them.
7. Report a clear PASS or FAIL and list remaining gaps.

When bootstrap is complete, tell the user that memory is ready and that `$gaai-oss:discover` can be used to define governed work.
