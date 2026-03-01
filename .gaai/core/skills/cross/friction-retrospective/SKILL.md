---
name: friction-retrospective
description: Scan delivery artefacts for friction log entries, detect recurring patterns, and produce retrospective reports. Invoked by Discovery Agent (never by Delivery) to identify systemic improvement opportunities from friction captured during delivery.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-FRICTION-RETROSPECTIVE-001
  updated_at: 2026-03-01
  status: experimental
inputs:
  - contexts/artefacts/impl-reports/**
  - contexts/artefacts/qa-reports/**
  - contexts/artefacts/delivery/**
  - scope_filter (optional): epic, date_range, or friction_type
outputs:
  - retrospective_report (contexts/artefacts/retrospectives/{scope}.retro.md or inline)
---

# Friction Retrospective

## Purpose / When to Activate

Activate to aggregate and analyze friction captured during delivery. This skill reads `## Friction Log` sections from delivery artefacts and detects patterns that warrant promotion to durable memory (conventions, decisions, rule updates).

**Recommended triggers (conventions, not rules):**
- **Per-Epic:** when an Epic is marked done
- **Monthly:** alongside `memory-refresh`
- **Incident:** if a single Story generates 3+ friction events

**Constraint:** Only the Discovery Agent may invoke this skill. Delivery agents capture friction; Discovery analyzes it.

---

## Process

1. **Scope resolution** — determine which artefacts to scan:
   - If `epic` filter: scan artefacts matching `{epic_id}S*`
   - If `date_range` filter: scan artefacts within date range (from frontmatter `created_at`)
   - If `type` filter: scan all artefacts but only extract entries matching the specified friction type
   - If no filter: scan all artefacts (full retrospective)

2. **Friction extraction** — for each artefact containing a `## Friction Log`:
   - Parse the table rows
   - Tag each entry with: Story ID (from filename), date (from frontmatter), artefact type (impl-report / qa-report / micro-delivery-report)

3. **Pattern detection** — analyze extracted entries:
   - Group by `type` (ac-ambiguity, missing-context, tool-failure, etc.)
   - Count frequency per type
   - Identify thematic clusters within each type (e.g., multiple `missing-context` about the same domain)
   - Flag all entries with `signal: high`
   - Flag types with frequency ≥ 3

4. **Classify promotion candidates** — for entries meeting promotion threshold:
   - `signal: high` → automatic promotion candidate (CAND-XXX)
   - frequency ≥ 3 for same type+theme → promotion candidate
   - Map each candidate to its promotion target (see Promotion Path below)

5. **Produce the report** — structured in 4 sections:
   - **Pattern Summary:** type distribution, top themes, overall friction density
   - **High-Signal Events (CAND-XXX):** each candidate with evidence, proposed promotion target, and recommended action
   - **Low-Signal Events:** grouped by type, listed for awareness
   - **Retrospective Notes:** observations, cross-cutting themes, questions for human review

6. **Write or return** — if scope is named (epic or date range), write to `contexts/artefacts/retrospectives/{scope}.retro.md`; otherwise return inline

---

## Promotion Path

| Friction type | Promotion target | Destination file |
|---|---|---|
| `missing-context` (pattern) | New coding pattern | `patterns/conventions.md` |
| `missing-context` (decision) | New decision | `decisions/DEC-{ID}.md` |
| `ac-ambiguity` (recurring) | Story template or Discovery rule | `orchestration.rules.md` or `_template.story.md` |
| `pattern-gap` | New code pattern | `patterns/conventions.md` |
| `rule-conflict` | Rule clarification | `orchestration.rules.md` |
| `tool-failure` (systemic) | Ops note or infra decision | `ops/platform.md` or new DEC |
| `retry-loop` (≥3 same domain) | QA pattern | `patterns/conventions.md` |

**Important:** This skill identifies candidates and recommends actions. Actual promotion to memory is performed by the Discovery Agent using `memory-ingest` — never automatically by this skill.

---

## Outputs

- Retrospective report with pattern analysis
- Promotion candidates (CAND-XXX) with evidence and recommended targets
- Friction density metrics (events per Story, per type)

---

## Quality Checks

- Every CAND-XXX has at least 2 supporting evidence entries (or 1 with `signal: high`)
- Promotion targets are specific (file path + section), not vague
- Low-signal events are listed but never promoted
- Report does not contain implementation fixes — only identifies what to fix and where

---

## Non-Goals

This skill must NOT:
- Write to memory directly (it produces candidates; Discovery promotes)
- Modify rules, conventions, or decisions
- Re-run or remediate delivery — it is purely analytical
- Assign blame to agents or sub-agents
