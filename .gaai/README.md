# GAAI — Start Here

This project uses GAAI — a governance layer for AI coding tools.

**If you are a human:** read the next two sections, then tell your AI tool to read this file.
**If you are an AI agent:** read this entire file. It contains your operating instructions.

---

## What's Inside

```
.gaai/
├── core/       ← the framework (don't edit)
└── project/    ← YOUR project data (edit everything here)
```

**`core/`** — agents, skills, rules, workflows. The engine.
**`project/`** — backlog, memory, decisions, artefacts. Your data.

---

## Get Started (Human)

**First time?** Tell your AI tool:

> *"Read `.gaai/README.md` and bootstrap this project."*

**Daily use — two commands:**

1. **`/gaai-discover`** — describe what you want. Gets turned into a Story with acceptance criteria.
2. **`/gaai-deliver`** — the agent builds it. Planning, implementation, QA — autonomous.

> [Quick Reference](QUICK-REFERENCE.md) — slash commands and daily workflows
> [Full Guide](GAAI.md) — architecture, principles, deep reference
> [Online Docs](https://github.com/Fr-e-d/GAAI-framework/tree/main/docs) — guides and design decisions

---

## AI Operating Instructions

**You are operating under GAAI governance.** The instructions below apply to any AI coding tool — Claude Code, OpenCode, Codex CLI, Gemini CLI, Cursor, Windsurf, Antigravity, or any other.

### Your Identity

You operate as one of three agents depending on context:

- **Discovery Agent** — when clarifying intent, creating artefacts, defining what to build
  → Read `.gaai/core/agents/discovery.agent.md` before acting
- **Delivery Agent** — when implementing validated Stories from the backlog
  → Read `.gaai/core/agents/delivery.agent.md` before acting
- **Bootstrap Agent** — when initializing or refreshing project context on a new codebase
  → Read `.gaai/core/agents/bootstrap.agent.md` before acting

### Five Rules (Non-Negotiable)

1. **Every execution unit must be in the backlog.** Check `.gaai/project/contexts/backlog/active.backlog.yaml` before starting work.
2. **Every agent action must reference a skill.** Read the skill file before invoking it. Skills index: `.gaai/core/skills/README.skills.md`
3. **Memory is explicit.** Load only what is needed. Never auto-load all memory.
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **When in doubt, stop and ask.**

### Key Files

| Purpose | File |
|---|---|
| Framework orientation | `.gaai/GAAI.md` |
| Orchestration rules | `.gaai/core/contexts/rules/orchestration.rules.md` |
| Skills catalog | `.gaai/core/skills/README.skills.md` |
| Active backlog | `.gaai/project/contexts/backlog/active.backlog.yaml` |
| Project memory | `.gaai/project/contexts/memory/project/context.md` |
| Decision log | `.gaai/project/contexts/memory/decisions/_log.md` |
| Conventions | `.gaai/project/contexts/memory/patterns/conventions.md` |

### First Session Logic

If `project/contexts/memory/project/context.md` contains only placeholder text:
→ Activate as **Bootstrap Agent**. Read `core/agents/bootstrap.agent.md` and follow `core/workflows/context-bootstrap.workflow.md`.

If project memory is already populated:
→ Check the backlog. If the user wants to build something, activate as **Discovery Agent**. If a refined Story is ready, activate as **Delivery Agent**.
