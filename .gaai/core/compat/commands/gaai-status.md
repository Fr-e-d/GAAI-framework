# /gaai-status

Show current GAAI project state: backlog, memory, and health.

## What This Does

Runs a quick status report:
1. Active backlog summary (total items, ready count, in-progress)
2. Memory state (files present, last updated)
3. Recent decisions
4. Health check summary

## When to Use

- At the start of a session to orient yourself
- To check what's ready to deliver
- To verify the framework is correctly set up

## Instructions for Claude Code

Run `.gaai/core/scripts/context-bootstrap.sh` if available, then:

1. Read `.gaai/project/contexts/backlog/active.backlog.yaml` — summarize items by status
2. Read `.gaai/project/contexts/memory/memory/project/context.md` — show project context summary
3. List any blocked items from `.gaai/project/contexts/backlog/blocked.backlog.yaml`
4. Note the count of active skills and rule files

Present a concise, human-readable summary. Flag anything that looks incomplete or missing.
