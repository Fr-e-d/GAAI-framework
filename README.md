# .gaai/ — GAAI Framework (v2.0.0)

## Directory Structure

```
.gaai/
├── core/          ← Framework (synced with GAAI OSS repo via git subtree)
│   └── README.md  ← This file
└── project/       ← Project-specific data (memory, backlog, artefacts, custom skills)
```

- `core/` is **git subtree**-synced with the [GAAI-framework](https://github.com/Fr-e-d/GAAI-framework) OSS repo
- `project/` is **local only** — never synced to OSS

---

## Core Principle

**Your project changes DO NOT auto-sync to OSS.** All syncing is explicit and intentional:
- `.gaai/core/` changes stay local in your project
- `.gaai/project/` is always 100% local (never pushed to OSS)
- Updates from OSS are pulled on-demand

---

## Optional: Autonomous Delivery

If your project uses git with a `staging` branch, the **Delivery Daemon** can automate everything:

1. Setup: `bash .gaai/core/scripts/daemon-setup.sh`
2. Start: `bash .gaai/core/scripts/daemon-start.sh`
3. Stop: `bash .gaai/core/scripts/daemon-start.sh --stop`

The daemon polls for `refined` stories and delivers them in parallel — no human in the loop.
Full reference: see `GAAI.md` → "Branch Model & Automation".

---

## Pulling Framework Updates

```bash
# One-time: add the OSS remote
git remote add gaai-framework https://github.com/Fr-e-d/GAAI-framework.git
git fetch gaai-framework

# Pull latest improvements from OSS
git subtree pull --prefix=.gaai gaai-framework main --squash

# Or pin to a specific release tag
git subtree pull --prefix=.gaai gaai-framework v2.1.2 --squash
```

---

## New Projects: Initialize .gaai/

```bash
git subtree add --prefix=.gaai gaai-framework main --squash
```
