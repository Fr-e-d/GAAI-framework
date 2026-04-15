---
description: Connect to GAAI Cloud or revert to local OSS mode
---

# /gaai-switch

Switch GAAI backend between local OSS mode and GAAI Cloud.

## Subcommands

- `/gaai-switch cloud` — Connect to GAAI Cloud: install MCP config, authenticate, migrate local contexts
- `/gaai-switch oss` — Revert to local OSS mode: export cloud data, restore local contexts

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

# /gaai-switch oss

Revert this project from GAAI Cloud back to local OSS mode. Exports all cloud data via MCP tools, writes it to local context files, removes the cloud MCP configuration, and sets the backend flag to local.

## What This Does

1. Guards: verifies cloud is active; verifies not already on OSS
2. Checks or installs `.gaai/core/` (OSS framework core)
3. Exports all memory entries from cloud to `contexts/memory/`
4. Exports all backlog items from cloud to `contexts/backlog/active.backlog.yaml`
5. Exports all artefacts from cloud to `contexts/artefacts/`
6. Reports export progress
7. Removes `gaai-cloud` from `.claude/settings.json`
8. Writes `backend: local` to `.gaai/project/config.yaml`

## When to Use

- You want to work offline or without a GAAI Cloud subscription
- You need to restore full local context files from cloud
- You are migrating to a different machine and want a local snapshot first

## Prerequisites

- GAAI Cloud is currently active (`.claude/settings.json` contains `gaai-cloud` under `mcpServers`)
- `git` is available (required if `.gaai/core/` must be installed from the OSS repository)

---

## Instructions for Claude Code

You are running `/gaai-switch oss`. Follow every step in order. Do not skip steps. If any export step fails before Step 7, execute the **Rollback: Export Failure** section and stop.

---

### Guard 1 — Verify cloud is active (AC1)

Check whether `.claude/settings.json` exists and contains a `"gaai-cloud"` key under `mcpServers`.

If the key is absent (file does not exist, or `mcpServers` is absent, or `gaai-cloud` is not present), stop immediately and tell the user:

> **Error:** GAAI Cloud not active. Already on OSS.

Do not proceed.

---

### Guard 2 — Verify backend flag is not already local

Check whether `.gaai/project/config.yaml` exists and contains `backend: local`.

If it does, stop immediately and tell the user:

> **Error:** GAAI Cloud not active. Already on OSS.

Do not proceed.

---

### Step 1 — Check or install `.gaai/core/` (AC2)

Check whether `.gaai/core/` exists in the project root.

**If `.gaai/core/` is absent** (user started on Cloud, never had OSS locally):

Tell the user:
> `.gaai/core/` not found. Installing GAAI OSS framework from the OSS repository.

Run:
```bash
git clone https://github.com/gaai-dev/gaai-oss.git /tmp/gaai-oss-install && bash /tmp/gaai-oss-install/.gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

If the clone or install fails (non-zero exit), execute **Rollback: Core Install Failure** (AC16) and stop.

Tell the user:
> `.gaai/core/` installed successfully.

**If `.gaai/core/` is already present** (user previously had OSS before switching to Cloud):

Tell the user:
> `.gaai/core/` found. Updating to latest version.

Run:
```bash
bash .gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

If the update fails (non-zero exit), continue with the existing `.gaai/core/` — do not abort. Log a warning:
> Warning: core update failed — proceeding with existing version. Run `/gaai-update oss` separately to retry.

---

### Step 2 — Export memory entries (AC3)

**Scope protection assertion (AC9):** The following directories are NEVER read, modified, or deleted during this command:
- `.gaai/project/skills/`
- `.gaai/project/agents/`
- `.gaai/project/workflows/`
- `.gaai/project/scripts/`
- `.gaai/project/hooks/`

Only `.gaai/project/contexts/` is written to.

**AC10 check:** If `.gaai/project/contexts-pre-cloud-backup/` exists, do NOT overwrite or delete it. All writes go to `.gaai/project/contexts/` only. If `contexts/` does not exist, create it.

Call `gaai_memory_retrieve` for each known memory category. The standard categories are: `project`, `decisions`, `patterns`, `constraints`, `goals`, `team`, `domain`. Also call with `category: all` or an equivalent wildcard if the tool supports it — to capture any non-standard categories.

For each memory entry returned:
1. Determine the file path: `.gaai/project/contexts/memory/{category}/{topic}.md`
2. Write the entry as a markdown file with YAML frontmatter:
   ```markdown
   ---
   category: {category}
   topic: {topic}
   tags: {tags}
   ---

   {content}
   ```
3. If the write succeeds, add to the memory success list.
4. If the write fails (disk error), add to the memory failure list. Do not abort — continue to the next entry.

