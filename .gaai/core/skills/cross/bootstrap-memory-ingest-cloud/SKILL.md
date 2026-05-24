---
name: bootstrap-memory-ingest-cloud
description: Write structured memory entries to the Cloud workspace via gaai_memory.store MCP tool with source='bootstrap'. Loops over entries from bootstrap-llm-synthesis, calls the tool per entry, collects success/fail counts. Used as Stage 5 of the /gaai:bootstrap pipeline (Cloud path only).
license: ELv2
compatibility: Requires GAAI Cloud MCP connection with bootstrap_status=in_progress in the target workspace
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-BOOTSTRAP-MEMORY-INGEST-CLOUD-001
  updated_at: 2026-05-01
  status: stable
inputs:
  - synthesis_result          # output of bootstrap-llm-synthesis (entries[], parse_errors[])
outputs:
  - ingest_result             # { success_count, fail_count, errors[] }
skills_invoked:
  - SKILL-BOOTSTRAP-MEMORY-INGEST-CLOUD-001
---

# Bootstrap Memory Ingest — Cloud

## Purpose / When to Activate

Activate:
- As Stage 5 of the `/gaai:bootstrap` pipeline, **Cloud path only**
- After `bootstrap-llm-synthesis` (Stage 3) has produced validated memory entries
- When the workspace bootstrap_status is `in_progress` (set by the bootstrap orchestrator)
- Do NOT activate if the workspace bootstrap_status is anything other than `in_progress` — the server gate will refuse all writes

## Pre-conditions

Before activating, verify:
1. The GAAI Cloud MCP session is active
2. `synthesis_result.entries` is non-empty
3. workspace `bootstrap_status` = `in_progress` (checked implicitly by the server gate — no pre-flight check needed)

## Process Steps

### Loop: for each entry in synthesis_result.entries

1. **Call** `gaai_memory` MCP tool:
   ```json
   {
     "action": "store",
     "scope": "ws",
     "category": "<entry.category>",
     "topic": "<entry.topic>",
     "content": "<entry.content>",
     "tags": ["<entry.tags...>"],
     "source": "bootstrap"
   }
   ```

2. **On success** (`result.action` = `"created"` or `"updated"`):
   - Increment `success_count`
   - Log entry: `[OK] <category>/<topic> → <action>`

3. **On error** (response has `isError: true` or contains `code` field):
   - Increment `fail_count`
   - Capture error: `{ category, topic, code, error }`
   - Log entry: `[FAIL] <category>/<topic> → <code>: <error>`
   - **Continue to next entry** — per-entry errors never abort the loop

### After loop: produce ingest_result

```json
{
  "success_count": <N>,
  "fail_count": <M>,
  "errors": [
    { "category": "...", "topic": "...", "code": "...", "error": "..." }
  ]
}
```

Report summary to user:
- `"Bootstrap ingest complete: {success_count} written, {fail_count} failed"`
- If `fail_count > 0`: list the failed entries with their error codes

## Server-Side Gate Behavior (AC6)

The `source: 'bootstrap'` parameter activates the server-side bootstrap gate on each write:

| Condition | Server response |
|---|---|
| `bootstrap_status = 'in_progress'` AND category not blocked | Write proceeds (HTTP 200 / MCP success) |
| `bootstrap_status != 'in_progress'` | `code: BOOTSTRAP_NOT_ACTIVE` |
| `category = 'decisions'` (any topic) | `code: BOOTSTRAP_CATEGORY_BLOCKED` |
| `category = 'rules'` AND `topic` starts with `active.` | `code: BOOTSTRAP_CATEGORY_BLOCKED` |

**Blocked categories are not writeable by bootstrap.** Entries with `code: BOOTSTRAP_CATEGORY_BLOCKED` are per-entry failures — increment `fail_count` and continue.

## Audit Events (AC3)

For each successful write with `source: 'bootstrap'`, the server emits a `memory.bootstrap.ingest` audit event:
- `action`: `"memory.bootstrap.ingest"`
- `resource`: `"memory"`
- `target`: `"<category>/<topic>"`
- `verdict`: `"OK"`
- `details.entry_action`: `"created"` or `"updated"`

This event is emitted server-side — no client-side action required.

## Dedup Behavior (AC2)

Re-running bootstrap (re-calling this skill with the same category+topic) does NOT produce duplicates.
The HMAC-based dedup in `StructuredMemory.store()` treats a second write as an `updated` action on the existing row. The `ingest_result.success_count` will reflect this as a successful write.

## Non-Goals (Out of Scope)

- **LLM inference**: This skill does NOT call the LLM. Call `bootstrap-llm-synthesis` first.
- **Consent gate**: This skill does NOT show the consent overlay. That is a later pipeline stage.
- **Local OSS path**: This skill is Cloud-native only. For local-only bootstrap, entries are written to `.gaai/project/contexts/memory/` filesystem directly by the bootstrap orchestrator.
- **Error recovery**: Per-entry errors are logged and skipped. No retry logic. If `fail_count > 0`, the operator should review the errors and re-run if needed.
- **Status transition**: This skill does NOT change `bootstrap_status`. The orchestrator transitions `in_progress → done` after the consent stage.
