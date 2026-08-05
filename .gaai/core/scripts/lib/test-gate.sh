#!/usr/bin/env bash
# lib/test-gate.sh — deterministic differential test gate
#
# Sourceable library. Public entry points:
#   _run_deterministic_test_gate <story_id> <worktree_path> <qa_report_path>
#     Returns: 0 = not blocked, 1 = blocked/escalated (caller must stop;
#       this function already performs the scheduler --set-phase-status +
#       notify_escalation_inline side effects). Used directly as the local
#       fallback path — see _run_merge_test_gate below.
#   _run_merge_test_gate <story_id> <worktree_path> <qa_report_path> <pr_url> <expected_head_sha>
#     Gates the MERGE step (post-push, post-PR-create). Prefers the GitHub
#     Actions test-gate.yml workflow-run conclusion for the exact pushed
#     commit when the diff is in that workflow's path scope; falls back to
#     _run_deterministic_test_gate (unchanged) when the CI result cannot be
#     observed (out-of-scope diff, no PR, timeout, gh API error) — never
#     treats an unobservable CI result as a pass.
#     Returns: 0 = proceed to merge, 1 = caller must skip merge and return 1
#       (same side-effect contract as _run_deterministic_test_gate).
#
# Differential semantics (must stay aligned with qa-review skill Step 4):
# only a test that PASSES on origin/<TARGET_BRANCH> and FAILS on the story's
# HEAD is a blocking regression. A test already red on the baseline (rot,
# documented flaky) never blocks. Concurrency-flaky tests that merely flip
# between the two runs are absorbed by the runner's native per-test retry
# (vitest `--retry`, see _test_gate_flaky_retry_suffix) so a single flip is
# not mistaken for a diff-introduced regression. Fail-safe direction
# throughout: on any ambiguity (no baseline, no resolvable test command) this
# gate escalates — it never silently passes and never loops the whole gate.
#
# Env vars (all optional, have defaults):
#   TARGET_BRANCH  — remote branch compared against (default: staging)
#   TEST_GATE_FLAKY_RETRIES — vitest per-test retries on both runs (default: 2;
#                             0 disables). Only applied to vitest-based scripts.
#   GAAI_TEST_UNIT_TIMEOUT_SEC — per-unit wall-clock backstop (default: 2400 =
#                             40 min). Deliberately generous: this does NOT
#                             replace the streaming-output design below (that
#                             solves the hang-detector false-positive on
#                             legitimately slow full-suite runs); it only
#                             bounds a unit that stops producing output
#                             entirely (deadlock, hung process waiting on
#                             stdin/network) — the case streaming cannot help.
#   SCHEDULER      — absolute path to backlog-scheduler.sh (required by caller)
#   BACKLOG_FILE   — absolute path to active.backlog.yaml (required by caller)
#
# Internal helpers (not part of the public contract, but stable within this
# file): _test_gate_resolve_units, _test_gate_run_units,
# _test_gate_parse_junit_failures, _test_gate_resolve_pm,
# _test_gate_pkg_script, _test_gate_append_report, _test_gate_restore,
# _test_gate_ci_scope_touched, _test_gate_poll_ci_verdict.
#
# CI-delegated merge gate env vars (all optional, have defaults):
#   GAAI_CI_TEST_GATE_TIMEOUT_SEC        — bounded poll wait (default: 1200,
#                                           same order of magnitude as
#                                           GAAI_AGENT_HANG_THRESHOLD_SEC)
#   GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC  — sleep between polls (default: 20;
#                                           keeps wrapper.log fresh so the
#                                           hang-detector never fires on a
#                                           legitimate CI wait — see
#                                           _test_gate_poll_ci_verdict)
#   GAAI_CI_TEST_GATE_API_TIMEOUT_SEC    — wall-clock bound for each GitHub
#                                           API call (default: 30)

[[ -n "${_TEST_GATE_SH_SOURCED:-}" ]] && return 0
_TEST_GATE_SH_SOURCED=1

_TEST_GATE_UNRESOLVED_MARKER="###TEST-GATE-UNRESOLVED###"

# ── PM / package-script resolution (generic, AC4) ──────────────────────────
_test_gate_resolve_pm() {
  local worktree_path="$1"
  local pkg="${worktree_path}/package.json"
  local pm=""
  if [[ -f "$pkg" ]]; then
    pm=$(grep -m1 '"packageManager"' "$pkg" 2>/dev/null | \
      sed -E 's/.*"packageManager"[[:space:]]*:[[:space:]]*"([a-zA-Z]+)@?[^"]*".*/\1/')
  fi
  if [[ -z "$pm" ]]; then
    if [[ -f "${worktree_path}/pnpm-lock.yaml" ]]; then
      pm="pnpm"
    elif [[ -f "${worktree_path}/yarn.lock" ]]; then
      pm="yarn"
    elif [[ -f "${worktree_path}/package-lock.json" ]]; then
      pm="npm"
    fi
  fi
  echo "$pm"
}

