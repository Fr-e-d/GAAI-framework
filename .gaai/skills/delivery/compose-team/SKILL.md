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
  - contexts/memory/project/context.md
  - contexts/memory/decisions/_log.md     (relevant entries)
  - contexts/memory/patterns/conventions.md
  - contexts/specialists.registry.yaml    (for Tier 3)
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

### For Tier 1 (MicroDelivery)

MicroDelivery bundle (minimal):
```
- Story artefact
- conventions.md (patterns)
- Directly affected file(s) — identified from acceptance criteria
- orchestration.rules.md (relevant sections only)
```

### For Tier 2 / Tier 3 (Core Team)

**Planning Sub-Agent bundle:**
```
- Story artefact
- orchestration.rules.md + artefacts.rules.md
- project/context.md
- decisions/_log.md (filtered: relevant decisions only)
- conventions.md
- codebase-scan artefact (if exists)
```

**Implementation Sub-Agent bundle:**
```
- Story artefact
- {id}.execution-plan.md (from Planning Sub-Agent)
- conventions.md
- project/context.md
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
- Read specialist entry from `contexts/specialists.registry.yaml`
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
