---
name: qa-review
description: Validate that implemented code fully satisfies Story acceptance criteria, respects rules, and introduces no regressions. This is the hard quality gate — no pass means no delivery. Activate after implementation is complete.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-QA-REVIEW-001
  updated_at: 2026-04-15
  status: stable
inputs:
  - contexts/artefacts/stories/**
  - contexts/artefacts/plans/**
  - codebase  (working tree)
  - contexts/rules/**
  - contexts/memory/**  (optional — past bugs, regressions, risks)
outputs:
  - qa_report  (PASS | FAIL)
---

# QA Review

## Purpose / When to Activate

Activate after implementation is complete. This is a **hard quality gate**.

**No pass → no delivery.**

---

## Process

### 1. Story Compliance Check
- Parse Story YAML frontmatter
- Extract acceptance criteria
- Validate each criterion is demonstrably satisfied in code
- **Required Skills AC verification**: if the story frontmatter contains `required_skills`,
  for each entry X, identify its co-declared bound output AC. Verify that the bound output
  AC is satisfied by inspecting the actual output or changed artefacts (file contents,
  generated output, behaviour). Do NOT verify by checking invocation traces or logs — the
  test is output-based only. If the bound output AC cannot be evaluated from output alone
  (ambiguous) → FAIL with escalation note. If the bound output AC is unmet → FAIL
  immediately with: `FAIL: bound output AC for required_skills entry "${X}" is not
  satisfied — [AC text] not met in output. Inspect [relevant file/output].`
- Any criterion unclear or unmet → FAIL immediately

### 2. Scope Integrity Check
- Only files within Story scope were modified
- No feature creep introduced
- No unrelated refactors included
- Unexpected changes → FAIL

### 3. Rule Enforcement
- Confirm compliance with each applicable rule
- Surface violations explicitly
- Any broken rule → FAIL

### 4. Regression Scan
- **Broken tests → FAIL — but only a *new* breakage is a regression.** A regression is a test that fails on this change yet passed on the pre-change baseline. Before failing on a red test, establish whether it is pre-existing: re-run it on the base branch / the story's fork-point, or consult known-failing context. A test already red on the baseline and unrelated to this story's changed surface is **not** a regression — record it as pre-existing and do **not** FAIL/ESCALATE on it. A failure this story caused, or in a test that exercises the surface this story changed, **is** a regression → FAIL. Do not weaken this by labelling a genuinely new failure "pre-existing" — verify, don't assume.
- Behavior drift → FAIL
- Known risk patterns from memory → FAIL

### 5. Build / Type / Lint Integrity

Test runners that transpile (vitest, jest, ts-jest, swc, esbuild, babel) execute code WITHOUT type checking — a green test suite does not prove the code compiles. Static-type or linter errors in test files, fixtures, and adjacent modules will pass tests locally and only surface at deploy time.

Identify and run the project's full static-analysis gate for every workspace package whose files were modified (directly or via type/dep propagation):
- TypeScript: `tsc --noEmit` (or `pnpm typecheck` / equivalent script)
- For Cloudflare Workers projects: regenerate runtime types first (`wrangler types`) — drift between `worker-configuration.d.ts` and `wrangler.jsonc` masks real errors
- Lint (if the project enforces it as a gate): `eslint`, `ruff`, `clippy`, etc.
- Other ecosystems: `cargo check`, `mypy`, `go vet`, etc.

If the project documents the exact command in `contexts/memory/patterns/conventions.md` or a delivery rules file, use that command verbatim — do not improvise.

Any error → FAIL. "Test files only" is not a mitigation: test files are part of the typecheck graph and break the deploy gate.

### 6. Quality Checks
- Error-prone operations lack error handling → FAIL
- External input enters functions without validation → FAIL
- Identifiers are ambiguous or non-descriptive → FAIL
- A function or module handles more than one responsibility without decomposition → FAIL
- Dead code or unreachable branches present → FAIL
- Tests were disabled or skipped to make the suite pass → FAIL

### 7. Memory Alignment (PASS only)

On PASS verdict, the skill MUST invoke `memory-alignment-check` (SKILL-MEMORY-ALIGNMENT-CHECK-001) before returning. QA MUST NOT improvise the delta — `memory-alignment-check` owns it.

The delta MUST match this exact skeleton (authoritative source: `memory-alignment-check/SKILL.md` Outputs). Do NOT invent alternative section headers (e.g. `## Summary`, `## New facts delivered by this story`, `## Implementation Footprint`, `## No memory updates required`) and do NOT change the frontmatter field names — any deviation FAILs the `validate-memory-deltas` CI gate:

```
---
artefact_type: memory-delta
skill: memory-alignment-check
story_id: {id}
generated_at: YYYY-MM-DD
verdict: ALIGNED | DRIFT_DETECTED | NEW_KNOWLEDGE_FOUND | DRIFT_AND_NEW_KNOWLEDGE
---

## Confirmed Entries
# (list, or leave the section present with no items)

## Contradicted Entries
# (list, or leave the section present with no items)

## New Knowledge Candidates
# (list, or leave the section present with no items)
```

A "nothing changed" delta is still expressed in this schema (`verdict: ALIGNED`, the three sections present with no items) — NOT as free prose. The full field-level schema lives in `memory-alignment-check/SKILL.md` Outputs. The delta is written exclusively to `contexts/artefacts/memory-deltas/{id}.memory-delta.md` (canonical path — never under `contexts/memory/`).

---

## Outputs

**If PASS:**
```
status: PASS
validated_stories:
  - E01S01
notes:
  - All acceptance criteria satisfied
  - No rule violations
  - No regressions detected
```

**If FAIL:**
```
status: FAIL
blocking_issues:
  - Story E01S01: acceptance criterion #2 not satisfied
  - Rule code-style violated in services/api/user.ts
  - Unexpected file modified: services/payments/
recommended_actions:
  - Fix acceptance behavior
  - Revert out-of-scope change
  - Apply code rule formatting
```

---

## Hard Rules

This skill must NEVER:
- Modify code
- Reinterpret Stories
- Negotiate acceptance criteria
- Approve partial conformance
- MUST NOT write or modify `contexts/artefacts/memory-deltas/{id}.memory-delta.md` directly. The delta is written exclusively by `memory-alignment-check` (invoked at Step 6). Free-form delta variants are a governance violation.

**If it's not explicitly validated → it's broken. If it's broken → it doesn't ship.**
