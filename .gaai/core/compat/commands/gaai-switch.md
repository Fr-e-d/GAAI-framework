---
description: Connect to GAAI Cloud or revert to local OSS mode
---

# /gaai-switch

Switch GAAI backend between local OSS mode and GAAI Cloud.

## Subcommands

- `/gaai-switch cloud` — Connect to GAAI Cloud: install MCP config, authenticate, migrate local contexts
- `/gaai-switch oss` — *(coming soon — E18S04)* Revert to local OSS mode

---

# /gaai-switch cloud

Connect this project to a GAAI Cloud workspace. Installs the cloud connector, authenticates via OAuth, and migrates your local memory, backlog, and artefacts to the cloud workspace.

## What This Does

1. Guards: verifies GAAI OSS is present; verifies cloud is not already active
2. Installs the gaai-cloud MCP server configuration
3. Guides you through OAuth 2.1 authentication (browser-based)
4. Confirms 32 governance tools are available
5. Migrates all entries from `contexts/memory/`, `contexts/backlog/`, and `contexts/artefacts/`
6. Archives the local `contexts/` folder as `contexts-pre-cloud-backup/`
7. Writes `backend: cloud` to `.gaai/project/config.yaml`

## When to Use

- You have been using GAAI OSS and want to upgrade to GAAI Cloud
- You want your backlog, memory, and artefacts backed by the cloud workspace
- You do NOT need to run `/gaai-update cloud` separately — this command includes the MCP install

## Prerequisites

- GAAI OSS is installed (`.gaai/` folder is present)
- You have a GAAI Cloud account at gaai.cloud
- `npx` is available (Node.js ≥ 18)

---

## Instructions for Claude Code

You are running `/gaai-switch cloud`. Follow every step in order. Do not skip steps. Do not proceed past a STOP point without explicit user confirmation.

---

### Guard 1 — Verify GAAI OSS is installed (AC1)

Check whether `.gaai/core/` exists in the project root.

If `.gaai/core/` is absent, stop immediately and tell the user:

> **Error:** GAAI OSS not detected — install via gaai.dev first.

Do not proceed.

---

### Guard 2 — Verify cloud is not already active (AC2)

Check whether `.claude/settings.json` exists and contains a `"gaai-cloud"` key under `mcpServers`.

Also check whether `.gaai/project/config.yaml` exists and contains `backend: cloud`.

If either condition is true, stop immediately and tell the user:

> **Error:** GAAI Cloud already active. Use `/gaai-update cloud` to update.

Do not proceed.

---

### Step 1 — Install MCP server configuration (AC3)

You will add the gaai-cloud MCP server to `.claude/settings.json` (project-level MCP config).

Read `.claude/settings.json`. If it does not exist, start with `{}`.

Add or merge the following into the `mcpServers` object:

```json
"gaai-cloud": {
  "command": "npx",
  "args": ["mcp-remote", "https://app.gaai.cloud/mcp"]
}
```

Write the updated `.claude/settings.json` back to disk.

Tell the user:

> MCP config written to `.claude/settings.json`. The gaai-cloud server points to `https://app.gaai.cloud/mcp` via mcp-remote.

---

### Step 2 — OAuth authentication (AC4)

Tell the user:

> **Action required:** Claude Code will now connect to the gaai-cloud MCP server. This will open a browser window for OAuth authentication.
>
> Please:
> 1. Reload Claude Code (or run `/mcp` to trigger MCP server initialization)
> 2. Complete the OAuth flow in your browser — log in and select your workspace
> 3. Return here and confirm authentication is complete

Wait for the user to confirm they have completed OAuth before proceeding.

---

### Step 3 — Confirm 32 tools are available (AC5)

After the user confirms OAuth is complete, instruct them to verify:

> In Claude Code, run `/mcp` and confirm that `gaai-cloud` is listed as connected with 32 tools available.
>
> If you see fewer than 32 tools or a connection error, stop here and check:
> - Your OAuth token is valid (try the browser flow again)
> - The MCP server URL `https://app.gaai.cloud/mcp` is reachable
>
> Confirm when you see "32 tools" before I continue.

Wait for the user to confirm 32 tools are visible before proceeding to migration.

If the user reports OAuth failure or cancellation, execute **Rollback: OAuth Failure** (AC15) below and stop.

---

### Step 4 — Migrate memory entries (AC6)

Scan `.gaai/project/contexts/memory/` recursively. Collect every YAML or Markdown file that represents a memory entry.

For each memory entry found:
1. Parse the file to extract: `category`, `topic`, `content`, `tags` (preserve all fields verbatim — do not rename or remap — DEC-17).
2. Call `gaai_memory_store` with these fields.
3. If the call succeeds, add the file path to the **migration success list**.
4. If the call fails, add the file path and error message to the **migration failure list**. Do not abort — continue to the next entry.

Keep a running count: `memory_migrated` (successes), `memory_failed` (failures).

---

### Step 5 — Migrate backlog items (AC7)

Read `.gaai/project/contexts/backlog/active.backlog.yaml`.

