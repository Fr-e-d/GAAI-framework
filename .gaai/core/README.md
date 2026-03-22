# .gaai/core/ — GAAI Framework Engine

**New to GAAI?** → [Start with the Quick Start guide](docs/guides/quick-start.md) — first working Story in 30 minutes.

---

## 4 Commands to Run Your AI-Assisted SDLC

| Command | What it does |
|---|---|
| `/gaai-bootstrap` | Initialize project context on an existing codebase |
| `/gaai-discover` | Activate Discovery Agent — clarify intent, create Stories |
| `/gaai-deliver` | Run Delivery Loop — implement next ready Story end-to-end |
| `/gaai-status` | Show backlog and memory state |

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

## Optional: Autonomous Delivery

If your project uses git with a `staging` branch, the **Delivery Daemon** can automate everything:

1. One-time setup: `bash .gaai/core/scripts/daemon-setup.sh`
2. `/gaai-daemon` — starts the daemon (3 concurrent slots, auto-opens monitoring)
3. `/gaai-daemon --stop` — graceful shutdown

The daemon polls for `refined` stories and delivers them in parallel — no human in the loop.
Full reference: see `GAAI.md` → "Branch Model & Automation".

> **Tested on:** macOS (Apple Silicon). Linux and WSL (Windows) are expected to work but not yet validated — issues and feedback welcome.

---

## New Projects: Install GAAI

```bash
# From the GAAI-framework repo
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```
