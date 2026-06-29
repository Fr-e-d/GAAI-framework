# GAAI OSS Framework — Codex Instructions

> This file is deployed to project root as `AGENTS.md` by the GAAI installer
> when `--tool codex` is selected.

## What This Is

This project uses GAAI Framework OSS from `.gaai/`.

Keep these layers separate:

- `.gaai/core/` is the reusable OSS framework and may be auto-synced upstream.
- `.gaai/project/` is this project's governed memory, backlog, artefacts, hooks, and local state.
- Product or application source code outside `.gaai/` belongs to the host repository, not to the OSS framework.

Do not confuse GAAI Framework OSS with GAAI Cloud. Cloud integrations, MCP connectors, subscriptions, or `/gaai:*` commands are product concerns and do not belong in the OSS compatibility adapter.

## Always Load

At the start of governed work, read:

1. `.gaai/core/GAAI.md`
2. `.gaai/core/contexts/rules/base.rules.md`
3. `.gaai/project/contexts/memory/index.md` when present

Then activate the right GAAI agent:

- Bootstrap: `.gaai/core/agents/bootstrap.agent.md`
- Discovery: `.gaai/core/agents/discovery.agent.md`
- Delivery: runs as 3-phase daemon-spawn per `orchestration.rules.md §Branch Rules`

For orchestration, branch, backlog, and handoff details, read:

- `.gaai/core/contexts/rules/orchestration.rules.md`

## Native Codex Entry Points

The installer deploys repo-scoped Codex skills to `.agents/skills/`:

- `$gaai-oss:ask`
- `$gaai-oss:bootstrap`
- `$gaai-oss:discover`
- `$gaai-oss:deliver`
- `$gaai-oss:daemon`
- `$gaai-oss:status`
- `$gaai-oss:update`

These are Codex-native wrappers. They are not GAAI internal skills. The internal GAAI skill catalogue remains in `.gaai/core/skills/` and is invoked through GAAI agents and workflows.

## Operating Modes

Use Bootstrap when initializing or refreshing project understanding.

Use Discovery when clarifying intent or creating governed artefacts such as PRDs, Epics, Stories, decisions, or backlog changes.

Use Delivery when implementing validated backlog Stories. Delivery is backlog-first: do not invent execution scope outside authorized Stories unless the human explicitly asks for a narrow direct change.

For autonomous daemon delivery with Codex headless execution, set `GAAI_DAEMON_EXECUTOR=codex` before starting the daemon. The daemon then runs Plan, Impl, and QA with `codex exec`; the default remains Claude Code for backwards compatibility.

Use Framework Maintenance when changing `.gaai/core/`. Keep changes generic, project-agnostic, and compatible with OSS sync.

## Codex Discipline

Prefer native Codex skills over ad hoc prompts when a matching `$gaai-oss:{tool}` skill exists.

When working inside `.gaai/core/`, preserve the distinction between:

- GAAI internal skills: `.gaai/core/skills/`
- Codex compatibility skills: `.gaai/core/compat/codex-skills/`
- Claude Code slash commands: `.gaai/core/compat/commands/`

Do not move Codex compatibility wrappers into `.gaai/core/skills/`.
