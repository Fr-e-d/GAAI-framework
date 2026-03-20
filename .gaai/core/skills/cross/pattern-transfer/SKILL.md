---
name: pattern-transfer
description: Discover structurally similar patterns across domains, assess transfer viability via structural invariant checking, and propose domain adaptations with risk gates. Activate when Discovery identifies a problem that may have been solved in another domain.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-027
  updated_at: 2026-03-20
  status: experimental
inputs:
  - target_problem: description of the problem in the target domain
  - target_domain: the domain where the problem exists
  - structural_tags: (optional) structural characteristics of the problem (e.g., "pipeline", "separation-of-concerns")
  - "contexts/memory/patterns/** (existing pattern catalog)"
  - "contexts/memory/index.md (to discover patterns)"
outputs:
  - "Transfer proposal document (inline or sessions/transfer-proposal-{id}.md)"
  - "Updated pattern card (if transfer validated post-delivery)"
---

# Pattern Transfer

## Purpose / When to Activate

Activate when:
- The Discovery Agent identifies a problem that may have been solved in another domain
- A structural similarity is noticed between a known pattern and a new problem context
- A validated pattern could apply to a different domain (cross-pollination opportunity)

This skill performs explicit cross-domain pattern transfer using structural alignment checking. It does NOT create new patterns (that is `post-mortem-learning` + `memory-ingest`). It discovers, validates, and proposes the transfer of existing patterns to new domains.

**Theoretical foundation:** Gentner's Structure-Mapping Theory (1983) — analogical transfer succeeds when structural relationships (not surface features) are preserved across domains. Alexander's Pattern Language (1977) — patterns are reusable solutions with explicit applicability conditions and contraindications.

**Status:** This skill is dormant until 3+ patterns exist in different domains in the pattern catalog. With fewer patterns, the transfer search space is too small for meaningful cross-domain discovery.

---

## Prerequisites

Before activating:
1. The pattern catalog (`contexts/memory/patterns/`) must contain at least 2 patterns with `structural_tags` in their frontmatter.
2. The target problem must be describable in structural terms (not just surface-level symptoms).
3. The invoking agent must provide a `target_domain` that differs from the source pattern's domain.

If the pattern catalog has no tagged patterns, STOP and report: "Pattern catalog lacks structural tags — run pattern card retrofit before invoking pattern-transfer."

---

## Process

### Step 1 — Pattern Discovery

1. Use `memory-search` (Mode C: structural tag filtering) to find candidate patterns from domains OTHER than `target_domain`.
2. Match by structural characteristics:
   - If `structural_tags` input is provided: match patterns sharing at least 1 tag
   - If not provided: infer structural tags from the `target_problem` description using the controlled vocabulary in `references/structural-tags.md`
3. Rank candidates by tag overlap count (more shared tags = higher rank).
4. Budget: top 5 candidates maximum. If more than 5 match, take the top 5 by tag overlap.
5. If zero candidates match: STOP and report "No structurally similar patterns found."

### Step 2 — Structural Alignment Check

For each candidate pattern:

1. Read the pattern card's `structural_invariants` list.
2. For each invariant, verify whether it holds in the target domain:
   - **PASS:** The invariant clearly applies in the target domain (explain why).
   - **FAIL:** The invariant does not hold or cannot be verified (explain why).
3. Check the pattern's `contraindications` list against the target domain context.
   - If any contraindication matches: mark the candidate as `contraindicated`.
4. Compute alignment score: `invariants_passed / invariants_total`.
5. Filter out candidates where:
   - Any structural invariant FAILS, OR
   - Any contraindication matches

### Step 3 — Domain Distance Assessment

For each surviving candidate, rate the structural distance between source and target domains:

| Distance | Criteria | Risk Level |
|---|---|---|
| `near` | Same industry, adjacent function (e.g., content-production → content-distribution) | Low |
| `medium` | Different industry, similar structure (e.g., content curation → data curation) | Moderate |
| `far` | Different industry, different function, structural match only (e.g., editorial curation → supply chain filtering) | High |

Record the distance rating with a one-sentence justification.

### Step 4 — Transfer Proposal

