#!/usr/bin/env bash
# lib/test-gate.sh — diagnostic local gate + hosted merge authority controller
#
# Sourceable library. Public entry points:
#   _run_deterministic_test_gate <story_id> <worktree_path> <qa_report_path>
#     Returns: 0 = not blocked, 1 = blocked/escalated (caller must stop;
#       this function already performs the scheduler --set-phase-status +
#       notify_escalation_inline side effects). This remains diagnostic-only;
#       it is never a fallback source of merge authority.
#   _run_merge_test_gate <story_id> <worktree_path> <qa_report_path> <pr_url> <expected_head_sha>
#     Gates the MERGE step (post-push, post-PR-create). Reads the project policy
#     from the live PR base commit and authorizes only an exact current hosted
#     `pull_request` run/attempt with one successful required aggregate job.
#     Local tests are never merge authority. Returns 0 only for hosted_pass,
#     2 for human_required:trust_surface_changed, and 1 for blocked:*.
#     Sets TEST_GATE_OUTCOME and, on hosted_pass, TEST_GATE_AUTH_* bindings.
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
# _test_gate_observe_authority_once, _test_gate_poll_hosted_authority,
# _test_gate_outcome_is_deterministic.
#
# Hosted merge-authority env vars (all optional, have defaults):
#   GAAI_CI_TEST_GATE_TIMEOUT_SEC        — technical poll timeout (default:
#                                           2700 = 45 min; distinct from any
#                                           project cost or latency target)
#   GAAI_CI_TEST_GATE_MATERIALIZE_SEC    — bounded sub-wait for a workflow run
#                                           to first appear for the expected
#                                           SHA (default: 300 = 5 min). If no
#                                           run has been observed within this
#                                           sub-budget, the poll returns
#                                           `blocked:run_missing` is returned.
#   GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC  — sleep between polls (default: 20;
#                                           keeps wrapper.log fresh so the
#                                           hang-detector never fires on a
#                                           legitimate hosted-CI wait)
#   GAAI_CI_TEST_GATE_API_TIMEOUT_SEC    — wall-clock bound for each GitHub
#                                           API call (default: 30)
#   GAAI_CI_TEST_GATE_API_RETRIES        — consecutive unavailable snapshots
#                                           allowed before fail-closed return
#                                           (default: 3)
#   GAAI_PREMERGE_AUTHORITY_POLICY_PATH  — repository-relative base-held
#                                           project policy path
#   GAAI_MERGE_AUTHORITY_MERGE_RETRIES   — bounded exact-head mutation/API
#                                           propagation attempts (default: 12)
#   GAAI_MERGE_AUTHORITY_RETRY_SLEEP_SEC — delay between mutation observations
#                                           (default: 5; 0 is useful in tests)
#   GAAI_MERGE_AUTHORITY_LOCK_TIMEOUT_SEC — kernel/process lock wait bound
#                                           (default: 300)
#   GAAI_MERGE_AUTHORITY_LOCK_POLL_SEC   — portable shlock polling interval
#                                           (default: 1; positive integer)

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

