---
type: reference
skill: pattern-transfer
id: PATTERN-TRANSFER-FORMAT-001
updated_at: 2026-03-20
---

# Enhanced Pattern Card Format

This document defines the extended frontmatter fields required for pattern cards to participate in cross-domain pattern transfer. These fields augment the existing GAAI memory file format.

---

## Overview

Pattern cards live in `contexts/memory/patterns/`. They are standard GAAI memory files with additional structural metadata that enables the `pattern-transfer` skill to discover, align, and validate transfers across domains.

---

## Required Extensions (New Fields)

These fields must be added to the YAML frontmatter of any pattern card that should be discoverable by `pattern-transfer`.

### `abstraction_level`

```yaml
abstraction_level: domain-specific | domain-portable | domain-agnostic
```

| Level | Definition | Transfer implications |
|---|---|---|
| `domain-specific` | Pattern is validated in exactly 1 domain | Transfer is speculative — requires full invariant checking |
| `domain-portable` | Pattern is validated in 3+ different domains | Transfer is lower risk — structural invariants are proven |
| `domain-agnostic` | Pattern applies universally regardless of domain | No transfer needed — pattern is directly applicable |

**Default for new patterns:** `domain-specific` (until validated in multiple domains).

### `structural_tags`

```yaml
structural_tags:
  - pipeline
  - separation-of-concerns
  - curator-renderer
```

Tags from the controlled vocabulary in `references/structural-tags.md`. These are the PRIMARY matching mechanism for pattern discovery. See that document for the full taxonomy and tagging rules.

### `structural_invariants`

```yaml
structural_invariants:
  - "Upstream agent curates; downstream agent has no access to raw sources"
  - "Output quality benefits from stochastic variance (generate N, select best)"
  - "Style constraints are data (part of the brief), not code (not hardcoded in the renderer)"
```

Statements that MUST be true for the pattern to function correctly. These are the core structural relationships that define the pattern. If any invariant fails in a target domain, the transfer is rejected.

**Writing good invariants:**
- State the relationship, not the implementation ("X curates, Y renders" not "use Claude for X and Gemini for Y")
- Each invariant should be independently verifiable in a new domain
- 2-5 invariants per pattern is typical. Fewer = pattern is too simple to formalize. More = pattern may need decomposition.

### `applicability_conditions`

```yaml
applicability_conditions:
  - "Output quality benefits from stochastic variance"
  - "Source material is richer than what the final output can contain (curation adds value)"
  - "The rendering medium has autonomous creative capability"
```

Conditions under which the pattern is MOST effective. Unlike invariants (which are hard requirements), applicability conditions are soft signals that increase confidence in transfer viability.

### `contraindications`

```yaml
contraindications:
  - "Domain requires deterministic, reproducible output"
  - "All source data must appear in the output (no curation allowed)"
  - "The rendering step is a pure formatting transform with no creative latitude"
```

Conditions under which the pattern should NOT be applied. These are checked during `pattern-transfer` Step 2. If any contraindication matches the target domain, the candidate is filtered out.

### `confidence`

```yaml
confidence: 2  # Scale: 0-5
```

A numeric confidence score reflecting how well-validated the pattern is:

| Score | Meaning |
|---|---|
| 0 | Theoretical — never tested |
| 1 | Single anecdotal success |
| 2 | Validated in 1 domain with measurable evidence |
| 3 | Validated in 2 domains |
| 4 | Validated in 3+ domains (domain-portable) |
| 5 | Widely validated, domain-agnostic |

Updated by `pattern-transfer` Step 6: +1 on successful transfer, -1 on failed transfer.

### `validated_in`

```yaml
validated_in:
  - domain: content-production
    date: 2026-03-08
    result: success
    decision_ref: DEC-{N}
```

History of domains where the pattern has been applied, with outcomes. Append-only — entries are never removed.

| Field | Type | Description |
|---|---|---|
| `domain` | string | The domain where the pattern was applied |
| `date` | ISO 8601 | Date of validation |
| `result` | `success` or `failure` | Outcome |
| `decision_ref` | string (optional) | Reference to the decision that documented the validation |

### `transfer_log` (Optional)

```yaml
transfer_log:
  - from_domain: content-production
    to_domain: data-curation
    date: 2026-04-15
    outcome: success
    adaptations: "Replaced editorial brief with data specification document"
    notes: "Invariant 1 (upstream curates) held perfectly"
```

Detailed log of transfer attempts. More granular than `validated_in`. Created by `pattern-transfer` Step 6 post-validation.

---

## Complete Enhanced Pattern Card Example

```yaml
---
type: memory
category: pattern
id: PAT-EDITORIAL-CURATOR-001
abstraction_level: domain-specific
structural_tags:
  - pipeline
  - separation-of-concerns
  - curator-renderer
  - information-asymmetry
  - batch-then-select
structural_invariants:
  - "Upstream agent curates; downstream agent has no access to raw sources"
  - "Output quality benefits from stochastic variance (generate N, select best)"
  - "Style constraints are data (part of the brief), not code (not hardcoded)"
applicability_conditions:
  - "Source material is richer than what the final output can contain"
  - "The rendering medium has autonomous creative capability"
  - "Multiple output variants are cheap to produce"
contraindications:
  - "Domain requires deterministic, reproducible output"
  - "All source data must appear in the output (no curation)"
  - "The rendering step is a pure formatting transform"
confidence: 2
validated_in:
  - domain: content-production
    date: 2026-03-08
    result: success
    decision_ref: DEC-{N}
tags:
  - visual-production
  - infographic
  - editorial
created_at: 2026-03-06
updated_at: 2026-03-20
source: >
  NotebookLM infographic system prompt, LLM-Grounded Diffusion,
  Infogen, Microsoft LIDA, Google Gemini best practices
informed_by: [visual-production-guide.md, content-visual/SKILL.md]
usage: Load before any skill that uses the editorial curator pipeline
---

# Editorial Curator Pattern (PAT-EDITORIAL-CURATOR-001)
{... pattern body ...}
```

---

## Retrofit Procedure

For existing pattern cards that lack the new fields:

1. Read the pattern body to understand its structural characteristics.
2. Assign `structural_tags` from `references/structural-tags.md`.
3. Extract `structural_invariants` from the pattern's core principles.
4. Derive `applicability_conditions` from the pattern's "when to use" guidance.
5. Derive `contraindications` from the pattern's anti-patterns or "when NOT to use."
6. Set `abstraction_level` based on `validated_in` count (default: `domain-specific`).
7. Set `confidence` based on evidence: 0 (theoretical) to 2 (validated with data in 1 domain).
8. Populate `validated_in` from any documented validations.

**Do NOT invent invariants or conditions.** Only formalize what the pattern body already states or strongly implies.
