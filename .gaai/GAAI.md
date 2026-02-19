# GAAI — Master Orientation

Welcome. This is the `.gaai/` folder — the GAAI framework living inside your project.

---

## What Is This Folder?

`.gaai/` contains everything needed to run an AI-assisted SDLC with governance:

```
.gaai/
├── GAAI.md              ← you are here
├── VERSION              ← framework version
├── agents/              ← who reasons and decides
├── skills/              ← what gets executed
├── contexts/            ← what constrains and informs
│   ├── rules/           ← governance (what is allowed)
│   ├── memory/          ← durable knowledge
│   ├── backlog/         ← execution queue
│   └── artefacts/       ← evidence and traceability
├── workflows/           ← how the pieces connect
├── scripts/             ← bash utilities
└── compat/              ← thin adapters per tool
```

**This folder contains governance files, not application code.** When scanning the codebase for application logic, there is no need to load `.gaai/` — its files are loaded explicitly by agents when needed, never automatically.

---

## How to Navigate

**If you are adding GAAI to an existing project:**
→ Start with `agents/bootstrap.agent.md`. The Bootstrap Agent is your entry point.
→ Its job: scan the codebase, extract architecture decisions, normalize rules, build memory.
→ Run `workflows/context-bootstrap.workflow.md` to guide the Bootstrap Agent through initialization.
→ Bootstrap completes when memory, rules, and decisions are all captured and consistent.
→ After bootstrap: switch to Discovery or Delivery depending on your current work.

**If you are just starting a new project:**
→ Read `contexts/README.contexts.md` first. It defines the operating model.
→ Then read `agents/README.agents.md` to understand who does what.
→ Then look at `workflows/context-bootstrap.workflow.md` to start your first session.

**If you want to understand the skills:**
→ Read `skills/README.skills.md` for the full catalog.
→ Each skill lives in its own directory with a `SKILL.md` file.

**If you want to customize rules:**
→ Edit files in `contexts/rules/`. Start with `orchestration.rules.md`.

**If you want to switch to a different AI tool:**
→ Read `compat/COMPAT.md` for the compatibility matrix and instructions.
→ Re-run `install.sh --tool <tool> --yes` from the GAAI framework repo. There is no other adapter deployment mechanism.

---

## First Steps

**Existing project (onboarding GAAI onto an existing codebase):**
1. Activate the Bootstrap Agent. Read `agents/bootstrap.agent.md`.
2. Follow `workflows/context-bootstrap.workflow.md` — the Bootstrap Agent will scan, extract, and structure your project's knowledge.
3. Bootstrap fills `contexts/memory/project/context.md`, `contexts/memory/decisions/_log.md`, and `contexts/rules/` automatically.
4. Once Bootstrap passes, switch to Discovery or Delivery.

**New project (starting from scratch):**
1. Activate the Discovery Agent. Read `agents/discovery.agent.md`.
2. Describe your project idea. The Discovery Agent will ask questions to understand your project and seed the memory automatically.
3. Once memory is seeded, start creating Epics and Stories.

---

## Core Principles (Non-Negotiable)

1. **Every execution unit must be in the backlog.** If it's not in the backlog, it must not be executed.
2. **Every agent action must reference a skill.** Agents reason. Skills execute.
3. **Memory is explicit.** Agents select what to remember. Memory is never auto-loaded.
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **When in doubt, stop and ask.** Ambiguity is always resolved before execution.

---

## Full Documentation

The complete documentation lives outside this folder, in `docs/`:

→ [Quick Start](../docs/guides/quick-start.md) — first working Story in 30 minutes
→ [What is GAAI?](../docs/01-what-is-gaai.md) — the problem and the solution
→ [Core Concepts](../docs/02-core-concepts.md) — dual-track, agents, backlog, memory, artefacts
→ [Vibe Coder Guide](../docs/guides/vibe-coder-guide.md) — fast daily workflow
→ [Senior Engineer Guide](../docs/guides/senior-engineer-guide.md) — governance and customization

---

## Framework Version

See `VERSION` file. This folder was installed from [gaai-framework](https://github.com/Fr-e-d/GAAI-framework) v1.0.0.

To check framework integrity: `bash .gaai/scripts/health-check.sh`
