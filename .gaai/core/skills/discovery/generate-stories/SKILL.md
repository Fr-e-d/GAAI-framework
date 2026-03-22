---
name: generate-stories
description: Translate a single Epic into clear, actionable User Stories with explicit acceptance criteria. Activate when an Epic is defined and work needs to be prepared for Delivery execution.
license: ELv2
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

   **CRITICAL — Decision Cross-Reference (MUST execute before writing any story):**
   - **a)** Extract keywords from the Epic scope and each story's intent (e.g., "email", "billing", "booking", "auth", "cron", "queue", "GCal", "GDPR").
   - **b)** Scan the Decision Registry in `contexts/memory/index.md` for DECs whose `domain`, `title`, or `tags` match these keywords. Use `grep` on `contexts/memory/decisions/` if the registry table is insufficient.
   - **c)** For each matching DEC, read the decision file and assess whether it **constrains** the story's implementation (e.g., DEC-11 constrains how emails are sent, DEC-44 constrains reminder behavior).
   - **d)** List constraining DECs in the story's `related_decs` frontmatter field. If a DEC imposes a specific implementation pattern (e.g., "all email via queues"), add an explicit AC referencing it (e.g., "AC-N: Email sent via CF Queue per DEC-11 — no synchronous sendEmail() calls").
   - **e)** If no DECs match, set `related_decs: []` explicitly — never leave the field empty by omission.
   - **Rationale:** On 2026-02-28, E06S39 created a synchronous `sendEmail()` utility despite DEC-11 (2026-02-19) explicitly prohibiting synchronous email calls. 6 subsequent stories reused it, creating 12 violations undetected for 17 days. The DEC was never referenced in any of the 6 stories because no cross-reference step existed.

   **CRITICAL — Collision Guard (MUST execute before writing any file):**
   - **a)** Scan `contexts/backlog/active.backlog.yaml` for any existing entries with the same Epic ID prefix. If entries exist, determine the **next available story number** (e.g., if E52S01–E52S05 exist, start at E52S06).
   - **b)** For each story file to be created, **check if the file already exists** on disk at `contexts/artefacts/stories/{id}.story.md`. If the file exists and its `id` frontmatter matches a **different** epic or title, **STOP immediately** — this means an ID collision between two epics. Surface the conflict to the human and do not proceed.
   - **c)** If the file exists and its content matches the current Epic (same epic ID, same intent), treat it as an update — read the existing content first and preserve any human edits.
   - **Rationale:** On 2026-03-17, two concurrent sessions assigned E52 to different epics. The second session overwrote E52S01–S04 story files without checking, destroying the admin Worker stories. This guard prevents recurrence.

2. Write from the user's perspective
3. Focus on behavior, not UI or technology
4. Keep stories small and independent
5. Ensure every story is testable
6. Avoid technical solutions in story body
7. For each story, answer: "What should the user be able to do or experience?"

   **CRITICAL — Definition of Ready: Mandatory AC Categories (MUST execute before finalizing any story):**
   - **a)** Read the parent Epic's `mandatory_ac_categories` field (e.g., `[i18n, copy-quality, url-routing, icp-targeting]`).
   - **b)** For each category listed, verify that the story has **at least one AC** that explicitly addresses it. An AC that merely mentions the category name is insufficient — it must specify the concrete requirement (e.g., "i18n: EN primary, FR secondary per DEC-199" not just "supports i18n").
   - **c)** If a story legitimately does not need an AC for a declared category (e.g., a backend-only story does not need `copy-quality`), add an explicit note in the story's Out of Scope: "copy-quality: not applicable — backend only."
   - **d)** If the Epic's `mandatory_ac_categories` field is empty `[]`, skip this check.
   - **Rationale:** On 2026-03-22, E61 stories were delivered without ACs for i18n (DEC-199 EN/FR routing) or copy quality (voice-guide.md). The omission was undetected because no mechanism enforced AC coverage by category. The DoR catches omissions — categories that should be addressed but were silently skipped.

8. Output using canonical Story template
9. **MANDATORY — Register in backlog.** After writing all story files, add each story to `contexts/backlog/active.backlog.yaml` with:
   - `id`, `epic`, `title` (from story frontmatter)
   - `status: refined` (if validated) or `status: draft` (if pending validation)
   - `priority` (derived from Epic priority or explicit input)
   - `artefact` path pointing to the story file
   - `dependencies` (from story frontmatter `depends_on` or Epic execution order)
   - `notes` (source context — e.g., Discovery session date, governing DEC)

   **A story that exists only as an artefact file but is not in the backlog is invisible to Delivery and will never be executed.** This step is non-negotiable.

10. **MANDATORY — Commit & push to staging (ATOMIC).** After all story files are written and registered in the backlog, commit all generated/modified files **and push to `staging` in the same step**. Commit without push is a violation — Delivery cannot pick up stories that exist only locally.
    - Stage: story files (`contexts/artefacts/stories/*.story.md`), backlog (`contexts/backlog/active.backlog.yaml`), and any other modified GAAI context files (memory, decisions, etc.)
    - Commit message format: `chore(discovery): generate stories {id_range} for Epic {epic_id}`
      - Example: `chore(discovery): generate stories E06S46–E06S50 for Epic E06`
    - Push to `staging` branch **immediately after commit — never wait for human to request the push**
    - **Rationale:** On 2026-03-22, Discovery committed E59S03 but did not push. The human had to explicitly request the push. The commit and push are a single atomic operation — separating them defeats the purpose of this step.

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
- **No existing story file was overwritten with a different Epic's content** — verify each written file's `epic` frontmatter matches the intended Epic. Mismatch = CRITICAL FAILURE.
- **Every story has a `related_decs` field in frontmatter** — either a non-empty list of constraining DECs, or an explicit empty list `[]`. Missing field = FAIL. Stories touching email, billing, booking, auth, or infrastructure domains with `related_decs: []` should be double-checked — these domains have the highest DEC density.

---

## Non-Goals

This skill must NOT:
- Define architecture or implementation approach
- Generate Epics (use `generate-epics`)
- Produce stories without a parent Epic

**Stories are the contract. Ambiguous stories produce ambiguous software.**
