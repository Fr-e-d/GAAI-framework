---
name: ci-watch-and-fix
description: Watch GitHub Actions CI after PR creation, detect failures, extract logs, apply minimal fixes, and re-push — keeping the delivery session alive until CI resolves or escalating after 3 cycles. Activate immediately after gh pr create and before marking the story done.
license: MIT
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
  - pr_number          (integer — from gh pr create output)
  - story_id           (string — e.g. E18S01)
  - story_branch       (string — e.g. story/E18S01)
  - repo               (string — e.g. your-org/your-repo)
  - worktree_path      (string — absolute path to story worktree)
  - log_dir            (string — absolute path to daemon log directory, for heartbeat lines)
outputs:
  - CI verdict: PASS | FAIL
  - ci_remediation_report (on FAIL — committed to docs/ci-failures/<story-id>-<timestamp>.md)
dependencies:
  - gh CLI authenticated with repo + actions:read scopes
---

# CI Watch and Fix

## Purpose / When to Activate

**Owner: Delivery Orchestrator.**

Activate **immediately after `gh pr create`** and **before marking the story `done`**.

This skill keeps the delivery session alive through GitHub Actions CI execution. It detects failures, fetches logs, applies minimal fixes, and re-pushes — up to 3 remediation cycles. If CI does not converge within 3 cycles, it escalates without marking the story `done`.

Do NOT use `gh pr checks --watch`. Active polling is mandatory to ensure the log file receives periodic output and the daemon heartbeat monitor does not falsely kill the session. See AC7.

---

## External Dependencies

- `gh` CLI authenticated with `repo` + `actions:read` scopes (already present in the project environment — no additional setup required).

---

## Process

### Initialization

```
cycle = 0
flaky_retry_used = false
previous_failure_signatures = {}   # map: check_name → error_message_hash
```

### Main Loop (max 3 cycles)

```
while cycle < 3:
    cycle += 1

    # Heartbeat — always write a log line at the start of each cycle
    echo "[ci-watch-and-fix] cycle ${cycle}/3 — polling PR #<pr-number> checks" >> $LOG_DIR/<story-id>.log

    # Step 1 — Poll PR checks
    run: gh pr checks <pr-number> --repo <repo>

    # Step 2 — All passing?
    if all checks pass:
        echo "[ci-watch-and-fix] CI PASS — all checks green" >> $LOG_DIR/<story-id>.log
        exit loop → return CI PASS

    # Step 3 — Identify failed checks and their run IDs
    for each failed check:
        get run_id from check

        # Step 4 — Fetch failure logs (truncated to last 3000 chars per job)
        raw_log = gh run view <run-id> --repo <repo> --log-failed
        failure_log = last 3000 chars of raw_log

        # Step 4b — Pre-existing infra failure detection (fast-path)
        # Detect infrastructure-level failures that code changes cannot fix.
        # These are pre-existing conditions unrelated to the story's changes.
        INFRA_PATTERNS = [
            "recent account payments have failed",
            "spending limit needs to be increased",
            "Actions minutes",
            "Actions quota",
            "not started because",       # job queuing failure (billing gate)
            "out of Actions minutes",
        ]
        if any(pattern matches failure_log) for any failed job:
            echo "[ci-watch-and-fix] Pre-existing infra failure detected — billing/quota. Escalating immediately (no retry)." >> $LOG_DIR/<story-id>.log
            convergence_failure_reason = "Pre-existing infrastructure failure: GitHub Actions billing/quota limit. Not caused by this story's changes."
            goto ESCALATE

        # Step 5 — Flaky test detection
        signature = hash(check_name + first_100_chars_of_failure_log)
        if signature in previous_failure_signatures:
            # Same failure seen in a previous cycle → suspected flaky
            if flaky_retry_used:
                # Already used the one flaky retry → escalate
                goto ESCALATE
            else:
                flaky_retry_used = true
                echo "[ci-watch-and-fix] suspected flaky test in <check_name> — pushing empty commit retry" >> $LOG_DIR/<story-id>.log
                git commit --allow-empty -m "ci: retry (suspected flaky)" (in worktree)
                git push origin <story_branch> (in worktree)
                sleep 60
                continue  # next cycle without applying code changes
        else:
            previous_failure_signatures[signature] = true

        # Step 6 — Analyze and fix (non-flaky failures)
        analyze failure_log to identify root cause
        apply minimal corrective code changes (in worktree — do not expand scope)
        git add → git commit -m "fix(ci/<story-id>): <description>" (in worktree)

    # Push all fixes
    git push origin <story_branch> (in worktree)

    # Step 7 — Wait then re-poll
    echo "[ci-watch-and-fix] fixes pushed — waiting 60s before re-poll" >> $LOG_DIR/<story-id>.log
    sleep 60

# Exhausted 3 cycles without CI PASS
goto ESCALATE
```

