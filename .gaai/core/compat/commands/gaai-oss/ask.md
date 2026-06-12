---
description: Search local GAAI OSS project memory
---

# /gaai-oss:ask

Search the local GAAI OSS memory corpus in `.gaai/project/contexts/memory/`.

## Usage

```
/gaai-oss:ask <question>
/gaai-oss:ask what is the auth model?
/gaai-oss:ask which decisions constrain delivery automation?
```

## Instructions for Claude Code

1. Extract `<question>` from the command invocation. Trim leading/trailing whitespace.
2. If `<question>` is empty, display:
   > Usage: `/gaai-oss:ask <question>` — e.g., `/gaai-oss:ask what is the auth model?`

   Stop.
3. Read `.gaai/project/contexts/memory/index.md` first if it exists.
4. Use the internal `memory-search` skill from `.gaai/core/skills/cross/memory-search/SKILL.md` when available.
5. Search only local files under `.gaai/project/contexts/memory/`. Do not call GAAI Cloud MCP tools from this OSS command.
6. Return the top relevant memory files with short excerpts and clickable relative file links.
7. If no relevant memory files are found, display:
   > No local GAAI memory entries found for: **`<question>`**

   Stop.

