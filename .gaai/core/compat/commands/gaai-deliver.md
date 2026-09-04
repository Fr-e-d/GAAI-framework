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
/gaai-deliver                        # start daemon (30s poll, 1 slot)
/gaai-deliver --start                # explicit start (same as default)
/gaai-deliver --start --max-concurrent 3  # 3 parallel deliveries
/gaai-deliver --interval 15          # poll every 15s
/gaai-deliver --status               # read-only lifecycle status (mutates nothing)
/gaai-deliver --monitor              # attach the monitoring dashboard (tmux)
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

**`--status` flag:** run the script with `--status`. This is a completed read-only lifecycle subprotocol — it reports state (socket, session, credential mode, daemon pid, verdict) and mutates nothing. Display the output and stop.

**`--monitor` flag:** run the script with `--monitor`. It completes the read-only status subprotocol first, then attaches a presentation UI in a **distinct** tmux socket and session, which is never daemon authority or evidence. Requires a terminal.

**`--stop` flag:** run the script with `--stop`. Display the output and stop.

**`--start` or no action flag (default):** the script verifies the pre-provisioned daemon home is clean, registered and exact-current, then launches the daemon inside a **private** tmux server whose socket is digest-bound to the physical git common directory. It does not open any window by itself. Inform the user:
- Daemon runs in a session named `gaai-daemon-<label>` on that private server, not on the default tmux server
- The monitor does NOT open automatically — attach it with `.gaai/core/scripts/daemon-start.sh --monitor`
- Each delivery runs in its own tmux session `gaai-deliver-<STORY_ID>`
- Logs: `.gaai/project/contexts/backlog/.delivery-logs/<STORY_ID>.log`
- Stop: `/gaai-deliver --stop` or `.gaai/core/scripts/daemon-start.sh --stop`
- Active deliveries keep running independently after daemon stop

**Prerequisite check:** before launching, verify `~/.claude/settings.json` contains `"skipDangerousModePermissionPrompt": true`. If missing, show the setup command and stop:

```bash
mkdir -p ~/.claude && echo '{ "skipDangerousModePermissionPrompt": true }' > ~/.claude/settings.json
```