# Creates one collision-safe identity file from inside the live unit worker.
# The path is carried in a shell variable; the process identity itself is never
# captured through command substitution (which would insert another process).
_test_gate_private_tempfile_is_safe() {
  local path="$1" permissions inspect_rc
  [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
  permissions=$(LC_ALL=C ls -ld "$path" 2>/dev/null)
  inspect_rc=$?
  [[ "$inspect_rc" -eq 0 ]] || return "$inspect_rc"
  permissions="${permissions%% *}"
  [[ "${permissions:0:1}" == "-" && "${permissions:4:6}" == "------" ]]
}

_test_gate_worker_identity_tempfile() {
  local old_umask create_rc restore_rc=0
  old_umask=$(umask) || return $?
  umask 077
  _TEST_GATE_WORKER_IDENTITY_PATH=$(mktemp "${TMPDIR:-/tmp}/gaai-test-gate-worker.XXXXXX")
  create_rc=$?
  umask "$old_umask" || restore_rc=$?
  [[ "$create_rc" -ne 0 ]] && return "$create_rc"
  [[ "$restore_rc" -ne 0 ]] && return "$restore_rc"
  _test_gate_private_tempfile_is_safe "$_TEST_GATE_WORKER_IDENTITY_PATH"
}

# This /bin/sh must remain a direct child of the live unit worker. Its PPID is
# therefore the exact process that renice must target so later children inherit
# the reduced scheduling priority on every supported Bash version.
_test_gate_worker_identity_write() {
  /bin/sh -c 'printf "%s\n" "$PPID"' > "$1"
}

_test_gate_worker_identity_read() {
  local identity_path="$1" line="" line_count=0
  _TEST_GATE_WORKER_PID=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_count=$((line_count + 1))
    [[ "$line_count" -eq 1 ]] || return 1
    _TEST_GATE_WORKER_PID="$line"
    line=""
  done < "$identity_path"
  [[ "$line_count" -eq 1 ]]
}

_test_gate_worker_identity_cleanup() {
  rm -f "$1"
}

_test_gate_worker_infra_write() {
  local state="$1"
  [[ -n "${_TEST_GATE_INFRA_MARKER_PATH:-}" ]] || return 1
  printf '%s\n' "$state" > "$_TEST_GATE_INFRA_MARKER_PATH"
}

# Emits only a closed, provider-neutral reason. When a prior operation already
# failed, its status remains authoritative even if best-effort cleanup also
# fails; when cleanup is the first failure, its own status is preserved.
_test_gate_worker_setup_failure() {
  local reason="$1" failure_rc="$2" identity_path="${3:-}" cleanup_rc=0
  if [[ -n "$identity_path" ]]; then
    _test_gate_worker_identity_cleanup "$identity_path" >/dev/null 2>&1
    cleanup_rc=$?
    if [[ "$cleanup_rc" -ne 0 ]]; then
      echo "[TEST-GATE] unit setup failed: identity temporary-file cleanup" >&2
      [[ "$failure_rc" -ne 0 ]] || failure_rc="$cleanup_rc"
    fi
  fi
  [[ "$failure_rc" =~ ^[0-9]+$ && "$failure_rc" -gt 0 && "$failure_rc" -le 255 ]] \
    || failure_rc=1
  if ! _test_gate_worker_infra_write "infra:${failure_rc}"; then
    echo "[TEST-GATE] unit setup failed: infrastructure result channel" >&2
  fi
  echo "[TEST-GATE] unit setup failed: ${reason}" >&2
  return "$failure_rc"
}

_test_gate_prepare_worker_identity() {
  local setup_rc
  _TEST_GATE_WORKER_IDENTITY_PATH=""
  _TEST_GATE_WORKER_PID=""

  _test_gate_worker_identity_tempfile
  setup_rc=$?
  if [[ "$setup_rc" -ne 0 ]]; then
    _test_gate_worker_setup_failure "identity temporary-file creation" "$setup_rc" \
      "${_TEST_GATE_WORKER_IDENTITY_PATH:-}"
    return $?
  fi
  if [[ -z "$_TEST_GATE_WORKER_IDENTITY_PATH" || ! -f "$_TEST_GATE_WORKER_IDENTITY_PATH" ]]; then
    _test_gate_worker_setup_failure "identity temporary-file creation" 1 \
      "$_TEST_GATE_WORKER_IDENTITY_PATH"
    return $?
  fi

  _test_gate_worker_identity_write "$_TEST_GATE_WORKER_IDENTITY_PATH"
  setup_rc=$?
  if [[ "$setup_rc" -ne 0 ]]; then
    _test_gate_worker_setup_failure "worker identity write" "$setup_rc" \
      "$_TEST_GATE_WORKER_IDENTITY_PATH"
    return $?
  fi

  _test_gate_worker_identity_read "$_TEST_GATE_WORKER_IDENTITY_PATH"
  setup_rc=$?
  if [[ "$setup_rc" -ne 0 ]]; then
    _test_gate_worker_setup_failure "worker identity read" "$setup_rc" \
      "$_TEST_GATE_WORKER_IDENTITY_PATH"
    return $?
  fi
  if [[ ! "$_TEST_GATE_WORKER_PID" =~ ^[1-9][0-9]*$ ]]; then
    _test_gate_worker_setup_failure "worker identity validation" 1 \
      "$_TEST_GATE_WORKER_IDENTITY_PATH"
    return $?
  fi

  _test_gate_worker_identity_cleanup "$_TEST_GATE_WORKER_IDENTITY_PATH"
  setup_rc=$?
  if [[ "$setup_rc" -ne 0 ]]; then
    _test_gate_worker_setup_failure "identity temporary-file cleanup" "$setup_rc" \
      "$_TEST_GATE_WORKER_IDENTITY_PATH"
    return $?
  fi
  _TEST_GATE_WORKER_IDENTITY_PATH=""
  return 0
}

_test_gate_unit_infra_marker_create() {
  local old_umask create_rc restore_rc=0
  old_umask=$(umask) || return $?
  umask 077
  _TEST_GATE_INFRA_MARKER_PATH=$(mktemp "${TMPDIR:-/tmp}/gaai-test-gate-infra.XXXXXX")
  create_rc=$?
  umask "$old_umask" || restore_rc=$?
  [[ "$create_rc" -ne 0 ]] && return "$create_rc"
  if [[ "$restore_rc" -ne 0 ]]; then
    rm -f "$_TEST_GATE_INFRA_MARKER_PATH" >/dev/null 2>&1 || true
    return "$restore_rc"
  fi
  _test_gate_private_tempfile_is_safe "$_TEST_GATE_INFRA_MARKER_PATH"
  create_rc=$?
  if [[ "$create_rc" -ne 0 ]]; then
    rm -f "$_TEST_GATE_INFRA_MARKER_PATH" >/dev/null 2>&1 || true
    return "$create_rc"
  fi
  return 0
}

_test_gate_unit_infra_marker_read() {
  local marker_path="$1" line="" line_count=0
  _TEST_GATE_INFRA_MARKER_STATE=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_count=$((line_count + 1))
    [[ "$line_count" -eq 1 ]] || return 1
    _TEST_GATE_INFRA_MARKER_STATE="$line"
    line=""
  done < "$marker_path"
  [[ "$line_count" -eq 1 ]]
}

_test_gate_unit_infra_marker_cleanup() {
  rm -f "$1"
}

# ── Run every resolved unit, collect failed labels ──────────────────────────
# Args: worktree_path, units (newline list of `<type>|<label>|<cmd>`).
# Prints one failed label per line to stdout — this IS the differential
# signal the orchestrator diffs, so all diagnostic logging in here goes to
# stderr (never stdout) to avoid contaminating the captured fail-list.
_test_gate_run_units() {
  local worktree_path="$1" units="$2"
  local -a failed=()
  local type label cmd exit_code sink_rc effective_exit unit_infra_rc infrastructure_rc=0
  local infra_marker marker_rc marker_failure_rc cleanup_rc raw_infra_rc
  local -a pipeline_status=()

  while IFS='|' read -r type label cmd; do
    [[ -z "$type" ]] && continue
    # Stream live instead of buffering the whole run in a `$(...)` capture:
    # a full-suite unit can legitimately take longer than the wrapper's
    # hang-detector threshold, and `out=$(... 2>&1)` produces zero output
    # until the command exits — indistinguishable from a real hang on the
    # log-mtime signal the detector watches. PIPESTATUS[0] preserves the
    # actual command's exit code (not the streaming sink's).
    echo "[TEST-GATE] unit=${label} type=${type} starting" >&2
    # Deprioritise: this can spawn several workerd-backed vitest workers at
    # 100%+ CPU each, run twice per commit-phase attempt (HEAD + baseline),
    # with up to MAX_CONCURRENT deliveries in parallel — background test
    # execution otherwise competes evenly with the operator's foreground work
    # for CPU scheduling. A direct /bin/sh child records this live worker's PID
    # through a collision-safe temporary file before renice runs; unlike $$,
    # that identity is rebound to this subshell and is available in Bash 3.2.
    # Every identity/file/scheduling failure stops the unit before its command.
    # macOS/Linux still grant idle CPU when nothing else needs it, so total
    # suite wall-clock is not meaningfully affected — only scheduling priority
    # under contention changes.
    local _tg_to_cmd
    _tg_to_cmd=$(declare -F _resolve_timeout_cmd >/dev/null 2>&1 && _resolve_timeout_cmd || true)
    unit_infra_rc=0
    exit_code=0
    infra_marker=""
    _TEST_GATE_INFRA_MARKER_PATH=""
    _test_gate_unit_infra_marker_create
    marker_rc=$?
    if [[ "$marker_rc" -ne 0 ]]; then
      [[ "$marker_rc" =~ ^[0-9]+$ && "$marker_rc" -gt 0 && "$marker_rc" -le 255 ]] \
        || marker_rc=1
      unit_infra_rc="$marker_rc"
      exit_code="$marker_rc"
      echo "[TEST-GATE] unit setup failed: infrastructure result channel" >&2
    else
      infra_marker="$_TEST_GATE_INFRA_MARKER_PATH"
      (_test_gate_prepare_worker_identity || exit $?
       renice -n 15 -p "$_TEST_GATE_WORKER_PID" >/dev/null 2>&1
       setup_rc=$?
       if [[ "$setup_rc" -ne 0 ]]; then
         _test_gate_worker_setup_failure "worker scheduling" "$setup_rc" ""
         exit $?
       fi
       cd "$worktree_path"
       setup_rc=$?
       if [[ "$setup_rc" -ne 0 ]]; then
         _test_gate_worker_setup_failure "unit working directory" "$setup_rc" ""
         exit $?
       fi
       _test_gate_worker_infra_write "ok"
       setup_rc=$?
       if [[ "$setup_rc" -ne 0 ]]; then
         _test_gate_worker_setup_failure "infrastructure result channel" "$setup_rc" ""
         exit $?
       fi
       if [[ -n "$_tg_to_cmd" ]]; then
         $_tg_to_cmd "${GAAI_TEST_UNIT_TIMEOUT_SEC:-2400}" bash -c "$cmd"
       else
         eval "$cmd"
       fi) 2>&1 | command cat >&2
      pipeline_status=("${PIPESTATUS[@]}")
      exit_code="${pipeline_status[0]}"
      sink_rc="${pipeline_status[1]}"
      marker_failure_rc="$exit_code"
      [[ "$marker_failure_rc" =~ ^[0-9]+$ && "$marker_failure_rc" -gt 0 \
            && "$marker_failure_rc" -le 255 ]] || marker_failure_rc=1

      if _test_gate_unit_infra_marker_read "$infra_marker"; then
        case "$_TEST_GATE_INFRA_MARKER_STATE" in
          ok) ;;
          infra:*)
            raw_infra_rc="${_TEST_GATE_INFRA_MARKER_STATE#infra:}"
            if [[ "$raw_infra_rc" =~ ^[0-9]+$ \
                  && "$raw_infra_rc" -gt 0 && "$raw_infra_rc" -le 255 ]]; then
              unit_infra_rc="$raw_infra_rc"
            else
              unit_infra_rc="$marker_failure_rc"
            fi
            ;;
          *) unit_infra_rc="$marker_failure_rc" ;;
        esac
      else
        unit_infra_rc="$marker_failure_rc"
      fi

      if [[ "$sink_rc" -ne 0 ]]; then
        echo "[TEST-GATE] unit setup failed: diagnostic streaming channel" >&2
        [[ "$unit_infra_rc" -ne 0 ]] || unit_infra_rc="$sink_rc"
      fi

      _test_gate_unit_infra_marker_cleanup "$infra_marker"
      cleanup_rc=$?
      if [[ "$cleanup_rc" -ne 0 ]]; then
        echo "[TEST-GATE] unit setup failed: infrastructure result channel cleanup" >&2
        [[ "$unit_infra_rc" -ne 0 ]] || unit_infra_rc="$cleanup_rc"
      fi
    fi

    effective_exit="$exit_code"
    [[ "$unit_infra_rc" -ne 0 ]] && effective_exit="$unit_infra_rc"
    echo "[TEST-GATE] unit=${label} type=${type} exit=${effective_exit}" >&2

    if [[ "$unit_infra_rc" -ne 0 ]]; then
      failed+=("$label")
      [[ "$infrastructure_rc" -ne 0 ]] || infrastructure_rc="$unit_infra_rc"
      continue
    fi

    case "$type" in
      bash|pm)
        [[ "$exit_code" -ne 0 ]] && failed+=("$label")
        ;;
      junit)
        local xml="${label}/test-results.xml"
        local parsed
        parsed=""
        if [[ -f "$xml" ]] && parsed=$(_test_gate_parse_junit_failures "$xml" "$label"); then
          if [[ -n "$parsed" ]]; then
            while IFS= read -r pl; do
              [[ -n "$pl" ]] && failed+=("$pl")
            done <<< "$parsed"
          elif [[ "$exit_code" -ne 0 ]]; then
            failed+=("$label")
          fi
        elif [[ "$exit_code" -ne 0 ]]; then
          failed+=("$label")
        fi
        ;;
    esac
  done <<< "$units"

  [[ "${#failed[@]}" -gt 0 ]] && printf '%s\n' "${failed[@]}"
  return "$infrastructure_rc"
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
  local head_fail_list="" head_run_rc=0
  head_fail_list=$(_test_gate_run_units "$worktree_path" "$units") \
    || head_run_rc=$?

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

  local base_fail_list="" base_run_rc=0
  base_fail_list=$(_test_gate_run_units "$worktree_path" "$units") \
    || base_run_rc=$?
  _test_gate_restore "$worktree_path" "$branch"

  # Infrastructure is authoritative before the differential failure lists.
  # An identical setup failure on HEAD and baseline must never cancel out into
  # PASS merely because the coarse labels compare equal.
  if [[ "$head_run_rc" -ne 0 || "$base_run_rc" -ne 0 ]]; then
    local infrastructure_reason="test infrastructure failed (HEAD exit ${head_run_rc}; baseline exit ${base_run_rc})"
    _test_gate_append_report "$qa_report_path" "ESCALATED" "$base_ref" "$base_sha" \
      "" "" "$infrastructure_reason"
    echo "[ERROR] ${story_id} test-gate: ${infrastructure_reason} [class=TEST_GATE_INFRASTRUCTURE_FAILED]"
    "$SCHEDULER" --set-phase-status "$story_id" failed "$BACKLOG_FILE" 2>/dev/null || true
    if declare -F notify_escalation_inline >/dev/null 2>&1; then
      notify_escalation_inline "$story_id" "test_gate_infrastructure_failed" \
        "$infrastructure_reason"
    fi
    return 1
  fi

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

  local output_file
  output_file=$(mktemp "${TMPDIR:-/tmp}/gaai-test-gate-api.XXXXXX") || return 125
  # Python is already a framework runtime dependency. It gives the command a
  # dedicated process group on both macOS and Linux, measures the complete
  # interval without integer timestamp truncation, and kills descendants too.
  # This matters for git transport helpers as well as the direct gh process.
  local command_rc=0
  python3 - "$timeout_sec" "$output_file" "$@" <<'PY' || command_rc=$?
