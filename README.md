![Version](https://img.shields.io/badge/version-2.1.1-blue)
![License: ELv2](https://img.shields.io/badge/license-ELv2-green)
![No SDK](https://img.shields.io/badge/stack-markdown%20%2B%20yaml%20%2B%20bash-orange)

# GAAI — Governed Agentic AI Infrastructure

A `.gaai/` folder you drop into any project. Markdown + YAML + bash. No SDK. No package. No external services.

**GAAI turns AI coding tools into reliable agentic software delivery systems.**

---

## See It in Action

```
You:        /gaai-discover
Discovery:  "What do you want to build?"
You:        "Add rate limiting — 100 req/min per user, 429 on exceeded."
Discovery:  "Got it. Checking memory for existing middleware patterns..."
            → Generates Epic E03 + Story E03S01 with acceptance criteria
            → Runs validation: artefact complete, criteria testable, no scope drift
            → Adds to backlog: status: refined
Discovery:  "Done. E03S01 is ready. Run /gaai-deliver when you're ready."

You:        /gaai-deliver
            → Spawns an isolated Delivery Agent (clean context — no Discovery bleed)
Delivery:   → Reads E03S01 from backlog
            → Loads middleware conventions from memory
            → Planning Sub-Agent: produces execution plan
            → Implementation Sub-Agent: adds rate-limiting middleware
            → QA Sub-Agent: all acceptance criteria PASS
            → Story marked done, PR merged to staging
Delivery:   "E03S01 complete. No further Stories in backlog."
```

Two slash commands. Two **isolated contexts**. Discovery reasons — it never executes. Delivery executes — it never decides scope. They never share a context window, so system prompts can't contaminate each other. The backlog is the contract between them.

> **Want it fully autonomous?** The Delivery Daemon polls your backlog and auto-delivers
> stories in parallel — no human in the loop. [See Automation →](#automation-optional)

> [Full walkthrough in Quick Start](docs/guides/quick-start.md)

---

## The Problem It Solves

Your AI coding tool writes code fast. But without a governance layer, speed creates drift:

- The agent ships the feature — and quietly refactors two unrelated modules you didn't mention
- You agreed three sessions ago: no ORM, raw SQL only. The agent just introduced an ORM dependency — it had no memory of that decision
- Acceptance criteria were written after implementation. No one can verify the agent built the right thing
- A critical bug appears. You open a new session. The agent has no idea what the system does or what was decided last week
- You're not sure what the agent touched or what it was allowed to touch. There's no record either way

None of these are bugs in the AI. They are symptoms of using a powerful execution engine without a governance layer.

---

## How It Works

**Discovery** — you talk to the Discovery Agent in your current session. Clarify what to build. Output: a Story with acceptance criteria in the backlog. Discovery reasons. It does not execute.

**Delivery** — always runs in an **isolated context**. `/gaai-deliver` spawns a separate agent with a clean context window — no Discovery residue, no conversation history bleed. The Delivery Agent orchestrates specialized sub-agents (Planning, Implementation, QA) per Story. No improvisation. No scope drift. No context contamination.

**The backlog is the contract.** Nothing gets built that isn't in it.

```
your-project/
└── .gaai/
    ├── core/                  ← framework engine (updated via git subtree)
    │   ├── README.md          ← start here (human + AI onboarding)
    │   ├── GAAI.md            ← full reference
    │   ├── QUICK-REFERENCE.md ← daily cheat sheet
    │   ├── VERSION
    │   ├── agents/            ← Discovery + Delivery + Bootstrap agent specs
    │   ├── skills/            ← 47 execution units
    │   ├── contexts/rules/    ← framework rules
    │   ├── workflows/         ← delivery loop, bootstrap, handoffs
    │   ├── scripts/           ← bash utilities
    │   ├── hooks/             ← git hook dispatcher + core hooks
    │   └── compat/            ← thin adapters per AI tool
    └── project/               ← your project data (never overwritten by updates)
        ├── agents/            ← custom project agents
        ├── skills/            ← custom project skills
        ├── scripts/           ← project-specific scripts
        ├── hooks/             ← project-specific git hooks
        ├── workflows/         ← custom workflow overrides
        ├── content/           ← content production assets
        └── contexts/
            ├── rules/         ← project rule overrides
            ├── memory/        ← persistent memory (decisions, patterns, context)
            ├── backlog/       ← execution queue (active, blocked, done)
            └── artefacts/     ← stories, epics, plans, reports
```

No SDK. No npm package. No pip install. Markdown + YAML + bash. Readable by humans and any AI tool.

---

## Who This Is For

GAAI is built for the developer — solo founder, small team, senior engineer — who is already using AI coding tools seriously and has started running into the governance problems that come with that.

It is particularly well-suited for **solo SaaS founders who know what they want to build**. You do not need to simulate a 12-person product team. You need an agent that helps you turn what's in your head into executable Stories, and another that ships them reliably without going off-script.

Discovery in GAAI is conversational and intentionally lightweight: it structures your thinking, not a committee's deliberation. If you already have product clarity, this is a feature — not a limitation.

If you are still in the "getting AI to write my first feature" phase, GAAI adds more structure than you need right now. If you have ever said "the agent broke something it wasn't supposed to touch" — GAAI is for you.

---

## Install (30 seconds)

**Copy the `.gaai/` folder into your project.** That's it.

Download from GitHub, drop `.gaai/` into your project root, and tell your AI tool: *"Read `.gaai/core/README.md` and bootstrap this project."*

<details open>
<summary>Option A — Ask your AI tool to do it</summary>

Paste this into your AI tool's chat:

```
Install the GAAI framework into my current project.

Determine {user-tool} by identifying which AI coding tool is running this
prompt. Valid values: claude-code | cursor | windsurf | other.
If you cannot determine it, ask the user before proceeding.

Then run:
  rm -rf /tmp/gaai
  git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai
  bash /tmp/gaai/.gaai/core/scripts/install.sh --target . --tool {user-tool} --yes
  rm -rf /tmp/gaai

After install, show the user the next steps exactly as printed by the
installer.
```

The installer copies `.gaai/` and deploys the right adapter for your tool (CLAUDE.md, AGENTS.md, or .cursor/rules/).

</details>

<details open>
<summary>Option B — CLI</summary>

```bash
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai && \
  bash /tmp/gaai/.gaai/core/scripts/install.sh --wizard && \
  rm -rf /tmp/gaai
```

</details>

---

## Compared to Other Approaches

**vs. AGENTS.md / cursor rules:** A well-written AGENTS.md solves context loss for a single session. It does not solve scope drift, cross-session memory, or the authorization problem. GAAI is what comes after you've maxed out what a good AGENTS.md can do.

**vs. BMAD-METHOD:** BMAD simulates a multi-agent Agile team with specialized personas (PM, Architect, Developer, QA, and more) and rich collaborative workflows. It is powerful when you want AI to co-drive product thinking. GAAI makes a different trade-off: a lighter Discovery track optimized for developers who already have clarity on what to build, paired with a Delivery track that is more rigidly governed. Different tools for adjacent problems — the key difference is in Delivery: GAAI's governance model is structural, not persona-based.

**vs. LangGraph / AutoGen / CrewAI:** Code-first orchestration frameworks for building AI systems. GAAI is a governance layer for using AI coding tools. Different abstraction level entirely.

---

## Automation (Optional)

GAAI works manually with `/gaai-deliver`. But if your project uses git with a `staging` branch, the **Delivery Daemon** runs deliveries autonomously:

- Polls the backlog for `refined` stories
- Launches parallel Claude Code sessions (configurable concurrency)
- Coordinates across devices via git push
- Monitors health, retries failures, archives completed work

**Setup (2 minutes):**

```bash
bash .gaai/core/scripts/daemon-setup.sh   # checks prereqs, configures
bash .gaai/core/scripts/daemon-start.sh   # starts the daemon
```

> Requires: git repo, `staging` branch, [Claude Code CLI](https://claude.com/claude-code), python3, tmux (Linux) or Terminal.app (macOS).

---

## Works With

**Deep integration** — slash commands, auto-loaded context, SKILL.md auto-discovery:

| Tool | Adapter |
|------|---------|
| Claude Code | `CLAUDE.md` + `.claude/commands/` |

**AGENTS.md compatible** — full GAAI capability via manual activation prompts:

| Tool | Adapter |
|------|---------|
| OpenCode | `AGENTS.md` |
| Codex CLI | `AGENTS.md` |
| Gemini CLI | `AGENTS.md` |
| Antigravity | `AGENTS.md` |
| Cursor | `.cursor/rules/*.mdc` |
| Windsurf | `AGENTS.md` |
| Any other | Read `.gaai/core/README.md` directly |

One canonical source (`.gaai/`). Thin adapters per tool. No duplication. The framework functions identically across all tools — the difference is activation convenience, not capability.

> [Full compatibility details](docs/reference/tool-compatibility.md)

---

## Honest Trade-offs

- Discovery is conversational and intentionally lightweight. It helps you structure what you know — it does not replace deep product research or collaborative brainstorming across a team.
- Trivial tasks still need a backlog item. You can make it a one-liner, but the gate is always there.
- The framework relies on the agent following the files. There is no programmatic enforcement.
- The repo is freshly open-sourced. Community is just getting started.

---

## Documentation

- [Quick Start](docs/guides/quick-start.md) — first working Story in 30 minutes
- [What is GAAI?](docs/01-what-is-gaai.md) — the problem in full
- [Core Concepts](docs/02-core-concepts.md) — dual track, backlog, memory, skills, artefacts
- [Vibe Coder Guide](docs/guides/vibe-coder-guide.md) — fast daily workflow
- [Senior Engineer Guide](docs/guides/senior-engineer-guide.md) — governance, rules, CI
- [Skills Index](.gaai/core/skills/README.skills.md) — all 47 skills
- [Tool Compatibility](docs/reference/tool-compatibility.md) — Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf
- [Design Decisions](docs/architecture/design-decisions.md) — why GAAI is structured the way it is (ADRs + research basis)

---

ELv2 — see [LICENSE](LICENSE)

---

## Support This Project

If you find this framework valuable, please consider showing your support:

- **[Sponsor on GitHub](https://github.com/sponsors/Fr-e-d)**

---

Created by [Frédéric Geens](https://www.linkedin.com/in/fr%C3%A9d%C3%A9ric-geens-04162233/)
