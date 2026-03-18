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

The **Delivery Daemon** (`core/scripts/delivery-daemon.sh`) automates delivery:
- Polls the backlog for `refined` stories
- Marks them `in_progress` on staging (cross-device coordination via git push)
- Launches AI agent sessions in isolated worktrees
- Supports parallel execution (`--max-concurrent`)
- Monitors session health via heartbeat and `--max-turns` safety limits

A pre-push hook (`.githooks/pre-push`) blocks all pushes to `production` from the development environment. Activate with `git config core.hooksPath .githooks`.

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

**Why:** LLM instruction-following degrades with context size (see DEC-194). Every token of context must earn its place. The right amount of context is the minimum needed for the current task.

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

See `VERSION` in this folder. This framework was installed from [gaai-framework](https://github.com/Fr-e-d/GAAI-framework).

To check framework integrity: `bash .gaai/core/scripts/health-check.sh --core-dir .gaai/core --project-dir .gaai/project`
