# .gaai/ — GAAI Framework (v2.0.0)

## Directory Structure

```
.gaai/
├── core/          ← Framework (auto-synced to OSS via post-commit hook)
│   └── README.md  ← This file
└── project/       ← Project-specific data (memory, backlog, artefacts, custom skills)
```

- `core/` changes are **automatically contributed to OSS** on every commit (via post-commit hook → PR → auto-merge)
- `project/` is **local only** — never synced to OSS

---

## Framework Sync (Automatic)

When you commit changes to `.gaai/core/`, a post-commit hook automatically:
1. Detects `.gaai/core/` was modified
2. Clones the OSS repo (shallow)
3. Replaces `core/` with your local version
4. Creates a PR on `Fr-e-d/GAAI-framework`
5. Schedules auto-merge

**You don't need to do anything.** The sync is transparent and non-blocking.

Setup: `git config core.hooksPath .githooks` (done by `install-hooks.sh`).
Logs: `.gaai/project/.sync-log`.

---

## Optional: Autonomous Delivery

If your project uses git with a `staging` branch, the **Delivery Daemon** can automate everything:

1. Setup: `bash .gaai/core/scripts/daemon-setup.sh`
2. Start: `bash .gaai/core/scripts/daemon-start.sh`
3. Stop: `bash .gaai/core/scripts/daemon-start.sh --stop`

The daemon polls for `refined` stories and delivers them in parallel — no human in the loop.
Full reference: see `GAAI.md` → "Branch Model & Automation".

> **Tested on:** macOS (Apple Silicon). Linux and WSL (Windows) are expected to work but not yet validated — issues and feedback welcome.

---

## New Projects: Install GAAI

```bash
# From the GAAI-framework repo
bash /tmp/gaai/install.sh --target . --tool claude-code --yes
```
