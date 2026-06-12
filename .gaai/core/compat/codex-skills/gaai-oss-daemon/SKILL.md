---
name: gaai-oss:daemon
description: Start, stop, or inspect the GAAI OSS autonomous delivery daemon from Codex.
---

# GAAI OSS Daemon

Use this skill when the user asks to start, stop, restart, inspect, or dry-run the GAAI autonomous delivery daemon.

## Procedure

1. Read `.gaai/core/contexts/rules/base.rules.md`.
2. Read `.gaai/core/contexts/rules/orchestration.rules.md`.
3. Parse the user's daemon arguments, preserving flags such as `--start`, `--stop`, `--status`, `--restart`, `--dry-run`, `--interval`, and `--max-concurrent`.
4. If the user wants Codex to execute daemon phases, set `GAAI_DAEMON_EXECUTOR=codex`.
5. Run:

```bash
bash .gaai/core/scripts/daemon-start.sh <args>
```

Use the actual repository root containing `.gaai/`.

## Runtime Note

This Codex skill is a native entry point for controlling the daemon from Codex.

Daemon executor modes:

- Default: Claude Code (`claude`) for backwards compatibility.
- Codex: `GAAI_DAEMON_EXECUTOR=codex`, which runs Plan, Impl, and QA through `codex exec`.

Optional Codex runtime variables:

- `GAAI_CODEX_MODEL` — optional `codex exec --model` value.
- `GAAI_CODEX_SANDBOX` — sandbox mode; defaults to `workspace-write`.
- `GAAI_CODEX_EPHEMERAL` — defaults to `1`, passing `--ephemeral`.
- `GAAI_CODEX_IGNORE_USER_CONFIG` — defaults to `0`.
