---
type: workflow
id: WORKFLOW-DELIVERY-LOOP-001
track: delivery
updated_at: 2026-05-01
---

# Delivery Loop Workflow

> **Branch model:** The delivery workflow targets the `staging` branch. AI never interacts with `production`. Promotion staging → production is a human action via GitHub PR.

Each Story is delivered by the daemon spawning three independent `claude -p` processes (Plan → Impl → QA), followed by deterministic bash commit operations. There is no orchestrator agent — the daemon bash state machine is the sole coordinator.

---

## Overview

The daemon (`delivery-daemon.sh`) directly spawns three standalone `claude -p` processes per story. Each phase agent spawns, executes autonomously, writes its artefact to a known path, then dies. The daemon reads the artefact and advances `phase_status`.

```
Daemon (bash)
  ├─ Phase 1 Plan  → claude -p (planning.daemon-prompt.md)  → execution-plan.md  → phase_status: planned
  ├─ Phase 2 Impl  → nested-claude-spawn.js runImpl()        → impl-report.md     → phase_status: implemented
  ├─ Phase 3 QA    → claude -p (qa.daemon-prompt.md)         → qa-report.md       → phase_status: qa_passed
  └─ Commit phase  → deterministic bash (git + gh)            → PR merged          → phase_status: done
```

Each phase has an isolated context window: cumulative-context risk is bounded per phase, not accumulated across the full story lifecycle.

For daemon state machine internals, see `daemon-dispatch.sh`.

---

## Phase 1 Plan

### Input contract

Env vars set by `handle_plan_phase()` in `daemon-dispatch.sh`:

| Variable | Purpose |
|---|---|
| `$GAAI_STORY_ID` | Story identifier |
| `$GAAI_WORKTREE_PATH` | Absolute worktree root |
| `$GAAI_STORY_PATH` | Path to `{id}.story.md` |
| `$GAAI_PLAN_PATH` | Output path for `execution-plan.md` |
| `$GAAI_EPIC_PATH` | Path to `{epic}.epic.md` |
| `$GAAI_DELIVERY_LOG_FILE` | Per-story log path |
| `$GAAI_WORKSPACE_ID` | Workspace UUID |
| `$GAAI_ORG_ID` | Org UUID |

### Prompt source

Daemon reads `.gaai/core/agents/sub-agents/planning.daemon-prompt.md` and passes it as the `claude -p` system prompt. Story file content at `$GAAI_STORY_PATH` is included in the prompt body.

### Output contract

- Writes: `$GAAI_PLAN_PATH` (`.gaai/project/contexts/artefacts/plans/{id}.execution-plan.md`)
- Phase transition: `phase_status: not_started → planned` (via `backlog-scheduler.sh --set-phase-status`)
- Daemon verifies file exists before advancing `phase_status`.

### Audit emit

`_emit_plan_routing_record` writes one record to `runtime-routing.jsonl`:

```
trace_id, story_id, phase=plan, provider=primary,
model=$CLAUDE_MODEL_PRIMARY, duration_ms, fallback_reason, impl_model_tag, pipeline=3phase
```

---

## Phase 2 Impl

### Input contract

Env vars consumed by `daemon-prompt-construct.sh` + `nested-claude-spawn.js`:

| Variable | Purpose |
|---|---|
| `$GAAI_STORY_ID` | Story identifier |
| `$GAAI_STORY_PATH` | Path to `{id}.story.md` |
| `$GAAI_PLAN_PATH` | Path to `{id}.execution-plan.md` |
| `$GAAI_EPIC_PATH` | Path to `{epic}.epic.md` |
| `$GAAI_WORKSPACE_PATH` | Worktree root (alias for `$GAAI_WORKTREE_PATH` in impl context) |
| `$GAAI_WORKTREE_PATH` | Absolute worktree root |
| `$GAAI_WORKSPACE_ID` | Workspace UUID |
| `$GAAI_ORG_ID` | Org UUID |
| `$SECONDARY_ROUTE` | `"true"|"false"` (routing decision set by `daemon-dispatch.sh`) |
| `$PROJECT_DIR` | Repository root |

### Prompt construction

