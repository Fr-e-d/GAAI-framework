---
type: rules
category: base
id: RULES-BASE-001
tags:
  - universal
  - conversational
  - governance
created_at: 2026-03-15
updated_at: 2026-03-17
---

# GAAI Base Rules (Universal)

These rules apply **at all times** — in structured GAAI flows AND in conversational mode.
They are loaded at session startup via the tool adapter.

For flow-specific rules (agent responsibilities, backlog states, branch rules, cron), see `orchestration.rules.md`.

---

## Core Governance Rules

1. **Backlog-first.** Every execution unit must be in the backlog. No work without a backlog entry.
2. **Skill-first.** Every agent action must reference a skill. Read the skill file before invoking it.
3. **Memory is explicit.** Load only what is needed. Never auto-load all memory.
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **Artefacts are never overwritten blindly.** Before writing any artefact file (story, epic, decision), check if the file already exists on disk. If it exists and belongs to a different entity (different epic, different intent), **STOP and escalate** — this is an ID collision. Never silently overwrite an existing artefact. This rule is absolute and applies even in conversational mode.

---

## Recommendation Validation

When any agent proposes a recommendation that implies a **choice between viable alternatives** (architecture, library, pattern, service), the agent must validate against industry standards and best practices BEFORE presenting the recommendation. If the recommendation diverges from an established standard, this must be signaled explicitly with justification.

This rule does NOT apply to: obvious choices with no viable alternative, bug fixes, minor refactoring, or conventions already established in `patterns/conventions.md`. Proportionality governs — do not slow down routine work with unnecessary research.

---

## Conflict & Escalation Protocol

When an agent encounters a conflict between a human instruction and an existing rule:
- Stop immediately. Do not attempt to resolve it silently.
- Surface the conflict explicitly: name the instruction, name the rule, state what they contradict.
- Wait for human resolution. Do not proceed until the conflict is resolved.

When an agent encounters ambiguity in a request or acceptance criteria:
- Stop. Do not interpret intent.
- Escalate for clarification.

**If in doubt: stop and ask. Always.**
