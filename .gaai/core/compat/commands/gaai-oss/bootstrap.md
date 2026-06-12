---
description: Initialize or refresh project context via the GAAI OSS Bootstrap Agent
---

# /gaai-oss:bootstrap

Activate the GAAI OSS Bootstrap Agent to initialize or refresh project context.

## Instructions for Claude Code

Read `.gaai/core/agents/bootstrap.agent.md` and `.gaai/core/workflows/context-bootstrap.workflow.md`.

Follow the Bootstrap workflow step by step. After each phase, report what was found and what was stored. At the end, provide a clear PASS or FAIL with any remaining gaps identified.

Once bootstrap is complete, tell the user:

> Memory is ready. Run `/gaai-oss:discover` when you're ready to define governed work.

