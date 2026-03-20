---
type: reference
skill: skill-optimize
id: SKILL-OPT-LEDGER-001
updated_at: 2026-03-20
---

# Quality Ledger Format Specification

This document defines the canonical format for `quality/ledger.yaml` files maintained by the `skill-optimize` skill.

---

## Overview

A `ledger.yaml` file is a persistent, append-only record of all quality evaluation iterations for a single skill. It accumulates across optimization runs, providing a historical view of quality trends, regressions, and improvements.

**Location:** `{skill-dir}/quality/ledger.yaml`

**Ownership:** Created and maintained exclusively by `skill-optimize`. No other skill or agent writes to this file.

---

## Top-Level Structure

```yaml
skill: {skill-name}           # Must match the target skill's name field
skill_path: {path}            # Relative path from .gaai/ to the target SKILL.md
evals_version: "1.0"          # Version of the evals.yaml used (tracks eval set changes)
slo_target: 0.85              # Service-level objective — set by human, never by the skill
created_at: {ISO 8601}        # Date of first iteration (baseline)
updated_at: {ISO 8601}        # Date of most recent iteration

iterations:
  - {iteration entry}         # One or more iteration entries (see below)

status:
  current_pass_rate: 0.XX     # Pass rate of the most recent iteration
  trend: improving | stable | degrading
  error_budget_remaining: 0.XX
  needs_optimization: false   # true if error_budget_remaining < 0
```

---

## Iteration Entry

Each iteration represents one complete evaluation cycle (Steps 3-6 of skill-optimize).

```yaml
- id: {N}                     # Sequential integer, starting at 1
  date: {ISO 8601}            # Date this iteration was run
  trigger: {trigger value}    # baseline | regression | skill-update | friction-flagged
  score:
    passed: N                 # Number of assertions that passed
    total: N                  # Total number of assertions evaluated
    pass_rate: 0.XX           # passed / total, rounded to 2 decimal places
  delta_vs_previous: null     # null for baseline, +/-0.XX for subsequent iterations
  failed_assertions:          # List of assertion IDs that failed
    - A02
    - A05
  new_regressions: []         # Assertions that passed in previous iteration but failed in this one
  new_passes: []              # Assertions that failed in previous iteration but passed in this one
  action_taken: "{description}"  # What SKILL.md change was made, or "baseline — no action"
  corpus_files:               # List of corpus files evaluated in this iteration
    - eval-corpus/corpus-1.md
    - eval-corpus/corpus-2.md
```

---

## Status Section

The `status` section is a derived summary, recalculated after every iteration.

### Fields

| Field | Type | Calculation |
|---|---|---|
| `current_pass_rate` | float | `pass_rate` from the most recent iteration |
| `trend` | enum | See trend calculation below |
| `error_budget_remaining` | float | `current_pass_rate - slo_target` |
| `needs_optimization` | boolean | `true` if `error_budget_remaining < 0` for 3+ consecutive iterations |

### Trend Calculation

Compare the last 3 iterations (or all iterations if fewer than 3):

- **improving:** pass_rate increased in at least 2 of the last 3 iterations
- **degrading:** pass_rate decreased in at least 2 of the last 3 iterations
- **stable:** pass_rate neither consistently increasing nor decreasing

For baseline (only 1 iteration): trend is always `stable`.
For 2 iterations: compare directly — improving, degrading, or stable (if equal).

---

## Append-Only Rules

1. **Never delete iteration entries.** History is preserved for trend analysis.
2. **Never modify past iteration entries.** If data was incorrect, add a correction note to the next iteration's `action_taken`.
3. **The `status` section is the only mutable part** — it is recalculated on every append.
4. **If `evals_version` changes** (eval set was modified), note this in the iteration's `action_taken` and reset trend calculation from that point forward.

---

## Complete Example

```yaml
skill: content-draft
skill_path: project/skills/content-production/content-draft/SKILL.md
evals_version: "1.0"
slo_target: 0.85
created_at: 2026-03-15
updated_at: 2026-03-20

iterations:
  - id: 1
    date: 2026-03-15
    trigger: baseline
    score:
      passed: 4
      total: 5
      pass_rate: 0.80
    delta_vs_previous: null
    failed_assertions: [A02]
    new_regressions: []
    new_passes: []
    action_taken: "baseline — no action"
    corpus_files:
      - eval-corpus/corpus-1.md
      - eval-corpus/corpus-2.md
      - eval-corpus/corpus-3.md

  - id: 2
    date: 2026-03-18
    trigger: skill-update
    score:
      passed: 5
      total: 5
      pass_rate: 1.00
    delta_vs_previous: +0.20
    failed_assertions: []
    new_regressions: []
    new_passes: [A02]
    action_taken: "Added explicit kill-list instruction to Step 3 of SKILL.md (human-approved)"
    corpus_files:
      - eval-corpus/corpus-1.md
      - eval-corpus/corpus-2.md
      - eval-corpus/corpus-3.md

  - id: 3
    date: 2026-03-20
    trigger: regression
    score:
      passed: 4
      total: 6
      pass_rate: 0.67
    delta_vs_previous: -0.33
    failed_assertions: [A04, A06]
    new_regressions: [A04]
    new_passes: []
    action_taken: "Added assertion A06 (new test). A04 regressed after voice-guide update — escalated to human."
    corpus_files:
      - eval-corpus/corpus-1.md
      - eval-corpus/corpus-2.md
      - eval-corpus/corpus-3.md

status:
  current_pass_rate: 0.67
  trend: degrading
  slo_target: 0.85
  error_budget_remaining: -0.18
  needs_optimization: false  # only 1 iteration below SLO so far
```

---

## Integration Points

| Consumer | How it uses the ledger |
|---|---|
| `skill-optimize` (Step 6) | Appends iterations, recalculates status |
| `skill-optimize` (Step 7) | Reads trend and error_budget for escalation decisions |
| `friction-retrospective` | May reference ledger trend when analyzing recurring friction sources |
| Discovery Agent | Reads `needs_optimization` flag to decide if a skill is safe to use |
| Human | Reviews full history for strategic quality decisions |

---

## What the Ledger Does NOT Contain

- Raw eval output (that's in `score-{iteration}.yaml`)
- Error analysis details (that's in `error-analysis.md`)
- SKILL.md diffs (those are in git history)
- Cross-skill comparisons (ledger is per-skill only)