For each viable candidate (passed Step 2 alignment, assessed in Step 3), produce:

```markdown
## Transfer Proposal: {source pattern name} → {target domain}

### Source Pattern
- **Name:** {pattern name}
- **Domain:** {source domain}
- **Abstraction level:** {domain-specific | domain-portable | domain-agnostic}
- **Confidence:** {N/5}

### Structural Alignment
- **Invariants checked:** {N}
- **Invariants passed:** {N} (all must be N/N to reach this step)
- **Contraindications checked:** {N} — none triggered

### Domain Distance
- **Rating:** {near | medium | far}
- **Justification:** {one sentence}

### Required Adaptations
{What changes when moving from source domain to target domain. Be specific: which roles, which data types, which constraints differ.}

### What Stays Invariant
{The structural relationships that transfer directly without modification.}

### Risk Assessment
- **Risk level:** {low | medium | high}
- **Key risk:** {the single most likely failure mode}
- **Mitigation:** {how to detect or prevent the key risk}

### Recommendation
{transfer | adapt-then-transfer | too-distant-reject}
```

### Step 5 — Risk Gate

Apply risk gates based on the combined assessment:

| Condition | Action |
|---|---|
| Confidence >= 3/5 AND distance = near | Proceed — agent can recommend transfer |
| Confidence >= 2/5 AND distance = medium | **FLAG for human review** — proceed only if approved |
| Distance = far OR contraindication triggered in a related domain | **STOP and escalate** — human must decide |
| Confidence < 2/5 (regardless of distance) | **REJECT** — pattern is too unproven for transfer |

**The risk gate is non-negotiable.** High-risk transfers without human approval are a governance violation.

### Step 6 — Post-Transfer Validation (After Delivery)

This step executes AFTER the transferred pattern has been used in a delivery cycle. It is NOT part of the initial transfer proposal — it is invoked separately when delivery is complete.

1. Update the source pattern card's `validated_in` list:
   ```yaml
   validated_in:
     - domain: {target_domain}
       date: {ISO 8601}
       result: success | failure
       decision_ref: {DEC-NNN if applicable}
   ```
2. Update `confidence` score: +1 if success, -1 if failure (floor at 0, ceiling at 5).
3. Add entry to the pattern card's `transfer_log`.
4. If the pattern is now validated in 3+ domains: promote `abstraction_level` to `domain-portable`.
5. If the transfer failed: document the failure context in the pattern card's anti-patterns section.

---

## Quality Checks

- Every structural invariant produces an explicit PASS or FAIL with justification — no silent skips
- Transfer proposals include at least one contraindication check (even if none triggered)
- Risk gate is applied to every proposal — no proposals skip the gate
- Post-transfer validation is mandatory — no fire-and-forget transfers
- Pattern cards are append-only for `transfer_log` and `validated_in` — history is preserved
- Domain distance rating includes a justification — not just a label
- Recommendations are one of exactly three values: `transfer`, `adapt-then-transfer`, `too-distant-reject`

---

## Outputs

| Output | Path | Persistence |
|---|---|---|
| Transfer proposal | Inline or `sessions/transfer-proposal-{id}.md` | Session-scoped |
| Updated pattern card | `contexts/memory/patterns/{pattern-name}.md` | Permanent (append-only sections) |

---

## Non-Goals

This skill must NOT:
- Auto-apply patterns to the target domain (the agent + risk gate decide, then Delivery implements)
- Create new patterns (that is `post-mortem-learning` + `memory-ingest`)
- Modify source pattern cards during transfer proposal (only after post-delivery validation in Step 6)
- Skip structural invariant checking (primary safeguard against false analogies — see `references/anti-patterns.md`)
- Transfer patterns with `confidence < 1/5` (insufficient evidence for any transfer)
- Match patterns by surface similarity alone (keywords, domain names) — structural tags are the matching mechanism
- Override the risk gate under any circumstances

For the structural tag taxonomy, see `references/structural-tags.md`.
For the enhanced pattern card format, see `references/pattern-card-format.md`.
For documented anti-patterns and risks, see `references/anti-patterns.md`.

**No silent analogies. Every structural match, every invariant check, every risk assessment becomes explicit and governed.**
