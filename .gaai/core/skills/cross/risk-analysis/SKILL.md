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
  status: stable
inputs:
  - contexts/artefacts/**  (PRD, Epics, Stories, Plans as provided)
  - memory_context_bundle  (optional)
outputs:
  - contexts/artefacts/risk-reports/{story_id}.risk-report.md
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

**CRITICAL — Anti-Collision Guard (MUST execute before writing any output file):**
Before writing `contexts/artefacts/risk-reports/{story_id}.risk-report.md`, check if the target file already exists on disk:
- If it does NOT exist → proceed normally.
- If it DOES exist → **read the existing file first**. Then decide:
  - If the existing content is from a **different entity** (different story ID, different epic) → **STOP immediately**, surface the ID collision to the human, do not proceed.
  - If the existing content is from the **same entity** and an update is warranted → proceed, but preserve any human edits or prior findings that remain relevant. Treat this as an **update**, not a replacement.
  - If the existing content is identical or still valid → skip writing, report "no changes needed".
This guard prevents the silent data loss incident of 2026-03-17 where concurrent sessions overwrote story files.

1. Read provided artefacts fully
2. Load relevant memory (if supplied)
3. Scan for: ambiguity, assumptions, complexity spikes, constraint conflicts, missing validations
4. For each risk: describe clearly, classify type, assess impact and likelihood, propose mitigation direction (not solution)
5. Rank risks by severity. Derive severity from impact × likelihood using this matrix:
   - **Critical:** high impact + high likelihood, OR any impact + touches security/payments/PII
   - **High:** high impact + medium likelihood, OR medium impact + high likelihood
   - **Medium:** medium impact + medium likelihood, OR high impact + low likelihood
   - **Low:** low impact + any likelihood, OR medium impact + low likelihood

---

## Risk Categories

**Product risks:** unclear outcomes, wrong user assumptions, missing edge cases, scope creep

**Delivery risks:** technical feasibility, hidden dependencies, performance/security concerns, testability gaps

**Systemic risks:** architectural erosion, rule violations, knowledge loss, repeated failure patterns

---

## Output Format

RISK-ID naming convention: use format `RISK-{STORY_ID}-{NNN}` (e.g., `RISK-E06S18-001`).

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
- Every risk must trace to a specific artefact section, assumption, or identified gap — not a general technical concern

---

## Non-Goals

This skill must NOT:
- Invent risks without evidence
- Propose detailed solutions
- Bypass artefacts
- Produce long lists of low-signal risks

**Unseen risk is what breaks AI-driven delivery. Surfaced risk is what makes it predictable.**