import os
import signal
import subprocess
import sys

timeout = int(sys.argv[1])
output_path = sys.argv[2]
command = sys.argv[3:]
process = None

def stop_group():
    if process is None or process.poll() is not None:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            break

def interrupted(signum, _frame):
    stop_group()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGHUP, interrupted)

with open(output_path, "wb") as output:
    process = subprocess.Popen(
        command,
        stdout=output,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        return_code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop_group()
        process.wait()
        raise SystemExit(124)

raise SystemExit(return_code if return_code >= 0 else 128 - return_code)
PY
  [[ -s "$output_file" ]] && command cat "$output_file"
  rm -f "$output_file"
  return "$command_rc"
}

# ── Hosted merge authority ──────────────────────────────────────────────────

_TEST_GATE_POLICY_PATH_DEFAULT=".gaai/project/ci/premerge-authority.json"

# Every executable entry point or sourced library that can select, replace, or
# invoke the hosted-authority controller and exact-head merge path must be held
# inside the trust surface. Keeping the closure in the generic controller makes
# an incomplete project policy fail closed instead of relying on review alone.
_test_gate_required_controller_paths() {
  printf '%s\n' \
    ".gaai/core/scripts/backlog-scheduler.sh" \
    ".gaai/core/scripts/daemon-start.sh" \
    ".gaai/core/scripts/delivery-daemon.sh" \
    ".gaai/core/scripts/daemon-dispatch.sh" \
    ".gaai/core/scripts/lib/backlog-journal.sh" \
    ".gaai/core/scripts/lib/backlog-yaml.sh" \
    ".gaai/core/scripts/lib/chore-commit.sh" \
    ".gaai/core/scripts/lib/commit-retry-containment.sh" \
    ".gaai/core/scripts/lib/daemon-home.sh" \
    ".gaai/core/scripts/lib/home-branch-guard.sh" \
    ".gaai/core/scripts/lib/stuck-classifier.sh" \
    ".gaai/core/scripts/lib/worktree-integrity.sh" \
    ".gaai/core/scripts/lib/test-gate.sh" \
    ".gaai/core/scripts/lib/delivery-routing.sh" \
    ".gaai/core/scripts/lib/yaml-runtime.sh" \
    ".gaai/core/vendor/pyyaml/6.0.3/pyyaml-runtime.pyz" \
    ".gaai/core/vendor/pyyaml/6.0.3/PROVENANCE.json"
}

# Project identity stays in the base-held project policy. The generic
# controller accepts only a small closed schema and literal safe paths.
_test_gate_policy_validate() {
  local policy_path="$1"
  local policy_rel="${2:-${GAAI_PREMERGE_AUTHORITY_POLICY_PATH:-$_TEST_GATE_POLICY_PATH_DEFAULT}}"
  [[ -s "$policy_path" ]] || return 1
  local policy required_path
  policy=$(jq -ce --arg policy_rel "$policy_rel" '
    def keys_are($wanted): (keys | sort) == ($wanted | sort);
    def safe_path:
      type == "string" and length > 0 and (startswith("/")|not)
      and (contains("\u0000")|not) and (contains("\n")|not)
      and (contains("*")|not) and (contains("?")|not)
      and (contains("[")|not) and (contains("]")|not)
      and (contains("\\")|not)
      and (split("/") | all(. != "" and . != "." and . != ".."))
      and (startswith(":")|not);
    . as $policy |
    (type == "object"
    and keys_are(["schema_version","repository","workflow","required_job","covered_paths"])
    and .schema_version == "1.0.0"
    and (.repository | type == "object"
      and keys_are(["id","full_name","base_ref"])
      and (.id | type == "number" and . > 0 and floor == .)
      and (.full_name | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))
      and (.base_ref | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._/-]*$")
        and (contains("..")|not)))
    and (.workflow | type == "object"
      and keys_are(["id","path","name","event"])
      and (.id | type == "number" and . > 0 and floor == .)
      and (.path | safe_path)
      and (.name | type == "string" and length > 0)
      and .event == "pull_request")
    and (.required_job | type == "string" and length > 0)
    and (.covered_paths | type == "array" and length > 0
      and length == (unique | length) and all(safe_path))
    and ($policy_rel | safe_path)
    and (.covered_paths | index($policy_rel) != null)
    and (.workflow.path as $workflow_path
      | .covered_paths | index($workflow_path) != null)) as $valid
    | select($valid) | $policy
  ' "$policy_path" 2>/dev/null) || return 1
  while IFS= read -r required_path; do
    jq -e --arg path "$required_path" \
      '.covered_paths | index($path) != null' >/dev/null 2>&1 <<<"$policy" \
      || return 1
  done < <(_test_gate_required_controller_paths)
  printf '%s\n' "$policy"
}

