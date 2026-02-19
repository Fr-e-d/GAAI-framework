---
name: create-prd
description: Produce a lightweight strategic PRD that defines product vision, user problem, value hypothesis, success metrics, and scope boundaries. Activate only when starting a new product, launching a major initiative, or facing strategic uncertainty.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-CREATE-PRD-001
  updated_at: 2026-01-27
inputs:
  - human_intent
  - core_user_problem
  - target_users
  - known_constraints
outputs:
  - contexts/artefacts/prd/*.md
---

# Create PRD

## Purpose / When to Activate

Activate when:
- Starting a new product
- Launching a major new initiative
- Facing strategic uncertainty
- Needing strong alignment before Epics begin

Skip when adding small features, tweaking existing flows, or implementing obvious improvements — go directly to Epics & Stories in those cases.

---

## Process

1. Clarify the core user problem before any solution
2. Identify target users (primary and secondary)
3. Define the value hypothesis: if this succeeds, what changes for users?
4. State explicit success metrics
5. Define scope: what is IN and what is OUT
6. Document constraints and assumptions
7. Output a lean PRD using the canonical template

---

## Output Format

Produces a file at `contexts/artefacts/prd/{name}.prd.md` using `_template.prd.md`:

Key sections:
- Vision
- User Problem
- Target Users
- Value Hypothesis
- Success Metrics
- Scope (in / out)
- Constraints & Assumptions
- Decomposition Path → Epics → Stories

---

## Quality Checks

- Problem is framed before solution
- Value is explicit, not implied
- Scope boundaries are clear
- Success metrics are measurable
- No technical design decisions included

---

## Non-Goals

This skill must NOT:
- Generate Epics or Stories (separate skills)
- Make architectural decisions
- Be invoked for small feature additions

**Always ask WHY before WHAT.**
