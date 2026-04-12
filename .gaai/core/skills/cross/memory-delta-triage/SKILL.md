---
name: memory-delta-triage
description: Apply three deterministic heuristics to a single memory-delta file to produce a structured verdict block; invoke memory-ingest on ACCEPTED candidates only in validate mode. Activate when Discovery processes a raw memory-delta from contexts/artefacts/memory-deltas/.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-DELTA-TRIAGE-001
  updated_at: 2026-04-12
  status: stable
inputs:
  - delta_id: exactly one memory-delta ID (e.g. E01S01) — zero or multiple exits immediately with error
  - mode: draft | validate
  - contexts/artefacts/memory-deltas/{delta_id}.memory-delta.md
  - contexts/rules/memory-architecture.rules.md (§1 — heuristic 1 and 3)
  - contexts/memory/index.md (heuristic 2)
  - .gaai/core/skills/cross/memory-ingest/SKILL.md (Anti-Collision Guard — heuristic 2)
outputs:
  - Triage Verdict block (YAML, inline in response or appended to delta file per mode)
  - In validate mode: memory-delta moved to contexts/artefacts/memory-deltas/processed/{delta_id}.memory-delta.md after memory-ingest is invoked for each ACCEPTED candidate
---

# Memory Delta Triage

## Purpose / When to Activate

Activate when Discovery holds a raw memory-delta file (produced by `memory-alignment-check`
after QA PASS) and needs a governed, auditable verdict before deciding whether to invoke
`memory-ingest`.

This skill applies exactly three heuristics to each candidate in the delta. It produces a
`## Triage Verdict` block. All judgment is attributed to the invoking Discovery agent — this
skill is a deterministic procedure, not a decision maker.

**Two modes:**

- **`draft`** — triage without writing memory. Writes the Triage Verdict block inline and
  leaves the delta file in its original location. Does NOT invoke `memory-ingest`.
  Use when Discovery wants to review verdicts before committing.

- **`validate`** — triage with write authority. For every candidate with `verdict: ACCEPT`,
  instructs Discovery to invoke `memory-ingest`. After all ACCEPTED candidates are processed,
  moves the delta file to `contexts/artefacts/memory-deltas/processed/`.

---

## Process

### Step 0 — Single-delta scope check

Verify exactly one `delta_id` argument is provided.
- If zero delta paths provided → exit immediately: "ERROR: memory-delta-triage requires exactly one delta_id. Received: 0."
- If multiple delta paths provided → exit immediately: "ERROR: memory-delta-triage requires exactly one delta_id. Received: N. Process deltas one at a time."

### Step 0b — Processed-delta collision check (base.rules.md §6)

Check whether a file already exists at `contexts/artefacts/memory-deltas/processed/{delta_id}.memory-delta.md`.
- If it exists → STOP. Emit: "ESCALATE: delta {delta_id} already exists in processed/. Re-processing a processed delta is forbidden (base.rules.md §6). Verify intent before proceeding."
- Do NOT continue.

### Step 0c — Schema check

Read `contexts/artefacts/memory-deltas/{delta_id}.memory-delta.md`.

Verify the file contains:
1. `artefact_type: memory-delta` in YAML frontmatter
2. At least one of the required structural sections: `## Confirmed Entries`, `## Contradicted Entries`, `## New Knowledge Candidates`

On FAIL (either check fails):
- Emit Triage Verdict block with `schema_check: FAIL`, all candidates set to `verdict: ESCALATE`
- STOP — do not proceed to heuristics

On PASS: continue to Step 1.

### Step 1 — Extract candidates

From the delta file, collect all items under `## New Knowledge Candidates` and
`## Contradicted Entries`. Each item is a candidate for triage. Confirmed-only entries
with no contradiction and no new candidate are noted in the verdict as informational
but receive no heuristic evaluation.

### Step 2 — Apply Heuristic 1: Invariant test

Reference: `contexts/rules/memory-architecture.rules.md` §1 (Content Principle — refactor test).

For each candidate, apply the test literally as stated in that section:
> "If the codebase is refactored tomorrow without changing the design intent, does this
> content still read correctly?"

Do NOT restate the rule content here. The rule file is the authoritative source.

- PASS → content is a conceptual invariant
- FAIL → content is a code snapshot; candidate is not suitable for memory ingestion

### Step 3 — Apply Heuristic 2: Dedup vs index check

Reference: `contexts/memory/index.md` (check for existing coverage) and
`memory-ingest` Anti-Collision Guard (`.gaai/core/skills/cross/memory-ingest/SKILL.md`,
Process section — Anti-Collision Guard paragraph).

For each candidate:
1. Check `contexts/memory/index.md` for entries whose category and tags match the candidate
2. If a matching entry exists, read it and assess: same topic/entity → FAIL (duplicate);
   different topic/entity → PASS (new knowledge)
3. If no matching entry exists → PASS

Do NOT restate the Anti-Collision Guard logic here. The skill file is the authoritative source.

- PASS → no duplicate detected
- FAIL → duplicate or collision risk; candidate requires escalation

### Step 4 — Apply Heuristic 3: Scope test

Reference: `contexts/rules/memory-architecture.rules.md` §1 "What does NOT belong".

