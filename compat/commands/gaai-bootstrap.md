# /gaai-bootstrap

Activate the Bootstrap Agent to initialize or refresh project context.

## What This Does

Runs the Bootstrap Agent workflow to:
1. Scan the codebase structure (`codebase-scan`)
2. Extract architecture understanding (`architecture-extract`)
3. Extract durable decisions (`decision-extraction`)
4. Build structured project memory (`memory-ingest`)
5. Normalize governance rules (`rules-normalize`)
6. Clean up memory (`memory-refresh`)
7. Validate: are there still gaps? If yes, iterate.

## When to Use

- First time adding GAAI to an existing project
- After major architectural changes
- When memory feels stale or incomplete

## Instructions for Claude Code

Read `.gaai/core/agents/bootstrap.agent.md` and `.gaai/core/workflows/context-bootstrap.workflow.md`.

Follow the Bootstrap workflow step by step. After each phase, report what was found and what was stored. At the end, provide a clear PASS or FAIL with any remaining gaps identified.

Once bootstrap is complete, tell the user:

> Memory is ready. Run `/gaai-discover` when you're ready to define what to build.
