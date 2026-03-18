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
  updated_at: 2026-03-03
  status: stable
inputs:
  - recent_agent_outputs: session outputs from the invoking agent, or file paths to artefacts produced in the current session (e.g., evaluation reports, refined stories, approach-evaluation outputs)
  - contexts/artefacts/**  (governed)
outputs:
  - contexts/memory/decisions/DEC-{N}.md  (individual ADR file)
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

0. **Decision Consistency Gate (mandatory).** Before extracting any new decision:
   - Read `contexts/memory/index.md` → scan the Decision Registry by domain to identify relevant existing decisions
   - Load the specific `decisions/DEC-{ID}.md` files for decisions in the affected domain(s)
   - Verify the proposed decision does NOT contradict any active decision
   - If contradiction found: either explicitly supersede (set `superseded_by` in old file + `supersedes` in new file) with rationale, or STOP and escalate to human
   - If unable to determine consistency → STOP and escalate to human
   - Never record a decision silently if it may conflict with an existing one

1. Scan outputs for explicit or implicit decisions: architectural choices, accepted trade-offs, scope boundaries, prioritization shifts, constraints introduced
2. Filter strictly for **durable, governance-relevant decisions**
3. **Deduplication check:** Scan the Decision Registry in `index.md` for existing entries covering the same topic. If found: (a) if the new decision supersedes the old, update the old `DEC-{ID}.md` file's frontmatter (`status: superseded`, `superseded_by: DEC-{new-id}`) and record the supersession in the new entry's `supersedes` field; (b) if the new decision confirms the old, skip writing a duplicate.
3b. **Cross-reference assignment:** For the new decision, populate `related_to` with up to 5 DEC IDs that are directly related (same domain cluster, supersession chain, or shared concern). Only include decisions the new entry explicitly builds on, refines, or constrains. If no strong relation exists, leave as `[]`.
4. Convert each into a structured ADR file (see Output Format below):
   - Context
   - Decision
   - Impact
5. Classify using the **10 canonical domains**: `architecture`, `matching`, `expert-system`, `billing`, `booking`, `infrastructure`, `strategy`, `governance`, `market`, `content`. And **3 levels**: `strategic` (WHAT/WHY), `architectural` (HOW), `operational` (PROCESS).
6. **Get next available ID** from `decisions/_log.md` → write `decisions/DEC-{N}.md`
7. **Update `_log.md`:** increment next available ID, add one-line entry for the new decision
8. **MANDATORY GATE — Update `index.md`:** Add one row per new decision to the Decision Registry table (columns: DEC ID | domain | level | one-line description). Increment the file count in the Shared Categories table. **Verify:** re-read the updated `index.md` and confirm the new DEC-{N} entry is present before completing this skill. This step is a blocking gate — do not output success until confirmed.
9. **Summary range check:** Read the Summaries section of `index.md`. If the new DEC ID exceeds the highest DEC covered by the latest summary file (e.g., summary covers 90–155 but new DEC is 156), append a line to `decisions/_log.md`: `# ⚠️ PENDING: extend summary range to DEC-{new-max-id} — run memory-refresh`. This signals the next `memory-refresh` cycle to extend the summary. Do NOT create a new summary mid-delivery.

---

## Output Format

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
related_to: []            # optional — max 5 DEC IDs
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
