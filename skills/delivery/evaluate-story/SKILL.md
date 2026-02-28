---
name: evaluate-story
description: Assess Story complexity, identify required domains, and determine delivery tier (MicroDelivery / Core Team / Core Team + Specialists). Activate as the first step of every delivery orchestration cycle.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DEL-007
  updated_at: 2026-02-26
  status: stable
inputs:
  - contexts/artefacts/stories/**       (the Story to evaluate)
  - agents/specialists.registry.yaml    (to check domain triggers)
  - skills/skills-index.yaml            (to verify skill coverage for identified domains)
  - contexts/memory/index.md            (registry — resolve project context file from `project` category)
outputs:
  - evaluation result (inline — not written to file)
---

# Evaluate Story

## Purpose / When to Activate

Activate as the **first action** of every Delivery Orchestration cycle, before any sub-agent is spawned.

The Orchestrator needs to know:
1. What tier applies (MicroDelivery / Core Team / Core Team + Specialists)
2. Which domains are involved (for specialist registry matching)
3. Whether any pre-flight risk analysis is warranted

---

## Process

### 1. Read the Story

Read the full Story artefact: acceptance criteria, complexity field, `depends_on` list, tags.

### 2. Assess complexity

| Signal | Weight |
|--------|--------|
| `complexity` field in backlog item | Primary signal |
| Number of acceptance criteria | Secondary signal |
| Number of files mentioned in criteria | Secondary signal |
| Cross-cutting concerns (API + DB + UI) | Complexity escalator |
| Prior QA failures on similar work (check decisions log) | Complexity escalator |

### 3. Scan for domain triggers

Read `agents/specialists.registry.yaml`. Scan the Story's acceptance criteria and title for trigger keywords. Record which specialists would be needed.

### 4. Verify skill coverage

Read `skills/skills-index.yaml`. For each domain identified in Step 3, verify that at least one skill in the index covers the required capability.

Check:
- Do the identified domains map to existing skills (by `description`, `tags`, or `category`)?
- Are there specialist-triggered domains with no corresponding skill?

If a required skill is missing:
- Record the gap: which capability is needed, for which domain
- This will be reported in the output as `skill_gaps`

If all required skills exist, record `skill_gaps: []`.

**This step does not block evaluation** — it reports gaps. The Orchestrator decides whether to proceed or escalate based on gap severity.

### 5. Determine tier

```
complexity ≤ 2  AND  files_affected ≤ 2  AND  criteria_count ≤ 3  AND  no specialist triggers
    → Tier 1: MicroDelivery

complexity 3–7  OR  criteria_count > 3  OR  moderate specialist triggers
    → Tier 2: Core Team

complexity ≥ 8  OR  multiple specialist triggers  OR  cross-cutting at scale
    → Tier 3: Core Team + Specialists
```

### 6. Determine pre-flight risk analysis

Risk analysis is warranted when:
- Story touches security, auth, payments, PII
- Schema or API contract changes
- Blast radius is unclear
- Same area has had prior QA failures

---

## Output

Returns (inline, to the Orchestrator's reasoning):

```
tier: 1 | 2 | 3
specialists_triggered: [list of specialist IDs or empty]
skill_gaps: [list of {domain, missing_capability, severity: critical|non-critical} or empty]
risk_analysis_required: true | false
complexity_assessment: brief note if complexity field is overridden
blocked: true | false  (true if any skill_gap has severity: critical)
```

This output drives the Orchestrator's next action. It is not written to a file — it is the Orchestrator's internal decision.

---

## Quality Checks

- Tier assignment is consistent with complexity signals
- Specialist triggers are matched against registry, not guessed
- Skill gaps are matched against `skills-index.yaml`, not guessed
- Over-staffing (Core Team for a typo fix) is as wrong as under-staffing
- A Story with critical skill gaps must not proceed to `compose-team`
