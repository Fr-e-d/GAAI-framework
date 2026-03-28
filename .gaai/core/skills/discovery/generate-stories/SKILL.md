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
   - **Rationale:** In a past incident, two concurrent sessions assigned the same Epic ID to different epics. The second session overwrote story files without checking, destroying existing stories. This guard prevents recurrence.

   **CRITICAL — Definition of Ready (DoR) Enforcement (MUST execute after writing each story):**
   - **a)** Read the parent Epic's `mandatory_ac_categories` frontmatter field.
   - **b)** For each declared category (e.g., `i18n`, `copy-quality`, `url-routing`, `icp-targeting`), verify that the story has **at least one AC** that explicitly addresses it.
   - **c)** If a story is missing an AC for a mandatory category: add one. If the requirement is unclear, add a placeholder AC with `[REQUIRES CLARIFICATION]` and flag it to the human.
   - **d)** If the Epic has `mandatory_ac_categories: []` (empty), skip this step.
   - **Rationale:** In a past incident, stories omitted mandatory AC categories (e.g., i18n, copy-quality) despite existing DECs requiring them. The Epic did not declare mandatory AC categories, so the omission went undetected. This step ensures domain-critical requirements cannot be silently skipped.

2. Write from the user's perspective
3. Focus on behavior, not UI or technology
4. Keep stories small and independent
5. Ensure every story is testable
6. Avoid technical solutions in story body
7. For each story, answer: "What should the user be able to do or experience?"
8. Output using canonical Story template
9. **MANDATORY — Validation gates via isolated sub-agents (MUST pass before backlog registration).**

   Before registering ANY story in the backlog, the Discovery Agent MUST execute both gates in sequence. **Both gates MUST be invoked as isolated sub-agents** (via the Agent tool) — never executed inline by the main Discovery agent, even if the main agent is the one that created the story. The author of a story cannot objectively validate its own work.

   a) **Format gate** — invoke `validate-artefacts` (SKILL-VALIDATE-ARTEFACTS-001) as an **isolated sub-agent**. Provide the generated stories and their parent Epic. If verdict is BLOCKED, fix the flagged issues in the main agent and re-invoke the sub-agent until PASS.

   b) **Alignment gate** — invoke `review-story-alignment` (SKILL-RSA-001) as an **isolated sub-agent**. Provide the stories + Epic + referenced DECs + Discovery Session Brief (if one was compiled). If no Session Brief exists, the gate still runs in **reduced-scope mode** (DEC constraints + DoR checks only — Pass A is skipped). If any story FAILs, the Discovery Agent resolves findings (from Brief + DECs) or escalates to the human, then re-invokes the sub-agent until ALL PASS.

   **These gates are sequential: format must PASS before alignment runs.**

   **No exceptions.** Both gates run for every story creation or modification — regardless of batch size (1 story or 20), origin (full Epic session, bug triage, single amendment), or whether a Session Brief was compiled. The reduced-scope mode ensures the alignment gate is always valuable even without a Brief.

   **A story registered in the backlog as `refined` without both gates passing via sub-agents is a governance violation.** If this step is skipped, the commit message will lack gate evidence, which is detectable in review.

   **Rationale:** (1) In a past incident, Discovery produced 14 stories and registered them as `refined` without running either gate — the gates were not in the skill's step list. (2) Later, Discovery self-validated both gates inline, using the "no Session Brief" skip condition to bypass the alignment gate entirely. In both cases, the main agent marked its own homework — no independent review occurred. This step closes both gaps by mandating sub-agent execution with no skip conditions.

10. **MANDATORY — Register in backlog.** After writing all story files, add each story to `contexts/backlog/active.backlog.yaml` with:
   - `id`, `epic`, `title` (from story frontmatter)
   - `status: refined` (if validated) or `status: draft` (if pending validation)
   - `priority` (derived from Epic priority or explicit input)
   - `artefact` path pointing to the story file
   - `dependencies` (from story frontmatter `depends_on` or Epic execution order)
   - `notes` (source context — e.g., Discovery session date, governing DEC)

   **A story that exists only as an artefact file but is not in the backlog is invisible to Delivery and will never be executed.** This step is non-negotiable.

11. **MANDATORY — Commit & push to staging (ATOMIC).** After all story files are written and registered in the backlog, commit all generated/modified files **and push to `staging` in the same step**. Commit without push is a violation — Delivery cannot pick up stories that exist only locally.
    - Stage: story files (`contexts/artefacts/stories/*.story.md`), backlog (`contexts/backlog/active.backlog.yaml`), and any other modified GAAI context files (memory, decisions, etc.)
    - Commit message format: `chore(discovery): generate stories {id_range} for Epic {epic_id}`
      - Example: `chore(discovery): generate stories E06S46–E06S50 for Epic E06`
    - Push to `staging` branch **immediately after commit — never wait for human to request the push**
    - **Rationale:** In a past incident, Discovery committed a story but did not push. The human had to explicitly request the push. The commit and push are a single atomic operation — separating them defeats the purpose of this step.

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
