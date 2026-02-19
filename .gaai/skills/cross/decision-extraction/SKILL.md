---
name: decision-extraction
description: Identify and formalize durable product and technical decisions from agent outputs into long-term memory. Activate after Discovery produces artefacts, Delivery resolves trade-offs, or product direction materially changes.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-DECISION-EXTRACTION-001
  updated_at: 2026-01-27
inputs:
  - recent_agent_outputs
  - contexts/artefacts/**  (governed)
outputs:
  - contexts/memory/decisions/*.memory.md
  - contexts/memory/index.md  (updated)
---

# Decision Extraction

## Purpose / When to Activate

Activate after:
- Discovery produces epics, scope clarifications, or priorities
- Delivery resolves technical trade-offs or architectural constraints
- QA surfaces systemic issues requiring policy decisions
- Product direction materially changes

Do NOT use for trivial steps, implementation details, brainstorming, or reversible micro-choices.

---

## Process

1. Scan outputs for explicit or implicit decisions: architectural choices, accepted trade-offs, scope boundaries, prioritization shifts, constraints introduced
2. Filter strictly for **durable, governance-relevant decisions**
3. Convert each into a structured Decision Memory entry:
   - Context
   - Decision
   - Rationale
   - Impact
4. Tag consistently
5. Register in memory index

---

## Output Format

Each decision file:

```yaml
---
type: memory
category: decision
id: DEC-YYYY-MM-DD-XX
tags:
  - product | architecture | scope | priority
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---

# Decision Title

## Context
...

## Decision
...

## Rationale
...

## Impact
...
```

---

## Quality Checks

- All major decisions become explicit memory
- No repeated reasoning across sessions
- Governance trail is traceable
- Memory grows only with high-signal knowledge

---

## Non-Goals

This skill must NOT:
- Summarize entire sessions
- Capture raw logs
- Duplicate existing decisions
- Store trivial steps
- Invent interpretation without artefact support

**If future agents benefit from knowing it → extract it. If not → do not store it. Memory is leverage — not history.**