Keep a running count: `memory_exported` (successes), `memory_failed` (failures).

If `gaai_memory_retrieve` itself returns a network or auth error, execute **Rollback: Export Failure** (AC15) and stop.

---

### Step 3 — Export backlog items (AC4)

Call `gaai_backlog_list` to retrieve all backlog items.

If the call returns a network or auth error, execute **Rollback: Export Failure** (AC15) and stop.

Reconstruct `.gaai/project/contexts/backlog/active.backlog.yaml` from the returned items. Each item is written as a YAML entry preserving all fields verbatim — id, title, status, dependencies, tags (DEC-17). Example structure:

```yaml
backlog:
  - id: {id}
    title: {title}
    status: {status}
    dependencies: {dependencies}
```

If the backlog directory does not exist, create it before writing.

Keep a count: `backlog_exported` (number of items written).

---

### Step 4 — Export artefacts (AC5)

Call `gaai_artefact_read` for each artefact. If the tool supports listing, call a list operation first to enumerate artefact IDs, then read each one individually.

If any `gaai_artefact_read` call returns a network or auth error, execute **Rollback: Export Failure** (AC15) and stop.

For each artefact returned:
1. Determine the file path from the artefact's `type`, `id`, or embedded path metadata. Write to `.gaai/project/contexts/artefacts/{type}/{id}.md` (or the path embedded in the artefact's content if present).
2. Write the full content (frontmatter + body) verbatim.
3. If the write succeeds, add to the artefact success list.
4. If the write fails (disk error), add to the artefact failure list. Do not abort.

Keep a running count: `artefacts_exported` (successes), `artefacts_failed` (failures).

---

### Step 5 — Report export progress (AC8)

After all three export steps are complete, report:

> **Export complete.**
>
> Exported: {memory_exported} memory entries, {backlog_exported} backlog items, {artefacts_exported} artefacts

If any write failures occurred, list them:

> **Write failures (data remains in cloud — not blocking):**
> - memory: `{file path}` — `{error}`
> - artefact: `{file path}` — `{error}`

---

### Step 6 — Remove gaai-cloud MCP configuration (AC6)

Read `.claude/settings.json`. Remove the `"gaai-cloud"` key from the `mcpServers` object. If `mcpServers` becomes empty after removal, remove the `mcpServers` key entirely. Write the updated file back to disk.

Tell the user:

> `gaai-cloud` removed from `.claude/settings.json`. The MCP server is no longer configured.

---

### Step 7 — Write backend flag (AC7)

Write `.gaai/project/config.yaml` with the following content:

```yaml
backend: local
```

If `.gaai/project/config.yaml` already exists, overwrite it.

Read `.gaai/project/config.yaml` back and confirm it contains `backend: local`.

Tell the user:

> `backend: local` confirmed in `.gaai/project/config.yaml`. GAAI skills will now use local context files.

---

### Completion

Tell the user:

> **GAAI OSS switch complete.**
>
> Your project is now running in local OSS mode. All cloud data has been exported to `.gaai/project/contexts/`.
>
> Exported: {memory_exported} memory entries, {backlog_exported} backlog items, {artefacts_exported} artefacts
>
> Next: run `/gaai-status` to confirm the local backlog is visible.

---

## Rollback: Export Failure (AC15)

If any of Steps 2, 3, or 4 returns a network or auth error from an MCP tool call:

1. Do NOT proceed to Step 6 (MCP config removal).
2. Do NOT proceed to Step 7 (config.yaml write).
3. Leave `.claude/settings.json` unchanged — the `gaai-cloud` entry remains active.
4. Leave `.gaai/project/config.yaml` unchanged (or absent if it did not exist before this command).
5. Partial files may have been written to `.gaai/project/contexts/` — they are incomplete. Inform the user.
6. Tell the user:

> **Export failed.** The switch has been aborted.
>
> The GAAI Cloud MCP configuration is still active — no data has been lost from the cloud.
>
> Partial local files may have been written to `.gaai/project/contexts/` — these are incomplete. Delete them before retrying.
>
> Check your network connection and authentication, then run `/gaai-switch oss` again.

---

## Rollback: Core Install Failure (AC16)

If Step 1 fails to install `.gaai/core/` from the OSS repository (non-zero exit from git clone or install script):

1. Do NOT proceed to any export steps.
2. Do NOT modify `.claude/settings.json`.
3. Do NOT modify `.gaai/project/config.yaml`.
4. Tell the user:

> **Error:** `.gaai/core/` installation failed. The switch has been aborted.
>
> Check your network connection and git access to the GAAI OSS repository, then run `/gaai-switch oss` again.
