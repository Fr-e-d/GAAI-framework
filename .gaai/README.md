# .gaai/ — GAAI Framework (v2.0.0)

## Directory Structure

```
.gaai/
├── core/       ← Framework (synced with GAAI OSS repo via git subtree)
├── project/    ← Project-specific data (memory, backlog, artefacts, custom skills)
└── README.md   ← This file
```

- `core/` is **git subtree**-synced with the [GAAI-framework](https://github.com/Fr-e-d/GAAI-framework) OSS repo
- `project/` is **local only** — never synced to OSS

---

## Core Principle

**Your project changes DO NOT auto-sync to OSS.** All syncing is explicit and intentional:
- `.gaai/core/` changes stay local until you choose to contribute
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

## Contributing Framework Improvements

When you improve `.gaai/core/` in this project, you can contribute those changes back to the OSS repo.

### Option 1: Patch-Based Contribution ⭐ (RECOMMENDED)

**Simplest, cleanest, zero git history pollution.**

```bash
# Extract your .gaai/core/ changes into a patch file
gaai-framework-contrib.sh --patch

# Follow the prompt to:
# 1. Review changes
# 2. Create a descriptive message
# 3. Export as patch file
# 4. Open PR on GAAI-framework repo

# The patch is then manually applied in the OSS repo
```

**Manual version:**
```bash
# Extract changes since last sync
git format-patch gaai-framework/main..HEAD -- .gaai/core/ \
  -o /tmp/gaai-contrib.patch

# Send to GAAI-framework repo (via PR or email)
# OSS maintainer applies: git apply /tmp/gaai-contrib.patch
```

**Why this works:**
- ✅ OSS repo history stays clean
- ✅ No subtree conflicts
- ✅ Clear PR review
- ✅ Works across multiple projects (A, B, C, ...)

---

### Option 2: Git Subtree Push (Advanced)

**Direct push to OSS repo. Requires write access.**

```bash
# Push your .gaai/core/ changes to a contribution branch
git subtree push --prefix=.gaai gaai-framework contrib/<your-project-name>

# Then:
# 1. Create a PR on GAAI-framework: contrib/<your-project-name> → main
# 2. OSS maintainer merges (handles the unrelated-history merge once)
# 3. CI auto-splits main → _subtree-export
```

**Caveats:**
- ⚠️ First push per project requires `--allow-unrelated-histories` handling
- ⚠️ More git knowledge required
- ✅ More direct if you have write access

---

## Pulling Framework Updates

### From `main` (after a contribution is merged)

```bash
# Pull latest improvements from OSS repo
git subtree pull --prefix=.gaai gaai-framework main --squash
```

### Version pinning (advanced)

```bash
# Pin to a specific release tag (e.g., v2.1.0)
git subtree pull --prefix=.gaai gaai-framework v2.1.0 --squash
```

---

## Setup

### One-time: Add the OSS remote

```bash
git remote add gaai-framework https://github.com/Fr-e-d/GAAI-framework.git
git fetch gaai-framework
```

### One-time: Initialize .gaai/ subtree (new projects only)

```bash
git subtree add --prefix=.gaai gaai-framework main --squash
```

---

## Workflow Diagram

```
Your Project (A or B)              GAAI-framework OSS Repo
─────────────────────              ───────────────────────

.gaai/ modifications (excl. project/)
       │
       ├─→ Option 1: PATCH-BASED ⭐
       │   └─→ gaai-framework-contrib.sh --patch
       │       └─→ Send patch to OSS repo (PR)
       │           └─→ Merged into main
       │
       └─→ Option 2: SUBTREE PUSH (advanced)
           └─→ git subtree push --prefix=.gaai gaai-framework contrib/your-project
               └─→ Create PR contrib/your-project → main
                   └─→ Merged into main

                                    main branch
                                        ↓
                          (Your .gaai/ changes are now in main!)
                                        ↓
                          Pull updates back anytime:
                          git subtree pull --prefix=.gaai \
                            gaai-framework main --squash
```

---

## Helper Script: `gaai-framework-contrib.sh`

Simplifies the patch-based contribution workflow.

Located in: **`~/.claude/scripts/gaai-framework-contrib.sh`** (user-level, not in git repos)

```bash
# Review and create a patch from your changes
gaai-framework-contrib.sh --patch

# Or directly push (requires write access)
gaai-framework-contrib.sh --push

# View status
gaai-framework-contrib.sh --status
```

**Why user-level?** The script lives in your home directory (outside any git repo) to prevent tampering. If it lived in `.gaai/scripts/`, someone with write access to the project could modify it to inject malicious code.

### Setup (one-time)

```bash
# Verify installation
ls -la ~/.claude/scripts/gaai-framework-contrib.sh

# If not found, copy from project documentation
# (See .gaai/scripts/README.md for installation)
```

See `.gaai/scripts/README.md` and `CONTRIBUTING-GAAI.md` for full documentation.

---

## Multi-Project Scenario

When working on **multiple projects (A, B, C)** simultaneously:

| Scenario | Best Approach |
|----------|---------------|
| Same improvement needed in A and B | Patch from A → merge into OSS → pull into B |
| Different improvements in A and B | Each sends own patch → OSS merges both |
| Bug fix in A affects B | Fix in A → patch to OSS → B pulls latest |
| Experimenting in B, don't want to share yet | Keep local in B, sync later when ready |

**Key:** OSS `main` becomes the "source of truth" for shared improvements.

---

## FAQ

**Q: What if I accidentally commit `.gaai/project/` changes?**
A: They stay local. Only `.gaai/core/` is eligible for OSS contribution via patch/push.

**Q: Can multiple projects contribute to OSS simultaneously?**
A: Yes! Each sends a patch. OSS repo merges them sequentially (no conflicts).

**Q: What if OSS has merged someone else's changes?**
A: Just run `git subtree pull --prefix=.gaai gaai-framework main --squash` to get them.

**Q: Do I need write access to GAAI-framework for patch contribution?**
A: No. Create a PR with the patch file. Maintainer applies it.

---

## Branching Strategy

|                     | Your Project | GAAI OSS                                           |
|---------------------|---------------------|------|
| Main branch         | `main` / `staging`            | `main`  |
| Contribution method | Patch-based (recommended) | PR merge  |
| Update source       | `gaai-framework/main` via `git subtree pull` | — |
