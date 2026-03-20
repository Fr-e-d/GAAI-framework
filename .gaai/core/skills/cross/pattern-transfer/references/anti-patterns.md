---
type: reference
skill: pattern-transfer
id: PATTERN-TRANSFER-AP-001
updated_at: 2026-03-20
---

# Pattern Transfer — Anti-Patterns and Risks

This document catalogs known risks in cross-domain pattern transfer. Each risk was identified through research across analogical reasoning literature (Gentner 1983, Boxology 2021, Corneli et al. 2025) and real-world transfer failure analyses.

---

## Risk 1: Negative Transfer

**Definition:** Applying a pattern from a source domain actually degrades performance in the target domain compared to developing a solution from scratch.

**When it happens:**
- Surface-level similarity masks deep structural differences
- The source domain's constraints don't exist in the target domain, making the pattern's structure unnecessary overhead
- The pattern's assumptions about data flow or role separation create friction in the target domain

**Real-world analog:** In machine learning, negative transfer occurs in ~30% of transfer learning attempts (Rosenstein et al., 2005). The rate is likely similar in architectural pattern transfer.

**Mitigation in skill-optimize:**
- Structural invariant checking (Step 2) catches structural mismatches before transfer
- Post-transfer validation (Step 6) detects negative transfer after delivery
- Confidence scoring ensures unproven patterns (-1 on failure) are deprioritized
- The risk gate (Step 5) escalates high-risk transfers to human judgment

---

## Risk 2: False Analogy (Surface Similarity Trap)

**Definition:** Two problems LOOK similar (same vocabulary, same domain adjacency) but have fundamentally different structural requirements.

**When it happens:**
- Pattern matching based on domain keywords instead of structural tags
- The target problem uses the same terminology but different information flows
- Humans see "curation" in both domains and assume the same pattern applies

**Example:** "Data curation" and "editorial curation" share the word "curation" but may have opposite invariants: editorial curation REMOVES data (selects the best subset), while data curation may need to PRESERVE all data (clean and organize without loss).

**Mitigation in pattern-transfer:**
- Matching is by structural tags, not domain keywords (Step 1)
- Every structural invariant is individually verified in the target domain (Step 2)
- Contraindication checking catches domain-specific exclusions
- The skill explicitly rejects surface-only matches (Non-Goals section)

---

## Risk 3: Overgeneralization

**Definition:** A pattern that works in 2-3 specific domains is assumed to be universal, leading to premature promotion to `domain-agnostic` status.

**When it happens:**
- Small sample size: 2 successful transfers creates false confidence
- Confirmation bias: only successful transfers are documented, failures are forgotten
- The shared structural tags happen to be common (e.g., `pipeline`) rather than discriminating

**Mitigation in pattern-transfer:**
- Promotion to `domain-portable` requires 3+ validated domains (not 2)
- Every validation records `result: success | failure` — failures are not hidden
- Confidence score increases gradually (+1 per success, max 5)
- The transfer_log preserves full history including adaptations needed (revealing how much the pattern had to bend)

---

## Risk 4: Algorithmic Transference

**Definition:** Transferring the specific IMPLEMENTATION of a pattern rather than its STRUCTURAL principle. The target domain gets a copy of the source domain's solution rather than an adaptation.

**When it happens:**
- Pattern cards describe implementation details instead of structural relationships
- The "Required Adaptations" section of the transfer proposal is empty or trivial
- The executor (Delivery Agent) treats the pattern as a template to copy rather than a principle to instantiate

**Example:** Transferring the editorial curator pattern to data processing by copying the exact brief template and renaming fields, instead of understanding WHY the brief structure works (information asymmetry) and redesigning for data contexts.

**Mitigation in pattern-transfer:**
- Structural invariants describe relationships, not implementations (pattern-card-format.md rule)
- Transfer proposals must include a "Required Adaptations" section (Step 4)
- The "What Stays Invariant" section forces explicit identification of what transfers vs. what changes
- Post-transfer validation checks whether the adaptation was genuine or cosmetic

---

## Risk 5: Hallucination Propagation

**Definition:** The LLM fabricates structural similarities that don't exist, producing plausible-sounding but incorrect transfer proposals.

**When it happens:**
- LLMs are strong at analogical reasoning but can over-extend patterns (Corneli et al., 2025)
- The target problem description is vague, giving the model latitude to "find" matches
- Structural invariant checking is performed as a reasoning exercise rather than a concrete verification

**Mitigation in pattern-transfer:**
- Invariant checking requires explicit PASS/FAIL with justification for each invariant (Step 2)
- The risk gate (Step 5) ensures medium and high-risk proposals get human review
- The skill cannot auto-apply patterns — human decision is always required for execution
- Contraindication checking provides a negative filter (easier to verify "this doesn't apply" than "this does apply")

---

## Risk 6: Cognitive Biases in Transfer Decisions

**Definition:** Human reviewers at the risk gate may accept or reject transfers based on cognitive biases rather than structural analysis.

**Specific biases:**
- **Anchoring:** The first transfer proposal shown influences judgment of subsequent proposals
- **Availability bias:** Recent successful transfers make humans overconfident in the next transfer
- **Not-invented-here:** Humans reject valid transfers because the pattern "came from somewhere else"
- **Sunk cost:** Humans accept dubious transfers because significant analysis effort was invested

**Mitigation in pattern-transfer:**
- Transfer proposals include structured risk assessments with concrete metrics (alignment score, distance rating, confidence)
- Multiple candidates are presented with explicit comparison (Step 4 produces proposals for each viable candidate)
- The three-value recommendation (`transfer`, `adapt-then-transfer`, `too-distant-reject`) constrains the decision space
- Post-transfer validation provides objective feedback that corrects biases over time
- The ledger of outcomes (pattern card's `validated_in` and `transfer_log`) creates an empirical record that overrides subjective impressions
