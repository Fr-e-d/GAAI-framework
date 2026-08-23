#!/usr/bin/env bash
# ── documentation-truth.test.sh ─────────────────────────────────────────────
# Hermetic drift test: controlled OSS docs must state supported autonomous
# executors and skill inventory totals derived from runtime code and the
# checked-out filesystem, never a frozen constant (E1095S02).
#
# Derives:
#  - the executor set from delivery-daemon.sh's GAAI_DAEMON_EXECUTOR case
#    block (the daemon's own accepted-values source of truth)
#  - skill counts from SKILL.md paths under .gaai/core/skills/ and
#    .gaai/core/compat/codex-skills/
#
# Then scans the 5 controlled files this Story authorizes for: stale
# exclusivity claims (under-claim), stale affirmative claims of an executor
# the daemon no longer accepts (over-claim), missing Claude-default wording,
# and numeric skill totals that don't match either derived count.
#
# Fail-closed (AC4): a missing controlled file, a missing case block, or a
# case block that parses to zero executors is a hard failure, never treated
# as empty/no-drift.
#
# Also covers two additional fail-closed contracts (E1126S04 AC1/AC3/AC6):
#  - check_skills_index_integrity: every `path:` entry in skills-index.yaml
#    resolves on disk, every on-disk SKILL.md is indexed, and `total:`
#    matches both counts. Catches a dangling entry left behind by a deleted
#    skill (the failure mode a pure-mtime regeneration check misses).
#  - check_local_status_contract: a given status-command doc never reads a
#    `.gaai/local/` cache or names subscription/plan/tier/billing state or a
#    connection status, and does positively assert filesystem-only, no
#    network operation.
#
# Run: bash .gaai/core/scripts/tests/documentation-truth.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_CORE="$(cd "$SCRIPT_DIR/../.." && pwd)"   # .../.gaai/core

declare -a TMP_DIRS=()
cleanup_all() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup_all EXIT

new_sandbox() {
  local tmp; tmp="$(mktemp -d)"
  TMP_DIRS+=("$tmp")
  echo "$tmp"
}

# ---------------------------------------------------------------------------
# Derivation helpers
# ---------------------------------------------------------------------------

# derive_executor_set <delivery-daemon.sh path>
# Prints newline-separated bare-word case arms (excluding the `*)` catch-all)
# found between `case "${GAAI_DAEMON_EXECUTOR:-claude}" in` and its `esac`.
# Fails loud (non-zero return + stderr reason) if the source is missing, the
# case block cannot be located, or zero arms are parsed.
derive_executor_set() {
  local src="$1" block arms
  if [[ ! -f "$src" ]]; then
    echo "derive_executor_set: source file not found: $src" >&2
    return 1
  fi
  block="$(sed -n '/case "\${GAAI_DAEMON_EXECUTOR:-claude}" in/,/^esac/p' "$src")"
  if [[ -z "$block" ]]; then
    echo "derive_executor_set: GAAI_DAEMON_EXECUTOR case block not found in $src" >&2
    return 1
  fi
  arms="$(echo "$block" | grep -oE '^[[:space:]]*[a-zA-Z0-9_]+\)' | tr -d ' )' | grep -v '^\*$')"
  if [[ -z "$arms" ]]; then
    echo "derive_executor_set: case block parsed to zero executor arms in $src" >&2
    return 1
  fi
  echo "$arms"
}

# derive_skill_counts <core-dir>
# Prints "core_count compat_count". Fails loud if $core_dir/skills is
# missing (compat dir absence is a valid zero-compat-skills state).
derive_skill_counts() {
  local core_dir="$1" core_count compat_count
  if [[ ! -d "$core_dir/skills" ]]; then
    echo "derive_skill_counts: $core_dir/skills not found" >&2
    return 1
  fi
  core_count="$(find "$core_dir/skills" -name 'SKILL.md' | wc -l | tr -d ' ')"
  if [[ -d "$core_dir/compat/codex-skills" ]]; then
    compat_count="$(find "$core_dir/compat/codex-skills" -name 'SKILL.md' | wc -l | tr -d ' ')"
  else
    compat_count="0"
  fi
  echo "$core_count $compat_count"
}

