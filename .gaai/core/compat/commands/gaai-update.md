---
description: Update the GAAI framework or switch AI tool adapter
---

# /gaai-update

Update the GAAI framework core or the GAAI Cloud connector.

## Subcommands

- `/gaai-update oss` — Update the local `.gaai/core/` framework from the OSS repository
- `/gaai-update cloud` — Update the GAAI Cloud MCP server configuration

---

## /gaai-update oss

### Guard — Verify OSS mode is active (AC11)

Before doing anything, check both conditions:

1. Check whether `.gaai/core/` exists in the project root.
2. Check whether `.claude/settings.json` contains a `"gaai-cloud"` key under `mcpServers`.

If `.gaai/core/` is absent, stop and tell the user:

> **Error:** `.gaai/core/` not found. GAAI OSS does not appear to be installed. Run `/gaai-switch oss` or install via gaai.dev first.

If `gaai-cloud` is present in `.claude/settings.json` (regardless of whether `.gaai/core/` exists), stop and tell the user:

> **Error:** Cannot update OSS while GAAI Cloud is active. Run `/gaai-switch oss` first.

Do not proceed if either condition triggers.

### Step 1 — Find the installer

Look for `.gaai/core/scripts/install.sh` in the current working directory. If it is not present, tell the user:

> **Error:** No `.gaai/core/scripts/install.sh` found. Ensure `.gaai/` is present in this project.

Do not proceed.

### Step 2 — Pull latest `.gaai/core/` (AC13)

Ask the user:

> "Provide the path to the GAAI OSS framework repo (e.g., `/tmp/gaai`), or press Enter to redeploy adapters from the existing local copy."

If a source repo path is provided, run:

```bash
bash <source-repo>/.gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

If no source repo path is provided (adapter redeploy only), run:

```bash
bash .gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

### Step 3 — Report outcome

If the update succeeded (exit code 0), confirm success and show the health check results.

If it failed, show the error output and suggest checking permissions or file integrity.

---

## /gaai-update cloud

### Guard — Verify cloud mode is active (AC12)

Before doing anything, check both conditions:

1. Check whether `.claude/settings.json` contains a `"gaai-cloud"` key under `mcpServers`.
2. Check whether `.gaai/project/config.yaml` exists and contains `backend: cloud`.

If `gaai-cloud` is absent from `.claude/settings.json`, stop and tell the user:

> **Error:** Cannot update Cloud connector while on OSS. Run `/gaai-switch cloud` first.

If `.gaai/project/config.yaml` is absent or contains `backend: local`, stop and tell the user:

> **Error:** Cannot update Cloud connector while on OSS. Run `/gaai-switch cloud` first.

Do not proceed if either condition triggers.

### Step 1 — Update MCP server configuration (AC14)

Read `.claude/settings.json`. Locate the `"gaai-cloud"` entry under `mcpServers`.

Ask the user:

> "Provide the updated MCP endpoint URL (press Enter to keep the current value), and/or any updated args."

Update the `gaai-cloud` entry with the new values provided. All other MCP server entries are preserved verbatim. Write the updated `.claude/settings.json` back.

Tell the user:

> `gaai-cloud` MCP configuration updated in `.claude/settings.json`. No project data was modified.
>
> Reload Claude Code (or run `/mcp`) to reconnect with the updated configuration.

### Step 2 — Report outcome

Tell the user:

> **GAAI Cloud connector updated.**
>
> Next: run `/mcp` to verify the updated connection, then `/gaai-status` to confirm your workspace data is accessible.
