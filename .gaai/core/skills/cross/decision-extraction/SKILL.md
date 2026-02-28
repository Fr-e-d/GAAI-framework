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
  updated_at: 2026-02-28
  status: stable
inputs:
  - recent_agent_outputs: session outputs from the invoking agent, or file paths to artefacts produced in the current session (e.g., evaluation reports, refined stories, approach-evaluation outputs)
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

0. **Decision Consistency Gate (mandatory — see `orchestration.rules.md`):** Before extracting any new decision, search existing decisions (`contexts/memory/decisions/`) for all entries touching the same domain/topic. List the relevant existing decisions explicitly. Verify that the new decision does not contradict any of them. If contradiction detected: the new decision MUST explicitly state "Supersedes DEC-XX" with rationale, OR be rejected. If the agent cannot determine consistency → stop and escalate to the human. **A decision extracted without this verification is invalid by governance.**
1. Scan outputs for explicit or implicit decisions: architectural choices, accepted trade-offs, scope boundaries, prioritization shifts, constraints introduced
2. Filter strictly for **durable, governance-relevant decisions**
3. **Deduplication check:** Before writing a new decision entry, scan `contexts/memory/decisions/` for existing entries covering the same topic. If found: (a) if the new decision supersedes the old, update the existing entry's `updated_at` and add a `supersedes` note; (b) if the new decision confirms the old, skip writing a duplicate.
4. Convert each into a structured Decision Memory entry:
   - Context
   - Decision
   - Rationale
   - Impact
5. Tag consistently — use tags from this controlled list: `product`, `architecture`, `scope`, `priority`, `billing`, `security`, `integration`, `infrastructure`. Add new tags only if none of these fit.
6. Register in memory index

---

## Output Format

Each decision file:

```yaml
---
type: memory
category: decision
id: DEC-YYYY-MM-DD-XX
tags:
  - product | architecture | scope | priority | billing | security | integration | infrastructure
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