# ---------------------------------------------------------------------------
# Per-file drift checks. Each returns 0 (no drift found) or 1 (drift found,
# with a reason on stdout via the caller's fail() call).
# ---------------------------------------------------------------------------

# check_underclaim <file> <executor_set (newline-separated)>
# If the file touches the daemon/autonomous-delivery topic, every member of
# the executor set must appear (case-insensitive) somewhere in the file.
check_underclaim() {
  local file="$1" executor_set="$2" exec_name missing=""
  grep -qiE 'daemon|autonomous delivery|GAAI_DAEMON_EXECUTOR|headless executor' "$file" || return 0
  while IFS= read -r exec_name; do
    [[ -z "$exec_name" ]] && continue
    grep -qi -- "$exec_name" "$file" || missing="${missing}${missing:+, }${exec_name}"
  done <<< "$executor_set"
  if [[ -n "$missing" ]]; then
    echo "$file: under-claims executor support — missing: $missing"
    return 1
  fi
  return 0
}

# check_overclaim_codex <file> <executor_set>
# If codex is NOT in the derived set but the file affirmatively mentions
# codex, that's drift.
check_overclaim_codex() {
  local file="$1" executor_set="$2"
  if ! grep -qx 'codex' <<< "$executor_set"; then
    if grep -qi 'codex' "$file"; then
      echo "$file: mentions codex but derived executor set is: $(echo "$executor_set" | tr '\n' ',')"
      return 1
    fi
  fi
  return 0
}

# check_claude_default <file>
# If the file mentions both claude and codex, at least one line containing
# claude must also contain "default".
check_claude_default() {
  local file="$1"
  grep -qi 'claude' "$file" || return 0
  grep -qi 'codex' "$file" || return 0
  if grep -i 'claude' "$file" | grep -qi 'default'; then
    return 0
  fi
  echo "$file: mentions both claude and codex but no line pairs claude with 'default'"
  return 1
}

# check_skill_totals <file> <core_count> <compat_count>
# Any bare number immediately followed by "skill(s)" must equal core_count
# or compat_count. No match at all is fine (removed-from-narrative branch).
check_skill_totals() {
  local file="$1" core_count="$2" compat_count="$3" line lineno num bad=0
  while IFS=: read -r lineno rest; do
    [[ -z "$lineno" ]] && continue
    num="$(echo "$rest" | grep -oE '[0-9]+' | head -1)"
    [[ -z "$num" ]] && continue
    if [[ "$num" != "$core_count" && "$num" != "$compat_count" ]]; then
      echo "$file:$lineno: skill total '$rest' ($num) matches neither derived core ($core_count) nor compat ($compat_count) count"
      bad=1
    fi
  done < <(grep -noE '[0-9]+[[:space:]]+skills?' "$file")
  [[ $bad -eq 0 ]]
}

# check_skills_index_integrity <core_dir>
# Asserts the skills index at $core_dir/skills/skills-index.yaml exists,
# every `path:` entry resolves to a real file (resolved against
# $core_dir/..), every on-disk SKILL.md under $core_dir/skills is present
# as a `path:` entry, and `total:` equals both counts. Absence of the index
# is a hard failure, never treated as no-drift.
check_skills_index_integrity() {
  local core_dir="$1"
  local index="$core_dir/skills/skills-index.yaml" parent base bad=0
  if [[ ! -f "$index" ]]; then
    echo "check_skills_index_integrity: index file not found: $index"
    return 1
  fi
  parent="$core_dir/.."
  base="$(basename "$core_dir")"

  local -a paths=()
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    paths+=("$p")
  done < <(grep -oE '^[[:space:]]*path:[[:space:]]*.+$' "$index" | sed -E 's/^[[:space:]]*path:[[:space:]]*//')

  local p
  for p in "${paths[@]}"; do
    if [[ ! -f "$parent/$p" ]]; then
      echo "check_skills_index_integrity: dangling index entry — path does not resolve on disk: $p"
      bad=1
    fi
  done

  local -a on_disk=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    on_disk+=("$f")
  done < <(cd "$parent" && find "$base/skills" -name 'SKILL.md' 2>/dev/null | sort)

  local f found
  for f in "${on_disk[@]}"; do
    found=0
    for p in "${paths[@]}"; do
      [[ "$p" == "$f" ]] && { found=1; break; }
    done
    if [[ $found -eq 0 ]]; then
      echo "check_skills_index_integrity: on-disk skill missing from index: $f"
      bad=1
    fi
  done

  local total_field entry_count="${#paths[@]}" disk_count="${#on_disk[@]}"
  total_field="$(grep -m1 -oE '^total:[[:space:]]*[0-9]+' "$index" | grep -oE '[0-9]+')"
  if [[ -z "$total_field" ]]; then
    echo "check_skills_index_integrity: no total: field found in $index"
    bad=1
  elif [[ "$total_field" != "$entry_count" || "$total_field" != "$disk_count" ]]; then
    echo "check_skills_index_integrity: total field ($total_field) does not match entry count ($entry_count) or on-disk count ($disk_count)"
    bad=1
  fi

  [[ $bad -eq 0 ]]
}

