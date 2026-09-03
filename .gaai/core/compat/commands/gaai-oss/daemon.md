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

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `GAAI_CLAUDE_PROXY_BASE_URL` | _(absent)_ | **Claude Code transport override.** When set, every `claude -p` subprocess spawned by the daemon receives `ANTHROPIC_BASE_URL=$GAAI_CLAUDE_PROXY_BASE_URL`. Controls where Claude Code connects; does not change which provider or model runs the work. Absent by default — users who do not set this variable are unaffected. |
| `GAAI_IMPL_BASE_URL` | _(absent)_ | **Secondary Impl provider intent.** URL of an Anthropic-compatible provider for the Implementation phase. Separate from `GAAI_CLAUDE_PROXY_BASE_URL`: this expresses *which provider* to use, not *how the subprocess connects*. In direct mode (no proxy), maps to `ANTHROPIC_BASE_URL` for Impl only. In proxy mode, forwarded alongside the proxy so the gateway can route upstream. |
| `GAAI_IMPL_AUTH_TOKEN` | _(absent)_ | Auth token for the secondary Impl provider. Required together with `GAAI_IMPL_BASE_URL` and `GAAI_IMPL_MODEL` to activate direct secondary routing. |
| `GAAI_IMPL_MODEL` | _(absent)_ | Model ID for the secondary Impl provider (e.g. `glm-4.6`). |

### Transport vs. provider intent

`GAAI_CLAUDE_PROXY_BASE_URL` and `GAAI_IMPL_*` are **orthogonal controls**, not alternatives:

- `GAAI_CLAUDE_PROXY_BASE_URL` sets the **transport endpoint** for every daemon-spawned `claude -p`. When present, all three phases (Plan, Impl, QA) route subprocess connections through it.
- `GAAI_IMPL_*` expresses **secondary Impl provider intent** — which provider and model should handle the Implementation phase. In proxy mode this intent is forwarded to the gateway so it can route upstream; it does not replace the proxy as the connection endpoint.

Setting both variables is valid and expected when using a local GAAI-LLM-Gateway or any Anthropic-compatible proxy alongside a secondary implementation provider.

When any proxy transport is active, the nested Claude Code subprocess automatically receives `--strict-mcp-config` to avoid a rejected MCP discovery payload on non-Anthropic shims. This is a function of transport only and has no opt-out.

## Instructions for Claude Code

Parse the argument string passed to this command. Then run:

```bash
.gaai/core/scripts/daemon-start.sh <args>
```

> **Privileged entry.** Invoke the script **directly** — it is an executable with a
> `#!/bin/bash -p` shebang. Prefixing the path with a plain `bash` interpreter is refused
> with `entry_authority_invalid`: a non-privileged interpreter has already applied
> `BASH_ENV` and imported exported functions before the script's first instruction.
> The only alternative is an absolute, verified Bash invoked `--noprofile --norc -p <script>`.

Use the actual project root containing `.gaai/`. Pass all arguments as-is.

Before launching with `--start` or no action flag, verify daemon prerequisites using:

```bash
.gaai/core/scripts/daemon-setup.sh
```

If setup reports missing requirements, show the setup output and stop.

