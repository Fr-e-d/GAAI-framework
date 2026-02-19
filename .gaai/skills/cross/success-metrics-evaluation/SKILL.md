---
name: success-metrics-evaluation
description: Evaluate delivery outcomes against defined success metrics and acceptance goals. Activate after Delivery to verify that delivered work creates real business and technical impact, not just output.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-SUCCESS-METRICS-EVALUATION-001
  updated_at: 2026-02-06
  status: future
inputs:
  - contexts/artefacts/stories/**
  - acceptance_criteria
  - delivered_artefacts
  - defined_success_metrics
  - runtime_or_usage_data  (optional)
outputs:
  - metric_results
  - story_level_success_report
  - gap_analysis
  - improvement_recommendations
---

# Success Metrics Evaluation

## Purpose / When to Activate

Activate after Delivery to verify outcomes, not just outputs. Prevents "output without outcome."

Use when:
- Success metrics were defined in the PRD or Story
- Delivery is complete and runtime data is available
- Objective quality gates are required

---

## Process

1. Map each Story to its defined success metrics
2. Measure artefacts and runtime results against targets
3. Detect underperformance and partial success
4. Generate actionable improvement insights

---

## Output

- Story-by-story KPI report
- Metric vs target comparisons
- Identified gaps with root signals
- Improvement suggestions linked to backlog items

---

## Quality Checks

- Each metric is measured against a defined target
- Gaps are identified with root cause signals
- Recommendations are linked to specific backlog items
- No invented metrics — only those defined in artefacts

---

## Non-Goals

This skill must NOT:
- Redefine success metrics post-delivery
- Make product decisions about gaps
- Substitute for `qa-review`

**Ensures delivery creates real impact. Makes scaling predictable.**
