---
description: Show workspace audit log with integrity proof (last 24h default)
---

# /gaai-audit

Display the workspace audit log as a chronological timeline with HMAC integrity status per event.

## Usage

```
/gaai-audit              # last 24 hours (default)
/gaai-audit --hours 48   # last 48 hours
/gaai-audit --hours 168  # last 7 days
```

## Instructions for Claude Code

1. Parse any `--hours <N>` argument from the command invocation. Default to 24 if not provided.
2. Call the `gaai_audit_log` MCP tool with:
   ```json
   { "action": "query", "hours": <N> }
   ```
3. If the result contains an error, display it as-is and stop.
4. If the result contains a `notice` field, display it prominently before the table.
5. Render `events` as a markdown table with columns:
   | Timestamp (UTC) | Actor | Event Type | Target | Verdict | Integrity |
   |---|---|---|---|---|---|
   - `Timestamp`: format `events[i].timestamp` as ISO-8601 (e.g. `new Date(ts).toISOString()`)
   - `Actor`: `events[i].actor_user_id`
   - `Event Type`: `events[i].event_type`
   - `Target`: `events[i].target ?? "—"`
   - `Verdict`: `events[i].verdict`
   - `Integrity`: `events[i].integrity_status` — render as:
     - `verified` → ✓ verified
     - `tampered` → ⚠ tampered
     - `missing` → – missing
6. After the table, display a summary line:
   `Showing <count> events over the last <hours>h (retention: <retention_days>d)`
7. If `count === 0`, display: `No audit events found in the requested window.`