_test_gate_gh_json() {
  local timeout_sec="$1"
  shift
  local output rc=0
  output=$(_test_gate_run_with_timeout "$timeout_sec" gh api --method GET "$@") || rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  jq -e . >/dev/null 2>&1 <<<"$output" || return 1
  printf '%s\n' "$output"
}

# Fetch every REST page and flatten an endpoint whose response is an array.
# `--slurp` preserves page boundaries so malformed or non-array pages fail
# closed instead of being silently concatenated by the CLI.
_test_gate_gh_paginated_array() {
  local timeout_sec="$1"
  shift
  local output rc=0
  output=$(_test_gate_run_with_timeout "$timeout_sec" \
    gh api --method GET --paginate --slurp "$@") || rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  jq -ce 'if type == "array" and all(type == "array") then add else error("invalid pages") end' \
    <<<"$output" 2>/dev/null
}

# Fetch every REST page and flatten one array member from each response object
# (for example `workflow_runs` or `jobs`).
_test_gate_gh_paginated_items() {
  local timeout_sec="$1" item_key="$2"
  shift 2
  local output rc=0
  output=$(_test_gate_run_with_timeout "$timeout_sec" \
    gh api --method GET --paginate --slurp "$@") || rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  jq -ce --arg key "$item_key" '
    if type == "array"
       and length > 0
       and all(type == "object" and (.[$key] | type == "array"))
       and (.[0].total_count | type == "number")
       and ([ .[][$key][] ] | length) == .[0].total_count
    then [ .[][$key][] ]
    else error("invalid pages")
    end
  ' <<<"$output" 2>/dev/null
}

_test_gate_fetch_base_policy() {
  local worktree_path="$1" base_sha="$2" timeout_sec="$3"
  local story_id="${4:-unknown}"
  local policy_rel="${GAAI_PREMERGE_AUTHORITY_POLICY_PATH:-$_TEST_GATE_POLICY_PATH_DEFAULT}"
  [[ "$base_sha" =~ ^[0-9a-fA-F]{40}$ ]] || return 1
  if ! git -C "$worktree_path" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
    _test_gate_run_with_timeout "$timeout_sec" \
      git -C "$worktree_path" fetch origin "$base_sha" --quiet >/dev/null 2>&1 || {
        echo "[TEST-GATE-CI] ${story_id}: base policy fetch failed for base commit" >&2
        return 1
      }
  fi
  local temp_policy
  temp_policy=$(mktemp "${TMPDIR:-/tmp}/gaai-premerge-authority.XXXXXX") || return 1
  if ! git -C "$worktree_path" show "${base_sha}:${policy_rel}" >"$temp_policy" 2>/dev/null; then
    echo "[TEST-GATE-CI] ${story_id}: base policy is absent at the live base commit" >&2
    rm -f "$temp_policy"
    return 1
  fi
  local policy
  policy=$(_test_gate_policy_validate "$temp_policy" "$policy_rel") || {
    echo "[TEST-GATE-CI] ${story_id}: base policy schema or controller closure is invalid" >&2
    rm -f "$temp_policy"
    return 1
  }
  rm -f "$temp_policy"
  printf '%s\n' "$policy"
}

_test_gate_conclusion_outcome() {
  local subject="$1" conclusion="$2"
  case "$conclusion" in
    success) printf '%s\n' "${subject}_success" ;;
    failure|action_required|stale|startup_failure) printf '%s\n' "blocked:${subject}_failed" ;;
    skipped) printf '%s\n' "blocked:${subject}_skipped" ;;
    neutral) printf '%s\n' "blocked:${subject}_neutral" ;;
    cancelled) printf '%s\n' "blocked:${subject}_cancelled" ;;
    timed_out) printf '%s\n' "blocked:${subject}_timed_out" ;;
    *) printf '%s\n' "blocked:github_unavailable" ;;
  esac
}

