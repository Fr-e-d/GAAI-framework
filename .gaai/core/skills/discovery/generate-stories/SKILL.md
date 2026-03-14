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
  updated_at: 2026-03-10
  status: stable
inputs:
  - one_epic: contexts/artefacts/epics/{id}.epic.md (the parent Epic file)
  - prd  (optional)
outputs:
  - contexts/artefacts/stories/*.md
  - contexts/backlog/active.backlog.yaml (mandatory — every story must be registered)
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
9. **MANDATORY — Register in backlog.** After writing all story files, add each story to `contexts/backlog/active.backlog.yaml` with:
   - `id`, `epic`, `title` (from story frontmatter)
   - `status: refined` (if validated) or `status: draft` (if pending validation)
   - `priority` (derived from Epic priority or explicit input)
   - `artefact` path pointing to the story file
   - `dependencies` (from story frontmatter `depends_on` or Epic execution order)
   - `notes` (source context — e.g., Discovery session date, governing DEC)

   **A story that exists only as an artefact file but is not in the backlog is invisible to Delivery and will never be executed.** This step is non-negotiable.

10. **MANDATORY — Commit & push to staging.** After all story files are written and registered in the backlog, commit all generated/modified files and push to `staging`:
    - Stage: story files (`contexts/artefacts/stories/*.story.md`), backlog (`contexts/backlog/active.backlog.yaml`), and any other modified GAAI context files (memory, decisions, etc.)
    - Commit message format: `chore(discovery): generate stories {id_range} for Epic {epic_id}`
      - Example: `chore(discovery): generate stories E06S46–E06S50 for Epic E06`
    - Push to `staging` branch
    - This ensures Delivery can pick up new stories immediately without a manual sync step.

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
- **Every generated story has a corresponding entry in `active.backlog.yaml`** — verify by counting story files vs backlog entries for this Epic. Mismatch = FAIL.

---

## Non-Goals

This skill must NOT:
- Define architecture or implementation approach
- Generate Epics (use `generate-epics`)
- Produce stories without a parent Epic

**Stories are the contract. Ambiguous stories produce ambiguous software.**
