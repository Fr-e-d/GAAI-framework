# GAAI — Agent Instructions

> This file is deployed to your project root as `AGENTS.md` by the installer.
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

## Rules

**Read `.gaai/core/contexts/rules/base.rules.md` at the start of every session.** These are the universal governance rules (backlog-first, skill-first, memory explicit, recommendation validation, conflict protocol).

For flow-specific rules (agent responsibilities, context isolation, backlog states, branch rules): `.gaai/core/contexts/rules/orchestration.rules.md`

## Key Paths

```
.gaai/
├── core/                            ← Framework (shared via subtree)
│   ├── GAAI.md                      ← Start here
│   ├── agents/                      ← Agent definitions
│   ├── skills/README.skills.md      ← All available skills
│   └── contexts/rules/              ← Governance rules
└── project/                         ← Project-specific data
    ├── contexts/memory/project/context.md ← Project context
    └── contexts/backlog/active.backlog.yaml ← Execution queue
```
