# GAAI — Agent Instructions

> This file is deployed to your project root as `AGENTS.md` by `install.sh`.
> Compatible with Windsurf, Gemini CLI, and any tool that reads `AGENTS.md`.

---

## You Are Operating Under GAAI Governance

This project uses GAAI (`.gaai/` folder). Read `.gaai/core/GAAI.md` for orientation.

## Agent Roles

Activate based on context:

**Discovery Agent** (`.gaai/core/agents/discovery.agent.md`)
→ Use when: clarifying intent, creating PRDs, Epics, Stories

**Delivery Agent** (`.gaai/core/agents/delivery.agent.md`)
→ Use when: implementing Stories from the validated backlog

**Bootstrap Agent** (`.gaai/core/agents/bootstrap.agent.md`)
→ Use when: first setup on an existing codebase, or refreshing project context

## Five Operating Rules

1. Every execution unit must be in the backlog (`contexts/backlog/active.backlog.yaml`)
2. Every agent action must reference a skill (`skills/README.skills.md`)
3. Memory is explicit — select what to load, never auto-inject all memory
4. Artefacts document — they do not authorize. Only the backlog authorizes execution.
5. When in doubt, stop and ask.

## Key Paths

```
.gaai/
├── GAAI.md                          ← Start here
├── agents/                          ← Agent definitions
├── skills/README.skills.md          ← All available skills
├── contexts/rules/                  ← Governance rules
├── contexts/memory/memory/project/context.md ← Project context
└── contexts/backlog/active.backlog.yaml ← Execution queue
```
