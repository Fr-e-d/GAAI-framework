---
type: rules
category: base
id: RULES-BASE-OVERRIDE-EXAMPLE
example_for: base.rules.md
override_scenario: Relax the backlog-first requirement for conversational quick-fixes
tags:
  - universal
  - governance
  - solo-dev
created_at: 2026-03-22
updated_at: 2026-03-22
---

# Example Override: Relax Backlog-First for Solo Dev Projects

> **This is an example file.** It does not override any core rule.
> To activate this override, copy this file to `project/contexts/rules/base.rules.md`
> (removing the `.example` suffix). The `base.rules.md` filename triggers the override.

---

## What This Overrides

Core rule: **Rule 1 — Backlog-first** from `core/contexts/rules/base.rules.md`:
> "Every execution unit must be in the backlog. No work without a backlog entry."

---

## Scenario

You are a **solo developer** running GAAI on a personal or early-stage project. You want agents to handle small conversational fixes (a typo correction, a one-line config change) without requiring a full backlog entry and story cycle. The overhead of creating a backlog entry for a two-minute change outweighs the governance benefit at this scale.

---

## The Override

```markdown
## Core Governance Rules

1. **Backlog-first (relaxed for quick-fixes).** Every execution unit should be in the backlog.
   Exception: a "quick-fix" conversational change is allowed without a backlog entry if ALL of:
   - It modifies ≤2 files
   - It requires no cross-agent coordination (no Delivery sub-agents)
   - It introduces no new behavior (typos, config values, minor copy edits)
   - The agent logs the change inline in the conversation for traceability

   Quick-fix exceptions are NOT allowed for: new features, schema changes, API surface changes,
   or any change affecting external integrations.

2–5. [Keep all other rules unchanged from core/contexts/rules/base.rules.md]
```

---

## Tradeoff

**What you gain:** Lower friction for trivial changes. Agents can act immediately on small, obvious corrections without the Discovery → refine → Delivery cycle.

**What you lose:** Full auditability for quick-fix changes. If a "quick-fix" later proves to have had side effects, there is no backlog entry or story artefact to trace back to the decision.

**When this is appropriate:** Solo founders, personal projects, early prototypes where the cost of governance overhead is higher than the cost of an occasional mis-scoped quick-fix.

**When this is NOT appropriate:** Teams with multiple contributors, production systems, or projects where compliance or audit trails are required.
