---
name: skill-optimize
description: Run a structured evaluate-analyze-improve cycle on any GAAI skill to measure quality, detect regressions, and propose targeted improvements. Activate when a skill needs baseline evaluation, after SKILL.md modifications, or when friction-retrospective flags a skill.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-026
  updated_at: 2026-03-20
  status: experimental
inputs:
  - target_skill_path: path to the SKILL.md being optimized
  - trigger: baseline | regression | skill-update | friction-flagged
  - evals_file: (optional) path to existing evals.yaml — if absent, Step 1 creates one
  - corpus_dir: (optional) path to existing corpus outputs — if absent, Step 2 creates samples
outputs:
  - "{skill-dir}/eval-corpus/evals.yaml (created if absent)"
  - "{skill-dir}/eval-corpus/score-{iteration}.yaml — score report per iteration"
  - "{skill-dir}/quality/ledger.yaml — persistent quality ledger (accumulated across runs)"
  - "Improvement proposal (inline, for human review — NEVER auto-applied)"
---

# Skill Optimize

## Purpose / When to Activate

Activate when:
- A skill needs a baseline quality measurement (no ledger.yaml exists yet)
- A SKILL.md has been modified and a before/after regression check is needed
- `friction-retrospective` flags a skill as a recurring friction source
- An eval cycle is needed after a manual skill update

This skill formalizes the Skill Optimize protocol referenced by `eval-run` (SKILL-CRS-025). It runs the full evaluate-analyze-improve loop with mandatory human gates at every modification step.

**Scope:** Any GAAI skill with measurable quality criteria — not limited to content-production skills. The inline Skill Optimize protocol in `discovery.agent.md` remains the agent's orchestration logic; this skill provides the structured execution procedure.

---

## Process

### Step 1 — Eval authoring

If no `evals.yaml` exists for the target skill:

1. Read the target `SKILL.md` in full.
2. Identify measurable quality criteria from the `Quality Checks` section.
3. Author `evals.yaml` following the `evals-format.md` spec (see `eval-run/references/evals-format.md`).
4. Include a minimum of 5 assertions with a mix of `code` and `llm-judge` types.
5. Store the file at `{skill-dir}/eval-corpus/evals.yaml`.

**HUMAN CHECKPOINT:** Present the drafted `evals.yaml` for validation. Do not proceed until approved. If rejected, revise based on feedback and re-present.

### Step 2 — Corpus generation

If no corpus outputs exist in `{skill-dir}/eval-corpus/`:

1. Identify the skill's expected inputs from its `inputs:` frontmatter and Process section.
2. Produce 2-3 representative outputs by simulating the skill's expected inputs.
3. Store each output in `{skill-dir}/eval-corpus/` with naming `corpus-{N}.md`.

If corpus outputs already exist (from prior runs or real production), use those. Prefer real outputs over synthetic when available.

### Step 3 — Baseline evaluation

1. Invoke `eval-run` (SKILL-CRS-025) with each corpus output against the `evals.yaml`.
2. Compile per-output scores into `{skill-dir}/eval-corpus/score-baseline.yaml`.
3. Record the aggregate: `passed / total` and `pass_rate`.

### Step 4 — Error analysis

For each failed assertion across all corpus outputs:

1. Identify the root cause in the target SKILL.md: which step, which instruction.
2. Classify the failure:
   - `instruction-gap` — the skill doesn't instruct what is needed
   - `instruction-ambiguity` — the skill instructs ambiguously
   - `eval-design-error` — the assertion is flawed, not the skill
   - `model-limitation` — the model cannot reliably produce what is asked
3. Produce `{skill-dir}/eval-corpus/error-analysis.md` with per-assertion findings.

### Step 5 — Improvement proposal

Based on the error analysis:

1. Propose specific, minimal SKILL.md edits addressing `instruction-gap` and `instruction-ambiguity` failures.
2. For `eval-design-error` failures: propose evals.yaml corrections instead.
3. For `model-limitation` failures: document as known limitations, do not propose changes.
4. Present the proposal to the human.

**HUMAN CHECKPOINT:** The human approves, modifies, or rejects the proposal. NEVER auto-apply SKILL.md changes.

If approved:
1. Apply the edits to SKILL.md.
2. Re-run Steps 3-4 as a new iteration (score file: `score-{iteration}.yaml`).
3. Compare against previous iteration scores.

### Step 6 — Ledger update

After each iteration (including baseline), append an entry to `{skill-dir}/quality/ledger.yaml`:

```yaml
iterations:
  - id: {N}
    date: {ISO 8601}
    trigger: {trigger input value}
    score:
      passed: N
      total: N
      pass_rate: 0.XX
    delta_vs_previous: +/-0.XX  # null for baseline
    failed_assertions: [ANN, ...]
    action_taken: "{description of SKILL.md change, or 'baseline — no action'}"
status:
  current_pass_rate: 0.XX
  trend: improving | stable | degrading
  slo_target: 0.85
  error_budget_remaining: 0.XX
```

The ledger is **append-only** — iteration history is never deleted or overwritten.

For ledger format details, see `references/ledger-format.md`.

### Step 7 — Trend detection

After updating the ledger:

1. If `trend: degrading` over 3+ consecutive iterations: **escalate to human** with full history and recommendation.
2. If `error_budget_remaining < 0` (pass rate below SLO for 3+ iterations): flag the skill as `needs-optimization` in the ledger status. This blocks new deliveries using this skill until the human resolves it.
3. If `trend: improving` or `stable`: report status inline and complete.

---

## Quality Checks

- Every iteration produces a score report — no silent skips
- Ledger is append-only — iteration history never deleted
- SKILL.md modifications require human approval (SkillsBench finding: self-generated skill edits = -1.3pp without human review)
- Per-assertion tracking in every score report, not just aggregate scores (prevents AP-8: aggregation hiding regressions)
- Mixed assertion types mandatory in evals.yaml: both `code` and `llm-judge` (prevents AP-1: self-model bias)
- Error analysis classifies every failure — unclassified failures are not allowed
- Improvement proposals are minimal and targeted — no wholesale rewrites

---

## Outputs

| Output | Path | Persistence |
|---|---|---|
| Eval assertions | `{skill-dir}/eval-corpus/evals.yaml` | Created once, updated on eval-design-error |
| Corpus outputs | `{skill-dir}/eval-corpus/corpus-{N}.md` | Stable across iterations |
| Score reports | `{skill-dir}/eval-corpus/score-{iteration}.yaml` | One per iteration |
| Error analysis | `{skill-dir}/eval-corpus/error-analysis.md` | Overwritten each iteration |
| Quality ledger | `{skill-dir}/quality/ledger.yaml` | Append-only, never overwritten |
| Improvement proposal | Inline in session | Not persisted |

---

## Non-Goals

This skill must NOT:
- Auto-modify SKILL.md without human approval (human gate is non-negotiable)
- Invoke the target skill to produce outputs (skills never chain — it evaluates existing outputs only)
- Compare quality across different skills (only within-skill across iterations)
- Set or modify SLO targets (human decision — skill only reads and reports against them)
- Generate corpus from production data without explicit human authorization
- Skip the error analysis step (every failure must be classified before proposing changes)
- Propose changes for `model-limitation` failures (these are documented, not "fixed")

For documented anti-patterns and mitigations, see `references/anti-patterns.md`.

**No silent assumptions. Every evaluation result, every failure classification, every improvement proposal becomes explicit and governed.**