# check_local_status_contract <file>
# Asserts $file exists, never references a `.gaai/local/` cache path, a
# `*-state.json` cache read, subscription/plan/tier/billing vocabulary, or
# a connection-status report ("not connected"), and DOES positively assert
# both `filesystem` and `no network`. Missing file is a hard failure.
check_local_status_contract() {
  local file="$1" bad=0
  if [[ ! -f "$file" ]]; then
    echo "check_local_status_contract: file not found: $file"
    return 1
  fi
  if grep -qiE '\.gaai/local/' "$file"; then
    echo "check_local_status_contract: $file references a local cache path (.gaai/local/)"
    bad=1
  fi
  if grep -qiE '[a-z0-9_-]+-state\.json' "$file"; then
    echo "check_local_status_contract: $file references a *-state.json cache read"
    bad=1
  fi
  if grep -qiE '\b(subscription|billing|tier|plan)\b' "$file"; then
    echo "check_local_status_contract: $file uses subscription/plan/tier/billing vocabulary"
    bad=1
  fi
  if grep -qiE 'not connected' "$file"; then
    echo "check_local_status_contract: $file reports a connection status"
    bad=1
  fi
  if ! grep -qi 'filesystem' "$file"; then
    echo "check_local_status_contract: $file is missing the positive local-only 'filesystem' assertion"
    bad=1
  fi
  if ! grep -qi 'no network' "$file"; then
    echo "check_local_status_contract: $file is missing the positive local-only 'no network' assertion"
    bad=1
  fi
  [[ $bad -eq 0 ]]
}

# ---------------------------------------------------------------------------
# B — Fixture scenarios (synthetic files, hermetic derivation inputs)
# ---------------------------------------------------------------------------

scenario_underclaim_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/stale-claude-only.md"
  cat > "$fixture" <<'EOF'
The daemon requires the Claude Code CLI as a hard dependency for autonomous delivery.
EOF
  if check_underclaim "$fixture" $'claude\ncodex' >/tmp/du_out_$$ 2>&1; then
    fail "B1: expected under-claim fixture to FAIL, but check passed"
  else
    pass "B1: stale Claude-only statement correctly flagged as under-claim"
  fi
  rm -f /tmp/du_out_$$
}

scenario_overclaim_fixture_regression() {
  local tmp core proj executor_set fixture
  tmp="$(new_sandbox)"
  # Fixture daemon script with the codex arm removed — simulates a future
  # regression where the daemon stops accepting codex.
  cat > "$tmp/delivery-daemon-regressed.sh" <<'EOF'
case "${GAAI_DAEMON_EXECUTOR:-claude}" in
  claude)
    echo ok
    ;;
  *)
    echo "unknown" >&2
    exit 1
    ;;
esac
EOF
  if ! executor_set="$(derive_executor_set "$tmp/delivery-daemon-regressed.sh")"; then
    fail "B2: expected regressed fixture to still derive a valid (claude-only) set, got failure: $executor_set"
    return
  fi
  if [[ "$executor_set" != "claude" ]]; then
    fail "B2: expected derived set 'claude' from regressed fixture, got: $executor_set"
    return
  fi
  fixture="$tmp/still-claims-codex.md"
  cat > "$fixture" <<'EOF'
