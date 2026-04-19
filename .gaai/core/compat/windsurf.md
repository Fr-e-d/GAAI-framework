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

**Read `.gaai/core/contexts/rules/base.rules.md` at the start of every session.** These are the universal governance rules (backlog-first, skill-first, memory discipline, backlog state lifecycle, archiving rules, forbidden patterns, default deny, conflict protocol).

For flow-specific rules (agent responsibilities, context isolation, branch rules, cron, capability readiness): `.gaai/core/contexts/rules/orchestration.rules.md`

## Memory Catalog (navigable map)

**Read `.gaai/project/contexts/memory/index.md` at the start of every session.** This is the catalog — categories, decisions, patterns, architecture, strategy, domains. Browse the index before retrieving content so you know *what exists* before acting. Do not retrieve memory blindly; the index tells you what's there and how to reach it.

## Key Paths

```
.gaai/
├── core/                            ← Framework (auto-synced to OSS)
│   ├── GAAI.md                      ← Start here
│   ├── agents/                      ← Agent definitions
│   ├── skills/README.skills.md      ← All available skills
│   └── contexts/rules/              ← Governance rules
└── project/                         ← Project-specific data
    ├── contexts/memory/project/context.md ← Project context
    └── contexts/backlog/active.backlog.yaml ← Execution queue
```
