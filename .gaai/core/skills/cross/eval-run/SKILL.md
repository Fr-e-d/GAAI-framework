---
name: eval-run
description: Evaluate any output file against a structured evals.yaml assertions file and produce a score report with per-assertion pass/fail results. Activate when the Discovery Agent runs the Skill Optimize protocol to measure output quality or detect regressions after skill instruction changes.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-025
  updated_at: 2026-03-15
  status: experimental
inputs:
  - output_file: path to the output file being evaluated (produced by any skill)
  - evals_file: path to the evals.yaml file containing assertions to run
outputs:
  - score report (YAML or structured Markdown) with per-assertion pass/fail, total score, and failed assertion details
---

# Eval Run

## Purpose / When to Activate

Activate when:
- The Discovery Agent runs the Skill Optimize protocol and needs to score a skill output
- A skill's instructions have been modified and a before/after quality comparison is needed
- A baseline score is being established for a skill that has never been evaluated

This skill is generic: it accepts any output file and any evals.yaml, regardless of skill domain.

It follows the GAAI principle "skills never chain" — it evaluates the output it receives; it does not invoke the skill that produced the output.

---

## Process

### Step 1 — Load inputs

1. Read the `output_file` path. Confirm the file exists and is non-empty. If missing: FAIL immediately with error "output_file not found: {path}".
2. Read the `evals_file` path. Confirm the file exists and is valid YAML. If missing: FAIL immediately with error "evals_file not found: {path}".
3. Parse the `evals.yaml` structure. Validate:
   - `skill`, `version`, `description`, and `assertions` fields are present
   - `assertions` list is non-empty
   - Each assertion has `id`, `type`, and `description` fields
   - If any required field is missing: FAIL with error "evals.yaml validation error: {details}"

For the full `evals.yaml` format spec, see `references/evals-format.md`.

### Step 2 — Run `code` assertions

For each assertion where `type: code`:

1. Read the `check` field. Execute the corresponding mechanical verification:

   | `check` | Verification method |
   |---|---|
   | `word_count` | Count whitespace-separated tokens in the output file. Compare against `params.min` and `params.max`. |
   | `char_count` | Count all characters in the output file. Compare against `params.min` and `params.max`. |
   | `regex_match` | Apply `params.pattern` as a regex to the full output text. PASS if at least one match found. |
   | `regex_not_match` | Apply `params.pattern` as a regex to the full output text. PASS if zero matches found. |
   | `structure_present` | Search the output text for the literal string `params.marker`. PASS if found. |
   | `structure_absent` | Search the output text for the literal string `params.marker`. PASS if NOT found. |

2. Record the result:
   - PASS: the assertion result is PASS with the measured value (e.g., word count = 1247)
   - FAIL: the assertion result is FAIL with the measured value and the expected condition

### Step 3 — Run `llm-judge` assertions

For each assertion where `type: llm-judge`:

1. Construct the evaluation prompt:
   ```
   {assertion.prompt}

   ---
   OUTPUT TO EVALUATE:
   {full content of output_file}
   ```

2. Submit the prompt. Parse the response for a binary verdict: `PASS` or `FAIL`.
3. Extract the one-sentence explanation from the response.
4. Record the result:
   - PASS: result is PASS with the LLM's explanation
   - FAIL: result is FAIL with the LLM's explanation

### Step 4 — Compile score report

After all assertions are evaluated, compile the score report:

1. Count total assertions run and total assertions passed.
2. List all failed assertions with their IDs, descriptions, and failure details.
3. Produce the structured output (see Outputs section).

---

## Quality Checks

- Every assertion in the evals.yaml is evaluated — no assertion is skipped silently
- Each assertion result records its measured value or LLM rationale, not just PASS/FAIL
- The total score is expressed as `N/total` (e.g., `4/5`)
- Failed assertions are listed with enough detail to understand what was measured and why it failed
- The score report is structured such that an agent can parse it programmatically (not free prose)
- If any assertion has an unsupported `check` value: report as ERROR, do not skip silently

---

## Outputs

The skill produces a score report in the following structured Markdown format:

```markdown
# Eval Report: {skill name} — {evals.yaml version}

**Output file:** {output_file path}
**Evals file:** {evals_file path}
**Run date:** {ISO 8601 date}
**Score:** {N}/{total} assertions passed

---

## Results

| ID | Type | Description | Result | Details |
|----|------|-------------|--------|---------|
| A01 | code | Word count within ±15% of target | PASS | 1247 words (range: 1020–1380) |
| A02 | code | Kill list word 'leverage' absent | FAIL | 2 matches found |
| A03 | llm-judge | Post stands alone without prior context | PASS | "The post opens with a clear hook and requires no prior context to understand." |

---

## Failed Assertions

### A02 — Kill list word 'leverage' absent
- **Type:** code
- **Check:** regex_not_match
- **Pattern:** `\bleverag(e|ing|ed)\b`
- **Result:** FAIL — 2 matches found at positions [line 4, line 11]
```

The score report may also be emitted as structured YAML if the invoking agent requires machine-readable output:

```yaml
eval_report:
  skill: content-draft
  evals_version: "1.0"
  output_file: {path}
  evals_file: {path}
  run_date: {ISO 8601}
  score:
    passed: 4
    total: 5
    ratio: "4/5"
  results:
    - id: A01
      type: code
      description: "Word count within ±15% of target"
      result: PASS
      details: "1247 words (range: 1020–1380)"
    - id: A02
      type: code
      description: "Kill list word 'leverage' absent"
      result: FAIL
      details: "2 matches found"
  failed_assertions:
    - id: A02
      description: "Kill list word 'leverage' absent"
      type: code
      check: regex_not_match
      pattern: "\\bleverag(e|ing|ed)\\b"
      details: "2 matches found at positions [line 4, line 11]"
```

---

## Non-Goals

This skill must NOT:
- Modify the output file being evaluated
- Modify the source skill whose output is being evaluated
- Invoke any other skill (skills never chain)
- Make recommendations about what to change in the skill or its output
- Generate an evals.yaml file (that is agent work in the Skill Optimize protocol)
- Compare scores across multiple runs (that is agent orchestration)
- Propose a verdict on whether the skill should be updated (that is a human decision)

**No silent skips. Every assertion produces an explicit PASS, FAIL, or ERROR result.**