Set GAAI_DAEMON_EXECUTOR=codex for the Codex headless daemon executor.
EOF
  if check_overclaim_codex "$fixture" "$executor_set" >/tmp/oc_out_$$ 2>&1; then
    fail "B2: expected over-claim fixture to FAIL against regressed (claude-only) derived set"
  else
    pass "B2: Codex executor regression correctly flagged as over-claim"
  fi
  rm -f /tmp/oc_out_$$

  # Same fixture doc against the real (claude+codex) derived set must PASS.
  if check_overclaim_codex "$fixture" $'claude\ncodex'; then
    pass "B2: same fixture doc passes over-claim check against the real (claude+codex) set"
  else
    fail "B2: fixture doc unexpectedly failed over-claim check against real derived set"
  fi
}

scenario_claude_default_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/no-default-wording.md"
  cat > "$fixture" <<'EOF'
The daemon supports claude and codex as autonomous executors.
EOF
  if check_claude_default "$fixture" >/tmp/cd_out_$$ 2>&1; then
    fail "B3: expected missing-default-wording fixture to FAIL"
  else
    pass "B3: missing Claude-default wording correctly flagged"
  fi
  rm -f /tmp/cd_out_$$

  fixture="$tmp/has-default-wording.md"
  cat > "$fixture" <<'EOF'
The daemon supports claude (default) and codex as autonomous executors.
EOF
  if check_claude_default "$fixture"; then
    pass "B3: correctly-worded default fixture passes"
  else
    fail "B3: correctly-worded default fixture unexpectedly failed"
  fi
}

scenario_stale_numeric_total_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/stale-count.md"
  cat > "$fixture" <<'EOF'
Everything else (999 skills, 8 rule files) is loaded on demand.
EOF
  if check_skill_totals "$fixture" "62" "7" >/tmp/st_out_$$ 2>&1; then
    fail "B4: expected stale numeric total fixture to FAIL"
  else
    pass "B4: stale numeric skill total correctly flagged"
  fi
  rm -f /tmp/st_out_$$

  fixture="$tmp/matching-count.md"
  cat > "$fixture" <<'EOF'
Everything else (62 skills, 8 rule files) is loaded on demand.
EOF
  if check_skill_totals "$fixture" "62" "7"; then
    pass "B4: matching numeric skill total passes"
  else
    fail "B4: matching numeric skill total unexpectedly failed"
  fi

  fixture="$tmp/no-count.md"
  cat > "$fixture" <<'EOF'
Everything else (skills, rule files) is loaded on demand.
EOF
  if check_skill_totals "$fixture" "62" "7"; then
    pass "B4: no numeric skill total passes (removed-from-narrative branch)"
  else
    fail "B4: no-numeric-total fixture unexpectedly failed"
  fi
}

scenario_compliant_fixture_false_positive_guard() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/compliant.md"
  cat > "$fixture" <<'EOF'
The daemon explicitly supports two local headless autonomous executors:
claude (Claude Code CLI, default) and codex (Codex CLI, via
GAAI_DAEMON_EXECUTOR=codex). An unknown or unavailable executor stops
before governed work begins.
EOF
  local ok=1
  check_underclaim "$fixture" $'claude\ncodex' || ok=0
  check_overclaim_codex "$fixture" $'claude\ncodex' || ok=0
  check_claude_default "$fixture" || ok=0
  check_skill_totals "$fixture" "62" "7" || ok=0
  if [[ $ok -eq 1 ]]; then
    pass "B5: fully compliant fixture passes all four checks (false-positive guard)"
  else
    fail "B5: fully compliant fixture unexpectedly failed at least one check"
  fi
}

# ---------------------------------------------------------------------------
# C — Real-file scan: proves the actual Story edits are correct AND guards
# regression on every future edit to these 5 controlled files.
# ---------------------------------------------------------------------------