<!-- BEGIN R1-R6-CANONICAL-REF -->
The R1-R6 context discipline preamble and NOTES.md bootstrap template live in
`daemon-prompt-construct.sh`. This helper is the single source of truth for impl prompt
construction, used by the 3-phase daemon path.

**Edits to R1-R6 or the NOTES.md template MUST be made in `daemon-prompt-construct.sh`,
NOT here.** Any copy of R1-R6 text in this workflow file is a drift hazard.

To understand the full impl prompt: read `.gaai/core/scripts/daemon-prompt-construct.sh`.
<!-- END R1-R6-CANONICAL-REF -->

### Routing

Impl phase invokes `nested-claude-spawn.js runImpl()` via CLI. Routing is resolved by `resolveMode()` (deterministic pure function inside the module). Modes: `primary` (explicit tag or absent-with-no-env) or `secondary` (explicit tag or absent-with-env-configured). `SECONDARY_ROUTE=true` causes `daemon-prompt-construct.sh` to prepend the R1-R6 context discipline preamble.

For routing matrix, see `contexts/memory/architecture/impl-phase-spawn-pattern.md`.

### Mandatory CLI pattern

```bash
result_json=$(node .gaai/core/adapters/claude-code/nested-claude-spawn.js \
  --prompt-file "$IMPL_PROMPT_FILE" \
  --report-path "$IMPL_REPORT_PATH" \
  --story-id "$GAAI_STORY_ID" \
  [--impl-model-tag primary|secondary|absent])
```

`--log-file` is NOT passed; the module reads `$GAAI_DELIVERY_LOG_FILE` from env.

### Output contract

- Writes: `$IMPL_REPORT_PATH` (`.gaai/project/contexts/artefacts/impl-reports/{id}.impl-report.md`)
- Phase transition: `phase_status: planned → implemented`
- `nested-claude-spawn.js` always exits 0; outcome determined by `result.success` in returned JSON.

### Audit emit

`nested-claude-spawn.js _emitLog()` writes one (or two on fallback) records to `runtime-routing.jsonl`:

```
trace_id, story_id, phase=impl, provider=primary|secondary,
model=$CLAUDE_MODEL_*, duration_ms, fallback_reason, pipeline=3phase
```

After the call, `STORY_TRACE_ID` is overwritten with `result.trace_id` unconditionally.

---

## Phase 3 QA

### Input contract

Env vars set by `handle_qa_phase()` in `daemon-dispatch.sh`:

| Variable | Purpose |
|---|---|
| `$GAAI_STORY_ID` | Story identifier |
| `$GAAI_WORKTREE_PATH` | Absolute worktree root |
| `$GAAI_STORY_PATH` | Path to `{id}.story.md` |
| `$GAAI_PLAN_PATH` | Path to `{id}.execution-plan.md` |
| `$GAAI_IMPL_REPORT_PATH` | Path to `{id}.impl-report.md` |
| `$GAAI_QA_REPORT_PATH` | Output path for `qa-report.md` |
| `$GAAI_QA_SCHEMA_PATH` | Path to `.gaai/core/schemas/qa-verdict.v1.schema.json` (DEC-200) |
| `$GAAI_QA_VERDICT_PATH` | Output path for the JSON sidecar `{id}.qa-verdict.json` (DEC-200) |
| `$GAAI_QA_EXPECTED_SURFACES_PATH` | Path to a daemon-materialized JSON array — the exact surface set the JSON sidecar's `changed_surface_inventory` must equal one-to-one (DEC-200) |
| `$GAAI_EPIC_PATH` | Path to `{epic}.epic.md` |
| `$GAAI_BASE_REF` | Git ref for diff comparison |
| `$GAAI_DELIVERY_LOG_FILE` | Per-story log path |
| `$GAAI_MEMORY_DELTA_PATH` | Output path for memory-delta (optional) |
| `$GAAI_WORKSPACE_ID` | Workspace UUID |
| `$GAAI_ORG_ID` | Org UUID |

### Prompt source

