---
description: Implement the next ready backlog item via Delivery Agent
---

# /gaai-deliver

Implement the next ready backlog item via an **isolated** Delivery Agent.

## Context Isolation — Non-Negotiable

**ALWAYS spawn the Delivery Agent as an isolated sub-agent.**

Discovery and Delivery system prompts must NEVER coexist in the same context window. The current session may contain Discovery context, human conversation, or other work. The Delivery Agent must start with a clean context — only its own agent definition, the workflow, and the story.

## What This Does

Spawns an isolated sub-agent that runs the Delivery Loop:
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

**Do NOT read `delivery.agent.md` in this session. Do NOT execute the delivery loop here.**

Instead, use the **Agent tool** to spawn a sub-agent with this prompt:

```
You are the GAAI Delivery Agent. Read these files FIRST, in order:
1. .gaai/core/agents/delivery.agent.md (your identity and rules)
2. .gaai/core/workflows/delivery-loop.workflow.md (your workflow)
3. .gaai/project/contexts/backlog/active.backlog.yaml (the backlog)

[If story ID provided]: Deliver story {STORY_ID}. Verify status is 'refined' or 'in_progress'.
[If no argument]: Select the FIRST story with status: refined (top-to-bottom order).

Follow the delivery loop exactly. Do not skip QA.
If QA fails, invoke remediate-failures.
If a fix requires changing product scope, STOP and escalate to the human.
Report PASS or FAIL at completion.
```

Do NOT use `isolation: "worktree"` at the Agent tool level — the Delivery Agent manages its own git worktrees as part of its pre-flight checks.

## After Sub-Agent Completes

Relay the result (PASS/FAIL + PR URL) to the user.
