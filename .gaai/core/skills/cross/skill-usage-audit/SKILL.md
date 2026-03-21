---
name: skill-usage-audit
description: Scan all artefacts (epics, stories, PRDs) for Base Rule #2 compliance — verify that every artefact declares skills_invoked and related_decs in frontmatter. Produces an audit report with pass/fail per artefact and overall compliance rate.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: governance
  id: SKILL-CRS-028
  updated_at: 2026-03-21
  status: stable
inputs:
  - contexts/artefacts/epics/*.epic.md
  - contexts/artefacts/stories/*.story.md
outputs:
  - skill_usage_audit_report (inline)
---

# Skill Usage Audit

## Purpose / When to Activate

Activate:
- Periodically (e.g., after a Discovery session) to verify governance compliance
- Before a release or milestone to audit artefact quality
- When trust in agent compliance needs verification
- On demand by the human (`/gaai-status` or direct invocation)

This skill enforces **Base Rule #2 (Skill-first)** by scanning artefacts for the `skills_invoked` attestation field. It detects artefacts that were produced from cached knowledge without reading the corresponding skill file.

---

## Process

1. **Scan all Epic files** at `contexts/artefacts/epics/*.epic.md` (exclude `_template.epic.md`):
   - Check frontmatter for `skills_invoked` field
   - If present: verify it includes `generate-epics`
   - If missing: mark as **FAIL**

2. **Scan all Story files** at `contexts/artefacts/stories/*.story.md` (exclude `_template.story.md`):
   - Check frontmatter for `skills_invoked` field
   - If present: verify it includes `generate-stories`
   - If missing: mark as **FAIL**
   - Check frontmatter for `related_decs` field
   - If missing: mark as **FAIL** (separate from skills_invoked)
   - Check frontmatter for `epic` field
   - If missing: mark as **WARN**

3. **Produce audit report** with:
   - Per-artefact pass/fail status
   - Compliance rate: `(passing artefacts / total artefacts) × 100`
   - List of non-compliant artefacts for remediation
   - Timestamp of audit

---

## Outputs

```
Skill Usage Audit Report — {date}

Epics scanned: {count}
Stories scanned: {count}

Non-compliant artefacts:
- {id}: FAIL — missing skills_invoked
- {id}: FAIL — missing related_decs
- {id}: WARN — missing epic field

Compliance rate: {n}/{total} ({pct}%)

Verdict: CLEAN | {n} VIOLATIONS FOUND
```

---

## Remediation

For each non-compliant artefact, the human or agent must:
1. Read the corresponding skill file (`generate-stories/SKILL.md` or `generate-epics/SKILL.md`)
2. Verify the artefact content follows all process steps
3. Add the missing frontmatter fields
4. Commit the fix

This skill does NOT auto-fix artefacts — it reports only. Remediation is a conscious act.

---

## Quality Checks

- Every artefact file in the scan directories is checked (no silent skips)
- Template files (`_template.*`) are excluded from the scan
- The report clearly distinguishes FAIL (blocking) from WARN (advisory)
- Compliance rate is computed correctly

---

## Non-Goals

This skill must NOT:
- Auto-fix artefacts (report only — remediation is deliberate)
- Check artefact content quality (use `validate-artefacts` for that)
- Scan non-artefact files (memory, decisions, patterns)