# Observe and bind the unique greatest run/attempt and required job. The run
# list is fetched again after the job read so a rerun or newer run that
# materializes during observation supersedes the earlier success.
_test_gate_observe_run_authority() {
  local api_timeout_sec="$1" workflow_id="$2" expected_event="$3"
  local expected_head_sha="$4" expected_head_ref="$5" repository_id="$6"
  local repository_name="$7" pr_number="$8" base_sha="$9" required_job="${10}"
  local runs refreshed_runs run_count latest_tuple latest_count run run_id run_number run_attempt
  local run_detail detail_number detail_attempt run_status run_conclusion conclusion_outcome
  local jobs authority_jobs authority_count authority_job job_id job_status job_conclusion
  local refreshed_tuple refreshed_number refreshed_attempt refreshed_count refreshed_id
  local runs_endpoint="repos/{owner}/{repo}/actions/workflows/${workflow_id}/runs?event=${expected_event}&head_sha=${expected_head_sha}&exclude_pull_requests=false&per_page=100"

  runs=$(_test_gate_gh_paginated_items "$api_timeout_sec" workflow_runs "$runs_endpoint") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '
    type == "array" and all(
      (.id|numbers) and (.run_number|numbers) and (.run_attempt|numbers)
      and (.status|strings) and (.event|strings) and (.workflow_id|numbers)
      and (.head_sha|strings) and (.head_branch|strings)
      and (.head_repository.id|numbers) and (.head_repository.full_name|strings))
  ' >/dev/null 2>&1 <<<"$runs" || { echo "blocked:github_unavailable"; return 0; }
  run_count=$(jq 'length' <<<"$runs")
  [[ "$run_count" -gt 0 ]] || { echo "blocked:run_missing"; return 0; }
  latest_tuple=$(jq -r 'map([.run_number,.run_attempt]) | max | @tsv' <<<"$runs")
  IFS=$'\t' read -r run_number run_attempt <<<"$latest_tuple"
  latest_count=$(jq --argjson n "$run_number" --argjson a "$run_attempt" \
    '[.[] | select(.run_number==$n and .run_attempt==$a)] | length' <<<"$runs")
  [[ "$latest_count" -eq 1 ]] || { echo "blocked:run_ambiguous"; return 0; }
  run=$(jq -c --argjson n "$run_number" --argjson a "$run_attempt" \
    '.[] | select(.run_number==$n and .run_attempt==$a)' <<<"$runs")
  run_id=$(jq -r '.id' <<<"$run")

  run_detail=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/actions/runs/${run_id}") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '
    (.id|numbers) and (.run_number|numbers) and (.run_attempt|numbers)
    and (.status|strings) and (.event|strings) and (.workflow_id|numbers)
    and (.head_sha|strings) and (.head_branch|strings)
    and (.head_repository.id|numbers) and (.head_repository.full_name|strings)
    and (.pull_requests|type=="array")
    and (.pull_requests | all(
      (.number|numbers) and (.head.sha|strings) and (.base.sha|strings)))
  ' >/dev/null 2>&1 <<<"$run_detail" \
    || { echo "blocked:github_unavailable"; return 0; }
  detail_number=$(jq -r '.run_number // empty' <<<"$run_detail")
  detail_attempt=$(jq -r '.run_attempt // empty' <<<"$run_detail")
  [[ "$detail_number" =~ ^[0-9]+$ && "$detail_attempt" =~ ^[0-9]+$ ]] \
    || { echo "blocked:github_unavailable"; return 0; }
  if (( detail_number > run_number || (detail_number == run_number && detail_attempt > run_attempt) )); then
    echo "blocked:run_superseded"; return 0
  fi
  [[ "$detail_number" -eq "$run_number" && "$detail_attempt" -eq "$run_attempt" \
      && "$(jq -r '.id' <<<"$run_detail")" == "$run_id" ]] \
    || { echo "blocked:run_ambiguous"; return 0; }
  run="$run_detail"

  [[ "$(jq -r '.workflow_id' <<<"$run")" == "$workflow_id" ]] \
    || { echo "blocked:workflow_mismatch"; return 0; }
  [[ "$(jq -r '.event' <<<"$run")" == "$expected_event" ]] \
    || { echo "blocked:event_mismatch"; return 0; }
  if [[ "$(jq -r '.head_sha' <<<"$run")" != "$expected_head_sha" \
        || "$(jq -r '.head_branch' <<<"$run")" != "$expected_head_ref" \
        || "$(jq -r '.head_repository.id' <<<"$run")" != "$repository_id" \
        || "$(jq -r '.head_repository.full_name' <<<"$run")" != "$repository_name" ]]; then
    echo "blocked:pr_tuple_mismatch"; return 0
  fi
  [[ "$(jq '.pull_requests | length' <<<"$run")" -eq 1 ]] \
    && jq -e --argjson number "$pr_number" --arg head "$expected_head_sha" \
      --arg base "$base_sha" '
        .pull_requests[0].number==$number
        and .pull_requests[0].head.sha==$head
        and .pull_requests[0].base.sha==$base
      ' >/dev/null 2>&1 <<<"$run" \
    || { echo "blocked:pr_tuple_mismatch"; return 0; }

  run_status=$(jq -r '.status' <<<"$run")
  case "$run_status" in
    queued|requested|waiting|pending|in_progress) echo "blocked:run_pending"; return 0 ;;
    completed) ;;
    *) echo "blocked:github_unavailable"; return 0 ;;
  esac
  run_conclusion=$(jq -r '.conclusion // empty' <<<"$run")
  conclusion_outcome=$(_test_gate_conclusion_outcome run "$run_conclusion")
  [[ "$conclusion_outcome" == "run_success" ]] \
    || { echo "$conclusion_outcome"; return 0; }

  jobs=$(_test_gate_gh_paginated_items "$api_timeout_sec" jobs \
    "repos/{owner}/{repo}/actions/runs/${run_id}/attempts/${run_attempt}/jobs?filter=all&per_page=100") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e 'type == "array" and all((.id|numbers) and (.name|strings) and (.status|strings))' \
    >/dev/null 2>&1 <<<"$jobs" || { echo "blocked:github_unavailable"; return 0; }
  authority_jobs=$(jq -c --arg name "$required_job" '[.[] | select(.name==$name)]' <<<"$jobs")
  authority_count=$(jq 'length' <<<"$authority_jobs")
  [[ "$authority_count" -gt 0 ]] || { echo "blocked:authority_job_missing"; return 0; }
  [[ "$authority_count" -eq 1 ]] || { echo "blocked:authority_job_ambiguous"; return 0; }
  authority_job=$(jq -c '.[0]' <<<"$authority_jobs")
  job_id=$(jq -r '.id' <<<"$authority_job")
  job_status=$(jq -r '.status' <<<"$authority_job")
  [[ "$job_status" == "completed" ]] \
    || { echo "blocked:authority_job_pending"; return 0; }
  job_conclusion=$(jq -r '.conclusion // empty' <<<"$authority_job")
  conclusion_outcome=$(_test_gate_conclusion_outcome authority_job "$job_conclusion")
  [[ "$conclusion_outcome" == "authority_job_success" ]] \
    || { echo "$conclusion_outcome"; return 0; }

  refreshed_runs=$(_test_gate_gh_paginated_items "$api_timeout_sec" workflow_runs "$runs_endpoint") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '
    type == "array" and all(
      (.id|numbers) and (.run_number|numbers) and (.run_attempt|numbers)
      and (.status|strings) and (.event|strings) and (.workflow_id|numbers)
      and (.head_sha|strings) and (.head_branch|strings)
      and (.head_repository.id|numbers) and (.head_repository.full_name|strings))
  ' >/dev/null 2>&1 <<<"$refreshed_runs" \
    || { echo "blocked:github_unavailable"; return 0; }
  [[ "$(jq 'length' <<<"$refreshed_runs")" -gt 0 ]] \
    || { echo "blocked:run_missing"; return 0; }
  refreshed_tuple=$(jq -r 'map([.run_number,.run_attempt]) | max | @tsv' <<<"$refreshed_runs")
  IFS=$'\t' read -r refreshed_number refreshed_attempt <<<"$refreshed_tuple"
  refreshed_count=$(jq --argjson n "$refreshed_number" --argjson a "$refreshed_attempt" \
    '[.[] | select(.run_number==$n and .run_attempt==$a)] | length' <<<"$refreshed_runs")
  [[ "$refreshed_count" -eq 1 ]] || { echo "blocked:run_ambiguous"; return 0; }
  refreshed_id=$(jq -r --argjson n "$refreshed_number" --argjson a "$refreshed_attempt" \
    '.[] | select(.run_number==$n and .run_attempt==$a) | .id' <<<"$refreshed_runs")
  [[ "$refreshed_number" -eq "$run_number" && "$refreshed_attempt" -eq "$run_attempt" \
      && "$refreshed_id" == "$run_id" ]] \
    || { echo "blocked:run_superseded"; return 0; }

  printf 'hosted_pass\t%s\t%s\t%s\t%s\t%s\n' \
    "$workflow_id" "$run_id" "$run_number" "$run_attempt" "$job_id"
}

