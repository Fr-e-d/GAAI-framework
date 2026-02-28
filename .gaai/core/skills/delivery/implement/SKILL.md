---
name: implement
description: Generate correct, minimal, maintainable code that satisfies a validated Story's acceptance criteria against an execution plan. Activate when a Story is validated, a plan exists, and all prerequisites are unambiguous.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-IMPLEMENT-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - contexts/artefacts/stories/**  (validated)
  - contexts/artefacts/plans/**
  - contexts/rules/**
  - memory_context_bundle
outputs:
  - code_changes
  - test_artifacts
  - implementation_report
---

# Implementation

## Purpose / When to Activate

Activate when:
- A Story is validated for implementation
- An execution plan exists decomposing the Story into actionable steps
- Relevant memory, rules, and constraints are available

Only proceed when all prerequisites are present and unambiguous.

---

## Process

1. **Load context** — retrieve minimal memory, load applicable rules and constraints
2. **Interpret acceptance criteria** — translate into specific expected behaviors, validate against plan
3. **Map plan to implementation** — determine file paths, naming, modules per conventions; clarify dependency edges
4. **Generate code** — write code per plan steps, annotate links to acceptance criteria, respect all style/architecture/quality rules
5. **Generate tests** — cover expected behavior from acceptance criteria, include required edge cases, ensure automatable
6. **Internal validation** — verify acceptance criteria map to code/tests, run linting if required by rules, confirm memory constraints respected
7. **Produce delivery outputs** — code changes, test artifacts, implementation report

---

## Output Definitions

**`code_changes`** — diffs or code fragments structured for integration

**`test_artifacts`** — test files (unit/integration) aligned with acceptance criteria

**`implementation_report`** — human-readable summary including:
- Mapping to plan steps
- Rules applied
- Memory constraints referenced
- Known risks and decisions

---

## Quality Checks

- All acceptance criteria are met
- All rule checks pass
- Relevant tests exist and are runnable
- Implementation report articulates decisions
- Scope is unchanged
- Error-prone operations (I/O, parsing, external calls) have explicit error handling — failures are surfaced, not silently swallowed
- Functions exposed to external input validate arguments before executing
- Identifiers are explicit and intention-revealing — no single-letter variables, no ambiguous abbreviations outside established conventions
- Each function or module has a single, clear responsibility — if it does more than one thing, it must be decomposed

---

## Non-Goals

This skill must NOT:
- Redefine product intent
- Add unrequested features
- Bypass governance rules
- Guess missing requirements
- Embed hidden context or implicit assumptions

**"I implement exactly what the plan defines, and I prove it."**
