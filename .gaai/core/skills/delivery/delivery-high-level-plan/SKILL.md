---
name: delivery-high-level-plan
description: Transform validated Stories into a clear, minimal, governed execution plan. Used by the Planning Sub-Agent as the first planning pass before prepare-execution-plan for Tier 2/3, or as the sole planning output for simple Stories.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DELIVERY-HIGH-LEVEL-PLAN-001
  updated_at: 2026-03-02
  owner: Planning Sub-Agent
  status: stable
inputs:
  - contexts/artefacts/stories/**  (validated)
  - acceptance_criteria
  - contexts/rules/**
  - contexts/memory/**  (selective)
  - technical_constraints  (optional)
outputs:
  - contexts/artefacts/plans/{id}.plan.md
---

# Delivery High-Level Execution Plan

## Purpose / When to Activate

**Owner: Planning Sub-Agent.** Not invoked directly by the Delivery Orchestrator.

Used by the Planning Sub-Agent as:
- The **sole planning output** for Tier 1 (MicroDelivery) when a brief plan is sufficient
- The **first planning pass** before `prepare-execution-plan` is invoked for Tier 2/3 Stories

Do NOT activate if Stories are unclear, acceptance criteria are missing, or product scope is still evolving.

---

## Process

**CRITICAL — Anti-Collision Guard (MUST execute before writing any output file):**
Before writing `contexts/artefacts/plans/{id}.plan.md`, check if the target file already exists on disk:
- If it does NOT exist → proceed normally.
- If it DOES exist → **read the existing file first**. Then decide:
  - If the existing content is from a **different entity** (different story ID, different epic) → **STOP immediately**, surface the ID collision to the human, do not proceed.
  - If the existing content is from the **same entity** and an update is warranted → proceed, but preserve any human edits or prior findings that remain relevant. Treat this as an **update**, not a replacement.
  - If the existing content is identical or still valid → skip writing, report "no changes needed".
This guard prevents the silent data loss incident of 2026-03-17 where concurrent sessions overwrote story files.

1. Load only relevant memory and rules
2. Read each Story and acceptance criteria fully
3. Identify required behavior and boundaries
4. Break work into minimal execution steps
5. Surface dependencies and risks
6. Avoid premature optimization or over-engineering
7. Produce a clean, high-signal plan

---

## Outputs

```
Execution Plan — Story <ID>

Objective:
<what must be achieved exactly>

Steps:
1. <clear action> — purpose
2. <clear action> — purpose
3. <clear action> — purpose

Dependencies:
- <if any>

Risks / Constraints:
- <if any>

Validation Gates:
- acceptance criteria covered: yes | no
- rules compliant: yes | no
```

Saves to `contexts/artefacts/plans/{id}.plan.md`.

For Tier 2/3: this output feeds directly into `prepare-execution-plan` for file-level decomposition.

---

## Mandatory Delivery Sequence (Non-Negotiable)

Every plan produced by this skill MUST include the following steps in this order as the **final phase** of any delivery:

```
... → create-pr → ci-watch-and-fix → [if CI PASS] → mark done
                                    → [if CI FAIL after retries] → mark failed
```

- `ci-watch-and-fix` is **always mandatory** — it is never optional.
- The plan must **never** include a "mark done" step without `ci-watch-and-fix` preceding it.
- If CI FAIL is returned by `ci-watch-and-fix`, the story is marked `failed` — not `done`.

**Turn budget note:** A 3-cycle CI remediation loop can consume ~60–90 tool turns. Plans for complex stories should reserve turn budget for CI remediation. Combined implementation + CI remediation should target under 150 turns out of the daemon's 200-turn budget.

---

## Quality Checks

- Every acceptance criterion maps to at least one step
- No rule is violated
- Scope is unchanged from the Story
- Dependencies are explicit
- Nothing ambiguous remains
- Mandatory delivery sequence (create-pr → ci-watch-and-fix → mark done/failed) is present in every plan

---

## Non-Goals

This skill must NOT:
- Redefine product scope
- Add new features
- Make architectural decisions beyond stated constraints
- Start coding
- Bypass rules

**A good execution plan makes coding boring. Boring is reliable. Reliable scales.**
