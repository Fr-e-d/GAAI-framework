---
name: gaai-oss:update
description: Update or redeploy the local GAAI OSS framework and Codex adapter without invoking GAAI Cloud behavior.
---

# GAAI OSS Update

Use this skill when the user wants to update `.gaai/core/` from a local GAAI Framework OSS checkout or redeploy the Codex adapter in the current project.

## Procedure

1. Verify `.gaai/core/scripts/install.sh` exists in the current project.
2. Ask for a source GAAI Framework OSS repository path only if the user wants to update from a different checkout.
3. If a source path is provided, run:

```bash
bash <source-repo>/.gaai/core/scripts/install.sh --target . --tool codex --yes
```

4. If no source path is provided, redeploy from the local copy:

```bash
bash .gaai/core/scripts/install.sh --target . --tool codex --yes
```

5. Report installer and health-check output.

This is OSS-only. Do not install or update GAAI Cloud MCP configuration from this skill.
