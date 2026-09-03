---
description: Launch or inspect the GAAI Delivery Daemon
---

# /gaai-deliver

Launch or inspect the GAAI Delivery Daemon.

> **Alias:** `/gaai-deliver` and `/gaai-daemon` are identical. Both run the same daemon infrastructure. Use whichever you prefer.

## What This Does

Runs `.gaai/core/scripts/daemon-start.sh` — the unified daemon lifecycle wrapper that handles start, stop, status, and monitoring via tmux.

## Usage

```
/gaai-deliver                        # start daemon (30s poll, 1 slot) + open monitor
/gaai-deliver --start                # explicit start (same as default)
/gaai-deliver --start --max-concurrent 3  # 3 parallel deliveries + open monitor
/gaai-deliver --interval 15          # poll every 15s
/gaai-deliver --status               # show live monitoring dashboard (tmux)
/gaai-deliver --stop                 # graceful shutdown
/gaai-deliver --restart              # stop + start
/gaai-deliver --dry-run              # preview without launching
```

## Instructions for Claude Code

Parse the argument string passed to this command (may be empty).

Then run the daemon launcher using the Bash tool:

```bash
cd /path/to/project && .gaai/core/scripts/daemon-start.sh <args>
```

> **Privileged entry.** Invoke the script **directly** — it is an executable with a
> `#!/bin/bash -p` shebang. Prefixing the path with a plain `bash` interpreter is refused
> with `entry_authority_invalid`: a non-privileged interpreter has already applied
> `BASH_ENV` and imported exported functions before the script's first instruction.
> The only alternative is an absolute, verified Bash invoked `--noprofile --norc -p <script>`.

Use the actual project root (the directory containing `.gaai/`). Pass all arguments as-is to the script.

**`--status` flag:** run the script with `--status`. On macOS with tmux this opens a live monitoring dashboard in a new Terminal.app window. Display the output and stop.

**`--stop` flag:** run the script with `--stop`. Display the output and stop.

**`--start` or no action flag (default):** the script starts the daemon in a background tmux session (`gaai-daemon`) and automatically opens a second Terminal.app window with the live monitoring dashboard. Inform the user:
- Daemon runs in tmux session `gaai-daemon`
- Monitor opens automatically in a new Terminal.app window
- Each delivery runs in its own tmux session `gaai-deliver-<STORY_ID>`
- Logs: `.gaai/project/contexts/backlog/.delivery-logs/<STORY_ID>.log`
- Stop: `/gaai-deliver --stop` or `.gaai/core/scripts/daemon-start.sh --stop`
- Active deliveries keep running independently after daemon stop

**Prerequisite check:** before launching, verify `~/.claude/settings.json` contains `"skipDangerousModePermissionPrompt": true`. If missing, show the setup command and stop:

```bash
mkdir -p ~/.claude && echo '{ "skipDangerousModePermissionPrompt": true }' > ~/.claude/settings.json
```