### Heartbeat Rule

The daemon heartbeat monitor kills sessions silent for >30 minutes. This skill MUST emit at least one line to `$LOG_DIR/<story-id>.log` **every 5 minutes** during CI wait time. During the 60-second sleep between cycles, this is not an issue. If a single CI run takes >5 minutes to complete, emit periodic heartbeat lines:

```
# During long CI waits, poll every 60s and emit a heartbeat line each time
while ci_running:
    sleep 60
    echo "[ci-watch-and-fix] waiting for CI — elapsed: <N>s" >> $LOG_DIR/<story-id>.log
    check if checks are still in_progress
```

---

## Escalation Path (AC3)

Trigger when: cycle > 3 AND CI not passing, OR flaky retries exhausted.

```
ESCALATE:
    # 1. Produce ci_remediation_report
    report_path = docs/ci-failures/<story-id>-<timestamp>.md
    write report containing:
        - story_id
        - pr_number
        - total_cycles_attempted
        - flaky_retry_used
        - per-cycle summary:
            - cycle number
            - checks that failed
            - failure log excerpt (last 500 chars)
            - fix attempted (or "flaky retry" / "none")
        - convergence_failure_reason: why CI did not converge

    # 2. Commit the report to the PR branch (in worktree)
    git add <report_path>
    git commit -m "ci(<story-id>): CI remediation report — convergence failed"
    git push origin <story_branch>

    # 3. Return CI FAIL — do NOT mark story done
    # The delivery wrapper's on_exit trap will mark the story failed (non-zero exit)
    return CI FAIL
```

**NEVER mark the story `done` when returning CI FAIL.**

---

## Flaky Test Detection Heuristic (AC4)

A CI failure is classified as **likely flaky** if:
1. The same CI check fails in the current cycle AND
2. A previous cycle saw a failure in that same check with an **identical error message** (matched via the first 100 characters of the failure log for that check)

When a likely-flaky failure is detected:
- Do **NOT** apply code changes
- Push an empty commit to re-trigger CI: `git commit --allow-empty -m "ci: retry (suspected flaky)"`
- Count this as consuming the **flaky retry slot** (max 1 flaky retry total per story)
- If the flaky retry slot is already used and the same failure recurs → escalate

---

## Fix Principles

When applying corrective code changes for non-flaky failures:
- **Minimal change only** — fix what CI identifies, nothing more
- **No scope expansion** — do not refactor, add features, or change behavior beyond the CI failure
- **Commit message convention:** `fix(ci/<story-id>): <description>` — distinguishable from feature commits
- **Truncate logs:** analyze only the last 3000 chars of each failed job log to stay within context limits

---

## Outputs

**CI PASS:**
```
status: CI PASS
cycles_used: <n>
flaky_retry_used: <true|false>
```

**CI FAIL:**
```
status: CI FAIL
cycles_used: 3
flaky_retry_used: <true|false>
escalation_reason: <why convergence failed>
remediation_report: docs/ci-failures/<story-id>-<timestamp>.md
```

---

## Non-Goals

This skill must NOT:
- Modify acceptance criteria or product scope
- Apply fixes to pre-existing CI failures unrelated to this story's changes
- Attempt to fix infrastructure failures (missing secrets, missing bindings, quota limits, billing limits) — these are ESCALATE conditions (detected via Step 4b fast-path; do NOT burn retry cycles)
- Merge the PR (that is the Orchestrator's responsibility after CI PASS)
- Use `gh pr checks --watch` (heartbeat requirement — see AC7)

---

## Quality Checks

- Every cycle emits at least one heartbeat line to `$LOG_DIR/<story-id>.log`
- Flaky detection compares against previous cycle signatures, not just the current cycle
- Escalation report is committed before returning CI FAIL
- Story is never marked `done` on CI FAIL
- Log truncation is applied before analysis (max 3000 chars per job)