# One current REST snapshot. Stdout is exactly one stable outcome, optionally
# followed by hosted-pass bindings separated by tabs. No local test function is
# called from this authority path.
_test_gate_observe_authority_once() {
  local story_id="$1" worktree_path="$2" expected_head_sha="$3" api_timeout_sec="$4"
  [[ "$expected_head_sha" =~ ^[0-9a-fA-F]{40}$ ]] \
    || { echo "blocked:github_unavailable"; return 0; }

  local repository pulls pull_count pr_number pr live_ref base_ref base_sha live_base_sha
  repository=$(_test_gate_gh_json "$api_timeout_sec" "repos/{owner}/{repo}") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '.id|numbers' >/dev/null 2>&1 <<<"$repository" \
    && jq -e '.full_name|strings' >/dev/null 2>&1 <<<"$repository" \
    || { echo "blocked:github_unavailable"; return 0; }

  pulls=$(_test_gate_gh_paginated_array "$api_timeout_sec" \
    "repos/{owner}/{repo}/commits/${expected_head_sha}/pulls?per_page=100") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e 'type=="array" and all((.number|numbers) and (.state|strings))' \
    >/dev/null 2>&1 <<<"$pulls" \
    || { echo "blocked:github_unavailable"; return 0; }
  pull_count=$(jq 'length' <<<"$pulls")
  [[ "$pull_count" -gt 0 ]] || { echo "blocked:pr_missing"; return 0; }
  local open_pulls open_pull_count
  open_pulls=$(jq -c '[.[] | select(.state == "open")]' <<<"$pulls")
  open_pull_count=$(jq 'length' <<<"$open_pulls")
  [[ "$open_pull_count" -gt 0 ]] || { echo "blocked:pr_closed"; return 0; }
  [[ "$open_pull_count" -eq 1 ]] || { echo "blocked:pr_ambiguous"; return 0; }
  pr_number=$(jq -r '.[0].number // empty' <<<"$open_pulls")
  [[ "$pr_number" =~ ^[0-9]+$ ]] || { echo "blocked:github_unavailable"; return 0; }

  pr=$(_test_gate_gh_json "$api_timeout_sec" "repos/{owner}/{repo}/pulls/${pr_number}") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '
    (.number|type)=="number" and (.state|type)=="string" and (.draft|type)=="boolean"
    and ((.mergeable == null) or ((.mergeable|type)=="boolean"))
    and (.head.ref|type)=="string" and (.head.sha|type)=="string" and (.head.repo.id|type)=="number"
    and (.head.repo.full_name|type)=="string" and (.base.ref|type)=="string" and (.base.sha|type)=="string"
    and (.base.repo.id|type)=="number" and (.base.repo.full_name|type)=="string"
  ' >/dev/null 2>&1 <<<"$pr" || { echo "blocked:github_unavailable"; return 0; }

  [[ "$(jq -r '.state' <<<"$pr")" == "open" ]] \
    || { echo "blocked:pr_closed"; return 0; }
  [[ "$(jq -r '.draft' <<<"$pr")" == "false" ]] \
    || { echo "blocked:pr_draft"; return 0; }

  base_ref=$(jq -r '.base.ref' <<<"$pr")
  base_sha=$(jq -r '.base.sha' <<<"$pr")
  [[ "$base_sha" =~ ^[0-9a-fA-F]{40}$ ]] \
    || { echo "blocked:github_unavailable"; return 0; }
  local policy
  policy=$(_test_gate_fetch_base_policy "$worktree_path" "$base_sha" "$api_timeout_sec" "$story_id") \
    || { echo "blocked:github_unavailable"; return 0; }

  local repository_id repository_name policy_repository_id policy_repository_name policy_base_ref
  repository_id=$(jq -r '.id' <<<"$repository")
  repository_name=$(jq -r '.full_name' <<<"$repository")
  policy_repository_id=$(jq -r '.repository.id' <<<"$policy")
  policy_repository_name=$(jq -r '.repository.full_name' <<<"$policy")
  policy_base_ref=$(jq -r '.repository.base_ref' <<<"$policy")
  if [[ "$repository_id" != "$policy_repository_id" \
        || "$repository_name" != "$policy_repository_name" \
        || "$(jq -r '.head.repo.id' <<<"$pr")" != "$repository_id" \
        || "$(jq -r '.base.repo.id' <<<"$pr")" != "$repository_id" \
        || "$(jq -r '.head.repo.full_name' <<<"$pr")" != "$repository_name" \
        || "$(jq -r '.base.repo.full_name' <<<"$pr")" != "$repository_name" ]]; then
    echo "blocked:repository_mismatch"; return 0
  fi
  [[ "$base_ref" == "$policy_base_ref" ]] \
    || { echo "blocked:policy_base_ref_mismatch"; return 0; }
  live_ref=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/git/ref/heads/${policy_base_ref}") \
    || { echo "blocked:github_unavailable"; return 0; }
  jq -e '(.object.sha|type)=="string"' >/dev/null 2>&1 <<<"$live_ref" \
    || { echo "blocked:github_unavailable"; return 0; }
  live_base_sha=$(jq -r '.object.sha // empty' <<<"$live_ref")
  [[ "$live_base_sha" =~ ^[0-9a-fA-F]{40}$ ]] \
    || { echo "blocked:github_unavailable"; return 0; }
  [[ "$(jq -r '.head.sha' <<<"$pr")" == "$expected_head_sha" ]] \
    || { echo "blocked:head_changed"; return 0; }
  [[ "$live_base_sha" == "$base_sha" ]] \
    || { echo "blocked:stale_base"; return 0; }
  # The controller computes the base-to-candidate diff itself. A covered
  # addition, deletion, rename, mode or content change is human-only.
  git -C "$worktree_path" cat-file -e "${base_sha}^{commit}" 2>/dev/null \
    && git -C "$worktree_path" cat-file -e "${expected_head_sha}^{commit}" 2>/dev/null \
    || { echo "blocked:github_unavailable"; return 0; }
  local -a covered_paths=()
  local covered_path covered_count
  covered_count=$(jq '.covered_paths | length' <<<"$policy")
  while IFS= read -r covered_path; do
    covered_paths[${#covered_paths[@]}]="$covered_path"
  done <<<"$(jq -r '.covered_paths[]' <<<"$policy")"
  [[ "${#covered_paths[@]}" -eq "$covered_count" ]] \
    || { echo "blocked:github_unavailable"; return 0; }
  git -C "$worktree_path" diff --no-ext-diff --no-textconv --quiet \
    "$base_sha" "$expected_head_sha" -- "${covered_paths[@]}"
  local diff_rc=$?
  [[ "$diff_rc" -eq 0 ]] || {
    if [[ "$diff_rc" -eq 1 ]]; then
      for covered_path in "${covered_paths[@]}"; do
        if ! git -C "$worktree_path" diff --no-ext-diff --no-textconv --quiet \
            "$base_sha" "$expected_head_sha" -- "$covered_path"; then
          echo "[TEST-GATE-CI] ${story_id}: protected path changed: ${covered_path}" >&2
        fi
      done
      echo "human_required:trust_surface_changed"
    else
      echo "blocked:github_unavailable"
    fi
    return 0
  }

  # GitHub reports false when the PR is definitively unmergeable and null
  # while mergeability is still being computed. The former is terminal; the
  # latter remains pollable within the configured hosted-authority budget.
  local mergeable_state
  mergeable_state=$(jq -r '
    if .mergeable == true then "true"
    elif .mergeable == false then "false"
    else "null"
    end
  ' <<<"$pr")
  case "$mergeable_state" in
    true) ;;
    false) printf 'blocked:pr_not_merge_ready\tterminal\n'; return 0 ;;
    *) printf 'blocked:pr_not_merge_ready\tpending\n'; return 0 ;;
  esac

  local workflow workflow_id
  workflow_id=$(jq -r '.workflow.id' <<<"$policy")
  workflow=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/actions/workflows/${workflow_id}") \
    || { echo "blocked:github_unavailable"; return 0; }
  if ! jq -e --argjson id "$workflow_id" \
      --arg path "$(jq -r '.workflow.path' <<<"$policy")" \
      --arg name "$(jq -r '.workflow.name' <<<"$policy")" '
        .id==$id and .path==$path and .name==$name and .state=="active"
      ' >/dev/null 2>&1 <<<"$workflow"; then
    echo "blocked:workflow_mismatch"; return 0
  fi

  local run_observation run_outcome
  run_observation=$(_test_gate_observe_run_authority "$api_timeout_sec" "$workflow_id" \
    "$(jq -r '.workflow.event' <<<"$policy")" "$expected_head_sha" \
    "$(jq -r '.head.ref' <<<"$pr")" "$repository_id" "$repository_name" \
    "$pr_number" "$base_sha" "$(jq -r '.required_job' <<<"$policy")")
  run_outcome="${run_observation%%$'\t'*}"
  [[ "$run_outcome" == "hosted_pass" ]] || { printf '%s\n' "$run_observation"; return 0; }

  printf 'hosted_pass\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$pr_number" "$repository_id" "$repository_name" "$base_ref" "$base_sha" \
    "$(jq -r '.head.ref' <<<"$pr")" "$expected_head_sha" "${run_observation#*$'\t'}"
}