scenario_real_file_scan() {
  local executor_set counts core_count compat_count file rc=0
  local -a files=(
    "$REAL_CORE/README.md"
    "$REAL_CORE/GAAI.md"
    "$REAL_CORE/scripts/README.md"
    "$REAL_CORE/compat/COMPAT.md"
    "$REAL_CORE/compat/codex.md"
  )

  if ! executor_set="$(derive_executor_set "$REAL_CORE/scripts/delivery-daemon.sh")"; then
    fail "C: could not derive real executor set: $executor_set"
    return
  fi
  pass "C: derived real executor set: $(echo "$executor_set" | tr '\n' ',')"

  if ! counts="$(derive_skill_counts "$REAL_CORE")"; then
    fail "C: could not derive real skill counts: $counts"
    return
  fi
  core_count="$(echo "$counts" | awk '{print $1}')"
  compat_count="$(echo "$counts" | awk '{print $2}')"
  pass "C: derived real skill counts — core=$core_count compat=$compat_count"

  for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
      fail "C: controlled file missing: $file"
      rc=1
      continue
    fi
    local out
    if out="$(check_underclaim "$file" "$executor_set" 2>&1)"; then
      : # ok
    else
      fail "C: $out"
      rc=1
    fi
    if out="$(check_overclaim_codex "$file" "$executor_set" 2>&1)"; then
      :
    else
      fail "C: $out"
      rc=1
    fi
    if out="$(check_claude_default "$file" 2>&1)"; then
      :
    else
      fail "C: $out"
      rc=1
    fi
    if out="$(check_skill_totals "$file" "$core_count" "$compat_count" 2>&1)"; then
      :
    else
      fail "C: $out"
      rc=1
    fi
  done

  [[ $rc -eq 0 ]] && pass "C: all 5 real controlled files are drift-free against derived runtime/filesystem truth"
}

# ---------------------------------------------------------------------------
# D — Fail-closed scenarios (AC4)
# ---------------------------------------------------------------------------

scenario_missing_controlled_file() {
  local tmp missing_reported=0 f
  tmp="$(new_sandbox)"
  mkdir -p "$tmp/skills/cross/demo"
  : > "$tmp/skills/cross/demo/SKILL.md"
  # Only create README.md — GAAI.md is deliberately absent.
  : > "$tmp/README.md"

  local -a check_files=("$tmp/README.md" "$tmp/GAAI.md")
  for f in "${check_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing_reported=1
      [[ "$f" == "$tmp/GAAI.md" ]] || fail "D1: wrong file reported missing: $f"
    fi
  done
  if [[ $missing_reported -eq 1 ]]; then
    pass "D1: missing controlled file ($tmp/GAAI.md) is reported as a hard failure, not skipped"
  else
    fail "D1: missing controlled file was not detected"
  fi
}

scenario_mangled_case_block() {
  local tmp src out
  tmp="$(new_sandbox)"
  src="$tmp/delivery-daemon-mangled.sh"
  cat > "$src" <<'EOF'
#!/usr/bin/env bash
echo "no case block here at all"
EOF
  if out="$(derive_executor_set "$src" 2>&1)"; then
    fail "D2: expected mangled/missing case block to fail loud, but derive_executor_set succeeded with: $out"
  else
    if echo "$out" | grep -q "case block not found"; then
      pass "D2: mangled case block source fails loud with an explicit reason, not a silent empty set"
    else
      fail "D2: failure reason not as expected: $out"
    fi
  fi
}

