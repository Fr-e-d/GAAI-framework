---
name: validate-artefacts
description: Validate that all Discovery artefacts (Epics, Stories) are clear, governed, complete, and safe to pass into Delivery. Activate after generating Epics or Stories and before any Delivery planning. This is the mandatory Discovery → Delivery gate.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.1"
  category: discovery
  track: discovery
  id: SKILL-VALIDATE-ARTEFACTS-001
  updated_at: 2026-04-18
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
- Has `related_decs` field in frontmatter (list or explicit empty `[]`)
- Has `skills_invoked` field in frontmatter (must list the skill IDs that were read to produce it)

### `impl_model` Field Validation (optional field — E94)

The `impl_model` field is **optional**. Stories without it validate exactly as before (non-regression guarantee).

**Valid values:** `['primary', 'secondary']` — checked as a list lookup, not an if/else chain, so V2 extension (e.g., `tertiary`) is a one-line change.

| Condition | Verdict |
|---|---|
| `impl_model` absent (story frontmatter or backlog entry) | **PASS** — default behavior |
| `impl_model: primary` | **PASS** |
| `impl_model: secondary` | **PASS** |
| Any other value (e.g. `tertiary`, `claude-opus-4-6`, `""`) | **FAIL** — `impl_model must be 'primary' or 'secondary' (got: '<value>')` |
| `impl_model` in frontmatter AND backlog entry with different values | **FAIL** — `impl_model mismatch: frontmatter=<X>, backlog=<Y>` |

**Field location rules (AC6 — canonical resolution):**
- **Canonical source:** the backlog entry (`active.backlog.yaml`). Delivery reads `impl_model` from the backlog at claim time.
- **Advisory source:** story frontmatter (`.story.md`). Allows Discovery to author the tag authoritatively.
- If only one source is present → accept it.
- If both are present and agree → PASS.
- If both are present and differ → **FAIL** with mismatch message above.

Test fixtures: `.gaai/core/skills/discovery/validate-artefacts/tests/impl_model.test.yaml`

### Cross-checks
- No Story exists without a parent Epic
- No scope contradictions with memory
- No rule violations
- Marketing artefacts (if present): hypothesis statuses align with Story acceptance criteria
- Strategy artefacts (if present): GTM phases align with Epic dependencies and gates
- **Epic dependency propagation check:** If the parent Epic's `## Dependencies` section lists other Epics, verify that every Story's `depends_on` includes at least one terminal story from each listed Epic. A phasing constraint in Epic prose that is not encoded in story `depends_on` is a **FAIL** — the daemon cannot enforce prose constraints, only `depends_on` fields.

### Skill Attestation (Base Rule #2 Enforcement)
- **Every artefact** (Epic, Story, PRD) must have a `skills_invoked` field in its frontmatter
- Epic artefacts must include `generate-epics` in `skills_invoked`
- Story artefacts must include `generate-stories` in `skills_invoked`
- PRD artefacts must include `create-prd` in `skills_invoked`
- An artefact with a missing or empty `skills_invoked` field is an automatic **FAIL** — the producing agent did not follow Base Rule #2
- This check exists because agents can produce format-correct artefacts from cached knowledge while silently skipping mandatory process steps defined in the skill file

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

Skill Attestation (Base Rule #2):
- E01: skills_invoked: [generate-epics] ✓ | MISSING ✗
- S01: skills_invoked: [generate-stories] ✓ | MISSING ✗
- S01: related_decs: [DEC-11] ✓ | MISSING ✗

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
- Any artefact is missing `skills_invoked` in frontmatter (Base Rule #2 violation)
- Any Story is missing `related_decs` in frontmatter

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
