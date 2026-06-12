---
description: Update the local GAAI OSS framework
---

# /gaai-oss:update

Update the local GAAI Framework OSS core and redeploy the Claude Code adapter.

## Instructions for Claude Code

1. Verify `.gaai/core/scripts/install.sh` exists in the current project.
2. Ask for a source GAAI Framework OSS repository path only if the user wants to update from a different checkout.
3. If a source path is provided, run:

```bash
bash <source-repo>/.gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

4. If no source path is provided, redeploy from the local copy:

```bash
bash .gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

5. Report installer and health-check output.

This is OSS-only. Do not install or update GAAI Cloud MCP configuration from this command.

