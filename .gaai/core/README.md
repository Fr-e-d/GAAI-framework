# .gaai/core/ — GAAI Framework Engine

**New to GAAI?** → [Start with the Quick Start guide](docs/guides/quick-start.md) — first working Story in 30 minutes.

---

## 4 Commands to Run Your AI-Assisted SDLC

| Command | What it does |
|---|---|
| `/gaai-bootstrap` | Initialize project context on an existing codebase |
| `/gaai-discover` | Activate Discovery Agent — clarify intent, create Stories |
| `/gaai-deliver` | Deliver the next refined Story in the current session (interactive or headless) |
| `/gaai-daemon` | Start the Delivery Daemon — polls backlog, delivers Stories autonomously via tmux |
| `/gaai-status` | Show backlog and memory state |

`/gaai-deliver` delivers a single Story in the current context. `/gaai-daemon` launches a background daemon that polls the backlog and delivers multiple Stories in parallel (each in its own tmux session).

Discovery works with any AI coding tool or MCP client (Claude Code, Cursor, Windsurf, and more). The daemon explicitly supports two local headless executors: Claude Code CLI (`claude` binary in PATH, the backwards-compatible default) or Codex CLI (`codex` binary in PATH, via `GAAI_DAEMON_EXECUTOR=codex`). An unknown or unavailable executor stops before governed work begins with an actionable error. See `compat/COMPAT.md` for the full 3-tier compatibility model.

That's the day-1 surface area. Everything else (skills, rule files, workflows) is loaded on demand — you never interact with it directly.

**Information preservation:** When Discovery delegates work to sub-agents, it compiles a *Discovery Session Brief* — a structured extraction of all conversation intelligence (decisions, observations, trade-offs, constraints). This prevents context loss between agents. See [`agents/discovery.agent.md`](agents/discovery.agent.md).

---

`core/` contains the framework engine: agents, skills, rules, and workflows. These files are shared across all GAAI-powered projects and are managed by the installer. **Do not edit files in `core/` directly** — your changes will be overwritten the next time you update GAAI.

To update the framework, run the installer with the new version:

```bash
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```

Customization lives in `project/` — add your rules, skills, agents, and memory there.

```
.gaai/
├── core/      ← Framework engine (managed by installer — do not edit)
└── project/   ← Your customizations: memory, backlog, skills, rules
```

---

## Delivery Daemon

If your project uses git with a `staging` branch, the **Delivery Daemon** delivers refined Stories autonomously:

1. One-time setup: `.gaai/core/scripts/daemon-setup.sh` — invoke it **directly**; a plain `bash <script>` entry is refused (`entry_authority_invalid`). This is also the only command that may provision or update the daemon home worktree.
2. `/gaai-daemon` — starts the daemon (default: 3 slots, auto-opens monitoring)
3. `/gaai-daemon --stop` — graceful shutdown

Override concurrency: `/gaai-daemon --max-concurrent 5`

The daemon polls for `refined` stories and delivers them in parallel via tmux — each delivery runs in its own tmux session with real-time visibility.
Full reference: see `GAAI.md` → "Branch Model & Automation".

**Runtime requirement:** The daemon explicitly supports two local headless executors: Claude Code CLI (`claude` binary in PATH, the backwards-compatible default) or Codex CLI (`codex` binary in PATH, via `GAAI_DAEMON_EXECUTOR=codex`). An unknown or unavailable executor stops before governed work begins with an actionable error. Discovery and manual Delivery work with any AI coding tool; this requirement applies only to autonomous delivery.

> **Tested on:** macOS (Apple Silicon). Linux (Ubuntu) is **expected** to work and
> is exercised by the hosted continuous-integration matrix once that lane has run on
> a published candidate; until then it is not claimed as validated. WSL is **not** claimed — no WSL run exists. Native
> Windows (Git Bash / MSYS2 / Cygwin) is explicitly unsupported and the daemon
> refuses to start there.

---

## Offline YAML Runtime

Every authority-bearing YAML operation in the Framework executes
repository-controlled parser bytes. There is no ambient dependency, nothing to
install, and no download, package-manager call or fallback anywhere in the
runtime, the helper, the builder or any consumer.

| File | What it is |
|---|---|
| `vendor/pyyaml/6.0.3/pyyaml-runtime.pyz` | the deterministic, non-executable, pure-Python parser archive |
| `vendor/pyyaml/6.0.3/PROVENANCE.json` | the closed source, content, rebuild and output manifest |
| [`vendor/pyyaml/6.0.3/LICENSE`](vendor/pyyaml/6.0.3/LICENSE) | the upstream licence of the vendored component, shipped verbatim |
| `scripts/build-yaml-runtime.sh` | the offline, digest-verified, deterministic builder |
| `scripts/lib/yaml-runtime.sh` | the only supported entry for a YAML program |

