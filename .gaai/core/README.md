# .gaai/core/ — GAAI Framework Engine

**New to GAAI?** → [Start with the Quick Start guide](docs/guides/quick-start.md) — first working Story in 30 minutes.

---

## 4 Commands to Run Your AI-Assisted SDLC

| Command | What it does |
|---|---|
| `/gaai-bootstrap` | Initialize project context on an existing codebase |
| `/gaai-discover` | Activate Discovery Agent — clarify intent, create Stories |
| `/gaai-deliver` | Start the Delivery Daemon — deliver refined Stories autonomously via tmux |
| `/gaai-status` | Show backlog and memory state |

`/gaai-deliver` and `/gaai-daemon` are aliases — both launch the same daemon infrastructure.

Discovery works with any AI coding tool or MCP client (Claude Code, Cursor, Windsurf, and more). The daemon requires the Claude Code CLI (`claude` binary in PATH) as a runtime dependency — not a preference. See `compat/COMPAT.md` for the full 3-tier compatibility model.

That's the day-1 surface area. Everything else (47 skills, 8 rule files, 4 workflows) is loaded on demand — you never interact with it directly.

**Information preservation:** When Discovery delegates work to sub-agents, it compiles a *Discovery Session Brief* — a structured extraction of all conversation intelligence (decisions, observations, trade-offs, constraints). This prevents context loss between agents. See [`agents/discovery.agent.md`](agents/discovery.agent.md).

---

`core/` contains the framework engine: agents, skills, rules, and workflows. These files are shared across all GAAI-powered projects and are managed by the installer. **Do not edit files in `core/` directly** — your changes will be overwritten the next time you update GAAI.

To update the framework, run the installer with the new version:

```bash
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```

Customization lives in `project/` — add your rules, skills, agents, and memory there.

```
.gaai/
├── core/      ← Framework engine (managed by installer — do not edit)
└── project/   ← Your customizations: memory, backlog, skills, rules
```

---

## Delivery Daemon

If your project uses git with a `staging` branch, the **Delivery Daemon** delivers refined Stories autonomously:

1. One-time setup: `bash .gaai/core/scripts/daemon-setup.sh`
2. `/gaai-deliver` — starts the daemon (default: 1 slot, auto-opens monitoring)
3. `/gaai-deliver --stop` — graceful shutdown

Override concurrency: `/gaai-deliver --max-concurrent 3`

The daemon polls for `refined` stories and delivers them in parallel via tmux — each delivery runs in its own tmux session with real-time visibility.
Full reference: see `GAAI.md` → "Branch Model & Automation".

**Runtime requirement:** The daemon requires the Claude Code CLI (`claude` binary in PATH). This is a hard dependency — not a recommendation. Discovery and manual Delivery work with any AI coding tool; this requirement applies only to autonomous delivery.

> **Tested on:** macOS (Apple Silicon). Linux and WSL (Windows) are expected to work but not yet validated — issues and feedback welcome.

---

## New Projects: Install GAAI

```bash
# From the GAAI-framework repo
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```
