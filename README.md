# GAAI — Governed Agentic AI Infrastructure

A `.gaai/` folder you drop into any project. Markdown + YAML + bash. No SDK. No package.

**GAAI turns AI coding tools into reliable agentic software delivery systems.**

Works with Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf — or any AI coding tool that can read files.

---

## The Problem

Your agentic coding tool writes code fast. The quality keeps improving. We're all shipping more than ever before.

But without the right steering system, speed and drift become the problem.

Then something starts breaking down — not the code. The process.

- The agent ships the feature. It also quietly refactors two unrelated modules, renames a function, and updates a config you didn't mention.
- You agreed three sessions ago: no ORM, raw SQL only. The agent just introduced an ORM dependency. It had no memory of that decision.
- You wrote the acceptance criteria after the implementation was already running. The agent built the right thing. Probably. No one can verify it.
- The agent is mid-implementation and asks: "Should I create a new service or extend the existing one?" You answer. It interprets your answer differently than you meant. You find out two hours later.
- A critical bug appears in production. You open a new session to fix it. The agent has no idea what the system does, what the constraints are, or what was decided last week.
- You're not sure what the agent touched. You're not sure what it was allowed to touch. There's no record either way.

None of these are bugs in the AI. They are symptoms of using a powerful execution engine without a governance layer.

---

## The Model — Dual-Track Delivery

```
You ←→ Discovery Agent     Understand. Define. Write Stories. Acceptance criteria.
              ↓
        active.backlog.yaml     Authorization gate. Only refined Stories proceed.
              ↓
       Delivery Agent →     Orchestrates. Coordinates. Escalates.
              ↓
       Sub-agents →         Plan. Implement. QA. (spawned per Story complexity tier)
              ↓
          Working code
```

**Discovery** — conversation with the Discovery Agent. Clarify what to build. Output: a Story with acceptance criteria in the backlog. Discovery reasons. It does not execute.

**Delivery** — autonomous execution. The Delivery Agent orchestrates a team of specialized sub-agents (Planning, Implementation, QA) that it spawns per Story. Simple Stories use a single MicroDelivery sub-agent. Complex Stories use the full team, plus domain specialists for security, database, API, and UI work. No improvisation. No scope drift. Delivery executes. It never decides scope or intent.

**The backlog is the contract.** Nothing gets built that isn't in it.

Planning and execution never share a context window — by design. → [Research basis](docs/architecture/design-decisions.md#adr-006-dual-track-discovery-vs-delivery)

---

## What GAAI Adds

Four questions AI tools don't answer by themselves:

**What is the agent allowed to do right now?**
The backlog. If it's not there with `status: refined`, the delivery agent doesn't touch it.

**What does the agent know about this project?**
Explicit memory — curated, versioned, agent-selected. The decision you made in session 1 is still binding in session 47. No re-explanation. No drift.

**What counts as "done"?**
Acceptance criteria. QA is a hard gate: PASS or FAIL, no "close enough."

**Who decides what?**
You decide. GAAI provides the framework. Agents execute within it.

Artefacts document. Memory informs. Rules constrain. Only the backlog authorizes execution.

---

## What GAAI Is (Technically)

A single `.gaai/` folder you drop into any project:

```
your-project/
└── .gaai/
    ├── core/            ← framework (synced via git subtree)
    │   ├── agents/      ← Discovery + Delivery + Bootstrap agent specs
    │   ├── skills/      ← 37 pure execution units (one thing, explicit output)
    │   ├── contexts/    ← framework rules
    │   ├── workflows/   ← delivery loop, bootstrap, handoffs, emergency rollback
    │   ├── scripts/     ← bash utilities (health check, backlog scheduler, bootstrap, sync, snapshot)
    │   └── compat/      ← thin adapters for Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf
    └── project/         ← your project data (created by installer)
        └── contexts/    ← rules, memory, backlog, artefacts
```

**No SDK. No npm package. No pip install. No external services.**
Markdown + YAML + bash. Readable by humans and any AI tool.

---

## Install

### Ask your AI assistant (Claude Code, OpenCode, Codex, Gemini, Cursor, Windsurf…)

Paste this into your AI tool's chat — it will handle the rest:

```
Install the GAAI framework into my current project.

Determine {user-tool} by identifying which AI coding tool is running this
prompt. Valid values: claude-code | cursor | windsurf | other.
If you cannot determine it, ask the user before proceeding.

Then run:
  rm -rf /tmp/gaai
  git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai
  bash /tmp/gaai/install.sh --target . --tool {user-tool} --yes
  rm -rf /tmp/gaai

After install, show the user the next steps exactly as printed by the
installer.
```

---

### CLI — git clone

```bash
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai && \
  bash /tmp/gaai/install.sh --wizard && \
  rm -rf /tmp/gaai
```

The wizard asks where to install and which AI tool you use.

---

### Downloaded ZIP or GitHub Desktop

Once the repo is on your machine, open a terminal in that folder and run:

```bash
bash install.sh --wizard
```

The wizard will ask for the target project directory.

---

## What a Session Looks Like

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
Delivery:   → Reads E03S01 from backlog
            → Loads middleware conventions from memory
            → Planning Sub-Agent: produces execution plan
            → Implementation Sub-Agent: adds rate-limiting middleware
            → QA Sub-Agent: all acceptance criteria PASS
            → Story marked done, archived
Delivery:   "E03S01 complete. No further Stories in backlog."
```

→ [Full walkthrough in Quick Start](docs/guides/quick-start.md)

---

## Five Rules (Non-Negotiable)

1. Every execution unit must be in the backlog.
2. Every agent action must reference a skill. If a skill appears to think, it is wrongly designed.
3. Memory is explicit — agents select what to load, never auto-loaded.
4. Artefacts document — they do not authorize. Only the backlog authorizes.
5. When in doubt, stop and ask.

---

## Tool Compatibility

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
| Any other | Read `.gaai/core/GAAI.md` directly |

One canonical source (`.gaai/`). Thin adapters per tool. No duplication.

The framework functions identically across all tools — the difference is activation convenience, not capability. → [Full compatibility details](docs/reference/tool-compatibility.md)

---

## Fork & Own

This is not a library you pin a version to. It is a design pattern expressed in files.

Fork or clone. Run `install.sh`. Adapt the rules, memory, and skills to your project. The `.gaai/` folder is yours.

---

## Branches

| Branch | Purpose |
|---|---|
| `staging` | Active development — PRs target this branch |
| `production` | Stable releases — merged from staging |
| `_subtree-export` | Auto-generated. Contains `.gaai/core/` content at root for `git subtree` consumers. Do not use directly. |

---

## Documentation

- [Quick Start](docs/guides/quick-start.md) — first working Story in 30 minutes
- [What is GAAI?](docs/01-what-is-gaai.md) — the problem in full
- [Core Concepts](docs/02-core-concepts.md) — dual track, backlog, memory, skills, artefacts
- [Vibe Coder Guide](docs/guides/vibe-coder-guide.md) — fast daily workflow
- [Senior Engineer Guide](docs/guides/senior-engineer-guide.md) — governance, rules, CI
- [Skills Index](.gaai/core/skills/README.skills.md) — all 37 skills
- [Tool Compatibility](docs/reference/tool-compatibility.md) — Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf
- [Design Decisions](docs/architecture/design-decisions.md) — why GAAI is structured the way it is (ADRs + research basis)

---

ELv2 — see [LICENSE](LICENSE)

---

## ❤️ Support This Project

If you find this framework valuable, please consider showing your support. It is greatly appreciated!

- **[Sponsor on GitHub](https://github.com/sponsors/Fr-e-d)**
