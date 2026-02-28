---
name: validate-artefacts
description: Validate that all Discovery artefacts (Epics, Stories) are clear, governed, complete, and safe to pass into Delivery. Activate after generating Epics or Stories and before any Delivery planning. This is the mandatory Discovery → Delivery gate.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-VALIDATE-ARTEFACTS-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - contexts/artefacts/epics/**
  - contexts/artefacts/stories/**
  - contexts/artefacts/prd/**  (optional)
  - contexts/artefacts/marketing/**  (optional — observation logs, validated hypotheses)
  - contexts/artefacts/strategy/**  (optional — GTM plans, positioning)
  - contexts/rules/**
  - contexts/memory/**  (selective)
outputs:
  - validation_report
  - updated artefact status (optional)
---

# Validate Artefacts

## Purpose / When to Activate

Activate:
- After generating Epics
- After generating Stories
- Before any Delivery planning or execution

This is the **mandatory gate** between Discovery and Delivery. No Story proceeds to Delivery without passing this check.

---

## Process

### Epic Validation
- Expresses a user outcome (not a feature or technical task)
- Aligns with product direction
- Avoids technical implementation detail
- Clearly scoped with no hidden assumptions

### Story Validation
- Maps to a parent Epic
- Includes measurable acceptance criteria
- Is unambiguous and executable
- Respects governance rules
- Avoids solution design

### Cross-checks
- No Story exists without a parent Epic
- No scope contradictions with memory
- No rule violations
- Marketing artefacts (if present): hypothesis statuses align with Story acceptance criteria
- Strategy artefacts (if present): GTM phases align with Epic dependencies and gates

---

## Outputs

```
Validation Report — Discovery

Epics:
- E01: PASS | FAIL — reason
- E02: PASS | FAIL — reason

Stories:
- S01: PASS | FAIL — reason
- S02: PASS | FAIL — reason

Governance:
- rules respected: yes | no
- missing artefacts: none | list
- risks detected: none | list

Overall Status:
PASS | BLOCKED
```

---

## Blocking Conditions

The skill MUST block progression if:
- Any Story lacks acceptance criteria
- Epics are solution-oriented rather than outcome-oriented
- Scope is unclear or ambiguous
- Governance rules are violated
- Contradictions exist between artefacts

**No partial approval. No silent warnings.**

---

## Non-Goals

This skill must NOT:
- Rewrite artefacts
- Invent missing content
- Make product decisions
- Soften failures

**It validates — it does not fix. If Delivery can misunderstand it, Discovery is not done.**

On BLOCKED verdict: the Discovery Agent must invoke `refine-scope` to resolve the identified gaps, then re-run this skill. Do not proceed to Delivery until the verdict is PASS.
