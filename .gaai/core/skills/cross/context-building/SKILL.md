---
name: context-building
description: Assemble a minimal, high-signal execution context bundle from already-retrieved memory, governed artefacts, and applicable rules. Activate after memory-retrieve and before any reasoning or execution skill.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CONTEXT-BUILDING-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - retrieved_memory_bundle
  - contexts/artefacts/**  (relevant only)
  - contexts/rules/**  (applicable only)
outputs:
  - execution_context_bundle
---

# Context Building

## Purpose / When to Activate

Activate when context is fragmented or multiple memory sources need to be merged before a complex task:
- After `memory-retrieve` when inputs come from multiple memory files
- Before planning or implementation skills on complex, multi-artefact Stories
- When previous context bundles are stale or need restructuring

For simple, single-artefact tasks, an agent may reason directly without this skill. This skill does not retrieve knowledge — it **structures and composes** already-selected inputs into a focused bundle.

---

## Process

1. Validate inputs are scoped and minimal
2. Remove duplicated or overlapping information
3. Prioritize: acceptance criteria, constraints, decisions, current artefacts
4. Structure the bundle in canonical order:
   - Current Objective
   - Governed Artefacts (Epics / Stories / Plans)
   - Acceptance Criteria & Constraints
   - Applicable Rules
   - Relevant Memory

5. Enforce minimal token footprint

---

## Outputs

```
=== EXECUTION CONTEXT ===

OBJECTIVE:
...

ARTEFACTS:
...

ACCEPTANCE & CONSTRAINTS:
...

RULES:
...

RELEVANT MEMORY:
...

=========================
```

No prose. No fluff. No hidden reasoning.

---

## Quality Checks

- Context is focused and task-specific
- No irrelevant memory included
- No artefacts outside scope
- Token usage minimized
- All constraints explicit

---

## Non-Goals

This skill must NOT:
- Retrieve memory (use `memory-retrieve` first)
- Infer missing artefacts
- Add assumptions or expand scope
- Inject creative interpretation

**Retrieval decides what is relevant. Context building decides how it is fed to reasoning.**
