---
description: Update the GAAI framework or switch AI tool adapter
---

# /gaai-update

Update the GAAI framework core.

## Subcommands

- `/gaai-update oss` — Update the local `.gaai/core/` framework from the OSS repository

---

## /gaai-update oss

### Precondition — `.gaai/core/` must be present

Check whether `.gaai/core/` exists in the project root. If it is absent, stop and tell the user:

> **Error:** `.gaai/core/` not found. GAAI OSS does not appear to be installed. Install the GAAI OSS framework first.

Do not proceed.

### Step 1 — Find the installer

Look for `.gaai/core/scripts/install.sh` in the current working directory. If it is not present, tell the user:

> **Error:** No `.gaai/core/scripts/install.sh` found. Ensure `.gaai/` is present in this project.

Do not proceed.

### Step 2 — Pull latest `.gaai/core/` (AC13)

Ask the user:

> "Provide the path to the GAAI OSS framework repo (e.g., `/tmp/gaai`), or press Enter to redeploy adapters from the existing local copy."

If a source repo path is provided, run:

```bash
bash <source-repo>/.gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

If no source repo path is provided (adapter redeploy only), run:

```bash
bash .gaai/core/scripts/install.sh --target . --tool claude-code --yes
```

### Step 3 — Report outcome

If the update succeeded (exit code 0), confirm success and show the health check results.

If it failed, show the error output and suggest checking permissions or file integrity.
