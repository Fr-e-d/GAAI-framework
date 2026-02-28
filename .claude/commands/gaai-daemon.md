# /gaai-daemon

Launch or inspect the GAAI Delivery Daemon.

## What This Does

Runs `.gaai/core/scripts/delivery-daemon.sh` with the options parsed from the command argument.

## Usage

```
/gaai-daemon                        # start daemon (30s poll, 1 slot)
/gaai-daemon --max-concurrent 2     # 2 parallel deliveries
/gaai-daemon --interval 15          # poll every 15s
/gaai-daemon --status               # show active / ready / exceeded
/gaai-daemon --dry-run              # preview without launching
```

## Instructions for Claude Code

Parse the argument string passed to this command (may be empty).

Then run the daemon using the Bash tool:

```bash
cd /path/to/project && .gaai/core/scripts/delivery-daemon.sh <args>
```

Use the actual project root (the directory containing `.gaai/`). Pass all arguments as-is to the script.

**`--status` flag:** run the script with `--status`, display the output, and stop. Do not keep a process running.

**All other invocations (including no argument):** the daemon runs as a blocking foreground process and polls continuously until `Ctrl+C`. Inform the user:
- On macOS: each delivery opens a new Terminal.app window
- Logs: `.gaai/project/contexts/backlog/.delivery-logs/<STORY_ID>.log`
- Monitor: `tail -f .gaai/project/contexts/backlog/.delivery-logs/<STORY_ID>.log`
- Stop: `Ctrl+C` (active deliveries keep running independently)

**Prerequisite check:** before launching, verify `~/.claude/settings.json` contains `"skipDangerousModePermissionPrompt": true`. If missing, show the setup command and stop:

```bash
mkdir -p ~/.claude && echo '{ "skipDangerousModePermissionPrompt": true }' > ~/.claude/settings.json
```
