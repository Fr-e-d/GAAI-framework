# GAAI Compatibility Layer

Thin adapter files for each supported AI coding tool.

`install.sh` deploys the correct adapter to the right location in your project. You do not use these files directly.

---

## Compatibility Matrix

| Tool | Adapter File | Deployed To | Status |
|---|---|---|---|
| Claude Code | `claude-code.md` | `CLAUDE.md` (project root) + `.claude/commands/` | ✅ Supported |
| Cursor | `cursor.mdc` | `.cursor/rules/gaai.mdc` | ✅ Supported |
| Windsurf / Generic | `windsurf.md` | `AGENTS.md` (project root) | ✅ Supported |
| Other tools | `windsurf.md` | Rename as needed | ⚠ Manual setup |

---

## How Adapters Work

Each adapter is a **thin wrapper** that points to the canonical GAAI files in `.gaai/`. No content is duplicated — adapters only provide tool-specific entry points.

The canonical source of truth is always in `.gaai/`:
- Rules → `.gaai/contexts/rules/`
- Skills → `.gaai/skills/`
- Agents → `.gaai/agents/`
- Memory → `.gaai/contexts/memory/`

---

## Manual Setup (Other Tools)

If your tool is not listed above:
1. Copy `windsurf.md` to your tool's equivalent of an `AGENTS.md` or system prompt file
2. Adjust the file paths if your project structure differs
3. The adapter content works with any tool that supports markdown-based instructions

---

## Changing Your AI Tool After Install

To switch to a different AI tool, re-run `install.sh` from the GAAI framework repo with `--tool` set explicitly:

```bash
rm -rf /tmp/gaai
git clone https://github.com/Fr-e-d/GAAI-framework.git /tmp/gaai
bash /tmp/gaai/install.sh --target /path/to/your/project --tool claude-code --yes
rm -rf /tmp/gaai
```

Replace `--tool claude-code` with `--tool cursor`, `--tool windsurf`, or `--tool other`.

Always pass `--tool` explicitly. Do not rely on auto-detection — it requires the tool's config directory to already exist in the target project.

There is no separate `deploy-adapter.sh` script. `install.sh` is the only installer.

---

## After Deployment

Once installed, your AI tool will:
1. Load the GAAI agent identity and authority model
2. Know which skills are available and how to invoke them
3. Respect the backlog as the authorization mechanism
4. Apply the governance rules from `.gaai/contexts/rules/`
