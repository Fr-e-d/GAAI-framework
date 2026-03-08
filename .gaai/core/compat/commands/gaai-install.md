# /gaai-install

Guided wizard to install the GAAI framework into a target project.

## What This Does

Runs the GAAI Setup Wizard interactively:
1. Asks which directory to install into (defaults to current working directory)
2. Auto-detects the AI tool in use (Claude Code, Cursor, Windsurf)
3. Shows a summary and asks for confirmation
4. Runs `.gaai/core/scripts/install.sh --wizard` and reports the result
5. Displays next steps for the installed tool

## When to Use

- First-time install of GAAI into a project
- Updating an existing GAAI installation
- Works from the GAAI framework repo **or** from any project that already has `.gaai/` installed

## Instructions for Claude Code

You are running a guided GAAI installation.

**Step 1 — Find the installer**

Look for `.gaai/core/scripts/install.sh` in the current working directory. If it is not present, tell the user: "No `.gaai/core/scripts/install.sh` found. Either clone the GAAI framework repo first, or ensure `.gaai/` is present in this project."

**Step 2 — Ask the user for the target directory**

Ask: "Which directory should GAAI be installed into? Provide an absolute or relative path (default: current directory)."

Wait for their answer.

**Step 3 — Run the wizard**

Execute:

```bash
bash .gaai/core/scripts/install.sh --wizard --target <target-dir>
```

Pass the target directory the user specified, or `.` if they accepted the default.

**Step 4 — Report outcome**

If the install succeeded (exit code 0), confirm success and show the next steps printed by the installer.

If it failed, show the error output and suggest: "Check that the target directory exists and that you have write permissions."
