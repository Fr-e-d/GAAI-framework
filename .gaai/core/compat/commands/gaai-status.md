---
description: Show backlog, memory state & delivery readiness
---

# /gaai-status

Show current GAAI project state: backlog, memory, and health.

## What This Does

Runs a quick status report:
1. Active backlog summary (total items, ready count, in-progress)
2. Archived/done summary (total completed items, archive files)
3. Memory state (files present, last updated)
4. Recent decisions
5. Health check summary

## When to Use

- At the start of a session to orient yourself
- To check what's ready to deliver
- To verify the framework is correctly set up

## Instructions for Claude Code

Run `.gaai/core/scripts/context-bootstrap.sh` if available, then:

1. Read `.gaai/project/contexts/backlog/active.backlog.yaml` — summarize items by status
2. Read `.gaai/project/contexts/backlog/done/` — list archive files, count total done items, show most recent completions
3. Read `.gaai/project/contexts/memory/project/context.md` — show project context summary
4. List any blocked items from `.gaai/project/contexts/backlog/blocked.backlog.yaml`
5. Note the count of active skills and rule files

Present a concise, human-readable summary. Flag anything that looks incomplete or missing.

6. **GAAI Cloud subscription state (E114S01 AC2):**
   - Run `cat .gaai/local/cloud-state.json 2>/dev/null` to read the cached subscription state.
   - If the file exists and is valid JSON with `tier` and `status` fields, display them as:
     ```
     GAAI Cloud: <tier> plan — <status>
     ```
     Where tier is one of: Free / Personal / Pro
     And status is one of: Active / Past due / Cancelled
   - If `cached_at` is present and older than 300 seconds (i.e. `Date.now()/1000 - cached_at > 300`), append `(stale — open dashboard to refresh)`
   - If the file does not exist or is not readable: display `GAAI Cloud: not connected`
   - Include this as a "GAAI Cloud" row in the summary output.