_test_gate_poll_hosted_authority() {
  local story_id="$1" worktree_path="$2" expected_head_sha="$3"
  local timeout_sec materialize_sec poll_interval api_timeout_sec api_retries
  timeout_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_TIMEOUT_SEC:-2700}" 2700 GAAI_CI_TEST_GATE_TIMEOUT_SEC)
  materialize_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_MATERIALIZE_SEC:-300}" 300 GAAI_CI_TEST_GATE_MATERIALIZE_SEC)
  poll_interval=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC:-20}" 20 GAAI_CI_TEST_GATE_POLL_INTERVAL_SEC)
  api_timeout_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_API_TIMEOUT_SEC:-30}" 30 GAAI_CI_TEST_GATE_API_TIMEOUT_SEC)
  api_retries=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_API_RETRIES:-3}" 3 GAAI_CI_TEST_GATE_API_RETRIES)

  local started_at deadline materialize_deadline now observation outcome readiness sleep_for github_error_streak=0
  started_at=$(date +%s)
  deadline=$(( started_at + timeout_sec ))
  materialize_deadline=$(( started_at + materialize_sec ))
  observation="blocked:github_unavailable"
  while :; do
    observation=$(_test_gate_observe_authority_once "$story_id" "$worktree_path" \
      "$expected_head_sha" "$api_timeout_sec")
    outcome="${observation%%$'\t'*}"
    readiness=""
    IFS=$'\t' read -r _ readiness _ <<<"$observation"
    case "$outcome" in
      hosted_pass|human_required:*|blocked:pr_closed|blocked:pr_draft|blocked:repository_mismatch|blocked:workflow_mismatch|blocked:event_mismatch|blocked:policy_base_ref_mismatch|blocked:pr_tuple_mismatch|blocked:head_changed|blocked:stale_base|blocked:run_ambiguous|blocked:run_superseded|blocked:run_failed|blocked:run_skipped|blocked:run_neutral|blocked:run_cancelled|blocked:run_timed_out|blocked:authority_job_missing|blocked:authority_job_ambiguous|blocked:authority_job_failed|blocked:authority_job_skipped|blocked:authority_job_neutral|blocked:authority_job_cancelled|blocked:authority_job_timed_out)
        printf '%s\n' "$observation"; return 0 ;;
      blocked:github_unavailable)
        github_error_streak=$(( github_error_streak + 1 ))
        [[ "$github_error_streak" -ge "$api_retries" ]] && { echo "$outcome"; return 0; }
        ;;
      blocked:pr_not_merge_ready)
        [[ "$readiness" == "terminal" ]] && { echo "$outcome"; return 0; }
        github_error_streak=0
        ;;
      *) github_error_streak=0 ;;
    esac

    now=$(date +%s)
    if [[ "$outcome" == "blocked:run_missing" && "$now" -ge "$materialize_deadline" ]]; then
      echo "$outcome"; return 0
    fi
    (( now >= deadline )) && { printf '%s\n' "$outcome"; return 0; }
    sleep_for="$poll_interval"
    (( sleep_for > deadline - now )) && sleep_for=$(( deadline - now ))
    if [[ "$outcome" == "blocked:run_missing" && "$materialize_deadline" -gt "$now" \
          && "$sleep_for" -gt $(( materialize_deadline - now )) ]]; then
      sleep_for=$(( materialize_deadline - now ))
    fi
    echo "[TEST-GATE-CI] ${story_id}: ${outcome}; waiting on current hosted authority (elapsed=$(( now - started_at ))s/${timeout_sec}s)" >&2
    sleep "$sleep_for"
  done
}

# Final live tuple check used while the daemon's merge-mutation lock is held.
_test_gate_recheck_pr_tuple() {
  local expected_pr_number="$1" expected_repository_id="$2" expected_repository_name="$3"
  local expected_base_ref="$4" expected_base_sha="$5" expected_head_ref="$6" expected_head_sha="$7"
  local expected_workflow_id="${8:-}" expected_run_id="${9:-}" expected_run_number="${10:-}"
  local expected_run_attempt="${11:-}" expected_job_id="${12:-}"
  local api_timeout_sec
  api_timeout_sec=$(_test_gate_positive_int "${GAAI_CI_TEST_GATE_API_TIMEOUT_SEC:-30}" 30 GAAI_CI_TEST_GATE_API_TIMEOUT_SEC)
  local repository pr live_ref
  repository=$(_test_gate_gh_json "$api_timeout_sec" "repos/{owner}/{repo}") \
    || { echo "blocked:github_unavailable"; return 1; }
  jq -e '(.id|numbers) and (.full_name|strings)' >/dev/null 2>&1 <<<"$repository" \
    || { echo "blocked:github_unavailable"; return 1; }
  [[ "$(jq -r '.id // empty' <<<"$repository")" == "$expected_repository_id" \
      && "$(jq -r '.full_name // empty' <<<"$repository")" == "$expected_repository_name" ]] \
    || { echo "blocked:repository_mismatch"; return 1; }
  pr=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/pulls/${expected_pr_number}") \
    || { echo "blocked:github_unavailable"; return 1; }
  jq -e '
    (.number|numbers) and (.state|strings) and (.draft|type=="boolean")
    and ((.mergeable == null) or ((.mergeable|type)=="boolean"))
    and (.head.ref|strings) and (.head.sha|strings)
    and (.head.repo.id|numbers) and (.head.repo.full_name|strings)
    and (.base.ref|strings) and (.base.sha|strings)
    and (.base.repo.id|numbers) and (.base.repo.full_name|strings)
  ' >/dev/null 2>&1 <<<"$pr" \
    || { echo "blocked:github_unavailable"; return 1; }
  [[ "$(jq -r '.number // empty' <<<"$pr")" == "$expected_pr_number" ]] \
    || { echo "blocked:pr_tuple_mismatch"; return 1; }
  [[ "$(jq -r '.state // empty' <<<"$pr")" == "open" ]] \
    || { echo "blocked:pr_closed"; return 1; }
  [[ "$(jq -r 'if .draft == false then "false" else "true" end' <<<"$pr")" == "false" ]] \
    || { echo "blocked:pr_draft"; return 1; }
  [[ "$(jq -r '.head.repo.id // empty' <<<"$pr")" == "$expected_repository_id" \
      && "$(jq -r '.base.repo.id // empty' <<<"$pr")" == "$expected_repository_id" \
      && "$(jq -r '.head.repo.full_name // empty' <<<"$pr")" == "$expected_repository_name" \
      && "$(jq -r '.base.repo.full_name // empty' <<<"$pr")" == "$expected_repository_name" ]] \
    || { echo "blocked:repository_mismatch"; return 1; }
  [[ "$(jq -r '.head.ref // empty' <<<"$pr")" == "$expected_head_ref" \
      && "$(jq -r '.head.sha // empty' <<<"$pr")" == "$expected_head_sha" ]] \
    || { echo "blocked:head_changed"; return 1; }
  [[ "$(jq -r '.base.ref // empty' <<<"$pr")" == "$expected_base_ref" \
      && "$(jq -r '.base.sha // empty' <<<"$pr")" == "$expected_base_sha" ]] \
    || { echo "blocked:stale_base"; return 1; }
  live_ref=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/git/ref/heads/${expected_base_ref}") \
    || { echo "blocked:github_unavailable"; return 1; }
  jq -e '(.object.sha|strings)' >/dev/null 2>&1 <<<"$live_ref" \
    || { echo "blocked:github_unavailable"; return 1; }
  [[ "$(jq -r '.object.sha // empty' <<<"$live_ref")" == "$expected_base_sha" ]] \
    || { echo "blocked:stale_base"; return 1; }
  case "$(jq -r 'if .mergeable == true then "true" elif .mergeable == false then "false" else "null" end' <<<"$pr")" in
    true) ;;
    false) printf 'blocked:pr_not_merge_ready\tterminal\n'; return 1 ;;
    *) printf 'blocked:pr_not_merge_ready\tpending\n'; return 1 ;;
  esac

  [[ "$expected_workflow_id" =~ ^[0-9]+$ && "$expected_run_id" =~ ^[0-9]+$ \
      && "$expected_run_number" =~ ^[0-9]+$ && "$expected_run_attempt" =~ ^[0-9]+$ \
      && "$expected_job_id" =~ ^[0-9]+$ ]] \
    || { echo "blocked:github_unavailable"; return 1; }
  local policy workflow run_observation run_outcome observed_workflow_id observed_run_id
  local observed_run_number observed_run_attempt observed_job_id
  policy=$(_test_gate_fetch_base_policy \
    "${TEST_GATE_AUTH_WORKTREE_PATH:-${PROJECT_DIR:-.}}" "$expected_base_sha" \
    "$api_timeout_sec" final-recheck) \
    || { echo "blocked:github_unavailable"; return 1; }
  [[ "$(jq -r '.repository.id' <<<"$policy")" == "$expected_repository_id" \
      && "$(jq -r '.repository.full_name' <<<"$policy")" == "$expected_repository_name" \
      && "$(jq -r '.repository.base_ref' <<<"$policy")" == "$expected_base_ref" \
      && "$(jq -r '.workflow.id' <<<"$policy")" == "$expected_workflow_id" ]] \
    || { echo "blocked:workflow_mismatch"; return 1; }
  workflow=$(_test_gate_gh_json "$api_timeout_sec" \
    "repos/{owner}/{repo}/actions/workflows/${expected_workflow_id}") \
    || { echo "blocked:github_unavailable"; return 1; }
  jq -e --argjson id "$expected_workflow_id" \
      --arg path "$(jq -r '.workflow.path' <<<"$policy")" \
      --arg name "$(jq -r '.workflow.name' <<<"$policy")" '
        .id==$id and .path==$path and .name==$name and .state=="active"
      ' >/dev/null 2>&1 <<<"$workflow" \
    || { echo "blocked:workflow_mismatch"; return 1; }
  run_observation=$(_test_gate_observe_run_authority "$api_timeout_sec" \
    "$expected_workflow_id" "$(jq -r '.workflow.event' <<<"$policy")" \
    "$expected_head_sha" "$expected_head_ref" "$expected_repository_id" \
    "$expected_repository_name" "$expected_pr_number" "$expected_base_sha" \
    "$(jq -r '.required_job' <<<"$policy")")
  IFS=$'\t' read -r run_outcome observed_workflow_id observed_run_id \
    observed_run_number observed_run_attempt observed_job_id <<<"$run_observation"
  [[ "$run_outcome" == "hosted_pass" ]] \
    || { printf '%s\n' "$run_observation"; return 1; }
  [[ "$observed_workflow_id" == "$expected_workflow_id" \
      && "$observed_run_id" == "$expected_run_id" \
      && "$observed_run_number" == "$expected_run_number" \
      && "$observed_run_attempt" == "$expected_run_attempt" \
      && "$observed_job_id" == "$expected_job_id" ]] \
    || { echo "blocked:run_superseded"; return 1; }
  echo "hosted_pass"
  return 0
}