For each backlog item in the file:
1. Extract: `id`, `title`, `dependencies` (preserve verbatim).
2. Also extract: `status` (for transition step).
3. Call `gaai_backlog_add` with `id`, `title`, `dependencies`.
4. If the item has a status other than `draft` (e.g., `refined`, `in_progress`, `done`, `failed`, `deferred`), call `gaai_backlog_transition` to advance the item to its current status. Transition through intermediate states if required by the backlog lifecycle (`draft → refined → in_progress → done`).
5. If any call succeeds, add the item to the **migration success list**.
6. If any call fails, add the item ID and error message to the **migration failure list**. Do not abort — continue to the next item.

Keep a running count: `backlog_migrated`, `backlog_failed`.

---

### Step 6 — Migrate artefacts (AC8)

Scan `.gaai/project/contexts/artefacts/` recursively. Collect every artefact file (any file with YAML frontmatter containing `type: artefact`).

For each artefact found:
1. Parse the frontmatter to extract: `artefact_type`, `backlog_id` (or `related_backlog_id`), `skills_invoked`.
2. Extract the full content (frontmatter + body) as the `content` field.
3. Call `gaai_artefact_produce` with `type`, `content`, `backlog_id`, `skills_invoked`.
4. If the call succeeds, add to success list.
5. If the call fails, add to failure list. Do not abort.

Keep a running count: `artefacts_migrated`, `artefacts_failed`.

---

### Step 7 — Report migration progress (AC9, AC10)

After all three migration steps are complete, report:

> **Migration complete.**
>
> Migrated: {memory_migrated} memory entries, {backlog_migrated} backlog items, {artefacts_migrated} artefacts
>
> Failed: {memory_failed} memory entries, {backlog_failed} backlog items, {artefacts_failed} artefacts

If there are any failures, list each failed item:

> **Failed items (logged, not blocking):**
> - memory: `<file path>` — `<error>`
> - backlog: `<item id>` — `<error>`
> - artefact: `<file path>` — `<error>`

If total migrated across all three categories is 0 (zero items succeeded), execute **Rollback: Complete Migration Failure** (AC16) and stop.

---

### Step 8 — Archive local contexts (AC13)

**Scope protection assertion (AC11, AC12):** The following directories are NEVER read, modified, or deleted:
- `.gaai/project/skills/`
- `.gaai/project/agents/`
- `.gaai/project/workflows/`
- `.gaai/project/scripts/`
- `.gaai/project/hooks/`
- `.gaai/core/` (any subdirectory)

Only `.gaai/project/contexts/` is archived.

Run:

```bash
mv .gaai/project/contexts/ .gaai/project/contexts-pre-cloud-backup/
```

If `mv` fails (e.g., permissions), try:

```bash
cp -r .gaai/project/contexts/ .gaai/project/contexts-pre-cloud-backup/ && rm -rf .gaai/project/contexts/
```

Tell the user:

> Local `contexts/` archived to `contexts-pre-cloud-backup/`. Your data is preserved locally as a backup.

---

### Step 9 — Write backend flag (AC14)

Write `.gaai/project/config.yaml` with the following content:

```yaml
backend: cloud
```

If `.gaai/project/config.yaml` already exists (with a different value), overwrite it. This is the authoritative backend flag — it is not a collision.

Tell the user:

> `backend: cloud` written to `.gaai/project/config.yaml`. GAAI skills will now use MCP tools for all contexts operations.

---

### Completion

Tell the user:

> **GAAI Cloud switch complete.**
>
> Your project is now connected to GAAI Cloud. Memory, backlog, and artefacts are live in your cloud workspace.
>
> Your local data is preserved in `.gaai/project/contexts-pre-cloud-backup/`.
>
> Next: run `/gaai-status` to confirm the backlog is visible.

---

## Rollback: OAuth Failure (AC15)

If the user reports that OAuth failed or was cancelled before completing Step 3:

1. Remove the `gaai-cloud` entry from `.claude/settings.json`. If `mcpServers` becomes empty, remove the key entirely. Write the cleaned file back.
2. Do NOT archive `.gaai/project/contexts/`.
3. Do NOT write `.gaai/project/config.yaml`.
4. Tell the user:

> OAuth was not completed. The switch has been aborted cleanly.
> No MCP config remains. Your local contexts are unchanged.
> Run `/gaai-switch cloud` again when you are ready to retry.

---

## Rollback: Complete Migration Failure (AC16)

If Step 7 reports 0 total items migrated (all calls failed):

1. Remove the `gaai-cloud` entry from `.claude/settings.json`. Write the cleaned file back.
2. Do NOT archive `.gaai/project/contexts/` (it was not yet archived — Step 8 runs after Step 7).
3. Do NOT write `.gaai/project/config.yaml`.
4. Tell the user:

> Migration failed — 0 items were successfully migrated to the cloud workspace.
> The switch has been rolled back. MCP config removed. Local contexts unchanged.
> Check your cloud workspace permissions and try again.

---

## Notes for E18S04

This file is designed to accommodate the `/gaai-switch oss` subcommand in E18S04.  
The `## Subcommands` section at the top already lists `oss` as coming soon.  
E18S04 will add a `# /gaai-switch oss` section below the `cloud` section in this file.  
Do not add that section here.
