# Tool Compatibility

GAAI works with any AI coding tool that can read files. This document covers setup for the tools with dedicated adapters. All others work via `AGENTS.md` or direct file access.

---

## Compatibility Matrix

| Tool | Slash commands | Rules auto-loading | SKILL.md discovery | Adapter |
|------|---------------|-------------------|-------------------|---------|
| Claude Code | ✅ Native | Via `CLAUDE.md` | ✅ Auto-scan | `CLAUDE.md` + `.claude/commands/` |
| OpenCode | ❌ | Via `AGENTS.md` | Manual | `AGENTS.md` |
| Codex CLI | ❌ | Via `AGENTS.md` | Manual | `AGENTS.md` |
| Gemini CLI | ❌ | Via `AGENTS.md` | Manual | `AGENTS.md` |
| Antigravity | ❌ | Via `AGENTS.md` | Manual | `AGENTS.md` |
| Cursor | ❌ | Via `.mdc` always-active | Via `.mdc` reference | `.cursor/rules/*.mdc` |
| Windsurf | ❌ | Via `AGENTS.md` | Manual | `AGENTS.md` |
| Any other | ❌ | Manual | Manual | Read `.gaai/core/GAAI.md` directly |

**Claude Code** has the deepest integration. All other tools provide full GAAI capability via manual activation — the framework works identically, the difference is convenience.

---

## Claude Code

The best-supported tool. Slash commands provide one-keystroke agent activation.

### Setup

After `bash install.sh`:
1. `CLAUDE.md` is deployed to your project root — Claude Code loads it automatically
2. `.claude/commands/` contains the slash command definitions

### Slash commands

| Command | Action |
|---|---|
| `/gaai-bootstrap` | Run Bootstrap Agent on existing codebase |
| `/gaai-discover` | Activate Discovery Agent |
| `/gaai-deliver` | Run Delivery Loop |
| `/gaai-status` | Show project status summary |

### CLAUDE.md

The deployed `CLAUDE.md` is a thin adapter that:
- Establishes agent identity and the 5 operating rules
- References `.gaai/` as the canonical source (not duplicating content)
- Lists available slash commands

To customize: edit `CLAUDE.md` in your project root. The framework source is at `.gaai/core/compat/claude-code.md`.

### Manual activation (without slash commands)

```
"Read .gaai/core/agents/discovery.agent.md. I want to build [idea]."
"Read .gaai/core/agents/delivery.agent.md and .gaai/core/workflows/delivery-loop.workflow.md. Execute the next ready backlog item."
```

---

## OpenCode, Codex CLI, Gemini CLI, Antigravity

These tools use `AGENTS.md` for context loading. Setup is identical across all of them.

### Setup

After `bash install.sh` (select "Other" at the tool prompt):
- `AGENTS.md` is deployed to your project root

Or manually: copy `.gaai/core/compat/windsurf.md` to `AGENTS.md` in your project root.

### Activating agents

**Discovery:**
> "Read `.gaai/core/agents/discovery.agent.md`. I want to build [idea]."

**Delivery:**
> "Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`. Execute the next ready backlog item."

**Bootstrap:**
> "Read `.gaai/core/agents/bootstrap.agent.md`, then follow `.gaai/core/workflows/context-bootstrap.workflow.md`."

**Status:**
> "Read `.gaai/project/contexts/backlog/active.backlog.yaml` and give me a summary."

All memory, rules, backlog, and artefact files are read directly from `.gaai/`. No additional setup required.

---

## Cursor

Setup uses `.mdc` rules files. No slash commands.

### Setup

After `bash install.sh`:
- `.cursor/rules/gaai.mdc` is deployed with `alwaysApply: true`

### What the .mdc file does

The `gaai.mdc` file (from `.gaai/core/compat/cursor.mdc`):
- Establishes agent identity at session start
- Lists the 5 operating rules
- References key `.gaai/` paths
- Provides invocation prompt templates for each agent

### Activating agents in Cursor

**Discovery:**
> "Read `.gaai/core/agents/discovery.agent.md`. I want to build [idea]."

**Delivery:**
> "Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`. Execute the next ready backlog item."

**Bootstrap:**
> "Read `.gaai/core/agents/bootstrap.agent.md`, then follow `.gaai/core/workflows/context-bootstrap.workflow.md`."

### Customizing rules in Cursor

Add additional `.mdc` files to `.cursor/rules/` for project-specific rules. Cursor loads all `.mdc` files with `alwaysApply: true` at session start.

---

## Windsurf

Setup uses `AGENTS.md`. No slash commands.

### Setup

After `bash install.sh`:
- `AGENTS.md` is deployed to your project root

### What AGENTS.md does

The `AGENTS.md` file (from `.gaai/core/compat/windsurf.md`):
- Establishes agent roles
- Lists the 5 operating rules
- Provides key paths and manual invocation templates

### Activating agents in Windsurf

Same manual prompt format as Cursor above.

---

## Other Tools (VS Code, Neovim, etc.)

For any tool that supports reading project files:

1. Copy the relevant content from `.gaai/core/compat/claude-code.md` or `.gaai/core/compat/windsurf.md` as a system prompt or instructions file for your tool
2. Use manual prompts to activate agents

The framework functions correctly regardless of how it's activated — the files are the system. The compat adapters only make activation more convenient.

---

## The Framework Is Tool-Agnostic

GAAI's governance is in the files, not in the tool. Changing AI tools requires only:
1. Deploying the right compat adapter (`install.sh` handles this)
2. Using the appropriate activation method (slash command vs manual prompt)

All memory, rules, backlog, and artefacts remain unchanged.

---

→ [Getting Started](../03-getting-started.md)
→ [Quick Start](../guides/quick-start.md)
