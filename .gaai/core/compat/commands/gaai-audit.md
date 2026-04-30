---
description: Show workspace audit log with filters and optional JSON export
---

# /gaai-audit

Display the workspace audit log as a chronological timeline with HMAC integrity status per event. Supports time-range filters, event-type and user filters, and JSON export for compliance reporting.

## Usage

```
/gaai-audit                                           # last 24 hours (default)
/gaai-audit --hours 48                                # last 48 hours
/gaai-audit --since 7d                                # last 7 days
/gaai-audit --since last-week                         # last 7 days (alias)
/gaai-audit --since 2026-04-01                        # from specific ISO date
/gaai-audit --since 2026-04-01 --until 2026-04-15     # date range
/gaai-audit --event-type memory.write                 # filter by event type
/gaai-audit --user alice@example.com                  # filter by actor
/gaai-audit --since 7d --event-type story.transition --export json  # combined
```

## Argument parsing

Parse all flags from the command invocation before calling the tool:

| Flag | Maps to | Notes |
|---|---|---|
| `--hours <N>` | `hours` | Ignored when `--since` is present |
| `--since <value>` | `since` | ISO date or relative (7d, 24h, 2w, last-week, last-month) |
| `--until <value>` | `until` | ISO date or relative; defaults to now |
| `--event-type <type>` | `event_type` | e.g. `memory.write`, `story.transition`, `audit_log.query` |
| `--user <email>` | `user` | Filter by actor identity |
| `--export json` | `export_format: "json"` | Machine-parseable output with HMAC proofs |

Default `action: "query"` always. Default `hours: 24` when no `--since` is provided.

## Instructions for Claude Code

1. Parse all flags from the command invocation (see table above).
2. Call the `gaai_audit_log` MCP tool with the resolved parameters:
   ```json
   {
     "action": "query",
     "hours": <N or omit when since is set>,
     "since": "<value or omit>",
     "until": "<value or omit>",
     "event_type": "<value or omit>",
     "user": "<value or omit>",
     "export_format": "<'table' or 'json' — omit if not specified>"
   }
   ```
3. If the result contains an error, display it as-is and stop.
4. If the result contains a `notice` field, display it prominently before the output.
5. Check `result.export_format`:

### When export_format is "table" (default)

Render `events` as a markdown table with columns:

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

After the table, display a summary line:
```
Showing <count> events | window: <from ISO> → <to ISO> | retention: <retention_days>d
```

If any filters were active (`result.filters.event_type`, `result.filters.user`), append:
```
Filters: event_type=<type>, user=<user>
```
(omit null filter fields)

If `count === 0`, display: `No audit events found in the requested window.`

### When export_format is "json"

Output a fenced JSON code block containing the full response object. The `event_hmac` field on each event is the HMAC-SHA256 integrity proof required for compliance verification:

```json
{
  "events": [
    {
      "id": 123,
      "timestamp": 1714512000000,
      "actor_user_id": "user@example.com",
      "event_type": "story.transition",
      "target": "ws_abc123",
      "verdict": "ALLOWED",
      "resource": "backlog",
      "integrity_status": "verified",
      "event_hmac": "sha256:abcd1234..."
    }
  ],
  "count": 1,
  "export_format": "json",
  "window": { "from_ms": 1714425600000, "to_ms": 1714512000000, "hours": 24, "retention_days": 90 },
  "filters": { "since": "7d", "until": null, "event_type": null, "user": null }
}
```

After the code block, display:
```
JSON export: <count> events | HMAC proofs included (<verified count> verified, <tampered count> tampered, <missing count> missing)
```
