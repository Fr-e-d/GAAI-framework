---
name: refine-scope
description: Iteratively refine Discovery artefacts (plans, epics, stories) when feedback, ambiguity, or uncertainty is detected. Activate when artefacts are incomplete, acceptance criteria are missing, or human feedback highlights gaps.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-REFINE-SCOPE-001
  updated_at: 2026-01-28
  status: stable
inputs:
  - discovery_action_plan
  - contexts/artefacts/**  (partially completed)
  - contexts/memory/**  (selective)
  - human_feedback: numbered list of feedback items provided by the Discovery Agent, sourced from human input in the current session
outputs:
  - refined_discovery_plan
  - refined artefacts
---

# Refine Scope

## Purpose / When to Activate

Activate when:
- Artefacts are ambiguous or incomplete
- Acceptance criteria are missing or unclear
- Human or peer feedback highlights gaps
- New information alters original intent
- Discovery action plan indicates unresolved risks

This skill is **not** for first-draft creation — it deepens clarity and reduces uncertainty in existing artefacts.

---

## Process

1. Load relevant context (artefacts + partial plan + memory)
2. Identify gaps, contradictions, or missing acceptance criteria
3. For each numbered feedback item: (a) identify the target artefact field or section, (b) apply the feedback as a direct modification to that field, (c) record what was changed and why in the refinement log.
4. Adjust scope, acceptance criteria, or artefact structure
5. Produce a refined Discovery plan or refined artefacts
6. Verify that all modified fields still comply with the Quality Checks below. If a field fails, mark it for re-refinement in the next iteration. Do NOT invoke `validate-artefacts` — that is the agent's responsibility after this skill completes.
7. Stop when all feedback items from Step 3 have been applied and all modified fields pass the Quality Checks. If any feedback item cannot be applied without changing product intent, flag it as requiring human escalation.

---

## Outputs

**Written outputs:**
- `contexts/artefacts/` — refined artefacts written back to their original locations

**Inline outputs:**
- `refined_discovery_plan` — returned inline to the invoking agent

```
Refined Discovery Action Plan

Goal:
<clarified objective based on feedback>

Steps:
1. <updated skill step> — improved focus
2. <updated skill step> — adjusted checkpoint

Artefact Updates:
- <Epic ID> — updated outcome wording
- <Story ID> — acceptance criteria strengthened

Validation:
- all gates passed: yes | no
- blockers: <if any>
```

---

## Quality Checks

- Acceptance criteria are present and testable
- Artefact scope is clear and bounded
- Cross-dependencies are explicit
- Risks and assumptions are documented
- All governance rules are satisfied

---

## Non-Goals

This skill must NOT:
- Invent new product direction
- Override human intent
- Generate completely new artefacts unconnected to context
- Bypass governance rules

**It enhances, not replaces, existing outputs. Quality drives clarity — refinement reduces ambiguity before execution.**
