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

**CRITICAL — Anti-Collision Guard (MUST execute before writing any output file):**
Before writing `contexts/artefacts/consistency-reports/{story_id}.consistency-report.md`, check if the target file already exists on disk:
- If it does NOT exist → proceed normally.
- If it DOES exist → **read the existing file first**. Then decide:
  - If the existing content is from a **different entity** (different story ID, different epic) → **STOP immediately**, surface the ID collision to the human, do not proceed.
  - If the existing content is from the **same entity** and an update is warranted → proceed, but preserve any human edits or prior findings that remain relevant. Treat this as an **update**, not a replacement.
  - If the existing content is identical or still valid → skip writing, report "no changes needed".
This guard prevents the silent data loss incident of 2026-03-17 where concurrent sessions overwrote story files.

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
