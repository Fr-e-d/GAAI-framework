# /gaai-deliver

Activate the Delivery Agent to implement the next ready backlog item.

## What This Does

Runs the Delivery Loop:
1. Reads `.gaai/contexts/backlog/active.backlog.yaml`
2. Selects the next ready Story (status: refined)
3. Builds execution context
4. Creates an execution plan
5. Implements the Story in a git worktree
6. Runs QA gate
7. Remediates failures if needed
8. Creates a **PR to staging** via `gh pr create` (human reviews + merges)
9. Marks done in backlog

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

### PR-Based Delivery with Immediate Merge (Non-Negotiable — DEC-71)

After QA PASS, the delivery agent:
1. Creates a PR to staging via `gh pr create --base staging --head story/{id}`
2. **Immediately merges** the PR via `gh pr merge --squash`
3. If merge fails due to conflicts: merges staging into the story branch, resolves conflicts, pushes, and retries the merge
4. Cleans up: removes worktree + deletes remote branch

**PRs must NEVER be left open.** Accumulated unmerged PRs cause cascading merge conflicts across all pending branches (19-PR incident, 2026-02-24). The QA gate is the quality safeguard — once QA passes, merge is immediate.

Promotion staging → production remains a human action via GitHub PR.

Report PASS or FAIL at completion. Include the merged PR URL in the STOP report.
