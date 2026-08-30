---
name: ci-watch-and-fix
description: Observe the authoritative exact PR/head/base workflow attempt, wait without mutation while it runs, and enter bounded remediation only after its aggregate job has completed with failure.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent using GitHub Actions CI
metadata:
  author: gaai-framework
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-DELIVERY-CI-WATCH-001
  updated_at: 2026-03-02
  owner: Delivery Orchestrator
  status: stable
inputs:
  - repository_id
  - pr_number
  - story_id
  - story_branch
  - admitted_head_sha
  - admitted_base_ref
  - configured_workflow_identity
  - configured_event
  - worktree_path
  - log_dir
outputs:
  - closed CI observation tuple with state WAIT | QUALIFIED | REMEDIATE | BLOCKED
dependencies:
  - gh CLI authenticated with repo + actions:read scopes
---

# CI Watch and Fix

## Purpose / When to Activate

**Owner: Delivery Orchestrator.**

Activate only after the exact locally admitted head has been published, the PR repository/head/base
identity has been bound, and `status: in_progress`, `phase_status: qa_passed`,
`pr_status: pending_review` has been durably persisted. Hosted observation does not authorize a
merge or a terminal lifecycle transition.

This skill resolves one authoritative current workflow attempt, waits without mutation while that
attempt is queued or running, and enters the existing bounded remediation loop only when the
selected attempt has completed with a failed aggregate authority job. It never enables auto-merge,
invokes a provider merge mutation, uses an admin fallback or treats hosted success as merge
permission.

Do not use `gh pr checks --watch`. Poll deterministic provider metadata so each observation can be
rebound to the exact candidate and the durable output stays closed and privacy-safe.

---

## External Dependencies

- `gh` CLI authenticated with `repo` + `actions:read` scopes.

---

## Preconditions

Fail closed before observation unless the PR repository, number, head SHA and base ref exactly match
the locally admitted tuple; the configured workflow has one exact stable ID plus path/name; the
configured event is known; the pending-review receipt names the same candidate; and provider run
and job metadata are available. Missing, stale, ambiguous or contradictory identity returns
`BLOCKED` with no retry, push, remediation or lifecycle mutation.

## Authoritative Attempt Selection

For every poll:

1. Re-read the PR and verify its exact repository, number, head and base association.
2. Build the authoritative run subset using exact repository, configured workflow ID and matching
   path/name, configured event, and unique PR/head/base association. Apply every filter before
   inspecting a job.
3. Select the lexicographic maximum `(run_number, run_attempt)` across the complete matching subset.
   Never fall back to an older successful run because the greatest current run is queued, running,
   incomplete or has no aggregate job yet.
4. If the selected run is queued or running, return `WAIT` without requiring a job. If it is
   completed, inspect jobs and require exactly one same-attempt job named `PR Authority`. A completed
   run with zero jobs, multiple jobs, attempt mismatch or unavailable job metadata is `BLOCKED`.
5. Re-resolve the subset and greatest-current attempt on every poll.

Required falsifiers include a higher matching run queued without jobs over an older success; a
higher attempt of the same run queued without jobs; a completed selected attempt with zero or
multiple aggregate jobs; and a numerically newer foreign workflow/event/PR/head/base run that must
be filtered before selection.

## State Partition

| Provider observation | State | Closed reason | Permitted action |
|---|---|---|---|
| selected run queued | `WAIT` | `run_queued` | observe again; no mutation |
| selected run running | `WAIT` | `run_running` | observe again; no mutation |
| completed run and aggregate succeeded | `QUALIFIED` | `aggregate_succeeded` | preserve pending-review hold |
| completed run and aggregate failed | `REMEDIATE` | `aggregate_failed` | enter one bounded remediation cycle |
| cancelled | `BLOCKED` | `run_cancelled` | preserve and escalate |
| skipped | `BLOCKED` | `run_skipped` | preserve and escalate |
| neutral | `BLOCKED` | `run_neutral` | preserve and escalate |
| timed out | `BLOCKED` | `run_timed_out` | preserve and escalate |
| action required | `BLOCKED` | `action_required` | preserve and escalate |
| unavailable observation | `BLOCKED` | `observation_unavailable` | preserve and escalate |
| no matching run | `BLOCKED` | `run_set_empty` | preserve and escalate |
| ambiguous matching run identity | `BLOCKED` | `run_set_ambiguous` | preserve and escalate |
| PR/head/base/workflow/event mismatch | `BLOCKED` | `identity_mismatch` | preserve and escalate |
| unknown provider state | `BLOCKED` | `run_state_unknown` | preserve and escalate |
| aggregate job absent | `BLOCKED` | `aggregate_missing` | preserve and escalate |
| aggregate job duplicated | `BLOCKED` | `aggregate_multiple` | preserve and escalate |
| aggregate job from another attempt | `BLOCKED` | `aggregate_mismatch` | preserve and escalate |

