---
type: reference
skill: pattern-transfer
id: PATTERN-TRANSFER-TAGS-001
updated_at: 2026-03-20
---

# Structural Tag Taxonomy

This document defines the controlled vocabulary of structural tags used by `pattern-transfer` for cross-domain pattern discovery. Tags describe structural relationships and roles, NOT domain-specific content.

---

## Purpose

Structural tags enable pattern matching across domains by describing HOW a pattern works (its structure) rather than WHAT it works on (its domain). Two patterns in completely different domains can share the same structural tags if they use similar organizational principles.

**Example:** An editorial curation pipeline and a data preprocessing pipeline both use the `pipeline` + `separation-of-concerns` tags, even though one operates on text and the other on datasets.

---

## Tag Categories

### Flow Patterns

Tags describing how information or control flows through the system.

| Tag | Description | Example |
|---|---|---|
| `pipeline` | Sequential processing stages where output of one stage feeds the next | ETL pipeline, content production pipeline |
| `feedback-loop` | Output is evaluated and fed back to modify earlier stages | Skill optimize cycle, A/B test iteration |
| `fan-out-fan-in` | Single input split into parallel tracks, results merged | Multi-platform social adaptation, parallel sub-agent delivery |
| `event-driven` | Actions triggered by events rather than sequential flow | Webhook handlers, notification systems |
| `information-asymmetry` | Downstream stages deliberately lack access to upstream raw data | Editorial curator pattern (renderer has no source access) |
| `batch-then-select` | Generate multiple candidates, then score and select the best | Image generation (generate 3-5, select best), A/B testing |

### Role Patterns

Tags describing the roles and responsibilities within the pattern.

| Tag | Description | Example |
|---|---|---|
| `separation-of-concerns` | Distinct components handle distinct responsibilities with clean boundaries | Curator/renderer split, agent/skill split |
| `curator-renderer` | One component selects/structures content, another presents it | Editorial curator pattern, data visualization pipeline |
| `validator-executor` | One component validates, another executes (validation gates execution) | QA review → implement cycle, eval-run → skill-optimize |
| `mediator` | A central component coordinates others without them knowing each other | Delivery agent coordinating sub-agents |
| `gatekeeper` | A component that enforces a quality/governance gate before progression | Risk gate in pattern-transfer, validation gate in discovery |
| `specialist-generalist` | Specialized components invoked by a generalist orchestrator | Sub-agent specialists, domain skill packs |

### Learning Patterns

Tags describing how the system learns, adapts, or improves.

| Tag | Description | Example |
|---|---|---|
| `generate-and-select` | Produce multiple variants, evaluate, keep the best | Image generation, hypothesis testing |
| `iterative-refinement` | Improve output through repeated cycles of feedback and revision | Skill optimize loop, discovery auto-refinement |
| `retrospective-extraction` | Extract reusable lessons from completed work | Post-mortem learning, friction retrospective |
| `knowledge-accumulation` | Progressive building of a knowledge base over time | Memory ingest, decision extraction |
| `transfer-learning` | Apply knowledge from one context to a structurally similar context | Pattern transfer itself |

---

## Tagging Rules

1. **Assign 1-4 tags per pattern.** Fewer = more precise matching. More than 4 = too generic.
2. **Use the most specific tag that applies.** If `curator-renderer` fits, prefer it over `separation-of-concerns` (though both may apply).
3. **Tags are structural, not domain-specific.** Never tag with domain names (e.g., "content", "video"). Domain information belongs in the pattern card's frontmatter, not in structural tags.
4. **Multiple categories are normal.** A pattern often combines a flow pattern with a role pattern (e.g., `pipeline` + `curator-renderer`).
5. **If no existing tag fits, document the gap.** Do not invent ad-hoc tags. Propose a new tag with description and examples, then add it to this taxonomy via a governed update.

---

## Tag Matching for Pattern Discovery

When `pattern-transfer` Step 1 searches for candidate patterns:

1. Compare the target problem's structural tags against each pattern's `structural_tags` list.
2. Count matching tags (intersection).
3. Rank by match count (descending).
4. Minimum 1 matching tag required for candidacy.

**Tie-breaking:** When two patterns have the same match count, prefer the one with higher `confidence` score.

---

## Adding New Tags

New structural tags may be needed as the pattern catalog grows. To add a tag:

1. Verify no existing tag covers the structural concept.
2. Write a description (1 sentence) and at least 2 examples from different domains.
3. Place the tag in the most appropriate category (flow, role, or learning).
4. Update this file via a governed change (commit with clear rationale).

Do NOT add tags speculatively. A tag without at least 2 real-world examples across different domains is premature.