**Licence.** GAAI Framework is source-available under the Elastic License 2.0
(ELv2) — see the `LICENSE` file at the root of this distribution for the full
text. The vendored PyYAML component is distributed under its own MIT licence,
shipped verbatim at [`vendor/pyyaml/6.0.3/LICENSE`](vendor/pyyaml/6.0.3/LICENSE);
that MIT licence applies only to that component and does not relicense the
Framework.

**Supported interpreters.** The runtime admits final CPython **3.12, 3.13 and
3.14** only. Older, pre-release and non-CPython interpreters are rejected even
where the upstream parser could import on them — the upstream compatibility
metadata recorded in the manifest is a fact about the component, never a widening
of this boundary.

Where the boundary looks when no interpreter is declared (these are the
directories it probes, not a claim that any of them is installed or qualifies):

- macOS — `/opt/homebrew/bin`, `/usr/local/bin`,
  `/Library/Frameworks/Python.framework/Versions/3.X/bin`, `/usr/bin`
- Linux — `/usr/bin`, `/bin`, `/usr/local/bin`

A discovered interpreter must be a native executable owned by root or by you,
with no group or other write permission on it or on any directory above it. To
use any other interpreter, declare it: `GAAI_YAML_PYTHON=/absolute/path/to/python`.

**`python3` on `PATH` is a separate requirement.** A few Framework modes use only
the Python standard library and were deliberately not migrated —
`backlog-scheduler.sh`'s `--list`, `--next`, `--set-status` and archive handling
are the concrete case. They still need `python3` on `PATH`. `install-check.sh`
reports that as its own check, next to the runtime check, and the two are
independent in both directions: the YAML runtime never falls back to an ambient
`python3`, and an ambient `python3` is never evidence that the runtime is valid.

**Verify the runtime:**

```bash
bash .gaai/core/scripts/lib/yaml-runtime.sh --verify-tuple
bash .gaai/core/scripts/lib/yaml-runtime.sh --validate .gaai/project/contexts/backlog/active.backlog.yaml
```

### Restrictive-umask checkouts

The three vendor files must be at exactly mode `0644` for the runtime to admit
them. A checkout made by a process with a restrictive `umask` materializes them
at `0600` instead — the delivery wrapper sets a restrictive `umask` for its own
phase worktrees, and a service manager or an operator shell can impose one on the
daemon (for example a service unit with `UMask=0077`).

The delivery paths repair this automatically for their own checkouts, including a
worktree they re-create during a self-heal recovery, and re-verify the tuple
afterwards. For a checkout made outside those paths, verify with the commands
above; the sanctioned repair is to restore **exactly those three files** to
`0644`:

```bash
chmod 0644 .gaai/core/vendor/pyyaml/6.0.3/pyyaml-runtime.pyz \
           .gaai/core/vendor/pyyaml/6.0.3/PROVENANCE.json \
           .gaai/core/vendor/pyyaml/6.0.3/LICENSE
```

A `chmod -R` over the checkout is **not** the remedy.

**Fail-closed startup.** The daemon verifies the runtime tuple of the tree it is
about to run from *before* it does anything else. A home directory that was never
successfully provisioned — or whose tuple cannot be repaired and verified — makes
startup stop with the bounded runtime diagnostic instead of continuing in a
degraded state. The same verification runs for `--status` and for a direct run
from the main checkout, so `--status` is the safe way to exercise the check
without starting a daemon.

### Rebuilding, updating and rolling back

The archive is reproducible offline from a locally supplied upstream source
distribution whose exact digest the manifest pins. The exact rebuild command is
recorded in `PROVENANCE.json` under `rebuild.command`; the builder performs no
network access and refuses anything whose digest does not match the pin. Two
independently created clean offline environments must reproduce the archive, the
licence and the manifest byte-identically.

A version, advisory or supported-minor change is a **new governed candidate for
the complete tuple** — archive, manifest, licence, builder, helper and every
consumer together — owned by the Framework release-maintainer role. Rollback is a
reviewed revert to a complete prior manifest + asset + consumer tuple. Reverting
the asset alone, or the consumers alone, is not a rollback, and an ambient-parser
fallback is never a rollback.

---

## New Projects: Install GAAI

```bash
# From the GAAI-framework repo
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```
