#!/usr/bin/env bash
# lib/test-gate.sh — deterministic differential test gate
#
# Sourceable library. Public entry point:
#   _run_deterministic_test_gate <story_id> <worktree_path> <qa_report_path>
#     Returns: 0 = not blocked (caller proceeds to push), 1 = blocked/escalated
#       (caller must stop the push; this function already performs the
#       scheduler --set-phase-status + notify_escalation_inline side effects).
#
# Differential semantics (must stay aligned with qa-review skill Step 4):
# only a test that PASSES on origin/<TARGET_BRANCH> and FAILS on the story's
# HEAD is a blocking regression. A test already red on the baseline (rot,
# documented flaky) never blocks. Fail-safe direction throughout: on any
# ambiguity (no baseline, no resolvable test command) this gate escalates —
# it never silently passes and never loops/retries.
#
# Env vars (all optional, have defaults):
#   TARGET_BRANCH  — remote branch compared against (default: staging)
#   SCHEDULER      — absolute path to backlog-scheduler.sh (required by caller)
#   BACKLOG_FILE   — absolute path to active.backlog.yaml (required by caller)
#
# Internal helpers (not part of the public contract, but stable within this
# file): _test_gate_resolve_units, _test_gate_run_units,
# _test_gate_parse_junit_failures, _test_gate_resolve_pm,
# _test_gate_pkg_script, _test_gate_append_report, _test_gate_restore.

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
      echo "junit|${abs_dir}|$(_test_gate_pm_cmd "$pm" "$abs_dir" "test:ci")"
      continue
    fi
    script=$(_test_gate_pkg_script "$abs_dir" "test")
    if [[ -n "$script" ]]; then
      echo "pm|${abs_dir}|$(_test_gate_pm_cmd "$pm" "$abs_dir" "test")"
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
  [[ -s "$xml_path" ]] && tc_count=$(grep -c '<testcase' "$xml_path" 2>/dev/null || echo 0)
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
  local type label cmd out exit_code

  while IFS='|' read -r type label cmd; do
    [[ -z "$type" ]] && continue
    out=$(cd "$worktree_path" && eval "$cmd" 2>&1)
    exit_code=$?
    echo "[TEST-GATE] unit=${label} type=${type} exit=${exit_code}" >&2
    printf '%s\n' "$out" | tail -40 >&2

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
