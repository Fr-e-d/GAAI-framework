---
description: Search workspace memory — ranked entries with 1-hop graph context (cognitive guarantee)
---

# /gaai:ask

Semantic memory search. Returns the top-5 relevant memory entries plus 1-hop graph neighbors for each result — the cognitive guarantee view for interactive use.

## Usage

```
/gaai:ask <question>
/gaai:ask what is the auth model?
/gaai:ask how does workspace scoping work in memory.search?
```

## Instructions for Claude Code

1. Extract `<question>` from the command invocation (everything after `/gaai:ask `). Trim leading/trailing whitespace.
2. If `<question>` is empty, display:
   > Usage: `/gaai:ask <question>` — e.g., `/gaai:ask what is the auth model?`

   Stop.
3. Call the `memory.search` MCP tool with:
   ```json
   { "query": "<question>", "top_k": 5 }
   ```
4. If the result contains an `error` field, display it as-is and stop.
5. If the result `data` is an empty array or missing, display:
   > No memory entries found for: **`<question>`**

   Stop.
6. For each entry in `data` (already sorted by score descending), render the following block. Use exact formatting — no extra blank lines between entries:

   **`[memory: {entry_id}]`** {title if present, else topic} · score {score formatted to 2 decimal places}
   {oneliner if present, else content_preview truncated to 80 chars}
   Category: {category}{tags.length > 0 ? ` · Tags: ${tags.join(', ')}` : ''}
   {if neighbors array is non-empty, render on a new line:}
   ↳ {for each neighbor: `[{neighbor_id}]` *{edge_type}* — {oneliner}; separate multiple neighbors with ` · `}

   Separate entries with a blank line.

7. After all entries, display a summary line:
   `{data.length} result(s) for: "{question}"`

## Formatting notes

- **Cite tags:** `[memory: {entry_id}]` is the canonical citation format for workspace memory entries. Render it in bold so it stands out.
- **Clickable cross-refs:** When the terminal client supports hyperlinks (e.g. Claude Code in VS Code), render neighbor `neighbor_id` values that match file paths (e.g. `decisions/DEC-42.md`, `patterns/conventions.md`) as clickable relative links using markdown link syntax pointing to the path relative to the project root. For other clients, render as plain bracketed text `[{neighbor_id}]`.
- **Score display:** Round to 2 decimal places (e.g. `0.87`).
- **Oneliner fallback:** If `oneliner` is absent and `content_preview` is present, truncate `content_preview` at 80 characters and append `…` if truncated.
- **Neighbor edge type:** Render `edge_type` in italic (e.g. *references*, *RELATED_TO*, *amends*).