# Per-package-manager directory-scoped invocation — flags genuinely differ
# (pnpm -C, npm --prefix, yarn --cwd); never assume pnpm's flag for another pm.
_test_gate_pm_cmd() {
  local pm="$1" dir="$2" script="$3"
  case "$pm" in
    npm)  echo "npm --prefix ${dir} run ${script}" ;;
    yarn) echo "yarn --cwd ${dir} run ${script}" ;;
    *)    echo "${pm} -C ${dir} run ${script}" ;;  # pnpm, and best-effort default
  esac
}

# Reads scripts[<script_name>] from <dir>/package.json. Empty stdout = not
# declared (or node/package.json unavailable) — caller treats as absent.
_test_gate_pkg_script() {
  local dir="$1" script_name="$2"
  local pkg="${dir}/package.json"
  [[ -f "$pkg" ]] || return 1
  command -v node >/dev/null 2>&1 || return 1
  TEST_GATE_PKG_PATH="$pkg" TEST_GATE_SCRIPT_NAME="$script_name" node -e '
    try {
      const p = require(process.env.TEST_GATE_PKG_PATH);
      const s = (p.scripts && p.scripts[process.env.TEST_GATE_SCRIPT_NAME]) || "";
      process.stdout.write(s);
    } catch (e) { process.stdout.write(""); }
  ' 2>/dev/null
}

# ── Flaky-tolerance: append the runner's native per-test retry ──────────────
# A differential gate blocks on a test that fails on HEAD but passed on the
# baseline run. Concurrency-sensitive tests (DO alarm / Workers-pool timing)
# flip between runs on their own, so a single flip is falsely read as a new
# regression introduced by the diff. Vitest can retry a failing test in-place
# (`--retry=N`) and reports the final outcome — a flaky test that passes on a
# retry never enters the fail list, while a genuine failure still fails every
# attempt. The suffix is applied to BOTH the HEAD and baseline runs (same
# resolved command), so the differential stays honest. Only appended when the
# resolved script actually runs vitest — other runners take a different retry
# flag, so for them the gate keeps its no-retry behaviour (stack-agnostic).
#
# `<pm> run <script> -- --retry=N` forwards the flag to the END of the script
# string, so it only lands on vitest when the script is a SINGLE vitest command.
# For a chained script (`vitest run … && tsc …`) the flag would attach to the
# trailing command instead (unknown flag → that command errors on both runs),
# so chained scripts are left untouched (no retry, prior behaviour). Best-effort
# for vitest + npm/pnpm; on yarn the passthrough may be ignored (retry simply
# not applied — still symmetric, never a false block).
# Args: script_body, base_cmd. Prints base_cmd, plus ` -- --retry=N` for vitest.
_test_gate_flaky_retry_suffix() {
  local script_body="$1" base_cmd="$2"
  local retries="${TEST_GATE_FLAKY_RETRIES:-2}"
  # Honour only a plain integer — never feed an arbitrary env string to bash
  # arithmetic ([[ -gt ]] evaluates array-subscript syntax = an eval class);
  # any non-integer disables retry rather than crashing the gate.
  [[ "$retries" =~ ^[0-9]+$ ]] || retries=0
  if [[ "$retries" -gt 0 && "$script_body" == *vitest* \
        && "$script_body" != *'&&'* && "$script_body" != *';'* \
        && "$script_body" != *'|'* ]]; then
    echo "${base_cmd} -- --retry=${retries}"
  else
    echo "$base_cmd"
  fi
}

