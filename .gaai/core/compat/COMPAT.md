# GAAI Compatibility Layer

Thin adapter files for each supported AI coding tool.

The installer (`core/scripts/install.sh`) deploys the correct adapter to the right location in your project. You do not use these files directly.

---

## Delivery Runtime

GAAI tool compatibility follows a 3-tier model. This applies to both GAAI OSS and GAAI Cloud.

| Tier | Mode | Tool requirement |
|---|---|---|
| 1 | Discovery / governance (interactive) | Any AI coding tool or MCP client |
| 2 | Delivery interactive (manual) | Any AI coding tool or MCP client |
| 3 | Delivery autonomous (daemon) | Claude Code CLI (`claude` binary) |

Discovery (Tier 1) and Delivery interactive (Tier 2) work with any AI coding tool — Cursor, Windsurf, Codex CLI, Gemini CLI, or any tool with MCP support. The daemon (Tier 3) requires the Claude Code CLI (`claude` binary in PATH, local). This is a hard runtime dependency — not a preference or recommendation. Users without Claude CLI can still use GAAI for Discovery and manual Delivery (tiers 1–2). This requirement applies to both GAAI OSS and GAAI Cloud: even Cloud users need Claude CLI locally for autonomous delivery (the LLM runs client-side, not on the server).

---

## Compatibility Matrix

### Deep Integration (slash commands, auto-loaded context, SKILL.md auto-discovery)

| Tool | Adapter File | Deployed To | Status |
|---|---|---|---|
| Claude Code | `claude-code.md` | `CLAUDE.md` (project root) + `.claude/commands/` | ✅ Supported |

### AGENTS.md Compatible (full GAAI capability via manual activation prompts)

| Tool | Adapter File | Deployed To | Status |
|---|---|---|---|
| OpenCode | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Codex CLI | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Gemini CLI | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Antigravity | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Cursor | `cursor.mdc` | `.cursor/rules/gaai.mdc` | ✅ Supported |
| Windsurf | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Other tools | `windsurf.md` | Rename as needed | ⚠ Manual setup |

---

## How Adapters Work

Each adapter is a **thin wrapper** that points to the canonical GAAI files in `.gaai/`. No content is duplicated — adapters only provide tool-specific entry points.

The canonical source of truth is always in `.gaai/`:
- Rules → `.gaai/core/contexts/rules/`
- Skills → `.gaai/core/skills/`
- Agents → `.gaai/core/agents/`
- Memory → `.gaai/project/contexts/memory/`

---

## Manual Setup (Other Tools)

If your tool is not listed above:
1. Copy `windsurf.md` to your tool's equivalent of an `AGENTS.md` or system prompt file
2. Adjust the file paths if your project structure differs
3. The adapter content works with any tool that supports markdown-based instructions

---

## Changing Your AI Tool After Install

To switch to a different AI tool, re-run the installer with `--tool` set explicitly:

```bash
rm -rf /tmp/gaai
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai
bash /tmp/gaai/.gaai/core/scripts/install.sh --target /path/to/your/project --tool claude-code --yes
rm -rf /tmp/gaai
```

Replace `--tool claude-code` with `--tool cursor`, `--tool windsurf`, or `--tool other`.

Always pass `--tool` explicitly. Do not rely on auto-detection — it requires the tool's config directory to already exist in the target project.

There is no separate `deploy-adapter.sh` script. `core/scripts/install.sh` is the only installer.

---

## After Deployment

Once installed, your AI tool will:
1. Load the GAAI agent identity and authority model
2. Know which skills are available and how to invoke them
3. Respect the backlog as the authorization mechanism
4. Apply the governance rules from `.gaai/core/contexts/rules/`
