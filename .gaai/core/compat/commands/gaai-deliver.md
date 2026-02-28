# /gaai-deliver

Activate the Delivery Agent to implement the next ready backlog item.

## What This Does

Runs the Delivery Loop:
1. Reads `.gaai/project/contexts/backlog/active.backlog.yaml`
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

Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`.

Check `.gaai/project/contexts/backlog/active.backlog.yaml` for the next Story with status `refined`.

Follow the delivery loop exactly. Do not skip QA. If QA fails, invoke `remediate-failures`. If a fix requires changing product scope, STOP and escalate to the human.

Report PASS or FAIL at completion.
