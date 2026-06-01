---
name: validate-artefacts
description: Validate that all Discovery artefacts (Epics, Stories) are clear, governed, complete, and safe to pass into Delivery. Activate after generating Epics or Stories and before any Delivery planning. This is the mandatory Discovery → Delivery gate.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.2"
  category: discovery
  track: discovery
  id: SKILL-VALIDATE-ARTEFACTS-001
  updated_at: 2026-05-31
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
- `required_skills` field is optional. If present, it must be a YAML list (e.g.
  `required_skills: [name-a, name-b]`). A bare string, map, or other non-list type
  returns BLOCKED: `required_skills must be a YAML list (got: <type>)`.
- Each string entry in `required_skills` must resolve to an existing custom skill via
  the project skills index (`.gaai/project/skills/skills-index.yaml`) or directly as
  `.gaai/project/skills/<track>/<name>/SKILL.md`. A non-resolving entry returns
  BLOCKED: `required_skills entry '<name>' not found in project skills`.
- Each entry in `required_skills` must have at least one AC in the story body that
  names the observable output of that skill. An entry with no co-declared output AC
  returns BLOCKED: `required_skills entry '<name>' has no bound output AC — add an AC
  naming the observable output the skill must produce`.
- Absence of `required_skills` (field missing or `required_skills: []`) does not affect
  any other validation. Non-regression for stories that do not use custom skills.

### Story Scope Pre-Flight (Plan contract symmetry)

The Plan phase agent enforces hard scope caps before producing an execution plan:
**>10 distinct files modified OR created**, **>6 acceptance criteria**, or **>300 lines of code projected** all trigger a plan-block + decomposition demand and waste a full Delivery cycle (worktree spin, branch chore commit, then PLAN exit non-zero with `plan-blocked.md`). To prevent this Discovery → Refined → Plan-blocked round-trip, this skill enforces the **same caps** at the Discovery gate. The Refined contract MUST guarantee Plan-feasibility upstream.

**Cap enforcement is hard, not advisory.**

| Cap | Threshold | Source of truth in story |
|---|---|---|
| Files | ≤ 10 distinct files modified or created | `## File Inventory` section (mandatory for any multi-file story) |
| Acceptance criteria | ≤ 6 | counted from `## Acceptance Criteria` bullets |
| LOC projection | ≤ 300 | optional `loc_estimate` line in File Inventory, summed |

**Multi-file detection (when File Inventory is mandatory):**

A story requires a `## File Inventory` section if BOTH of the following are true (concrete signals — vibe-only triggers produce false-positives on legitimate single-file refactor stories):

- (signal 1 — language) Title or body contains at least one of: "migrate ... to", "centralise", "eliminate ... regex", "scan-and-replace", "audit across", "every consumer", "all sites", "all callers", "across the codebase", or analogous explicit cross-cutting framing
- (signal 2 — concrete references) The story body OR acceptance criteria reference at least **2 distinct file paths** (e.g. `path/to/foo.sh` + `path/to/bar.sh`). A single-file refactor mentioning one file fails this signal and is NOT subject to the File Inventory requirement.

When BOTH signals match, the story body MUST contain a `## File Inventory` section listing each file to be modified or created, with a 1-line scope note per file (and an optional `loc_estimate` per row). Stories matching the detection criteria without this section are BLOCKED — the validator cannot compute the file cap without an explicit list.

A `## File Inventory` listing more than 10 files is BLOCKED. Discovery must decompose before re-running this skill. This is the PLAN contract symmetry — any story that would plan-block at Delivery MUST be caught here instead. There is no escape hatch in V1: the cap mirrors the Plan agent's hard cap exactly, and the Plan agent does not honor exemption flags. Truly atomic cross-file refactors are vanishingly rare ; if encountered, raise the cap in BOTH this skill AND the Plan agent prompt as a single coordinated decision.

**Single-file stories** (one of the two detection signals does not match) may omit the File Inventory section. AC and LOC caps still apply.

