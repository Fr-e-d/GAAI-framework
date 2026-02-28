# Migration Guide

**Moving to GAAI from ad-hoc prompting, other frameworks, or existing project setups.**

---

## From Ad-Hoc Prompting

This is the most common starting point. You've been prompting your AI directly — no structure, no backlog, no explicit memory.

### What changes

| Before | After |
|---|---|
| "Write me a login page" | Discovery turns intent into Stories first |
| Context in the chat window | Memory in `.gaai/project/contexts/memory/` |
| AI decides what to build | Backlog authorizes what gets built |
| Prompt → code directly | Prompt → Discovery → Backlog → Delivery |
| Decisions lost between sessions | Decisions in `memory/decisions/_log.md` |

### How to migrate

**Step 1 — Install GAAI**

```bash
bash install.sh
```

**Step 2 — Run Bootstrap**

The Bootstrap Agent reads your existing codebase and builds initial memory. This is the hardest manual step with ad-hoc prompting — there may be no existing structure to extract from.

If Bootstrap finds little to extract, fill in these files manually:
- `contexts/memory/project/context.md` — what the project is, who it's for
- `contexts/memory/patterns/conventions.md` — how code is written in this project (naming, testing, structure)
- `contexts/memory/decisions/_log.md` — major decisions already made

**Step 3 — Formalize your backlog**

If you have in-progress work, capture it as backlog items. They don't need artefacts immediately — start with `status: refined` and good acceptance criteria.

**Step 4 — Run your first Delivery loop**

Pick one item. `/gaai-deliver`. See what happens.

You'll notice the agent asks clarifying questions rather than assuming. That's the framework working.

---

## From Cursor Rules / Custom System Prompts

If you've been managing AI behavior through `.cursorrules`, `.cursor/rules/`, custom system prompts, or large context files:

### What changes

Your rules become explicit files in `.gaai/core/contexts/rules/`. The advantage: they're versioned, reviewable, and structured with clear loading priority.

### How to migrate

**Step 1 — Install GAAI**

**Step 2 — Extract your rules**

Your existing rules file may be a mix of:
- Project context (→ goes to `contexts/memory/project/context.md`)
- Coding conventions (→ goes to `contexts/memory/patterns/conventions.md`)
- Governance rules (→ goes to a custom `contexts/rules/project.rules.md`)
- Tool instructions (→ stays in the compat layer)

Have your AI help: "Read my existing rules file and categorize each rule by whether it belongs in memory, rules, or compat adapter. Then help me move it."

**Step 3 — Deploy the compat adapter**

Copy the right adapter from `.gaai/core/compat/` to replace your old config:
- Cursor: `.gaai/core/compat/cursor.mdc` → `.cursor/rules/gaai.mdc`
- Claude Code: `.gaai/core/compat/claude-code.md` → `CLAUDE.md`

**Step 4 — Bootstrap and verify**

Run Bootstrap. It will validate that the extracted memory and rules are consistent.

---

## From Another AI Framework

If you're migrating from a framework that uses agents, workflows, or structured prompts (LangChain, AutoGen, CrewAI, or similar):

### Key conceptual shifts

| Other frameworks | GAAI |
|---|---|
| SDK/library | File-based (Markdown + YAML) |
| Dynamic agent routing | Explicit backlog authorization |
| Auto-memory / RAG | Manual, agent-selected memory |
| Framework executes agents | AI tool executes against framework files |
| Built for services | Built for SDLC |

GAAI is not a runtime. It has no orchestration layer. The AI tool you use (Claude Code, Cursor) reads the files and follows the structure.

### Migration approach

1. Install GAAI in your project
2. Run Bootstrap — extract what architecture decisions exist
3. Map your existing agent workflows to GAAI's agents:
   - Planning agents → Discovery Agent
   - Execution agents → Delivery Agent
   - Memory systems → `contexts/memory/`
4. Convert your task backlog to GAAI backlog YAML format
5. Drop your old framework configuration

---

## What You Don't Need to Migrate

GAAI is additive. You don't change:
- Your tech stack
- Your test framework
- Your CI/CD (though you can add GAAI validation)
- Your branching model (though there are recommendations)
- Your code style (just capture it in `memory/patterns/conventions.md`)

GAAI wraps around what you already have.

---

## Common Migration Pitfalls

**Trying to be perfect before starting.**
You don't need complete memory files before your first Delivery session. Start with `memory/project/context.md` half-filled. The Delivery Agent will surface gaps as it works.

**Adding GAAI to a project with no tests.**
GAAI's QA gate is only as strong as your test suite. If there are no tests, the agent will flag this. Fix the test gap first, or update acceptance criteria to make the test expectation explicit.

**Rules that contradict each other.**
If you migrate rules from multiple places, conflicts are likely. Run the `rules-normalize` skill after migration to detect and resolve them.

**Expecting immediate autonomy.**
The first few sessions will have more escalations than later. This is the agent learning your project's constraints. Fill in decisions and patterns as they surface. After 3-5 sessions, escalations drop significantly.

---

→ [Getting Started](../03-getting-started.md)
→ [Quick Start](quick-start.md)
→ [Senior Engineer Guide](senior-engineer-guide.md)
