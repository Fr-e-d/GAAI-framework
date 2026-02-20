# /gaai-deliver

Activate the Delivery Agent to implement the next ready backlog item.

## What This Does

Runs the Delivery Loop:
1. Reads `.gaai/contexts/backlog/active.backlog.yaml`
2. Selects the next ready Story (status: refined)
3. Builds execution context
4. Creates an execution plan
5. Implements the Story
6. Runs QA gate
7. Remediates failures if needed
8. Marks done when PASS

## When to Use

- When backlog has refined Stories ready to implement
- To run the full governed delivery cycle
- After Discovery has validated artefacts

## Instructions for Claude Code

Read `.gaai/agents/delivery.agent.md` and `.gaai/workflows/delivery-loop.workflow.md`.

### Story Selection — Non-Negotiable

**The backlog is the ONLY source of truth for story selection.**

1. Open `.gaai/contexts/backlog/active.backlog.yaml`
2. If an argument was passed (e.g. `/gaai-deliver E06S07`), select that story — verify its status is `refined` before proceeding.
3. If no argument: select the **first** story in the backlog with `status: refined` (top-to-bottom order).
4. **Ignore completely:** git branch name, git worktree state, artefact existence, impl-report or qa-report files. A story with `status: done` in the backlog is done — regardless of what branch or files exist.

### Parallel Execution

Multiple `/gaai-deliver` sessions may run simultaneously **if and only if**:
- Each session targets a **different** story (use explicit story ID argument)
- The two stories have **no shared dependencies** (both already `done`) per the backlog
- The user explicitly launches each session

When in doubt: pass the story ID as argument to avoid ambiguity.

### Delivery Loop

Follow the delivery loop exactly. Do not skip QA. If QA fails, invoke `remediate-failures`. If a fix requires changing product scope, STOP and escalate to the human.

Report PASS or FAIL at completion.