**Rationale (why this lives in the Discovery gate, not in Plan only):**

The Plan phase agent is the executor — its scope caps protect single-pass implementation reliability. But by the time PLAN runs, the wrapper has already spun a worktree, made a chore commit, and consumed a retry slot. Mirroring the caps here closes the gap: Discovery never produces a Refined story that PLAN would block. Defense-in-depth at the wrapper exit trap (reconcile to status=blocked when `plan-blocked.md` is detected) catches any edge case this skill misses.

---

### `impl_model` Field Validation (optional field — E94)

The `impl_model` field is **optional**. Stories without it validate exactly as before (non-regression guarantee).

**Valid values:** `['primary', 'secondary']` — checked as a list lookup, not an if/else chain, so V2 extension (e.g., `tertiary`) is a one-line change.

| Condition | Verdict |
|---|---|
| `impl_model` absent (story frontmatter or backlog entry) | **PASS** — default behavior |
| `impl_model: primary` | **PASS** |
| `impl_model: secondary` (any tier) | **PASS** — Tier × impl_model hard-gate retired ; daemon hard-gate previously removed ahead of formal decision. Fallback to primary on secondary failure is preserved via the universal-cascade fallback policy. |
| Any other value (e.g. `tertiary`, `claude-opus-4-6`, `""`) | **FAIL** — `impl_model must be 'primary' or 'secondary' (got: '<value>')` |
| `impl_model` in frontmatter AND backlog entry with different values | **FAIL** — `impl_model mismatch: frontmatter=<X>, backlog=<Y>` |

**Field location rules (AC6 — canonical resolution):**
- **Canonical source:** the backlog entry (`active.backlog.yaml`). Delivery reads `impl_model` from the backlog at claim time.
- **Advisory source:** story frontmatter (`.story.md`). Allows Discovery to author the tag authoritatively.
- If only one source is present → accept it.
- If both are present and agree → PASS.
- If both are present and differ → **FAIL** with mismatch message above.

#### Tier × impl_model compatibility (skill-side gate retired)

Current routing doctrine :
- **Default routing** : `impl_model` ABSENT → `secondary` when env-configured (else `primary`, OSS non-regression)
- **Fallback** : secondary spawn failure (any class) → primary subprocess via the universal-cascade fallback policy (preserved)
- **Tier 2 stories needing primary's stronger reasoning** : declare `impl_model: primary` explicitly per story author judgment. The current decision does NOT auto-coerce Tier 2 to primary (former hard-gate behavior is removed).

This skill now :
- Enforces only the `primary | secondary` value list (lines 65-71)
- Enforces frontmatter / backlog parity
- No longer pre-blocks any `tier × impl_model` combination (the prior tier-aware hard-gate is retired)

**Setting `impl_model: secondary` explicitly**: always passes. Useful for cost-optimal stories where the author has verified the secondary model's context budget is comfortably sufficient OR is comfortable relying on the universal-cascade fallback.

**Setting `impl_model: primary` explicitly**: always passes. Useful for Tier 2+ stories needing stronger reasoning, security/compliance-critical work, or other sensitivity overrides.

**Leaving `impl_model` ABSENT**: routes to default (secondary when env-configured else primary). Recommended for Tier 1 stories.

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
- S01: related_decs: [<DEC-id>] ✓ | MISSING ✗

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
- A multi-file story (both detection signals match) is missing the `## File Inventory` section
- A `## File Inventory` lists more than 10 files (no V1 escape hatch — decompose)
- Acceptance criteria count exceeds 6 (Plan contract symmetry)
- A `loc_estimate` total in File Inventory exceeds 300 (Plan contract symmetry)
- `required_skills` entry present without a co-declared output AC in the story body
  (unbound contract — per the contract-carried delivery invariant)
- `required_skills` entry does not resolve to an existing custom skill in
  `.gaai/project/skills/` (referential integrity failure)
- `required_skills` value is not a YAML list (malformed field)

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