scenario_missing_skills_dir() {
  local tmp out
  tmp="$(new_sandbox)"
  # No $tmp/skills directory created at all.
  if out="$(derive_skill_counts "$tmp" 2>&1)"; then
    fail "D3: expected missing skills/ dir to fail loud, but derive_skill_counts succeeded with: $out"
  else
    if echo "$out" | grep -q "skills not found"; then
      pass "D3: missing skills/ directory fails loud with an explicit reason"
    else
      fail "D3: failure reason not as expected: $out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# E — check_skills_index_integrity fixtures (AC1/AC6): dangling entry,
# inverse drift (on-disk skill absent from index), total mismatch, missing
# index file, and a consistent false-positive guard. Deliberately generic —
# no hard-coded skill name/ID appears here (AC5).
# ---------------------------------------------------------------------------

scenario_skills_index_integrity_fixtures() {
  local tmp core_dir out

  # E1: dangling path entry
  tmp="$(new_sandbox)"
  core_dir="$tmp/core"
  mkdir -p "$core_dir/skills/cross/demo-skill"
  : > "$core_dir/skills/cross/demo-skill/SKILL.md"
  cat > "$core_dir/skills/skills-index.yaml" <<'EOF'
generated_at: {date}
total: 2

cross:
  - id: SKILL-DEMO-001
    name: demo-skill
    path: core/skills/cross/demo-skill/SKILL.md
  - id: SKILL-GHOST-001
    name: ghost-skill
    path: core/skills/cross/ghost-skill/SKILL.md
EOF
  if out="$(check_skills_index_integrity "$core_dir" 2>&1)"; then
    fail "E1: expected dangling index entry to FAIL, but check passed"
  else
    if echo "$out" | grep -q "ghost-skill"; then
      pass "E1: dangling index entry correctly flagged, naming the entry"
    else
      fail "E1: dangling entry detected but reason did not name it: $out"
    fi
  fi

  # E2: on-disk skill missing from index (inverse drift)
  tmp="$(new_sandbox)"
  core_dir="$tmp/core"
  mkdir -p "$core_dir/skills/cross/demo-skill" "$core_dir/skills/cross/orphan-skill"
  : > "$core_dir/skills/cross/demo-skill/SKILL.md"
  : > "$core_dir/skills/cross/orphan-skill/SKILL.md"
  cat > "$core_dir/skills/skills-index.yaml" <<'EOF'
generated_at: {date}
total: 1

cross:
  - id: SKILL-DEMO-001
    name: demo-skill
    path: core/skills/cross/demo-skill/SKILL.md
EOF
  if out="$(check_skills_index_integrity "$core_dir" 2>&1)"; then
    fail "E2: expected on-disk skill missing from index to FAIL, but check passed"
  else
    if echo "$out" | grep -q "orphan-skill"; then
      pass "E2: on-disk skill missing from index correctly flagged (inverse drift)"
    else
      fail "E2: missing-from-index detected but reason did not name it: $out"
    fi
  fi

  # E3: total field mismatch
  tmp="$(new_sandbox)"
  core_dir="$tmp/core"
  mkdir -p "$core_dir/skills/cross/demo-skill"
  : > "$core_dir/skills/cross/demo-skill/SKILL.md"
  cat > "$core_dir/skills/skills-index.yaml" <<'EOF'
generated_at: {date}
total: 5

cross:
  - id: SKILL-DEMO-001
    name: demo-skill
    path: core/skills/cross/demo-skill/SKILL.md
EOF
  if check_skills_index_integrity "$core_dir" >/tmp/sii_out_$$ 2>&1; then
    fail "E3: expected total field mismatch to FAIL"
  else
    pass "E3: total field mismatch correctly flagged"
  fi
  rm -f /tmp/sii_out_$$

  # E4: missing index file fails loud (not silently treated as no-drift)
  tmp="$(new_sandbox)"
  core_dir="$tmp/core"
  mkdir -p "$core_dir/skills"
  if out="$(check_skills_index_integrity "$core_dir" 2>&1)"; then
    fail "E4: expected missing index file to FAIL loud"
  else
    if echo "$out" | grep -q "index file not found"; then
      pass "E4: missing index file fails loud with an explicit reason"
    else
      fail "E4: missing-index failure reason not as expected: $out"
    fi
  fi

  # E5: consistent index + skill tree (false-positive guard)
  tmp="$(new_sandbox)"
  core_dir="$tmp/core"
  mkdir -p "$core_dir/skills/cross/demo-skill" "$core_dir/skills/discovery/other-skill"
  : > "$core_dir/skills/cross/demo-skill/SKILL.md"
  : > "$core_dir/skills/discovery/other-skill/SKILL.md"
  cat > "$core_dir/skills/skills-index.yaml" <<'EOF'
generated_at: {date}
total: 2

cross:
  - id: SKILL-DEMO-001
    name: demo-skill
    path: core/skills/cross/demo-skill/SKILL.md
discovery:
  - id: SKILL-OTHER-001
    name: other-skill
    path: core/skills/discovery/other-skill/SKILL.md
EOF
  if check_skills_index_integrity "$core_dir"; then
    pass "E5: consistent index + skill tree passes (false-positive guard)"
  else
    fail "E5: consistent index + skill tree unexpectedly failed"
  fi
}

# ---------------------------------------------------------------------------
# F — check_local_status_contract fixtures (AC3/AC6). F1 is a
# shape-equivalent synthetic defect, not a verbatim copy of any real
# pre-fix text — pasting the real pre-fix wording would reintroduce a
# hosted product name into this Story's own files, which AC5 forbids.
# ---------------------------------------------------------------------------

scenario_local_status_contract_fixtures() {
  local tmp fixture

  # F1: shape-equivalent defect fixture (local cache path + plan vocabulary)
  tmp="$(new_sandbox)"
  fixture="$tmp/status-with-remote-state.md"
  cat > "$fixture" <<'EOF'
Run `cat .gaai/local/account-state.json 2>/dev/null` to read the cached state.
Display: <Example Service>: Pro plan — Active
EOF
  if check_local_status_contract "$fixture" >/tmp/lsc_out_$$ 2>&1; then
    fail "F1: expected local-cache-and-plan-shaped defect fixture to FAIL"
  else
    pass "F1: local-cache-and-plan-shaped defect fixture correctly flagged"
  fi
  rm -f /tmp/lsc_out_$$

  # F2: missing the positive local-only assertion
  tmp="$(new_sandbox)"
  fixture="$tmp/status-no-assertion.md"
  cat > "$fixture" <<'EOF'
Reads the active backlog and memory files under the project directory.
EOF
  if check_local_status_contract "$fixture" >/tmp/lsc_out2_$$ 2>&1; then
    fail "F2: expected fixture missing the local-only assertion to FAIL"
  else
    pass "F2: fixture missing the local-only positive assertion correctly flagged"
  fi
  rm -f /tmp/lsc_out2_$$

  # F3: compliant fixture (false-positive guard)
  tmp="$(new_sandbox)"
  fixture="$tmp/status-compliant.md"
  cat > "$fixture" <<'EOF'
This command reports only state read from the filesystem under the project
directory. It makes no network call and reads no cached external state.
EOF
  if check_local_status_contract "$fixture"; then
    pass "F3: compliant local-only fixture passes (false-positive guard)"
  else
    fail "F3: compliant local-only fixture unexpectedly failed"
  fi
}

# ---------------------------------------------------------------------------
# C2 — Real-file scan for the two new contracts: proves this Story's own
# edits are correct AND guards every future edit to these files.
# ---------------------------------------------------------------------------

scenario_real_index_and_status_scan() {
  local out

  if out="$(check_skills_index_integrity "$REAL_CORE" 2>&1)"; then
    pass "C2: real skills-index.yaml is consistent with the on-disk skill tree"
  else
    fail "C2: $out"
  fi

  local status_file="$REAL_CORE/compat/commands/gaai-status.md"
  if out="$(check_local_status_contract "$status_file" 2>&1)"; then
    pass "C2: real gaai-status.md satisfies the local-only status contract"
  else
    fail "C2: $out"
  fi
}

# ---------------------------------------------------------------------------
echo "GAAI documentation-truth.test.sh — hermetic drift test"
echo "========================================================"
echo ""
echo "=== B1: stale Claude-only statement (under-claim) ==="
scenario_underclaim_fixture
echo ""
echo "=== B2: Codex executor regression fixture (over-claim) ==="
scenario_overclaim_fixture_regression
echo ""
echo "=== B3: Claude-default wording ==="
scenario_claude_default_fixture
echo ""
echo "=== B4: stale numeric skill total ==="
scenario_stale_numeric_total_fixture
echo ""
echo "=== B5: fully compliant fixture (false-positive guard) ==="
scenario_compliant_fixture_false_positive_guard
echo ""
echo "=== C: real-file scan against derived runtime/filesystem truth ==="
scenario_real_file_scan
echo ""
echo "=== D1: missing controlled file fails loud ==="
scenario_missing_controlled_file
echo ""
echo "=== D2: mangled/missing executor case block fails loud ==="
scenario_mangled_case_block
echo ""
echo "=== D3: missing skills/ directory fails loud ==="
scenario_missing_skills_dir
echo ""
echo "=== E: skills-index integrity fixtures ==="
scenario_skills_index_integrity_fixtures
echo ""
echo "=== F: local-only status contract fixtures ==="
scenario_local_status_contract_fixtures
echo ""
echo "=== C2: real-file scan — skills-index integrity + local-only status ==="
scenario_real_index_and_status_scan

echo ""
echo "========================================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "❌ documentation-truth.test.sh FAILED"
  exit 1
else
  echo "✅ documentation-truth.test.sh PASSED"
  exit 0
fi
