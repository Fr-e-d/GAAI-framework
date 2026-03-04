# Getting Started

## Prerequisites

- bash 3.2+ (macOS default is fine)
- git
- An AI coding tool: Claude Code, Cursor, or Windsurf

---

## Installation

From your project root — one command:

```bash
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai && \
  bash /tmp/gaai/install.sh --target . --tool claude-code --yes && \
  rm -rf /tmp/gaai
```

Replace `--tool claude-code` with `--tool cursor` or `--tool windsurf` as needed.

For an interactive install (tool selector prompt):

```bash
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai && \
  bash /tmp/gaai/install.sh --target . && \
  rm -rf /tmp/gaai
```

The installer will:
1. Check prerequisites
2. Ask which AI tool you use (interactive mode) or use `--tool` flag
3. Copy `.gaai/` into your project
4. Deploy the right tool adapter (CLAUDE.md, .mdc file, or AGENTS.md)
5. Run a health check

That's it. Your project now has a `.gaai/` folder.

---

## First Session

> **Claude Code users:** Restart your Claude Code session after install. Slash commands (`/gaai-bootstrap`, `/gaai-discover`, etc.) are loaded at startup — they won't appear in an already-open session.

### Existing project? Run Bootstrap first.

The Bootstrap Agent scans your codebase and builds project memory.

**Claude Code:** `/gaai-bootstrap`

**Cursor / Windsurf / Other:** Ask your AI:
> "Read `.gaai/README.md` and bootstrap this project."

Bootstrap will:
1. Scan your codebase
2. Extract architecture decisions
3. Build memory files in `.gaai/project/contexts/memory/`
4. Normalize existing conventions into rules

When it's done, you'll see: `✅ Bootstrap PASS — context ready.`

---

### New project? Start with Discovery.

No existing codebase to scan. Go straight to Discovery.

Fill in `.gaai/project/contexts/memory/project/context.md` with your project's basic context.

Then activate Discovery:

**Claude Code:** `/gaai-discover`

**Other tools:** Tell your AI:
> "Read `.gaai/core/agents/discovery.agent.md`. I want to build [your idea]. Help me create the first Epics and Stories."

---

## Your First Delivery

Once you have Stories in the backlog (status: `refined`), run the Delivery Loop:

**Claude Code:** `/gaai-deliver`

**Other tools:** Tell your AI:
> "Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`. Execute the next ready backlog item."

The Delivery Agent will:
1. Pick the highest-priority refined Story
2. Build an execution plan
3. Implement it
4. Run QA
5. Report PASS or FAIL

---

## Check Your Status

At any time:

**Claude Code:** `/gaai-status`

**Other tools:** Ask:
> "Read `.gaai/project/contexts/backlog/active.backlog.yaml` and give me a summary of what's ready to deliver."

---

## What's Next

- Add more Stories through Discovery
- Customize rules in `.gaai/project/contexts/rules/`
- Review the skills catalog: `.gaai/core/skills/README.skills.md`
- Read [Core Concepts](02-core-concepts.md) for deeper understanding

→ [Quick Start](guides/quick-start.md) for a concrete walkthrough
→ [Senior Engineer Guide](guides/senior-engineer-guide.md) for governance customization
