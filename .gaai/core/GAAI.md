# GAAI — Master Orientation

Welcome. This is the `.gaai/` folder — the GAAI framework living inside your project.

---

## What Is This Folder?

`.gaai/` contains everything needed to run an AI-assisted SDLC with governance:

```
.gaai/
├── README.md               ← start here (human + AI onboarding)
├── GAAI.md                 ← you are here (full reference)
├── QUICK-REFERENCE.md      ← daily cheat sheet
├── VERSION                 ← framework version
│
├── core/                   ← framework engine (auto-synced to OSS via post-commit hook)
│   ├── agents/             ← who reasons and decides
│   ├── skills/             ← what gets executed
│   ├── contexts/rules/     ← governance (what is allowed)
│   ├── workflows/          ← how the pieces connect
│   ├── scripts/            ← bash utilities
│   └── compat/             ← thin adapters per tool
│
└── project/                ← YOUR project data (never overwritten by updates)
    ├── agents/             ← custom agents (project-specific)
    ├── skills/             ← custom skills (domains/, cross/)
    ├── contexts/
    │   ├── rules/          ← rule overrides
    │   ├── memory/         ← durable knowledge
    │   ├── backlog/        ← execution queue
    │   └── artefacts/      ← evidence and traceability
    ├── workflows/          ← custom workflows
    ├── scripts/            ← custom scripts
    └── content/            ← content drafts
```

**Resolution pattern:** for agents, skills, and rules — the framework loads `core/` first, then `project/` as extension/override.

**This folder contains governance files, not application code.** When scanning the codebase for application logic, there is no need to load `.gaai/` — its files are loaded explicitly by agents when needed, never automatically.

---

## How to Navigate

**If you are adding GAAI to an existing project:**
→ Start with `core/agents/bootstrap.agent.md`. The Bootstrap Agent is your entry point.
→ Its job: scan the codebase, extract architecture decisions, normalize rules, build memory.
→ Run `core/workflows/context-bootstrap.workflow.md` to guide the Bootstrap Agent through initialization.
→ Bootstrap completes when memory, rules, and decisions are all captured and consistent.
→ After bootstrap: switch to Discovery or Delivery depending on your current work.

**If you are just starting a new project:**
→ Read `core/agents/README.agents.md` to understand who does what.
→ Then look at `core/workflows/context-bootstrap.workflow.md` to start your first session.

**If you want to understand the skills:**
→ Read `core/skills/README.skills.md` for the full catalog.
→ Each skill lives in its own directory with a `SKILL.md` file.

**If you want to customize rules:**
→ Add override files in `project/contexts/rules/`. Start with `core/contexts/rules/orchestration.rules.md` as reference.

**If you want to switch to a different AI tool:**
→ Read `core/compat/COMPAT.md` for the compatibility matrix and instructions.
→ Re-run `install.sh --tool <tool> --yes` from the GAAI framework repo. There is no other adapter deployment mechanism.

---

## First Steps

**Existing project (onboarding GAAI onto an existing codebase):**
1. Activate the Bootstrap Agent. Read `core/agents/bootstrap.agent.md`.
2. Follow `core/workflows/context-bootstrap.workflow.md` — the Bootstrap Agent will scan, extract, and structure your project's knowledge.
3. Bootstrap fills `project/contexts/memory/project/context.md`, `project/contexts/memory/decisions/_log.md`, and `project/contexts/rules/` automatically.
4. Once Bootstrap passes, switch to Discovery or Delivery.

**New project (starting from scratch):**
1. Activate the Discovery Agent. Read `core/agents/discovery.agent.md`.
2. Describe your project idea. The Discovery Agent will ask questions to understand your project and seed the memory automatically.
3. Once memory is seeded, start creating Epics and Stories.

---

## Branch Model & Automation

AI agents work exclusively on the **`staging`** branch. Promotion to `production` is a human action via GitHub PR.

```
staging  ←── AI works here
   │  PR (human review)
production  ←── Deploy via GitHub Actions
```

The **Delivery Daemon** automates delivery end-to-end:
- Polls the backlog for `refined` stories
- Marks them `in_progress` on staging (cross-device coordination via git push)
- Launches AI agent sessions in isolated worktrees
- Parallel execution (default: 3 concurrent slots, configurable via `--max-concurrent`)
- Monitors session health via heartbeat and `--max-turns` safety limits
- Auto-opens a monitoring dashboard (tmux split: daemon config + active deliveries)

Usage: `/gaai-daemon` to start, `/gaai-daemon --stop` to stop. One-time setup: `bash .gaai/core/scripts/daemon-setup.sh`.

Git hooks are managed via dispatchers in `.githooks/` that delegate to scripts in `.gaai/core/hooks/<hook>.d/` (framework) and `.gaai/project/hooks/<hook>.d/` (project-specific). The installer (`install.sh`) sets up all dispatchers automatically.

Active hooks:
- **pre-push** — blocks pushes to protected branches (`production`, `main`) via `core/hooks/pre-push.d/01-block-production.sh`
- **post-commit** — runs framework maintenance (skills index, lint, memory check) and project hooks

