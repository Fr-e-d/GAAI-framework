---
name: compose-team
description: Assemble the context bundles for each sub-agent based on evaluate-story output. Produces spawn-ready packages for Planning, Implementation, QA, or MicroDelivery sub-agents. Activate after evaluate-story, before spawning any sub-agent.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DEL-008
  updated_at: 2026-02-18
inputs:
  - contexts/artefacts/stories/**         (the Story)
  - contexts/rules/**                     (applicable rules)
  - contexts/memory/index.md              (registry — resolve memory file paths before composing bundles)
  - contexts/memory/**                    (categories resolved from index.md at runtime)
  - agents/specialists.registry.yaml      (for Tier 3)
  - evaluate-story output                 (inline — tier + specialists_triggered)
outputs:
  - context bundles (inline — file lists passed to each sub-agent at spawn)
---

# Compose Team

## Purpose / When to Activate

Activate after `evaluate-story` returns the tier, before the first sub-agent is spawned.

The Orchestrator must give each sub-agent **exactly the context it needs — no more, no less**. Context pollution wastes tokens and introduces drift. Context starvation causes failures.

This skill determines what goes into each sub-agent's context bundle.

---

## Process

### Step 0 — Resolve memory file paths (always first)

Read `contexts/memory/index.md`. For each bundle below that references a memory category, resolve the actual file path from the index before including it. Never hardcode memory file paths — the index is the source of truth.

Key categories to resolve:
- `project` category → project context file (stack, architecture, constraints)
- `decisions` category → decisions log
- `patterns` category → conventions and code patterns

If a category is absent from the index, omit it from the bundle silently — do not fail.

---

### For Tier 1 (MicroDelivery)

MicroDelivery bundle (minimal):
```
- Story artefact
- patterns category file (resolved from index.md)
- Directly affected file(s) — identified from acceptance criteria
- orchestration.rules.md (relevant sections only)
```

### For Tier 2 / Tier 3 (Core Team)

**Planning Sub-Agent bundle:**
```
- Story artefact
- orchestration.rules.md + artefacts.rules.md
- project category file (resolved from index.md)
- decisions category file (filtered: relevant decisions only — resolved from index.md)
- patterns category file (resolved from index.md)
- codebase-scan artefact (if exists)
```

**Implementation Sub-Agent bundle:**
```
- Story artefact
- {id}.execution-plan.md (from Planning Sub-Agent)
- patterns category file (resolved from index.md)
- project category file (resolved from index.md)
- Codebase files identified in execution plan (file list, not full content)
```

**QA Sub-Agent bundle:**
```
- Story artefact (acceptance criteria is the test spec)
- {id}.execution-plan.md (test checkpoints)
- {id}.impl-report.md (from Implementation Sub-Agent)
- orchestration.rules.md + artefacts.rules.md
```

**On remediation pass (QA re-spawn):**
```
QA bundle + {id}.qa-report.md (prior failure record)
Implementation bundle + {id}.qa-report.md (failure diagnosis)
```

### For Tier 3 Specialists

For each specialist in `specialists_triggered`:
- Read specialist entry from `agents/specialists.registry.yaml`
- Add `context_bundle` files from registry entry to Implementation Sub-Agent bundle
- Record which specialists are activated (for impl-report)

---

## Output

Returns (inline, to the Orchestrator) the file list for each sub-agent's context bundle. The Orchestrator uses this list when spawning each sub-agent.

Not written to file — this is the Orchestrator's coordination state, not a durable artefact.

---

## Quality Checks

- Every sub-agent receives its required inputs (Story, rules, relevant memory)
- No sub-agent receives another sub-agent's full context (isolation is structural)
- Specialist bundles include only the registry-defined files, not the full memory set
- Remediation passes receive the prior failure artefact — no exceptions
