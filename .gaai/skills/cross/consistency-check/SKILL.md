---
name: consistency-check
description: Detect inconsistencies across related artefacts and governance constraints. Activate after story generation, after plan preparation, before implementation, or after remediation attempts. Reports issues — does not fix them.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CONSISTENCY-CHECK-001
  updated_at: 2026-01-30
inputs:
  - contexts/artefacts/**  (Epics, Stories, Plans, PRDs as applicable)
  - contexts/rules/**
  - memory_context_bundle  (optional)
outputs:
  - consistency_report.md
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

---

## Output Format

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

---

## Non-Goals

This skill must NOT:
- Invent fixes
- Suppress issues
- Judge without evidence

**Check everything against everything. Consistency is a governance requirement, not an optimization.**
