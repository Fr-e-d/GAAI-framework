---
name: gaai-oss:ask
description: Search local GAAI OSS project memory without using GAAI Cloud MCP tools.
---

# GAAI OSS Ask

Use this skill when the user asks a question that should be answered from local GAAI OSS project memory.

## Procedure

1. Read `.gaai/project/contexts/memory/index.md` if present.
2. Read `.gaai/core/skills/cross/memory-search/SKILL.md` when available.
3. Search only local files under `.gaai/project/contexts/memory/`.
4. Do not call GAAI Cloud MCP tools from this OSS skill.
5. Return the relevant memory file paths, short excerpts, and the answer.

If no relevant memory files are found, say so clearly and continue from codebase context only if appropriate.