# ── Unit resolution (bash + JS/TS surfaces, AC3+AC4) ────────────────────────
# Args: worktree_path, changed_files (newline list, repo-relative, from
# `git diff --name-only`). Emits `<type>|<label>|<cmd>` lines (type in
# bash|junit|pm) to stdout, followed by an optional unresolved-roots block
# (marker line + one root per line) when a touched root declared neither
# `test:ci` nor `test`. Kept pure (no diagnostic logging) because callers
# invoke it via command substitution.
_test_gate_resolve_units() {
  local worktree_path="$1" changed_files="$2"
  local pm
  pm=$(_test_gate_resolve_pm "$worktree_path")

  local -a unresolved=()
  local f has_bash_root=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" == .gaai/core/scripts/* ]] && has_bash_root=1
  done <<< "$changed_files"

  if [[ "$has_bash_root" -eq 1 ]]; then
    local t bash_unit_count=0
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      echo "bash|${t}|bash ${t}"
      bash_unit_count=$(( bash_unit_count + 1 ))
    done < <(find "${worktree_path}/.gaai/core/scripts/tests" -maxdepth 1 -name '*.test.sh' 2>/dev/null | sort)
    [[ "$bash_unit_count" -eq 0 ]] && unresolved+=(".gaai/core/scripts/tests (no *.test.sh found)")
  fi

  local dirs
  dirs=$(
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ "$f" == .gaai/core/scripts/* ]] && continue
      local d
      d="$(dirname "$f")"
      while [[ "$d" != "." && "$d" != "/" ]]; do
        if [[ -f "${worktree_path}/${d}/package.json" ]]; then
          echo "$d"
          break
        fi
        d="$(dirname "$d")"
      done
    done <<< "$changed_files" | sort -u
  )

  local d abs_dir script
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    abs_dir="${worktree_path}/${d}"
    if [[ -z "$pm" ]]; then
      unresolved+=("$d (package manager unresolved)")
      continue
    fi
    script=$(_test_gate_pkg_script "$abs_dir" "test:ci")
    if [[ -n "$script" ]]; then
      echo "junit|${abs_dir}|$(_test_gate_flaky_retry_suffix "$script" "$(_test_gate_pm_cmd "$pm" "$abs_dir" "test:ci")")"
      continue
    fi
    script=$(_test_gate_pkg_script "$abs_dir" "test")
    if [[ -n "$script" ]]; then
      echo "pm|${abs_dir}|$(_test_gate_flaky_retry_suffix "$script" "$(_test_gate_pm_cmd "$pm" "$abs_dir" "test")")"
      continue
    fi
    unresolved+=("$d (no test:ci or test script declared)")
  done <<< "$dirs"

  if [[ "${#unresolved[@]}" -gt 0 ]]; then
    echo "$_TEST_GATE_UNRESOLVED_MARKER"
    printf '%s\n' "${unresolved[@]}"
  fi
}

# ── JUnit XML failure extraction ────────────────────────────────────────────
# Args: xml_path, dir_label. Prints `<dir_label>::<classname>::<name>` per
# failing <testcase> to stdout. Returns 1 (nothing printed, caller must
# degrade to coarse exit-code) when the file is empty/absent or contains no
# <testcase> element at all — never crashes on malformed XML.
_test_gate_parse_junit_failures() {
  local xml_path="$1" dir_label="$2"
  local tc_count=0
  [[ -s "$xml_path" ]] && tc_count=$(grep -c '<testcase' "$xml_path" 2>/dev/null || true)
  [[ "${tc_count:-0}" -eq 0 ]] && return 1

  awk -v dir="$dir_label" '
    /<testcase[^>]*\/>/ { next }
    /<testcase[[:space:]]/ {
      line = $0
      classname = ""; name = ""
      # Space-anchored: "name=" is also a suffix of "classname=", so an
      # unanchored match on /name="[^"]*"/ would wrongly capture the
      # classname value instead of the real name attribute.
      if (match(line, /[[:space:]]classname="[^"]*"/)) {
        full = substr(line, RSTART, RLENGTH)
        classname = substr(full, 13, length(full) - 13)
      }
      if (match(line, /[[:space:]]name="[^"]*"/)) {
        full = substr(line, RSTART, RLENGTH)
        name = substr(full, 8, length(full) - 8)
      }
      infail = 0
      next
    }
    /<failure|<error/ { infail = 1 }
    /<\/testcase>/ {
      if (infail == 1) print dir "::" classname "::" name
      infail = 0
    }
  ' "$xml_path"
  return 0
}

# ── Run every resolved unit, collect failed labels ──────────────────────────
# Args: worktree_path, units (newline list of `<type>|<label>|<cmd>`).
# Prints one failed label per line to stdout — this IS the differential
# signal the orchestrator diffs, so all diagnostic logging in here goes to
# stderr (never stdout) to avoid contaminating the captured fail-list.
_test_gate_run_units() {
  local worktree_path="$1" units="$2"
  local -a failed=()
  local type label cmd exit_code

  while IFS='|' read -r type label cmd; do
    [[ -z "$type" ]] && continue
    # Stream live instead of buffering the whole run in a `$(...)` capture:
    # a full-suite unit can legitimately take longer than the wrapper's
    # hang-detector threshold, and `out=$(... 2>&1)` produces zero output
    # until the command exits — indistinguishable from a real hang on the
    # log-mtime signal the detector watches. PIPESTATUS[0] preserves the
    # actual command's exit code (not tee's).
    echo "[TEST-GATE] unit=${label} type=${type} starting" >&2
    # Deprioritise: this can spawn several workerd-backed vitest workers at
    # 100%+ CPU each, run twice per commit-phase attempt (HEAD + baseline),
    # with up to MAX_CONCURRENT deliveries in parallel — background test
    # execution otherwise competes evenly with the operator's foreground work
    # for CPU scheduling. Renice THIS subshell before spawning the test
    # process so its children inherit the lowered niceness — must target
    # $BASHPID, not $$: inside `( ... )`, $$ still resolves to the PARENT
    # shell's PID (bash never rebinds it for subshells), so `renice -p $$`
    # relabels a process that already forked this subshell before the call
    # ran and has no effect on anything forked from here. Verified: children
    # spawned after `renice -p $$` stayed at nice 0; after `renice -p
    # $BASHPID` they correctly inherit 15. macOS/Linux still grant idle CPU
    # when nothing else needs it, so total suite wall-clock is not
    # meaningfully affected — only scheduling priority under contention
    # changes.
    local _tg_to_cmd
    _tg_to_cmd=$(declare -F _resolve_timeout_cmd >/dev/null 2>&1 && _resolve_timeout_cmd || true)
    (renice -n 15 -p $BASHPID >/dev/null 2>&1
     cd "$worktree_path" || exit
     if [[ -n "$_tg_to_cmd" ]]; then
       $_tg_to_cmd "${GAAI_TEST_UNIT_TIMEOUT_SEC:-2400}" bash -c "$cmd"
     else
       eval "$cmd"
     fi) 2>&1 | tee -a /dev/stderr >/dev/null
    exit_code=${PIPESTATUS[0]}
    echo "[TEST-GATE] unit=${label} type=${type} exit=${exit_code}" >&2

    case "$type" in
      bash|pm)
        [[ "$exit_code" -ne 0 ]] && failed+=("$label")
        ;;
      junit)
        local xml="${label}/test-results.xml"
        local parsed
        if [[ -f "$xml" ]] && parsed=$(_test_gate_parse_junit_failures "$xml" "$label"); then
          while IFS= read -r pl; do
            [[ -n "$pl" ]] && failed+=("$pl")
          done <<< "$parsed"
        elif [[ "$exit_code" -ne 0 ]]; then
          failed+=("$label")
        fi
        ;;
    esac
  done <<< "$units"

  [[ "${#failed[@]}" -gt 0 ]] && printf '%s\n' "${failed[@]}"
  return 0
}

# ── QA-report audit trail (AC5) ─────────────────────────────────────────────
_test_gate_append_report() {
  local qa_report_path="$1" verdict="$2" base_ref="$3" base_sha="$4" \
    new_failures="$5" base_fail_list="$6" reason="$7"
  {
    printf '\n## Test Gate\n\n'
    printf -- '- Verdict: %s\n' "$verdict"
    printf -- '- Baseline: %s (%s)\n' "$base_ref" "${base_sha:-unresolved}"
    if [[ -n "$new_failures" ]]; then
      printf -- '- New failures (vs baseline):\n'
      while IFS= read -r l; do
        [[ -n "$l" ]] && printf '  - %s\n' "$l"
      done <<< "$new_failures"
    fi
    if [[ -n "$base_fail_list" ]]; then
      printf -- '- Pre-existing baseline failures (non-blocking):\n'
      while IFS= read -r l; do
        [[ -n "$l" ]] && printf '  - %s\n' "$l"
      done <<< "$base_fail_list"
    fi
    [[ -n "$reason" ]] && printf -- '- Reason: %s\n' "$reason"
    printf -- '- Timestamp: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >> "$qa_report_path" 2>/dev/null || true
}

# Restores the worktree to $branch. Never errors the caller (best-effort) —
# called explicitly at each orchestrator return point after the baseline
# checkout (NOT via `trap ... RETURN`: that trap is not function-scoped in
# bash — it re-fires on every ancestor function's return for the rest of the
# call chain, using whatever `$worktree_path`/`$branch` are in scope there).
_test_gate_restore() {
  local worktree_path="$1" branch="$2"
  git -C "$worktree_path" checkout --quiet "$branch" >/dev/null 2>&1 || true
}

# ── Orchestrator ─────────────────────────────────────────────────────────────
_run_deterministic_test_gate() {
  local story_id="$1" worktree_path="$2" qa_report_path="$3"
  local target_branch="${TARGET_BRANCH:-staging}"
  local base_ref="origin/${target_branch}"

  echo "[TEST-GATE] ${story_id} : starting differential test gate (base=${base_ref})"

  # ── Step 1: fresh baseline fetch (AC1 "freshly-fetched", AC4 degrade) ─────
  if ! git -C "$worktree_path" fetch origin "$target_branch" --quiet 2>/dev/null || \
     ! git -C "$worktree_path" rev-parse --verify -q "$base_ref" >/dev/null 2>&1; then
    _test_gate_append_report "$qa_report_path" "ESCALATED" "$base_ref" "" "" "" \
      "baseline ${base_ref} could not be fetched/resolved"
    echo "[ERROR] ${story_id} test-gate: baseline unresolved [class=TEST_GATE_BASELINE_UNRESOLVED]"
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    if declare -F notify_escalation_inline >/dev/null 2>&1; then
      notify_escalation_inline "$story_id" "test_gate_baseline_unresolved" \
        "git fetch/resolve of ${base_ref} failed in ${worktree_path}"
    fi
    return 1
  fi

  local base_sha
  base_sha=$(git -C "$worktree_path" rev-parse "$base_ref" 2>/dev/null)

  # ── Step 2: diff vs baseline (AC2 no-op short-circuit) ────────────────────
  local changed_files
  changed_files=$(git -C "$worktree_path" diff --name-only "${base_ref}...HEAD" 2>/dev/null)
  if [[ -z "$changed_files" ]]; then
    _test_gate_append_report "$qa_report_path" "PASS" "$base_ref" "$base_sha" "" "" \
      "no diff vs baseline"
    echo "[TEST-GATE] ${story_id} : PASS — no diff vs ${base_ref}"
    return 0
  fi

  # ── Step 3: resolve affected units (AC3+AC4) ──────────────────────────────
  local resolve_raw units unresolved_roots
  resolve_raw=$(_test_gate_resolve_units "$worktree_path" "$changed_files")
  units=$(printf '%s\n' "$resolve_raw" | awk -v m="$_TEST_GATE_UNRESOLVED_MARKER" '$0==m{exit} {print}')
  unresolved_roots=$(printf '%s\n' "$resolve_raw" | awk -v m="$_TEST_GATE_UNRESOLVED_MARKER" 'f{print} $0==m{f=1}')

  if [[ -z "$units" ]]; then
    if [[ -n "$unresolved_roots" ]]; then
      _test_gate_append_report "$qa_report_path" "ESCALATED" "$base_ref" "$base_sha" "" "" \
        "no test command resolvable for touched root(s): ${unresolved_roots}"
      echo "[ERROR] ${story_id} test-gate: command unresolved for: ${unresolved_roots} [class=TEST_GATE_COMMAND_UNRESOLVED]"
      "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
      if declare -F notify_escalation_inline >/dev/null 2>&1; then
        notify_escalation_inline "$story_id" "test_gate_command_unresolved" \
          "No test/test:ci command declared for: ${unresolved_roots}"
      fi
      return 1
    fi
    _test_gate_append_report "$qa_report_path" "PASS" "$base_ref" "$base_sha" "" "" \
      "diff touches no known test-mapped source root"
    echo "[TEST-GATE] ${story_id} : PASS — diff touches no test-mapped source root"
    return 0
  fi

  # ── Step 4: run affected units on HEAD (current committed diff) ──────────
  local head_fail_list
  head_fail_list=$(_test_gate_run_units "$worktree_path" "$units")

  # ── Step 4.5: detached-checkout baseline, run same units, restore ────────
  # _test_gate_restore is called explicitly at every return point below
  # (checkout-failure / differential-blocked / PASS) instead of via
  # `trap ... RETURN` — see the comment on _test_gate_restore for why.
  local branch
  branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)

  if ! git -C "$worktree_path" checkout --quiet --detach "$base_ref" 2>/dev/null; then
    _test_gate_append_report "$qa_report_path" "ESCALATED" "$base_ref" "$base_sha" "" "" \
      "baseline detached-checkout failed"
    echo "[ERROR] ${story_id} test-gate: baseline checkout failed [class=TEST_GATE_BASELINE_CHECKOUT_FAILED]"
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    if declare -F notify_escalation_inline >/dev/null 2>&1; then
      notify_escalation_inline "$story_id" "test_gate_baseline_checkout_failed" \
        "git checkout --detach ${base_ref} failed in ${worktree_path}"
    fi
    # No detached checkout took hold (the command above failed) — nothing to restore.
    return 1
  fi

  local base_fail_list
  base_fail_list=$(_test_gate_run_units "$worktree_path" "$units")
  _test_gate_restore "$worktree_path" "$branch"

  # ── Step 5-9: differential compare + report + terminal routing ───────────
  local new_failures
  new_failures=$(comm -23 <(printf '%s\n' "$head_fail_list" | sort) \
                          <(printf '%s\n' "$base_fail_list" | sort) | grep -v '^$' || true)

  if [[ -n "$new_failures" ]]; then
    _test_gate_append_report "$qa_report_path" "BLOCKED" "$base_ref" "$base_sha" \
      "$new_failures" "$base_fail_list" ""
    echo "[ERROR] ${story_id} test-gate: new failures vs baseline: ${new_failures} [class=TEST_GATE_NEW_FAILURE]"
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    if declare -F notify_escalation_inline >/dev/null 2>&1; then
      notify_escalation_inline "$story_id" "test_gate_new_failure" \
        "New test failure(s) vs ${base_ref}: ${new_failures}"
    fi
    return 1
  fi

  _test_gate_append_report "$qa_report_path" "PASS" "$base_ref" "$base_sha" "" "$base_fail_list" ""
  echo "[TEST-GATE] ${story_id} : PASS — no new failures vs ${base_ref}"
  return 0
}

# ── CI-delegated merge gate ──────────────────────────────────────────────────

# Scope pre-check — mirrors .github/workflows/test-gate.yml's own `paths:`
# filter (workers/**, packages/**). Pure git, no network/gh call: this is
# what lets an out-of-scope diff (e.g. .gaai/**-only) resolve to the local
# fallback instantly, with zero gh API calls. If the workflow's paths filter
# is ever widened without updating this glob list (or vice versa), the two
# drift — see Risk Register in this feature's execution plan; drift fails safe
# (an extra unavailable:timeout fallback cycle), never a silent pass.
# Returns 0 = in scope, 1 = not in scope (including "no diff at all").
_test_gate_ci_scope_touched() {
  local worktree_path="$1"
  local base_ref="origin/${TARGET_BRANCH:-staging}"
  local changed_files
  changed_files=$(git -C "$worktree_path" diff --name-only "${base_ref}...HEAD" 2>/dev/null)
  [[ -z "$changed_files" ]] && return 1
  local f
  while IFS= read -r f; do
    case "$f" in workers/*|packages/*) return 0 ;; esac
  done <<< "$changed_files"
  return 1
}

# Validates a positive, arithmetic-safe integer setting. Invalid values fall
# back to the documented default instead of creating a zero-sleep busy loop,
# an infinite negative-elapsed loop, or an arithmetic-expression injection.
_test_gate_positive_int() {
  local raw="$1" fallback="$2" label="$3"
  if [[ "$raw" =~ ^[1-9][0-9]{0,8}$ ]]; then
    printf '%s\n' "$raw"
  else
    echo "[WARN] test-gate: invalid ${label}='${raw}' — using ${fallback}" >&2
    printf '%s\n' "$fallback"
  fi
}

# Runs one command with a portable wall-clock timeout (GNU `timeout` is not
# available by default on macOS). Stdout is replayed to the caller; stderr is
# intentionally suppressed because GitHub CLI diagnostics may contain noisy
# transport details and the caller emits the stable fallback reason. Returns
# 124 when the watchdog fires, otherwise the command's actual exit code.
_test_gate_run_with_timeout() {
  local timeout_sec="$1"
  shift

  local output_file timeout_marker
  output_file=$(mktemp "${TMPDIR:-/tmp}/gaai-test-gate-api.XXXXXX") || return 125
  timeout_marker="${output_file}.timeout"

  "$@" >"$output_file" 2>/dev/null &
  local command_pid=$!
  (
    # Poll in short increments so cancelling a completed call's watchdog cannot
    # strand a long-lived `sleep` child on shells that do not cascade signals.
    local watchdog_deadline watchdog_now
    watchdog_deadline=$(( $(date +%s) + timeout_sec ))
    while kill -0 "$command_pid" 2>/dev/null; do
      watchdog_now=$(date +%s)
      (( watchdog_now >= watchdog_deadline )) && break
      sleep 1
    done
    if kill -0 "$command_pid" 2>/dev/null; then
      : > "$timeout_marker"
      kill -TERM "$command_pid" 2>/dev/null || true
      # This is a read-only CLI call, so do not add a post-deadline grace
      # period that would weaken the caller's wall-clock bound.
      kill -0 "$command_pid" 2>/dev/null && kill -KILL "$command_pid" 2>/dev/null || true
    fi
  ) >/dev/null 2>&1 &
  local watchdog_pid=$!

  local command_rc=0
  wait "$command_pid" || command_rc=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  local did_timeout=0
  [[ -f "$timeout_marker" ]] && did_timeout=1
  [[ -s "$output_file" ]] && command cat "$output_file"
  rm -f "$output_file" "$timeout_marker"

  [[ "$did_timeout" -eq 1 ]] && return 124
  return "$command_rc"
}

# Polls the workflow-run endpoint for `.github/workflows/test-gate.yml`,
# filtered to the exact pushed head SHA. A workflow run is the authoritative
# aggregate: unlike a `gh pr checks` row snapshot, it cannot report success in
# the window after the detect job completes but before its dynamic matrix jobs
# materialise. Before returning a decisive verdict, the PR's current head is
# re-read and must still equal the expected SHA. The eventual merge command
# also sends that SHA to the REST merge endpoint as its atomic TOCTOU backstop.
#
# Bounded and sleep-based — never busy-waits. Prints exactly one line to
# STDOUT: "pass", "fail", "blocked:head_moved", or
# "unavailable:<reason>" (reason in timeout|api_error). Progress logging goes
# to stderr because stdout is the signal captured by the caller. No scheduler
# or notification side effects occur here.
_test_gate_poll_ci_verdict() {
  local story_id="$1" pr_url="$2" expected_head_sha="$3"
  local timeout_sec poll_interval api_timeout_sec
  timeout_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_TIMEOUT_SEC:-1200}" 1200 GAAI_CI_TEST_GATE_TIMEOUT_SEC)
  poll_interval=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC:-20}" 20 GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC)
  api_timeout_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_API_TIMEOUT_SEC:-30}" 30 GAAI_CI_TEST_GATE_API_TIMEOUT_SEC)

  local started_at deadline now remaining call_timeout sleep_for
  started_at=$(date +%s)
  deadline=$(( started_at + timeout_sec ))
  local api_err_streak=0
  local jq_expr='if (.workflow_runs | length) == 0 then "missing" else (.workflow_runs | sort_by(.created_at) | last | [(.status // "unknown"), (.conclusion // "pending"), (.head_sha // "missing")] | @tsv) end'

  while :; do
    now=$(date +%s)
    (( now >= deadline )) && break
    remaining=$(( deadline - now ))
    call_timeout="$api_timeout_sec"
    (( call_timeout > remaining )) && call_timeout="$remaining"

    local run_line gh_rc=0
    run_line=$(_test_gate_run_with_timeout "$call_timeout" gh api --method GET \
      "repos/{owner}/{repo}/actions/workflows/test-gate.yml/runs" \
      -f event=pull_request -f head_sha="$expected_head_sha" -F per_page=10 \
      --jq "$jq_expr") || gh_rc=$?

    if [[ "$gh_rc" -eq 0 && "$run_line" == "missing" ]]; then
      api_err_streak=0
    elif [[ "$gh_rc" -eq 0 && "$run_line" == *$'\t'* ]]; then
      local run_status run_conclusion observed_head_sha
      IFS=$'\t' read -r run_status run_conclusion observed_head_sha <<< "$run_line"
      if [[ "$observed_head_sha" != "$expected_head_sha" ]]; then
        api_err_streak=$(( api_err_streak + 1 ))
      elif [[ "$run_status" == "completed" ]]; then
        # A completed blocking conclusion for the exact pushed SHA is already
        # decisive. Do not let an unrelated PR-head lookup outage downgrade a
        # known CI failure into the local fallback path.
        if [[ "$run_conclusion" != "success" && "$run_conclusion" != "cancelled" ]]; then
          echo "fail"
          return 0
        fi

        # The workflow lookup may have consumed most of this iteration's
        # budget. Recompute the remaining wall clock before the second call.
        # Both success and cancellation need this check: success may authorize
        # only the current head, while cancellation caused by a superseding
        # push must report the moved head rather than masquerading as failure.
        now=$(date +%s)
        (( now >= deadline )) && break
        remaining=$(( deadline - now ))
        local head_call_timeout="$api_timeout_sec"
        (( head_call_timeout > remaining )) && head_call_timeout="$remaining"

        local current_head_sha head_rc=0
        current_head_sha=$(_test_gate_run_with_timeout "$head_call_timeout" gh pr view "$pr_url" \
          --json headRefOid --jq .headRefOid) || head_rc=$?
        if [[ "$head_rc" -ne 0 || ! "$current_head_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
          api_err_streak=$(( api_err_streak + 1 ))
        elif [[ "$current_head_sha" != "$expected_head_sha" ]]; then
          echo "blocked:head_moved"
          return 0
        elif [[ "$run_conclusion" == "success" ]]; then
          echo "pass"
          return 0
        else
          # A same-head cancelled run is non-decisive: a manual re-run may
          # supersede it. Keep polling until a decisive run appears or the
          # bounded wait falls back locally.
          api_err_streak=0
        fi
      else
        # queued/in_progress/waiting/requested/pending are valid observations.
        api_err_streak=0
      fi
    else
      api_err_streak=$(( api_err_streak + 1 ))
    fi

    if (( api_err_streak >= 3 )); then
      echo "unavailable:api_error"
      return 0
    fi

    now=$(date +%s)
    (( now >= deadline )) && break
    remaining=$(( deadline - now ))
    sleep_for="$poll_interval"
    (( sleep_for > remaining )) && sleep_for="$remaining"
    echo "[TEST-GATE-CI] ${story_id} : waiting on ${pr_url}@${expected_head_sha} (elapsed=$(( now - started_at ))s/${timeout_sec}s)" >&2
    sleep "$sleep_for"
  done
  echo "unavailable:timeout"
}

# ── Orchestrator (public) ───────────────────────────────────────────────────
# Gates the merge step. Decision tree: out-of-scope diff or no PR → immediate
# local fallback (zero gh calls) ; in-scope + PR → poll CI ; CI pass/fail is
# decisive ; CI unavailable (timeout/api_error) → local fallback. Never
# treats an unobservable CI result as a pass (fail-safe precedent).
_run_merge_test_gate() {
  local story_id="$1" worktree_path="$2" qa_report_path="$3" pr_url="$4" expected_head_sha="$5"

  local _fallback_reason=""
  if ! _test_gate_ci_scope_touched "$worktree_path"; then
    _fallback_reason="path_scope_excluded"
  elif [[ -z "$pr_url" ]]; then
    _fallback_reason="no_pr"
  elif [[ ! "$expected_head_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
    _fallback_reason="head_unresolved"
  fi

  if [[ -n "$_fallback_reason" ]]; then
    echo "[WARN] ${story_id} handle_commit_phase: CI test-gate result unavailable (${_fallback_reason}) — falling back to local gate [class=TEST_GATE_CI_UNAVAILABLE_FALLBACK]"
    _run_deterministic_test_gate "$story_id" "$worktree_path" "$qa_report_path"
    return $?
  fi

  local verdict reason
  verdict=$(_test_gate_poll_ci_verdict "$story_id" "$pr_url" "$expected_head_sha")
  case "$verdict" in
    pass)
      echo "[TEST-GATE] ${story_id} : PASS (CI, ${pr_url}@${expected_head_sha})"
      _test_gate_append_report "$qa_report_path" "PASS" "CI:${pr_url}@${expected_head_sha}" "" "" "" ""
      return 0
      ;;
    fail)
      echo "[ERROR] ${story_id} handle_commit_phase: CI test gate reported failure [class=TEST_GATE_BLOCKED]"
      "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
      if declare -F notify_escalation_inline >/dev/null 2>&1; then
        notify_escalation_inline "$story_id" "test_gate_ci_failure" \
          "CI test-gate run failed for ${pr_url}"
      fi
      _test_gate_append_report "$qa_report_path" "BLOCKED" "CI:${pr_url}@${expected_head_sha}" "" "" "" "CI test-gate workflow run reported failure"
      return 1
      ;;
    blocked:head_moved)
      echo "[ERROR] ${story_id} handle_commit_phase: PR head moved after push; refusing merge [class=TEST_GATE_BLOCKED]"
      "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
      if declare -F notify_escalation_inline >/dev/null 2>&1; then
        notify_escalation_inline "$story_id" "test_gate_head_moved" \
          "PR head no longer matches pushed commit ${expected_head_sha} for ${pr_url}"
      fi
      _test_gate_append_report "$qa_report_path" "BLOCKED" "CI:${pr_url}@${expected_head_sha}" "" "" "" "PR head moved after the tested push"
      return 1
      ;;
    *)
      reason="${verdict#unavailable:}"
      echo "[WARN] ${story_id} handle_commit_phase: CI test-gate result unavailable (${reason}) — falling back to local gate [class=TEST_GATE_CI_UNAVAILABLE_FALLBACK]"
      _run_deterministic_test_gate "$story_id" "$worktree_path" "$qa_report_path"
      return $?
      ;;
  esac
}