`WAIT`, `QUALIFIED` and `BLOCKED` never consume a remediation cycle, rerun a workflow, create an
empty commit, republish a candidate, push a branch or mutate lifecycle state. A repository without
branch protection, an empty check set or infrastructure failure never becomes an advisory PASS.

## Remediation

Only `REMEDIATE` may enter the existing maximum-three-cycle remediation policy. For each admitted
cycle, inspect the selected failed aggregate's raw logs ephemerally in memory, apply only a
cause-based Story-scoped correction, run deterministic local validation, obtain fresh final
admission, publish and bind the new exact candidate, persist `pending_review`, then resolve a fresh
authoritative attempt. Raw logs may not be copied into emitted or durable output. Scope or contract
drift returns `BLOCKED`. Exhaustion preserves the branch, PR, worktree and closed evidence.

## Heartbeat

During `WAIT`, emit only the closed durable tuple below at the configured heartbeat cadence. Waiting
and polling are deterministic operations and must not invoke fresh model inference. The heartbeat
must not contain provider messages, log excerpts, timestamps, paths, actor identities or candidate
content.

## Closed Durable CI Tuple

Every persisted or emitted CI observation contains exactly these fields:

```
schema_version
story_id
repository_id
pull_request_id
head_sha_digest
base_ref_digest
workflow_id
workflow_definition_digest
event
run_id
run_number
run_attempt
aggregate_job_id
state
reason
evidence_digest
```

`state` is exactly one of `WAIT`, `QUALIFIED`, `REMEDIATE`, `BLOCKED`. `reason` is exactly one of the
closed reasons in the State Partition. Identifiers and candidate references that could expose raw
values are represented by stable opaque identifiers or digests. No additional field or free-form
text is allowed. Durable output must not contain raw log text, error excerpts, filesystem paths,
timestamps, operator identities, candidate bodies, environment values, command output or provider
messages.

## Privacy-Safety Census

Verify the positive closed tuple and the negative exclusions across stdout and stderr; delivery and
daemon reports; journals and lifecycle projections; QA or evidence artefacts; commit subjects and
bodies; and heartbeat or completion output. Falsify raw-log, free-form, path, timestamp, operator
and candidate-body leakage independently. Raw failed logs are allowed only in ephemeral memory
during an admitted `REMEDIATE` cycle and must be discarded before any durable write or output.

## Outputs

Return exactly one closed durable CI tuple:

- `WAIT`: the authoritative greatest-current attempt is queued or running.
- `QUALIFIED`: the exact selected completed attempt and unique aggregate succeeded; remain
  `pending_review` until an external exact-current merge is watcher-verified.
- `REMEDIATE`: the exact selected completed attempt and unique aggregate failed; the bounded
  remediation path may run.
- `BLOCKED`: observation or identity is unsafe, ambiguous, unavailable or otherwise terminal;
  preserve all recoverable state and escalate.

## Non-Goals

This skill must not:

- authorize or execute a merge, enable auto-merge or use admin fallback;
- mark a Story `done`, `merged` or terminal;
- downgrade absent checks, provider failure or infrastructure failure to advisory success;
- fall back from a newer authoritative attempt to an older successful one;
- retry or mutate on any observation other than completed aggregate failure;
- persist raw CI logs or free-form remediation evidence;
- expand Story scope or alter acceptance criteria.

## Quality Checks

- Pending-review persistence precedes hosted observation for every exact candidate.
- The authoritative subset is filtered before greatest-current selection.
- Job inspection occurs only for the selected completed attempt and yields exactly one aggregate
  authority job; queued or running attempts wait without requiring one.
- The state partition is exhaustive, closed and fail-closed.
- Only a selected completed aggregate failure enters remediation.
- Hosted qualification never becomes merge permission.
- The closed tuple and privacy-safety census cover every durable and visible sink.
- External exact-current merge verification remains the watcher's sole terminal authority.
