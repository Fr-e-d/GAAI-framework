# GAAI — Quick Reference

## Slash Commands

| Command | What it does |
|---|---|
| `/gaai-bootstrap` | Scan codebase, extract decisions, build memory files |
| `/gaai-discover` | Start Discovery — clarify intent, create Stories with acceptance criteria |
| `/gaai-deliver` | Start Delivery — execute the next refined Story from the backlog |
| `/gaai-status` | Show current backlog state and memory summary |

## Starting a Session

1. Run `/gaai-discover` and describe what you want to build
2. Discovery creates a Story with acceptance criteria and adds it to the backlog
3. Run `/gaai-deliver` — the Delivery Agent handles planning, implementation, and QA

## Adding a Feature

1. `/gaai-discover` — "I want to add [feature description]"
2. Answer Discovery's clarifying questions until the Story is `refined`
3. `/gaai-deliver` — Delivery picks up the Story and executes it autonomously

## Key Files

| File | Purpose |
|---|---|
| `.gaai/project/contexts/backlog/active.backlog.yaml` | What's authorized for execution |
| `.gaai/project/contexts/memory/project/context.md` | What the agent knows about your project |
| `.gaai/project/contexts/memory/decisions/_log.md` | Decisions that persist across sessions |
| `.gaai/GAAI.md` | Full framework orientation |

## Core Rule

Nothing gets built that isn't in the backlog. Discovery decides *what*. Delivery decides *how*. You decide *when*.

---

> [Full documentation](https://github.com/Fr-e-d/GAAI-framework/tree/main/docs)
