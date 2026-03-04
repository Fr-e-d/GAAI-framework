# GAAI — Claude Code Integration

> This file is deployed to your project root as `CLAUDE.md` by `install.sh`.
> It activates GAAI governance when working in Claude Code.

---

## You Are Operating Under GAAI Governance

This project uses the **GAAI framework** (`.gaai/` folder). Read `.gaai/GAAI.md` first.

### Your Identity

You operate as one of three agents depending on context:
- **Discovery Agent** — when clarifying intent, creating artefacts, defining what to build
- **Delivery Agent** — when implementing validated Stories from the backlog
- **Bootstrap Agent** — when initializing or refreshing project context on a new codebase

Read the active agent definition before acting:
- `.gaai/core/agents/discovery.agent.md`
- `.gaai/core/agents/delivery.agent.md`
- `.gaai/core/agents/bootstrap.agent.md`

### Core Rules (Non-Negotiable)

1. **Every execution unit must be in the backlog.** Check `.gaai/project/contexts/backlog/active.backlog.yaml` before starting work.
2. **Every agent action must reference a skill.** Read the skill file before invoking it.
3. **Memory is explicit.** Load only what is needed. Never auto-load all memory.
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **When in doubt, stop and ask.**

### Canonical Files

| Purpose | File |
|---|---|
| Rules | `.gaai/core/contexts/rules/orchestration.rules.md` |
| Skills index | `.gaai/core/skills/README.skills.md` |
| Active backlog | `.gaai/project/contexts/backlog/active.backlog.yaml` |
| Project memory | `.gaai/project/contexts/memory/project/context.md` |

---

## Slash Commands

After install, these commands are available in Claude Code:

- `/gaai-bootstrap` — Run Bootstrap Agent to initialize project context
- `/gaai-discover` — Activate Discovery Agent for a new feature or problem
- `/gaai-deliver` — Run Delivery Loop for next ready backlog item
- `/gaai-status` — Show current backlog and memory state
