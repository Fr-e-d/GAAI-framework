---
description: Launch or inspect the GAAI OSS Delivery Daemon
---

# /gaai-oss:deliver

Alias for `/gaai-oss:daemon`. Use this when the user's intent is delivery rather than daemon administration.

## Instructions for Claude Code

Parse the argument string passed to this command and run:

```bash
.gaai/core/scripts/daemon-start.sh <args>
```

> **Privileged entry.** Invoke the script **directly** — it is an executable with a
> `#!/bin/bash -p` shebang. Prefixing the path with a plain `bash` interpreter is refused
> with `entry_authority_invalid`: a non-privileged interpreter has already applied
> `BASH_ENV` and imported exported functions before the script's first instruction.
> The only alternative is an absolute, verified Bash invoked `--noprofile --norc -p <script>`.

Use the actual project root containing `.gaai/`. Pass all arguments as-is.

