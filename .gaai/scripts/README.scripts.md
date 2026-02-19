# GAAI Scripts

Utility scripts that support workflows. They do one thing well: sort, filter, validate, extract.

**Scripts are not agents. Scripts do not reason. Scripts do not orchestrate.**

---

## Role of Scripts

Scripts:
- Perform utility operations (sorting, filtering, validation, extraction)
- Are called by workflows — not directly by agents
- Contain no AI logic or governance decisions
- Are idempotent, simple, and have no heavy external dependencies

Scripts do NOT:
- Replace agents
- Contain reasoning or governance logic
- Be invoked directly by the user in normal operation (only for debug or CI)

---

## Script Index

Scripts are self-documenting. Each `.sh` file begins with a header comment describing its purpose, usage, inputs, outputs, and exit codes. Browse this directory to see what scripts exist.

---

## Naming Convention

All scripts use kebab-case with `.sh` extension:
- `health-check.sh`
- `backlog-scheduler.sh`

---

## Script Standards

Every script must:
- Start with `#!/usr/bin/env bash` and `set -euo pipefail`
- Include a header comment with: Description, Usage, Inputs, Outputs, Exit codes
- Be testable in isolation
- Work in a POSIX-compatible shell (bash 3.2+)
- Have predictable inputs and outputs
- Be idempotent where possible

Exit codes:
- `0` — success
- `1` — usage error
- `2` — data error
