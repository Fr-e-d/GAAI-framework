# Callibrate MCP Server

Callibrate exposes a **Model Context Protocol (MCP)** server over HTTP at `/mcp`.
It allows AI agents (Claude, GPT-4, etc.) to find and engage AI experts on behalf of prospects.

## Authentication

All MCP requests require a Callibrate Agent API key issued via the prospect dashboard.

```
Authorization: Bearer {64-hex-char-api-key}
```

API keys are managed at: `POST /api/prospects/:id/agent-keys`

## Endpoint

```
POST https://api.callibrate.io/mcp
Content-Type: application/json
Authorization: Bearer {api-key}
```

## Protocol

JSON-RPC 2.0 over HTTP. Single request/response per POST.

## Available Tools

### `callibrate_describe_project`

Extract structured requirements from a freetext project description.

**Input:**
```json
{
  "text": "I need to automate our lead scoring using n8n and Claude API...",
  "satellite_id": "optional-satellite-id"
}
```

**Output:** `ExtractionResponse` with `requirements`, `confidence`, `needs_confirmation`, `ready_to_match`.

---

### `callibrate_find_experts`

Run matching to find relevant AI experts for extracted requirements.

**Input:**
```json
{
  "requirements": { "challenge": "...", "skills_needed": ["n8n", "Python"] },
  "satellite_id": "optional-satellite-id",
  "freetext": "Original description for storage"
}
```

**Output:** `{ project_id, computed, top_matches: [{ match_id, score, score_breakdown }] }`

Note: `expert_id` is never returned — use `callibrate_request_reveal` to unlock profiles.

---

### `callibrate_request_reveal`

Request human confirmation to reveal an expert profile.

Sends a confirmation email to the prospect with Confirm/Refuse buttons.
The human-in-the-loop step ensures the prospect controls which experts are revealed.

**Input:**
```json
{
  "match_id": "uuid-from-find_experts",
  "project_summary": "Lead scoring automation with n8n"
}
```

**Output:** `{ match_id, status: "pending", message }`

Poll `GET /api/agent/reveal/:matchId/status` to check confirmation.

---

### `callibrate_request_booking`

Send a booking email to the prospect for a confirmed-reveal expert.

Requires the expert to have been revealed (status: "confirmed").

**Input:**
```json
{
  "match_id": "uuid-of-confirmed-reveal",
  "project_summary": "Lead scoring automation with n8n"
}
```

**Output:** `{ match_id, status: "booking_email_sent", booking_link }`

## Rate Limits

| Endpoint | Limit |
|---|---|
| `callibrate_describe_project` | 10 req/min |
| `callibrate_find_experts` | 5 req/min |
| `callibrate_request_reveal` | 3 req/hour |
| `callibrate_request_booking` | 3 req/hour |

## Claude Desktop Configuration

Add to your Claude Desktop `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "callibrate": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-http-bridge"],
      "env": {
        "MCP_HTTP_URL": "https://api.callibrate.io/mcp",
        "MCP_HTTP_HEADERS": "{\"Authorization\": \"Bearer YOUR_API_KEY\"}"
      }
    }
  }
}
```

## `.mcp.json` Example

For projects using the MCP SDK directly:

```json
{
  "servers": {
    "callibrate": {
      "type": "http",
      "url": "https://api.callibrate.io/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_API_KEY"
      }
    }
  }
}
```

## Human-in-the-Loop Design

All expert identity reveals and booking requests require explicit prospect approval via email.
The AI agent cannot reveal or book without the human prospect's active consent.

This is by design:
- Prospects control which experts their AI sees
- No expert profile is exposed without human confirmation
- All agent actions are logged and attributable to the API key
