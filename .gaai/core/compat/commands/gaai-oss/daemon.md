---
description: Launch or inspect the GAAI OSS Delivery Daemon
---

# /gaai-oss:daemon

Launch or inspect the GAAI OSS Delivery Daemon.

## Usage

```
/gaai-oss:daemon
/gaai-oss:daemon --start
/gaai-oss:daemon --start --max-concurrent 3
/gaai-oss:daemon --interval 15
/gaai-oss:daemon --status
/gaai-oss:daemon --stop
/gaai-oss:daemon --restart
/gaai-oss:daemon --dry-run
```

## Instructions for Claude Code

Parse the argument string passed to this command. Then run:

```bash
bash .gaai/core/scripts/daemon-start.sh <args>
```

Use the actual project root containing `.gaai/`. Pass all arguments as-is.

Before launching with `--start` or no action flag, verify daemon prerequisites using:

```bash
bash .gaai/core/scripts/daemon-setup.sh
```

If setup reports missing requirements, show the setup output and stop.