For each candidate, verify it is a cross-module / durable concern and NOT story-specific
transient state. Specifically:
- If the content would be stale after the story branch is merged → FAIL (story-specific)
- If the content applies only to the transient state of a single story → FAIL
- If the content is a cross-cutting invariant relevant beyond this story → PASS

Do NOT restate the rule content here. The rule file is the authoritative source.

- PASS → cross-module durable concern
- FAIL → story-specific; does not belong in long-term memory

### Step 5 — Unanimity gate and verdict per candidate

For each candidate:
- `verdict: ACCEPT` if and only if ALL THREE heuristics return PASS
- `verdict: ESCALATE` if ANY heuristic returns FAIL (unanimity: MIXED)

This gate is hard-coded. No partial acceptance. No override.

### Step 6 — Produce Triage Verdict block

Emit the block in the schema defined in the `## Triage Verdict Block Schema` section below.

- In `draft` mode: append the block inline to the response. Leave the delta file in
  `contexts/artefacts/memory-deltas/` (do not move it).
- In `validate` mode: append the block to the delta file, then proceed to Step 7.

### Step 7 (validate mode only) — Invoke memory-ingest and move delta

For each candidate with `verdict: ACCEPT`:
- Instruct Discovery to invoke `memory-ingest` with the candidate content as input.
  The skill itself does NOT call `memory-ingest` directly — it issues an explicit
  instruction to the invoking Discovery agent, including the exact candidate content
  and the target memory category derived from the candidate metadata.

After all ACCEPTED candidates are processed by `memory-ingest` (confirmed by Discovery):
- Move the delta file from `contexts/artefacts/memory-deltas/{delta_id}.memory-delta.md`
  to `contexts/artefacts/memory-deltas/processed/{delta_id}.memory-delta.md`

---

## Triage Verdict Block Schema

```yaml
## Triage Verdict

triaged_by: "[agent identity — e.g. Discovery Agent, autonomous draft mode]"
triaged_at: "YYYY-MM-DD"
mode: draft | validate
delta_id: "{delta_id}"
schema_check: PASS | FAIL

candidates:
  - candidate_id: "{CANDIDATE-NNN or memory_id}"
    verdict: ACCEPT | ESCALATE
    heuristic_1_invariant: PASS | FAIL
    heuristic_2_dedup: PASS | FAIL
    heuristic_3_scope: PASS | FAIL
    unanimity: ALL_PASS | MIXED
    rationale: "{one sentence — specific finding, not vague}"

overall: ACCEPTED | ESCALATED | MIXED | SCHEMA_FAIL
# validate mode only — added after memory-ingest is complete:
validated_by: "[agent identity]"
validated_at: "YYYY-MM-DD"
```

**Field rules:**
- `unanimity: ALL_PASS` only when all three heuristics are PASS; `MIXED` otherwise
- `verdict: ACCEPT` only when `unanimity: ALL_PASS`
- `overall: ACCEPTED` when all candidates are ACCEPT
- `overall: ESCALATED` when all candidates are ESCALATE
- `overall: MIXED` when at least one ACCEPT and at least one ESCALATE
- `overall: SCHEMA_FAIL` when schema check failed (Step 0c)
- `validated_by` and `validated_at` are present ONLY in `validate` mode and only after
  `memory-ingest` has been invoked; absent in `draft` mode

---

## Quality Checks

- Exactly one delta_id was provided — Step 0 enforces this
- Processed-delta collision was checked before any writes — Step 0b
- Schema check was performed and recorded in verdict block — Step 0c
- All three heuristics applied to every candidate — Steps 2–4
- Unanimity gate not bypassed — Step 5
- Verdict block matches schema above — Step 6
- In validate mode: `memory-ingest` instruction is explicit (candidate content + target category) — Step 7
- In validate mode: delta moved to `processed/` only after Discovery confirms `memory-ingest` is complete — Step 7
- All content in this file is OSS-generic — zero project names (per AC13)

---

## Outputs

- `## Triage Verdict` block (YAML) — inline in `draft` mode; appended to delta file in `validate` mode
- In `validate` mode: explicit `memory-ingest` instruction per ACCEPTED candidate
- In `validate` mode: delta file moved to `contexts/artefacts/memory-deltas/processed/{delta_id}.memory-delta.md`

No memory is written by this skill. Memory is written only by `memory-ingest`, invoked by
Discovery on explicit instruction from this skill in `validate` mode only.

---

## Non-Goals

This skill must NOT:
- Invoke `memory-ingest` directly in `draft` mode — in draft mode, the skill writes the
  verdict block and stops. Only Discovery may decide to invoke `memory-ingest`, and only
  after the verdict is reviewed (AC8).
- Process more than one delta at a time — single-delta scope is enforced at Step 0 (AC14).
- Perform architecture-file verify-before-update — that protocol is the responsibility of
  `memory-ingest` (governed by `contexts/rules/memory-architecture.rules.md` §2). This
  skill evaluates suitability only; it does not verify code paths or populate attestation
  fields (AC15).
- Make product or architectural decisions — it applies heuristics and returns verdicts.
  All judgment is attributed to the invoking Discovery agent.
- Write or update any memory file directly.
- Scan the full codebase or all memory files.
- Process memory-deltas that have already been processed (checked at Step 0b).
