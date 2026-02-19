# Show HN: GAAI – A governance layer for AI coding tools. Drop `.gaai/` into any project, Bootstrap, ship.

The problem every AI-assisted developer hits eventually is not speed. It's drift.

Your agent ships the feature. It also quietly refactors two unrelated modules. You agreed three sessions ago: no ORM, raw SQL only. The agent introduced an ORM — it had no memory of that decision. A critical bug appears in production. You open a new session. The agent has no idea what the system does, what the constraints are, or what was decided last week.

These are not bugs in the AI. They are symptoms of running a powerful execution engine without a governance layer.

---

## What GAAI Is

A single `.gaai/` folder you drop into any project.

```
your-project/
└── .gaai/
    ├── agents/      ← Discovery + Delivery + Bootstrap
    ├── skills/      ← 31 pure execution units
    ├── contexts/    ← rules, memory, backlog, artefacts
    ├── workflows/   ← delivery loop, bootstrap, handoffs
    ├── scripts/     ← bash utilities
    └── compat/      ← adapters for Claude Code, Cursor, Windsurf, and more
```

No SDK. No npm install. No pip. No Node.js required. Markdown + YAML + bash. Readable by humans and any AI tool.

Works with Claude Code, Cursor, Windsurf, Codex CLI, Gemini CLI — anything that reads files.

---

## How It Works in 3 Steps

**1. Drop and Bootstrap (5 minutes)**

Copy `.gaai/` into your project. Run:

```
/gaai-bootstrap
```

The Bootstrap Agent scans your existing codebase, extracts architecture decisions, fills your memory files, and normalizes governance rules. It tells you when it's done:

```
✅ Bootstrap PASS — context ready.
```

Starting a brand new project with no codebase? Skip Bootstrap — go straight to Discovery. The Discovery Agent will ask you questions about your project and seed the memory from your answers. No manual file editing, ever.

**2. Describe What You Want to Build**

Talk to the Discovery Agent:

```
/gaai-discover

"I want users to reset their password via email."
```

The Discovery Agent helps you structure the idea, surfaces edge cases, asks the right questions, and produces a Story with explicit acceptance criteria — then writes it directly to the backlog.

```yaml
- id: BL-007
  title: Password reset via email
  status: refined
  acceptance_criteria: |
    - Reset link sent within 30 seconds
    - Token expires after 1 hour
    - Invalid/expired tokens return 400
    - All existing auth tests pass
```

**3. Run Delivery**

```
/gaai-deliver
```

The Delivery Agent picks the next refined Story and runs the full loop autonomously — planning, implementation, QA — until criteria pass or it escalates to you. It does not improvise scope. It does not touch things outside the Story.

---

## The Architecture Behind It

GAAI is built on one principle: **planning and execution must never share a context window**.

This is not philosophical. It is measurable.