# ── Deterministic (non-retryable) block classification ──────────────────────
# A blocked outcome is deterministic when re-observing the same candidate can
# never change it: the base-held policy and the live GitHub identity disagree on
# repository, workflow, event or target base ref. Re-running the commit phase re-pushes
# the candidate and buys another full hosted run for an outcome that is already
# decided, so the caller must stall these for an operator instead of retrying.
#
# Every other blocked outcome stays retryable, deliberately:
#   - github_unavailable / run_missing are transient by definition;
#   - head_changed / stale_base are resolved by the next observation;
#   - pr_closed / pr_draft leave the heavy lanes unexecuted, so a retry is cheap;
#   - run_* carry a real hosted verdict and keep the existing lifecycle.
_test_gate_outcome_is_deterministic() {
  case "${1:-}" in
    blocked:repository_mismatch|blocked:workflow_mismatch|blocked:event_mismatch|blocked:policy_base_ref_mismatch)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_run_merge_test_gate() {
  local story_id="$1" worktree_path="$2" qa_report_path="$3" pr_url="$4" expected_head_sha="$5"
  TEST_GATE_OUTCOME="blocked:github_unavailable"
  TEST_GATE_AUTH_PR_NUMBER=""; TEST_GATE_AUTH_REPOSITORY_ID=""; TEST_GATE_AUTH_REPOSITORY_NAME=""
  TEST_GATE_AUTH_BASE_REF=""; TEST_GATE_AUTH_BASE_SHA=""; TEST_GATE_AUTH_HEAD_REF=""; TEST_GATE_AUTH_HEAD_SHA=""
  TEST_GATE_AUTH_WORKFLOW_ID=""; TEST_GATE_AUTH_RUN_ID=""; TEST_GATE_AUTH_RUN_NUMBER=""
  TEST_GATE_AUTH_RUN_ATTEMPT=""; TEST_GATE_AUTH_JOB_ID=""
  export TEST_GATE_OUTCOME TEST_GATE_AUTH_PR_NUMBER TEST_GATE_AUTH_REPOSITORY_ID \
    TEST_GATE_AUTH_REPOSITORY_NAME TEST_GATE_AUTH_BASE_REF TEST_GATE_AUTH_BASE_SHA TEST_GATE_AUTH_HEAD_REF \
    TEST_GATE_AUTH_HEAD_SHA TEST_GATE_AUTH_WORKFLOW_ID TEST_GATE_AUTH_RUN_ID TEST_GATE_AUTH_RUN_NUMBER \
    TEST_GATE_AUTH_RUN_ATTEMPT TEST_GATE_AUTH_JOB_ID

  TEST_GATE_AUTH_WORKTREE_PATH="$worktree_path"
  export TEST_GATE_AUTH_WORKTREE_PATH

  [[ -n "$pr_url" && "$expected_head_sha" =~ ^[0-9a-fA-F]{40}$ ]] || {
    TEST_GATE_OUTCOME="blocked:pr_missing"
    echo "[ERROR] ${story_id} merge authority: ${TEST_GATE_OUTCOME} [class=TEST_GATE_BLOCKED]"
    _test_gate_append_report "$qa_report_path" "BLOCKED" "HOSTED:${expected_head_sha:-unknown}" "" "" "" "$TEST_GATE_OUTCOME"
    return 1
  }

  local observation
  observation=$(_test_gate_poll_hosted_authority "$story_id" "$worktree_path" "$expected_head_sha")
  IFS=$'\t' read -r TEST_GATE_OUTCOME TEST_GATE_AUTH_PR_NUMBER \
    TEST_GATE_AUTH_REPOSITORY_ID TEST_GATE_AUTH_REPOSITORY_NAME TEST_GATE_AUTH_BASE_REF \
    TEST_GATE_AUTH_BASE_SHA TEST_GATE_AUTH_HEAD_REF TEST_GATE_AUTH_HEAD_SHA \
    TEST_GATE_AUTH_WORKFLOW_ID TEST_GATE_AUTH_RUN_ID TEST_GATE_AUTH_RUN_NUMBER \
    TEST_GATE_AUTH_RUN_ATTEMPT TEST_GATE_AUTH_JOB_ID <<<"$observation"
  export TEST_GATE_OUTCOME TEST_GATE_AUTH_PR_NUMBER TEST_GATE_AUTH_REPOSITORY_ID \
    TEST_GATE_AUTH_REPOSITORY_NAME TEST_GATE_AUTH_BASE_REF TEST_GATE_AUTH_BASE_SHA TEST_GATE_AUTH_HEAD_REF \
    TEST_GATE_AUTH_HEAD_SHA TEST_GATE_AUTH_WORKFLOW_ID TEST_GATE_AUTH_RUN_ID TEST_GATE_AUTH_RUN_NUMBER \
    TEST_GATE_AUTH_RUN_ATTEMPT TEST_GATE_AUTH_JOB_ID

  case "$TEST_GATE_OUTCOME" in
    hosted_pass)
      echo "[TEST-GATE] ${story_id}: hosted_pass pr=${TEST_GATE_AUTH_PR_NUMBER} head=${TEST_GATE_AUTH_HEAD_SHA} base=${TEST_GATE_AUTH_BASE_REF}@${TEST_GATE_AUTH_BASE_SHA}"
      _test_gate_append_report "$qa_report_path" "PASS" \
        "HOSTED:PR-${TEST_GATE_AUTH_PR_NUMBER}@${TEST_GATE_AUTH_HEAD_SHA}" \
        "$TEST_GATE_AUTH_BASE_SHA" "" "" "hosted_pass"
      return 0
      ;;
    human_required:trust_surface_changed)
      echo "[WARN] ${story_id} merge authority: ${TEST_GATE_OUTCOME}; PR remains open for human review [class=TEST_GATE_HUMAN_REQUIRED]"
      _test_gate_append_report "$qa_report_path" "HUMAN_REQUIRED" \
        "HOSTED:${pr_url}@${expected_head_sha}" "" "" "" "$TEST_GATE_OUTCOME"
      return 2
      ;;
    blocked:*)
      echo "[ERROR] ${story_id} merge authority: ${TEST_GATE_OUTCOME} [class=TEST_GATE_BLOCKED]"
      _test_gate_append_report "$qa_report_path" "BLOCKED" \
        "HOSTED:${pr_url}@${expected_head_sha}" "" "" "" "$TEST_GATE_OUTCOME"
      return 1
      ;;
    *)
      TEST_GATE_OUTCOME="blocked:github_unavailable"
      echo "[ERROR] ${story_id} merge authority: ${TEST_GATE_OUTCOME} [class=TEST_GATE_BLOCKED]"
      return 1
      ;;
  esac
}
