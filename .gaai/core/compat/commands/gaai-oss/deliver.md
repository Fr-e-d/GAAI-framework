---
description: Launch or inspect the GAAI OSS Delivery Daemon
---

# /gaai-oss:deliver

Alias for `/gaai-oss:daemon`. Use this when the user's intent is delivery rather than daemon administration.

## Instructions for Claude Code

Parse the argument string passed to this command and run:

```bash
bash .gaai/core/scripts/daemon-start.sh <args>
```

Use the actual project root containing `.gaai/`. Pass all arguments as-is.

