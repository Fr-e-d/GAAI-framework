---
name: generate-epics
description: Translate product intent or a PRD into a small set of outcome-driven Epics (3–7 max). Activate when starting a new product, adding a significant feature domain, or breaking down a PRD into actionable user outcomes.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-GENERATE-EPICS-001
  updated_at: 2026-01-27
  status: stable
inputs:
  - product_intent  (or PRD if available)
outputs:
  - contexts/artefacts/epics/*.md
---

# Generate Epics

## Purpose / When to Activate

Activate when:
- Starting a new product
- Adding a significant feature or domain
- Restructuring product scope
- Breaking down a PRD into actionable outcomes

Works with or without a PRD.

---

## Process

1. Read the Epic template at `contexts/artefacts/epics/_template.epic.md` before writing any Epic file.

   **CRITICAL — ID Allocation via guarded allocator (MUST execute before writing any Epic file):**

   Obtain the next Epic ID by invoking the guarded allocator:

     GAAI_REPO_ROOT=$(git rev-parse --show-toplevel)
     NEXT_ID=$(bash "$GAAI_REPO_ROOT/.gaai/core/scripts/lib/allocate-id.sh" epic)

   The allocator serializes allocation under `flock` and records a reservation in a host-stable ledger visible to parallel Discovery sessions on the same host. It computes the next ID as `max(highest ID in active.backlog.yaml, highest reserved ID in the ledger) + 1`, so it accounts for both already-merged IDs and in-flight reservations. If `GAAI_BACKLOG_PATH` is not set, it discovers the backlog relative to the repo root.

   - **a)** If the allocator exits non-zero, **STOP immediately** and surface the error to the human. Do not proceed.
   - **b)** Backstop — for each Epic file to be created, **check if the file already exists** at `contexts/artefacts/epics/{id}.epic.md`. If it exists with different content, **STOP immediately** — surface the conflict to the human.
   - **Rationale:** In a past incident, two concurrent sessions both assigned the same Epic ID to different epics via independent scan-max +1. The second overwrote the first's stories. The guarded allocator serializes the read-decide-reserve step so racing sessions never pick the same ID; the file-exists check is the residual backstop.

2. Think in **user outcomes**, not features
3. Keep Epics high-level and value-focused
4. Avoid implementation detail
5. Limit to 3–7 Epics maximum
6. For each Epic, answer: "What meaningful user result will this create?"
7. Set domain based on the Epic's primary intent (e.g., engineering, marketing, legal). Leave empty if not applicable.
8. Output using the canonical Epic template

---

## Outputs

Template: `contexts/artefacts/epics/_template.epic.md`

Produces files at `contexts/artefacts/epics/{id}.epic.md`.

Key sections per Epic:
- Purpose: what user outcome this delivers and why it matters
- Scope: high-level description of what is included
- Out of Scope: what is explicitly excluded
- Stories: list of story IDs (descriptive only; authoritative tracking is in the backlog)
- Success Metrics: how to know the Epic delivered value
- Dependencies: other Epics or external factors this depends on

---

## Quality Checks

- Each Epic expresses a user outcome, not a technical feature
- Maximum 7 Epics per initiative
- No implementation detail present
- Each Epic is independently valuable
- **No Epic ID collision** — the assigned ID does not exist in the backlog or on disk with different content

---

## Non-Goals

This skill must NOT:
- Generate Stories (use `generate-stories`)
- Make technical architecture decisions
- Produce more than 7 Epics per initiative

**Epics are the bridge between vision and execution.**