Daemon reads `.gaai/core/agents/sub-agents/qa.daemon-prompt.md` and passes it as the `claude -p` system prompt. Story, execution-plan, and impl-report are included in the prompt body. The prompt requires the QA agent to evaluate and record `state_of_the_art_conformance` before `plan_conformance` (DEC-200 D1).

### Verdict format

QA agent writes `phase_status:` as the first YAML frontmatter field in `$GAAI_QA_REPORT_PATH`. Daemon reads this field to determine disposition:

- `qa_passed` → advance to commit phase
- `qa_failed` → retry impl (up to `MAX_RETRIES=3` total cycles); if exhausted → `failed`
- `qa_escalated` → mark `escalated`, surface to human

### Two-axis JSON handoff (validation-only)

Per **DEC-200**, the QA agent also writes a JSON sidecar to `$GAAI_QA_VERDICT_PATH`
(`{id}.qa-verdict.json`) conforming to `$GAAI_QA_SCHEMA_PATH`, carrying two independent axes
(`plan_conformance`, `state_of_the_art_conformance`), a changed-surface inventory, structured
findings/evidence, a machine-derived aggregate `verdict`, and `remediation_route` /
`replan_required`. The daemon runs `.gaai/core/scripts/lib/qa-verdict.mjs validate` against it
immediately after the existing "qa-report missing" check and before the Markdown `## Verdict:`
parse: **fail-closed** — a missing, malformed, or internally-inconsistent JSON handoff (or one
whose `verdict` disagrees with the parsed Markdown `## Verdict:` line) sends the story straight
to `failed` (no retry), even when the Markdown report looks like a clean PASS.

**This Story (E1096S01) is validation-only.** Phase routing (`phase_status` transitions on
PASS/FAIL/ESCALATE) remains driven exclusively by the Markdown `## Verdict:` line, unchanged.
The JSON sidecar is produced and independently validated, but does not yet drive
`phase_status` transitions on its own axes — only its *invalidity* is a new fail-closed gate.
**E1096S02** owns switching live/recovery consumption to the two-axis contract.

### Output contract

- Writes: `$GAAI_QA_REPORT_PATH` (`.gaai/project/contexts/artefacts/qa-reports/{id}.qa-report.md`)
- Writes: `$GAAI_QA_VERDICT_PATH` (`.gaai/project/contexts/artefacts/qa-reports/{id}.qa-verdict.json`)
- Optional: `$GAAI_MEMORY_DELTA_PATH` if QA agent identifies memory-worthy decisions
- Phase transition: `phase_status: implemented → qa_passed | qa_failed | qa_escalated`

### Audit emit

`_emit_qa_routing_record` writes one record to `runtime-routing.jsonl`:

```
trace_id, story_id, phase=qa, provider=primary,
model=$CLAUDE_MODEL_PRIMARY, duration_ms, fallback_reason, impl_model_tag, pipeline=3phase
```

