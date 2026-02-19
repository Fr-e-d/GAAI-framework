---
name: risk-analysis
description: Systematically identify and structure product, delivery, and systemic risks before they become failures. Activate before finalizing Epics and Stories, before execution planning, after repeated QA failures, or after major scope changes.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-RISK-ANALYSIS-001
  updated_at: 2026-01-27
inputs:
  - contexts/artefacts/**  (PRD, Epics, Stories, Plans as provided)
  - memory_context_bundle  (optional)
outputs:
  - risk_report.md
  - flagged_risks  (structured list)
---

# Risk Analysis

## Purpose / When to Activate

Activate:
- Before finalizing Epics & Stories
- Before execution planning
- After repeated QA failures
- After major scope changes

This skill makes risks **explicit, prioritized, and actionable**. It does not solve problems.

---

## Process

1. Read provided artefacts fully
2. Load relevant memory (if supplied)
3. Scan for: ambiguity, assumptions, complexity spikes, constraint conflicts, missing validations
4. For each risk: describe clearly, classify type, assess impact and likelihood, propose mitigation direction (not solution)
5. Rank risks by severity

---

## Risk Categories

**Product risks:** unclear outcomes, wrong user assumptions, missing edge cases, scope creep

**Delivery risks:** technical feasibility, hidden dependencies, performance/security concerns, testability gaps

**Systemic risks:** architectural erosion, rule violations, knowledge loss, repeated failure patterns

---

## Output Format

Each risk:

```
### RISK-ID

Type: product | delivery | systemic
Description: clear concise risk
Impact: low | medium | high | critical
Likelihood: low | medium | high
Why it matters: concrete consequence
Suggested mitigation direction: what needs clarification, validation or control
```

---

## Quality Checks

- No vague risks ("might be complex" is invalid)
- Each risk is actionable
- Severity is explicit
- No risk inflation
- Focus on real failure points

---

## Non-Goals

This skill must NOT:
- Invent risks without evidence
- Propose detailed solutions
- Bypass artefacts
- Produce long lists of low-signal risks

**Unseen risk is what breaks AI-driven delivery. Surfaced risk is what makes it predictable.**
