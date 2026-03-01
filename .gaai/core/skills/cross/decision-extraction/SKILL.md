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
  updated_at: 2026-03-01
  status: stable
inputs:
  - recent_agent_outputs: session outputs from the invoking agent, or file paths to artefacts produced in the current session (e.g., evaluation reports, refined stories, approach-evaluation outputs)
  - contexts/artefacts/**  (governed)
outputs:
  - contexts/memory/decisions/DEC-{N}.md  (individual ADR file per DEC-138)
  - contexts/memory/decisions/_log.md  (next ID updated)
  - contexts/memory/index.md  (registry + file count updated)
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

0. **Decision Consistency Gate (mandatory, DEC-130).** Before extracting any new decision:
   - Read `contexts/memory/index.md` → scan the Decision Registry by domain to identify relevant existing decisions
   - Load the specific `decisions/DEC-{ID}.md` files for decisions in the affected domain(s)
   - Verify the proposed decision does NOT contradict any active decision
   - If contradiction found: either explicitly supersede (set `superseded_by` in old file + `supersedes` in new file) with rationale, or STOP and escalate to human
   - If unable to determine consistency → STOP and escalate to human
   - Never record a decision silently if it may conflict with an existing one

1. Scan outputs for explicit or implicit decisions: architectural choices, accepted trade-offs, scope boundaries, prioritization shifts, constraints introduced
2. Filter strictly for **durable, governance-relevant decisions**
3. **Deduplication check:** Scan the Decision Registry in `index.md` for existing entries covering the same topic. If found: (a) if the new decision supersedes the old, update the old `DEC-{ID}.md` file's frontmatter (`status: superseded`, `superseded_by: DEC-{new-id}`) and record the supersession in the new entry's `supersedes` field; (b) if the new decision confirms the old, skip writing a duplicate.
4. Convert each into a structured ADR file (see Output Format below):
   - Context
   - Decision
   - Impact
5. Classify using the **10 canonical domains**: `architecture`, `matching`, `expert-system`, `billing`, `booking`, `infrastructure`, `strategy`, `governance`, `market`, `content`. And **3 levels**: `strategic` (WHAT/WHY), `architectural` (HOW), `operational` (PROCESS).
6. **Get next available ID** from `decisions/_log.md` → write `decisions/DEC-{N}.md`
7. **Update `_log.md`:** increment next available ID, add one-line entry for the new decision
8. **Update `index.md`:** add row to Decision Registry, increment file count in Shared Categories table

---

## Output Format (DEC-138)

Each decision is an individual ADR file: `decisions/DEC-{N}.md` (sequential numeric ID).

```yaml
---
id: DEC-{N}
domain: architecture | matching | expert-system | billing | booking | infrastructure | strategy | governance | market | content
level: strategic | architectural | operational
title: "Decision Title"
status: active
created_by: discovery
created_at: YYYY-MM-DD
last_updated_by: discovery
last_updated_at: YYYY-MM-DD
supersedes: null          # or DEC-{old-id} if replacing
superseded_by: null
tags:
  - {relevant tags}
---

# DEC-{N} — Decision Title

## Context
...

## Decision
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
