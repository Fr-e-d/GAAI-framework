---
name: generate-stories
description: Translate a single Epic into clear, actionable User Stories with explicit acceptance criteria. Activate when an Epic is defined and work needs to be prepared for Delivery execution.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-GENERATE-STORIES-001
  updated_at: 2026-01-27
  status: stable
inputs:
  - one_epic: contexts/artefacts/epics/{id}.epic.md (the parent Epic file)
  - prd  (optional)
outputs:
  - contexts/artefacts/stories/*.md
---

# Generate Stories

## Purpose / When to Activate

Activate when:
- An Epic is defined
- Adding or refining functionality
- Preparing work items for AI implementation

Stories are the **contract between Discovery and Delivery**. They must be the main execution unit in GAAI.

---

## Process

1. Read the Story template at `contexts/artefacts/stories/_template.story.md`. Read the parent Epic file. Derive story IDs using the parent Epic ID prefix (e.g., Epic E01 produces stories E01S01, E01S02, etc.).
2. Write from the user's perspective
3. Focus on behavior, not UI or technology
4. Keep stories small and independent
5. Ensure every story is testable
6. Avoid technical solutions in story body
7. For each story, answer: "What should the user be able to do or experience?"
8. Output using canonical Story template

---

## Outputs

Template: `contexts/artefacts/stories/_template.story.md`

Produces files at `contexts/artefacts/stories/{id}.story.md`:

```
As a {user role},
I want {goal},
so that {benefit/value}.

Acceptance Criteria:
- [ ] Given {context}, when {action}, then {expected result}
```

---

## Quality Checks

- Written from the user's perspective
- Acceptance criteria are explicit and testable
- No technical implementation detail in story body
- Each story maps to a single Epic
- Stories are independent and deliverable individually
- Each story file's frontmatter `id` and `related_backlog_id` match the parent Epic's ID prefix

---

## Non-Goals

This skill must NOT:
- Define architecture or implementation approach
- Generate Epics (use `generate-epics`)
- Produce stories without a parent Epic

**Stories are the contract. Ambiguous stories produce ambiguous software.**