On successful JSON handoff validation, the daemon additionally logs a one-line summary
(story ID, schema version, both axes, aggregate, remediation route, `evaluated_as_of`,
surface/evidence counts, safe sidecar/report locators — no report bodies, credentials or
authority-URL query values) to the phase log/stdout for observability (AC5). This same summary
is also passed to `_emit_qa_routing_record` as `--qa-summary` on every PASS/FAIL/ESCALATE call
site and is part of the `runtime-routing.jsonl` schema as the `qa_summary` field (allowlisted in
`runtime-routing-logger.js`'s `TELEMETRY_FIELDS`) — so the routing record itself, not only the
phase log, carries the two-axis summary for every terminal QA outcome.

---

## Commit Phase

Deterministic bash only — no `claude -p` invocation. Implemented in `handle_commit_phase()` in `daemon-dispatch.sh`.

**Sequence:**

1. Git add + commit delivery artefacts to story branch
2. Push story branch with retry-rebase pattern (3 attempts, backoff 2s / 4s / 6s)
3. `gh pr create --base staging --head story/{id}`
4. CI watch (advisory mode if no branch protection)
5. `gh pr merge --squash --delete-branch`
6. Backlog status → `done` (flock-serialized push to staging)
7. Worktree removal (the *remote* branch is deleted by `--delete-branch` at step 5; the local worktree is removed here, and the reaper drops any surviving local branch ref)

**Normative authority:** the worktree + PR + cleanup invariants are defined in `orchestration.rules.md §Branch Rules → Worktree lifecycle & cleanup`. This sequence is the procedure; the rules file is the authority. The procedure restates only hard safety boundaries (see **Safety boundary** below); it does not define invariants.

**Base-source invariant:** Story and repair branches must be created from `origin/staging` after a fresh fetch, or from a local `staging` ref that has just been verified byte-equal to `origin/staging`. Do not commit or push Delivery code/content directly on `staging`; use a worktree branch, open a PR to `staging`, then squash-merge it.

**Cleanup backstop:** step 7 is the happy-path removal. If it does not run (crash, dirty tree), the daemon's periodic orphan reaper (`reap_orphaned_worktrees` in `daemon-dispatch.sh`) is the eventually-consistent backstop. Orphan removal is therefore convergent, not synchronous.

**Data-safety refusal:** a dirty or still-active worktree is never force-removed at step 7 or by the reaper — the reaper refuses removal and defers it (skip-and-retry next cycle) rather than risking data loss (see `orchestration.rules.md §Branch Rules`).

**Safety boundary:** `gh pr merge` targeting `main` or `production` is FORBIDDEN. Self-merge to `staging` is permitted after diff-sanity passes.

**Diff-sanity check:** Spawn sub-agent reviewer when `NON_GAAI_DELETIONS > 0` OR `CHANGED_COUNT > 30`. Reviewer verdicts PROCEED or ESCALATE (base.rules.md Rule 5). Reviewer runs in an isolated context window — it receives only Story ACs and the file list, not the daemon's self-assessment.

**Audit emit:** `_emit_commit_routing_record` writes to `runtime-routing.jsonl`:
`trace_id, story_id, phase=commit, pr_url, auto_merge_applied, pipeline=3phase`.

---

## Error Semantics

### Phase-level retry policy

`MAX_RETRIES=3` applies per phase cycle independently (defined as a constant in `daemon-dispatch.sh`; cross-reference there for current value).

QA cycles count toward impl retries: if QA returns `qa_failed`, impl is re-spawned and the counter increments. After 3 `qa_failed` / impl-retry cycles, story transitions to `failed`.

### Failure mode taxonomy

Canonical failure mode enums are defined in `daemon-dispatch.sh`. Refer to:

- **Plan phase:** `PLAN_PHASE_FAILED`, `NO_ARTEFACT`, `PARSE_ERROR`, `SCHEDULER_FAILURE`
- **Impl phase:** `PARSE_ERROR` (JSON parse on spawn output), `False|<error_reason>` from `nested-claude-spawn.js`
- **QA phase:** `QA_SPAWN_FAILED`, `QA_NO_ARTEFACT`, `QA_VERDICT_PARSE_ERROR`, `QA_HANDOFF_INVALID` (DEC-200 JSON sidecar missing/malformed/internally-inconsistent, or disagrees with the Markdown verdict — immediate `failed`, no retry), `QA_VERDICT:FAIL`, `QA_VERDICT:ESCALATE`, `QA_SCHEDULER_FAILURE`
- **Commit phase:** `COMMIT_FAILED`, `PUSH_FAILED`, `PR_CREATE_FAILED`, `AUTO_MERGE_FAILED`, `GH_AUTH_MISSING`, `SCHEDULER_FAILURE`

All constants are defined in `daemon-dispatch.sh`.

### Terminal failure semantics

After `MAX_RETRIES` exhausted at any phase: story transitions to `phase_status: failed`, `status: failed` in backlog. Daemon main loop continues — other ready stories are unaffected. The `failed` state is terminal: no automatic retry. Human intervention required.

### Operator runbook

When a story enters `failed` state:

1. Read `.gaai/project/contexts/backlog/.delivery-logs/{id}.fail-debug.jsonl` (last `phase_status`, error code, stdout/stderr tail)
2. Identify the failure mode from the `fallback_reason` field
3. Fix the root cause (AC gap, dependency missing, etc.)
4. Re-trigger via `backlog-scheduler.sh --set-status {id} refined`