GoalAct (Chen et al., 2025) demonstrated that separating global planning from hierarchical execution yields **+12.22% success rate** on complex agent benchmarks. [[arXiv:2504.16563](https://arxiv.org/abs/2504.16563)]

Plan-then-Execute (Del Rosario et al., 2025) shows the same separation provides control-flow integrity and reduces prompt injection risk — the Executor can only act on what the Planner explicitly authorized. [[arXiv:2509.08646](https://arxiv.org/abs/2509.08646)]

ACE (Zhang et al., ICLR 2026) demonstrates that unmanaged context accumulation degrades agent performance over time. Deliberate context engineering yields **+10.6% on agent benchmarks**. [[arXiv:2510.04618](https://arxiv.org/abs/2510.04618)]

GAAI implements this as two separate agents with a hard gate between them:

- **Discovery** — human-facing, conversational. Helps you structure intent into executable Stories. Never writes code.
- **Delivery** — autonomous, execution-only. Reads the backlog, ships, and QAs. Never decides scope.

The backlog is the gate. Nothing gets built unless it has `status: refined`. No exceptions.

---

## What This Solves That Your Current Setup Doesn't

**Session continuity.** Decisions made in session 1 are still binding in session 47. Memory is structured, versioned, and explicitly selected — never auto-loaded, never bloating the context window.

**Scope integrity.** The Delivery agent cannot touch what is not in the backlog. The refactor you didn't ask for does not happen.

**Auditability.** Every Story has acceptance criteria. Every delivery produces artefacts. You can always trace why something was built and whether it passed.

**No token waste.** Memory is explicit. The agent loads what it needs for the task — not everything that ever happened. Over a 6-month project, this matters.

---

## Who This Is For

GAAI is built for the developer — solo founder, small team, senior engineer — who is already using AI coding tools seriously and has started running into the governance problems that come with that.

It is particularly well-suited for **solo SaaS founders who know what they want to build**. You do not need to simulate a 12-person product team. You need an agent that helps you turn what's in your head into executable Stories, and another that ships them reliably without going off-script.

Discovery in GAAI is conversational and intentionally lightweight: it structures your thinking, not a committee's deliberation. If you already have product clarity, this is a feature — not a limitation.

If you are still in the "getting AI to write my first feature" phase, GAAI adds more structure than you need right now. If you have ever said "the agent broke something it wasn't supposed to touch" — GAAI is for you.

---

## Compared to Other Approaches

**vs. AGENTS.md / cursor rules:** A well-written AGENTS.md solves context loss for a single session. It does not solve scope drift, cross-session memory, or the authorization problem. GAAI is what comes after you've maxed out what a good AGENTS.md can do.

**vs. BMAD-METHOD:** BMAD simulates a full Agile team — PM, Architect, Scrum Master, Developer, QA — with rich collaborative brainstorming between personas. It is powerful when you want AI to co-drive product thinking. GAAI makes a different trade-off: a lighter Discovery track optimized for developers who already have clarity on what to build, paired with a Delivery track that is more rigidly governed. BMAD requires Node.js and a CLI. GAAI requires copying a folder. Different tools for adjacent problems — the key difference is in Delivery: GAAI's governance model is structural, not persona-based.

**vs. LangGraph / AutoGen / CrewAI:** Code-first orchestration frameworks for building AI systems. GAAI is a governance layer for using AI coding tools. Different abstraction level entirely.

---

## The Honest Trade-offs

- Discovery is conversational and intentionally lightweight. It helps you structure what you know — it does not replace deep product research or collaborative brainstorming across a team.
- Trivial tasks still need a backlog item. You can make it a one-liner, but the gate is always there.
- The framework relies on the agent following the files. There is no programmatic enforcement.
- The repo is freshly open-sourced. Community is just getting started.

---

## Try It

```bash
git clone https://github.com/Fr-e-d/GAAI-framework.git
cp -r GAAI-framework/.gaai/ your-project/
```

**Existing codebase** — run Bootstrap:
> "Read `.gaai/agents/bootstrap.agent.md` and follow `.gaai/workflows/context-bootstrap.workflow.md`."

**New project** — go straight to Discovery:
> "Read `.gaai/agents/discovery.agent.md`. I'm starting a new project: [your idea]. Help me define the first Stories."

First working Story in under 30 minutes.

Full docs: [github.com/Fr-e-d/GAAI-framework](https://github.com/Fr-e-d/GAAI-framework)

---

*MIT licensed. Markdown + YAML + bash. No SDK.*

---

**References**
- Chen et al. (2025). GoalAct. [arXiv:2504.16563](https://arxiv.org/abs/2504.16563)
- Del Rosario et al. (2025). Plan-then-Execute. [arXiv:2509.08646](https://arxiv.org/abs/2509.08646)
- Zhang et al. (2025). Agentic Context Engineering. ICLR 2026. [arXiv:2510.04618](https://arxiv.org/abs/2510.04618)
