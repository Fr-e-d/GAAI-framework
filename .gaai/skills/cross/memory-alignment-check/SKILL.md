---
name: memory-alignment-check
description: After QA PASS, compare the Story's implementation footprint against relevant memory entries. Reports confirmed entries, contradictions, and new knowledge candidates. Never writes to memory — produces a delta report for Discovery to action.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-ALIGNMENT-CHECK-001
  updated_at: 2026-02-19
inputs:
  - contexts/artefacts/reports/{id}.impl-report.md
  - contexts/artefacts/stories/{id}.story.md
  - contexts/memory/index.md
  - [selective memory entries by scope tags]
outputs:
  - contexts/artefacts/reports/{id}.memory-delta.md
---

# Memory Alignment Check

## Purpose / When to Activate

Activate after QA verdict is PASS — never before (avoids analysis on code that will change).

This skill checks that long-term memory (decisions, patterns, project context) remains accurate after a Story is delivered. It compares only the Story's implementation footprint against relevant memory entries — not the full codebase.

The codebase is the source of truth for implementation.
Memory is the source of truth for decisions and patterns.
This skill checks that both remain consistent after each delivery.

**This skill reports. It never writes to memory.**

---

## Process

### 1. Extract Implementation Footprint

From `{id}.impl-report.md`:
- Files modified or created
- New modules or services introduced
- Patterns applied during implementation
- Technical decisions made during implementation
- New integrations or external dependencies introduced

### 2. Retrieve Relevant Memory (Selective)

Using `contexts/memory/index.md`:
- Identify memory entries whose tags intersect the Story's scope and touched modules
- Load only those entries — do not load all memory
- Scope: project context, patterns, decisions relevant to the implementation footprint

### 3. Compare Footprint Against Memory

For each relevant memory entry, assign one verdict:

- **CONFIRMED** — implementation is consistent with what memory states
  → Record entry ID, suggest `last_verified_at` update to today, `verified_against_story` to Story ID

- **CONTRADICTED** — implementation contradicts or obsoletes what memory states
  → Record exact contradiction, affected memory entry ID, severity (high / medium / low)

- **UNADDRESSED** — memory entry is not touched by this Story
  → Skip — no verdict needed

### 4. Identify New Knowledge Not Yet in Memory

From the implementation footprint, extract candidates not present in memory:
- New patterns introduced not in `contexts/memory/patterns/`
- New architectural or technical decisions not in `contexts/memory/decisions/`
- New constraints or conventions applied for the first time

These are **ingestion candidates** — flagged for Discovery to validate and ingest.

---

## Output Format

Written to: `contexts/artefacts/reports/{id}.memory-delta.md`

```yaml
---
skill: memory-alignment-check
story_id: E01S01
generated_at: YYYY-MM-DD
verdict: ALIGNED | DRIFT_DETECTED | NEW_KNOWLEDGE_FOUND | DRIFT_AND_NEW_KNOWLEDGE
---

## Confirmed Entries

- memory_id: PATTERNS-001
  status: CONFIRMED
  suggested_last_verified_at: YYYY-MM-DD
  suggested_verified_against_story: E01S01
  note: Implementation of X is consistent with stated convention.

## Contradicted Entries

- memory_id: DEC-2026-01-15-01
  status: CONTRADICTED
  severity: high | medium | low
  description: Memory states [X]. Implementation did [Y]. These are incompatible.
  action_required: Update or invalidate memory entry.

## New Knowledge Candidates

- candidate_id: CANDIDATE-001
  category: patterns | decisions | project
  description: New retry pattern introduced in services/api/client.ts — not yet in memory.
  suggested_tags: [api, resilience, patterns]
  ingestion_priority: high | medium | low
```

---

## Verdict Logic

| Verdict | Condition |
|---|---|
| `ALIGNED` | No contradictions, no new knowledge candidates |
| `DRIFT_DETECTED` | One or more memory entries contradicted by the implementation |
| `NEW_KNOWLEDGE_FOUND` | New knowledge candidates identified, no contradictions |
| `DRIFT_AND_NEW_KNOWLEDGE` | Both contradictions and new knowledge candidates present |

---

## Quality Checks

- Only memory entries intersecting the Story scope are loaded — never full memory
- Confirmed entries include specific evidence from impl-report (not assertions)
- Contradictions describe the exact mismatch — no vague statements
- New knowledge candidates are concrete and grounded in impl-report — not speculative
- No memory is written — this skill produces a report only

---

## Non-Goals

This skill must NOT:
- Write or update any memory file
- Trigger `memory-ingest` directly (only Discovery may do so)
- Scan the full codebase
- Analyse code outside the Story's implementation footprint
- Make product or architectural decisions
- Block or modify the QA verdict
