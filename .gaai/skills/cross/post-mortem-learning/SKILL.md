---
name: post-mortem-learning
description: Analyze failures and suboptimal deliveries to identify root causes, contributing factors, and raw lessons. Activate after significant delivery failures, repeated QA failures, or when patterns of issues need to be understood.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-POST-MORTEM-LEARNING-001
  updated_at: 2026-02-06
  status: experimental
inputs:
  - failed_or_degraded_story_results
  - qa_reports
  - contexts/artefacts/**  (delivered)
  - contexts/memory/decisions/**
  - contexts/rules/**  (applied)
outputs:
  - root_cause_analysis
  - contributing_factors
  - raw_lessons
  - failure_scenarios
  - improvement_candidates
---

# Post-Mortem Learning

## Purpose / When to Activate

Activate after:
- Significant delivery failures
- Repeated QA failures on the same area
- Delivery that missed its success metrics
- Patterns of issues that need systemic understanding

---

## Process

1. Reconstruct what happened end-to-end
2. Compare expected vs actual outcomes
3. Identify: technical causes, contextual gaps, decision errors, rule weaknesses
4. Produce concrete failure narratives
5. Extract **raw lessons (non-generalized)** — specific to this failure

---

## Output

- Root cause analysis report
- Failure timeline
- Mapped rule gaps
- Raw lesson list (specific, not generic)
- Candidate improvement areas (for backlog or rules)

---

## Quality Checks

- Root causes are specific, not generic ("insufficient testing" is invalid — "acceptance criterion #3 had no test coverage" is valid)
- Lessons are raw and specific, not platitudes
- Failure timeline is traceable
- Rule gaps link to specific rule files

---

## Non-Goals

This skill must NOT:
- Propose solutions (produces inputs for backlog and rules, not fixes)
- Assign blame
- Generalize into vague lessons

**Makes failures understandable and actionable. Enables serious continuous improvement.**
