---
description: Clarify intent & produce governed artefacts via Discovery Agent
---

# /gaai-discover

Activate the Discovery Agent to clarify intent and produce governed artefacts.

## What This Does

Activates the Discovery Agent to:
1. Understand what you want to build and why
2. Create a Discovery action plan
3. Produce Epics and Stories with acceptance criteria
4. Validate artefacts before handing off to Delivery

## When to Use

- Starting a new feature or product
- When you have an idea but need to clarify scope
- When backlog items need refinement
- When you're not sure what to build next

## How to Trigger

Just describe your intent:
- "I want to add user authentication"
- "Users are abandoning the checkout flow"
- "We need to improve the onboarding experience"

The Discovery Agent will take it from there.

## Instructions for Claude Code

Read `.gaai/core/agents/discovery.agent.md`.

Ask the human to describe their intent if not already provided. Then follow the Discovery workflow: plan → create artefacts → validate → hand off to Delivery if ready.

At the end, confirm what was added to the backlog.
