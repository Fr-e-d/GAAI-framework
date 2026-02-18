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
       Delivery Agent →     Plan. Implement. QA. Done.
              ↓
          Working code
```

**Discovery** — conversation with the Discovery Agent. Clarify what to build. Output: a Story with acceptance criteria in the backlog. Discovery reasons. It does not execute.

**Delivery** — autonomous execution. The agent runs until criteria pass. No improvisation. No scope drift. Delivery executes. It never decides scope or intent.

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
    ├── agents/      ← Discovery + Delivery + Bootstrap agent specs
    ├── skills/      ← 31 pure execution units (one thing, explicit output)
    ├── contexts/    ← rules, memory, backlog, artefacts
    ├── workflows/   ← delivery loop, bootstrap, handoffs, emergency rollback
    ├── scripts/     ← bash utilities (health check, backlog scheduler, bootstrap, sync, snapshot)
    └── compat/      ← thin adapters for Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf
```

**No SDK. No npm package. No pip install. No external services.**
Markdown + YAML + bash. Readable by humans and any AI tool.

---

## 30-Second Install

```bash
git clone https://github.com/your-org/gaai-framework.git
cd gaai-framework && ./install.sh
```

The installer asks which AI tool you use, copies `.gaai/` into your project, and deploys the right adapter.

Or manually: copy `.gaai/` into your project root. Done.

---

## Five Rules (Non-Negotiable)

1. Every execution unit must be in the backlog.
2. Every agent action must reference a skill. If a skill appears to think, it is wrongly designed.
3. Memory is explicit — agents select what to load, never auto-loaded.
4. Artefacts document — they do not authorize. Only the backlog authorizes.
5. When in doubt, stop and ask.

---

## Tool Compatibility

| Tool | Adapter |
|------|---------|
| Claude Code | `CLAUDE.md` + `.claude/commands/` (slash commands) |
| OpenCode | `AGENTS.md` |
| Codex CLI | `AGENTS.md` |
| Gemini CLI | `AGENTS.md` |
| Antigravity | `AGENTS.md` |
| Cursor | `.cursor/rules/*.mdc` |
| Windsurf | `AGENTS.md` |
| Any other | Read `.gaai/GAAI.md` directly |

One canonical source (`.gaai/`). Thin adapters per tool. No duplication.

Claude Code has the deepest integration: slash commands, auto-loaded CLAUDE.md, SKILL.md auto-discovery. All other tools work via `AGENTS.md` or direct file access.

---

## Fork & Own

This is not a library you pin a version to. It is a design pattern expressed in files.

Fork or clone. Run `install.sh`. Adapt the rules, memory, and skills to your project. The `.gaai/` folder is yours.

---

## Documentation

- [Quick Start](docs/guides/quick-start.md) — first working Story in 30 minutes
- [What is GAAI?](docs/01-what-is-gaai.md) — the problem in full
- [Core Concepts](docs/02-core-concepts.md) — dual track, backlog, memory, skills, artefacts
- [Vibe Coder Guide](docs/guides/vibe-coder-guide.md) — fast daily workflow
- [Senior Engineer Guide](docs/guides/senior-engineer-guide.md) — governance, rules, CI
- [Skills Index](.gaai/skills/README.skills.md) — all 31 skills
- [Tool Compatibility](docs/reference/tool-compatibility.md) — Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf
- [Design Decisions](docs/architecture/design-decisions.md) — why GAAI is structured the way it is (ADRs + research basis)

---

MIT — see [LICENSE](LICENSE)
