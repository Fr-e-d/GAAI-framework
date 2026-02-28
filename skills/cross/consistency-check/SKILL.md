---
name: consistency-check
description: Detect inconsistencies across related artefacts and governance constraints. Activate after story generation, after plan preparation, before implementation, or after remediation attempts. Reports issues — does not fix them.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CONSISTENCY-CHECK-001
  updated_at: 2026-01-30
  status: stable
inputs:
  - contexts/artefacts/**  (Epics, Stories, Plans, PRDs as applicable)
  - contexts/rules/**
  - memory_context_bundle  (optional)
outputs:
  - contexts/artefacts/consistency-reports/{story_id}.consistency-report.md
  - flagged_issues  (structured list)
---

# Consistency Check

## Purpose / When to Activate

Activate:
- After story generation
- After plan preparation
- Before implementation
- After remediation attempts
- During governance gating

This skill **reports issues** — it does not fix them.

---

## Process

### Structural Consistency
- Artefacts link properly (Story → Epic → PRD)
- Required artefact fields exist
- Frontmatter identity and linkage correct

### Scope Consistency
- Story scopes align with Plans
- Plans contain no out-of-scope actions
- Story acceptance criteria match plan deliverables

### Rule Consistency
- No triggered rule goes unhandled
- Compliance status of each artefact
- Rule violations flagged

### Completeness Consistency
- No missing acceptance criteria
- No empty or placeholder fields
- No partially generated artefact

### Inter-artefact Alignment
- No contradictions between Epics & Stories
- Plan steps correlate with acceptance criteria
- No unresolved split dependencies

> **Partial artefact handling:** If the artefact set is incomplete (e.g., Story exists but parent Epic is absent), check only what is available. Report missing artefacts as `ISSUE-{ID}: required artefact absent` with severity: medium. Do not fail the entire check.

---

## Output Format

ISSUE-ID naming convention: use format `ISSUE-{STORY_ID}-{NNN}` (e.g., `ISSUE-E06S18-001`).

```
ISSUE-ID
Type: structural | scope | rule | completeness | alignment
Artefacts involved: ...
Description: concise violation or inconsistency
Why it matters: short impact statement
Severity: low | medium | high | critical
Location: file/path/position
```

---

## Quality Checks

- Issues are clearly reported with exact artefact/rule references
- Severity is explicit
- No duplicates
- No invented fixes
- Description fields must not contain fix proposals — report the inconsistency factually

---

## Non-Goals

This skill must NOT:
- Invent fixes
- Suppress issues
- Judge without evidence

**Check everything against everything. Consistency is a governance requirement, not an optimization.**
