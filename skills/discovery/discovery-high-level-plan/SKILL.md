---
name: discovery-high-level-plan
description: Transform vague or high-level human intent into a governed Discovery action plan. Activate when intent is unclear, broad, or when multiple discovery steps are required before any artefact is created.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-DISCOVERY-HIGH-LEVEL-PLAN-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - human_intent
  - contexts/artefacts/**  (optional)
  - contexts/memory/**  (selective)
outputs:
  - discovery_action_plan
---

# Discovery High-Level Planning

## Purpose / When to Activate

Activate this skill when:
- Intent is unclear or broad
- Multiple discovery steps are required
- You don't know which skills to run first
- Refinement is needed before committing to artefacts

Typical triggers: "I have an idea for a feature", "Users are dropping during onboarding", "We should rethink pricing"

**This skill plans — it does not produce artefacts.**

---

## Process

1. Understand the real problem or opportunity
2. Determine Discovery scope: new initiative / feature addition / iteration / removal / clarification
3. Identify required artefacts
4. Select necessary skills in logical order
5. Insert validation and refinement gates
6. Output a minimal, governed plan

---

## Outputs

```
Discovery Action Plan

Goal:
<what clarity must be achieved>

Steps:
1. <skill name> — purpose
2. <skill name> — purpose
3. <skill name> — purpose

Validation Gates:
- artefact completeness
- acceptance criteria present
- uncertainties flagged

Ready For Delivery:
yes / no

Blocking Reasons (if any):
- ...
```

---

## Quality Checks

- Plan is minimal and focused
- All necessary artefacts will be produced
- Skill sequence is logical
- Governance is respected
- Human can approve or adjust easily

---

## Non-Goals

This skill must NOT:
- Generate epics, stories, or PRDs
- Make product decisions
- Execute other skills
- Write artefact content

**If the next step isn't obvious — plan first. Planning prevents waste more than speed increases output.**