<details>
<summary>How the dispatcher pattern works</summary>

Each git hook in `.githooks/` is a thin dispatcher — it does not contain business logic. Instead, it iterates over executable scripts in two directories, in order:

```
.gaai/core/hooks/<hook>.d/     ← framework scripts (shipped with GAAI)
.gaai/project/hooks/<hook>.d/  ← project scripts (yours to customize)
```

**Safe installation:** The installer never overwrites an existing `.githooks/<hook>` file. If you already have a hook (e.g. from Husky, lint-staged, or custom scripts), the installer appends a GAAI dispatcher block at the end — your existing logic runs first, then GAAI scripts run after. The appended block is marked with `# ── GAAI dispatcher ──` so the installer can detect it on subsequent runs and skip re-injection.

**To add a new hook script:** create an executable file in the appropriate `.d/` directory. Use numeric prefixes for ordering (e.g. `01-check.sh`, `02-notify.sh`).

**To add a new hook type** (e.g. `pre-commit`):

1. Create the dispatcher template in `.gaai/core/hooks/pre-commit`:
   ```bash
   #!/bin/bash
   # pre-commit dispatcher — executes hooks from core/ then project/
   ROOT="$(git rev-parse --show-toplevel)"
   CORE_DIR="$ROOT/.gaai/core/hooks/pre-commit.d"
   PROJECT_DIR="$ROOT/.gaai/project/hooks/pre-commit.d"

   for dir in "$CORE_DIR" "$PROJECT_DIR"; do
       [ -d "$dir" ] || continue
       for script in "$dir"/*; do
           [ -x "$script" ] || continue
           "$script" || exit $?
       done
   done
   exit 0
   ```
2. Create `.gaai/core/hooks/pre-commit.d/` and add your scripts.
3. Run `install.sh` — it auto-discovers all dispatcher templates in `core/hooks/` and installs them to `.githooks/`.

**Blocking vs non-blocking:** For hooks where failure should abort the git operation (pre-push, pre-commit), use `|| exit $?`. For informational hooks (post-commit), use `|| echo "warning"` to continue on failure.

**stdin-aware hooks:** Hooks like `pre-push` receive data on stdin from git. Their dispatchers capture stdin once and replay it to each script so multiple scripts can inspect the same data.

</details>

---

## Core Principles (Non-Negotiable)

The governance rules are defined in `core/contexts/rules/base.rules.md` (universal) and `core/contexts/rules/orchestration.rules.md` (flow-specific). The foundational principles:

1. **Backlog-first.** If it's not in the backlog, it must not be executed.
2. **Skill-first.** Agents reason. Skills execute.
3. **Memory is explicit.** Load only what is needed. Never auto-load all memory.
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **When in doubt, stop and ask.** Ambiguity is always resolved before execution.

## Progressive Disclosure (Architectural Principle)

GAAI never loads everything at once. Context is assembled on demand, in layers:

1. **Session startup** — only `base.rules.md` is auto-loaded (via tool adapter `@import`). Lightweight, universal rules.
2. **Agent activation** — the active agent definition is loaded when a flow starts (`/gaai-discover`, `/gaai-deliver`). Only one agent at a time.
3. **Sub-agent spawn** — each sub-agent receives a minimal, targeted context bundle. No full rule set, no full memory — only what the task requires.
4. **Memory retrieval** — 3-level progressive disclosure: index scan → targeted file load → cross-domain (rare). See `memory-retrieve` skill.
5. **Skills** — discovered via index frontmatter, loaded individually when invoked. Never bulk-loaded.

**Why:** LLM instruction-following degrades with context size. Every token of context must earn its place. The right amount of context is the minimum needed for the current task.

---

## Full Documentation

The complete documentation lives in `docs/` in the [GAAI framework repo](https://github.com/Fr-e-d/GAAI-framework):

→ [Quick Start](https://github.com/Fr-e-d/GAAI-framework/blob/main/docs/guides/quick-start.md) — first working Story in 30 minutes
→ [What is GAAI?](https://github.com/Fr-e-d/GAAI-framework/blob/main/docs/01-what-is-gaai.md) — the problem and the solution
→ [Core Concepts](https://github.com/Fr-e-d/GAAI-framework/blob/main/docs/02-core-concepts.md) — dual-track, agents, backlog, memory, artefacts
→ [Vibe Coder Guide](https://github.com/Fr-e-d/GAAI-framework/blob/main/docs/guides/vibe-coder-guide.md) — fast daily workflow
→ [Senior Engineer Guide](https://github.com/Fr-e-d/GAAI-framework/blob/main/docs/guides/senior-engineer-guide.md) — governance and customization

---

## Framework Version

See `VERSION` in this folder. The framework is maintained at [gaai-framework](https://github.com/Fr-e-d/GAAI-framework).

To check framework integrity: `bash .gaai/core/scripts/health-check.sh --core-dir .gaai/core --project-dir .gaai/project`
