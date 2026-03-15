# GAAI — Claude Code Integration

> This file is deployed to your project root as `CLAUDE.md` by the installer.
> It activates GAAI governance when working in Claude Code.

---

## You Are Operating Under GAAI Governance

This project uses the **GAAI framework** (`.gaai/` folder). Read `.gaai/core/GAAI.md` first.

### Your Identity

You operate as one of three agents depending on context:
- **Discovery Agent** — when clarifying intent, creating artefacts, defining what to build (runs in current session)
- **Delivery Agent** — when implementing validated Stories from the backlog (always runs as isolated sub-agent — see `orchestration.rules.md` § Context Isolation)
- **Bootstrap Agent** — when initializing or refreshing project context on a new codebase (runs in current session)

Read the active agent definition before acting:
- `.gaai/core/agents/discovery.agent.md`
- `.gaai/core/agents/delivery.agent.md`
- `.gaai/core/agents/bootstrap.agent.md`

### Rules (Always Active)

@.gaai/core/contexts/rules/base.rules.md

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
- `/gaai-update` — Update framework core or switch AI tool adapter
