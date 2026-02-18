# GAAI — Governed Agentic AI Infrastructure

A `.gaai/` folder you drop into any project. Markdown + YAML + bash. No SDK. No package.

**GAAI turns agentic coding tools into reliable delivery systems.**

Works with Claude Code, OpenCode, Codex CLI, Gemini CLI, Antigravity, Cursor, Windsurf — or any AI coding tool that can read files.

---

## The Problem

You're using Claude Code, OpenCode, Codex CLI, Cursor, or another agentic coding tool. It writes code fast. Sometimes very good code. You ship more than before.

Then something starts breaking down — not the code. The process.

- You ask the agent to implement something. It does. But it also changes three things you didn't ask for.
- You start a new session. The agent has no idea what was decided last week. You re-explain. Again.
- The agent asks a clarifying question mid-implementation. You answer. It goes in a different direction than you meant.
- You have a rule: "always use the repository pattern for database access." The agent follows it sometimes.
- Three sessions in, you realize the feature that just shipped contradicts a decision you made two weeks ago.
- You're not sure what the agent is allowed to do on its own versus what it should ask you first.

None of these are bugs in the AI. They are symptoms of using a powerful execution engine without a governance layer.

An LLM is a V12 engine. Without the right steering system, speed becomes the problem.

---

## What GAAI Adds

Four questions AI tools don't answer by themselves:

**What is the agent allowed to do right now?**
The backlog. If it's not there with `status: refined`, the agent doesn't touch it.

**What does the agent know about this project?**
Explicit memory — never auto-loaded. Agents load exactly what they need.

**What counts as "done"?**
Acceptance criteria. QA is a hard gate: PASS or FAIL, no "close enough."

**Who decides what?**
You decide what to build. The agent decides how. Separate tracks, clear handoff.

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

**Discovery** — conversation with the Discovery Agent. Clarify what to build. Output: a Story with acceptance criteria in the backlog.

**Delivery** — autonomous execution. The agent runs until criteria pass. No improvisation. No scope drift.

**The backlog is the contract.** Nothing gets built that isn't in it.

---

## What GAAI Is (Technically)

A single `.gaai/` folder you drop into any project:

```
your-project/
└── .gaai/
    ├── agents/      ← Discovery + Delivery + Bootstrap agent specs
    ├── skills/      ← 31 pure execution units (one thing, explicit output)
    ├── contexts/    ← rules, memory, backlog, artefacts
    ├── workflows/   ← delivery loop, bootstrap, handoffs
    ├── scripts/     ← bash utilities (backlog scheduler, health check)
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
2. Every agent action must reference a skill.
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

---

MIT — see [LICENSE](LICENSE)
