#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

SCRIPTS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gaai-portable-mktemp.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

scan_suffix_templates() {
  local scan_root="$1"
  if [[ ! -d "$scan_root" || ! -r "$scan_root" ]]; then
    printf 'scan root unavailable\n'
    return 2
  fi

  local manifest
  manifest=$(mktemp "$ROOT/scan-manifest-XXXXXX" 2>/dev/null) || {
    printf 'scan manifest creation failed\n'
    return 2
  }
  if ! find "$scan_root" -type f -print > "$manifest" 2>/dev/null; then
    rm -f "$manifest"
    printf 'scan traversal failed\n'
    return 2
  fi

  local file hits found=0 grep_rc
  while IFS= read -r file; do
    hits=$(mktemp "$ROOT/scan-hits-XXXXXX" 2>/dev/null) || {
      rm -f "$manifest"
      printf 'scan result creation failed\n'
      return 2
    }
    if LC_ALL=C grep -nE 'mktemp[^[:cntrl:]]*X{3,}\.[[:alnum:]][[:alnum:]._-]*' \
      "$file" > "$hits" 2>/dev/null; then
      found=1
      while IFS= read -r match; do
        printf '%s:%s\n' "${file#"$scan_root"/}" "$match"
      done < "$hits"
    else
      grep_rc=$?
      if [[ "$grep_rc" -ne 1 ]]; then
        rm -f "$hits" "$manifest"
        printf 'scan read failed\n'
        return 2
      fi
    fi
    rm -f "$hits"
  done < "$manifest"
  rm -f "$manifest"
  [[ "$found" -eq 0 ]]
}

scan_output=""
if scan_output=$(scan_suffix_templates "$SCRIPTS_ROOT"); then
  pass 'complete scripts surface has no suffix-bearing mktemp template'
else
  fail "suffix-bearing template scan: ${scan_output:-scan failed}"
fi

SCAN_FIXTURE="$ROOT/scan-fixture"
mkdir -p "$SCAN_FIXTURE"
printf 'fixture=$(mktemp "${TMPDIR:-/tmp}/fixture-%s%s")\n' 'XXXXXX' '.sh' \
  > "$SCAN_FIXTURE/bad.test.sh"
negative_output=""
if ! negative_output=$(scan_suffix_templates "$SCAN_FIXTURE") \
  && [[ "$negative_output" == bad.test.sh:* \
  && "$negative_output" != *"$ROOT"* ]]; then
  pass 'scanner negative control reports only a relative offending path'
else
  fail 'scanner negative control did not reject the suffix-bearing fixture'
fi

unavailable_rc=0
scan_suffix_templates "$ROOT/missing-scripts-root" >/dev/null 2>&1 || unavailable_rc=$?
if [[ "$unavailable_rc" -eq 2 ]]; then
  pass 'unavailable scripts surface fails closed'
else
  fail 'unavailable scripts surface passed without a scan'
fi

LOCK_DIR="$ROOT/locks"
mkdir -p "$LOCK_DIR"
daemon_result="$ROOT/daemon-result"
harness_result="$ROOT/harness-result"
mktemp "$LOCK_DIR/.recovery-phase-XXXXXX" > "$daemon_result" 2>/dev/null &
daemon_pid=$!
mktemp "$ROOT/test-harness-XXXXXX" > "$harness_result" 2>/dev/null &
harness_pid=$!
daemon_rc=0; harness_rc=0
wait "$daemon_pid" || daemon_rc=$?
wait "$harness_pid" || harness_rc=$?
daemon_path=$(cat "$daemon_result" 2>/dev/null || true)
harness_path=$(cat "$harness_result" 2>/dev/null || true)
if [[ "$daemon_rc" -eq 0 && "$harness_rc" -eq 0 \
  && -f "$daemon_path" && -f "$harness_path" \
  && "$daemon_path" != "$harness_path" \
  && "$(basename "$daemon_path")" != *XXXXXX* \
  && "$(basename "$harness_path")" != *XXXXXX* ]]; then
  pass 'concurrent daemon and harness templates create distinct substituted paths'
else
  fail 'concurrent representative template creation was not unique'
fi

owner_a_result="$ROOT/owner-a-result"
owner_b_result="$ROOT/owner-b-result"
mktemp "$ROOT/invocation-owned-XXXXXX" > "$owner_a_result" 2>/dev/null &
owner_a_pid=$!
mktemp "$ROOT/invocation-owned-XXXXXX" > "$owner_b_result" 2>/dev/null &
owner_b_pid=$!
owner_a_rc=0; owner_b_rc=0
wait "$owner_a_pid" || owner_a_rc=$?
wait "$owner_b_pid" || owner_b_rc=$?
owner_a=$(cat "$owner_a_result" 2>/dev/null || true)
owner_b=$(cat "$owner_b_result" 2>/dev/null || true)
rm -f "$owner_a"
if [[ "$owner_a_rc" -eq 0 && "$owner_b_rc" -eq 0 \
  && "$owner_a" != "$owner_b" && ! -e "$owner_a" && -f "$owner_b" ]]; then
  pass 'one invocation cleanup leaves the concurrent sibling artefact intact'
else
  fail 'invocation-owned cleanup affected a concurrent sibling artefact'
fi
rm -f "$owner_b"

bsd_first=$(mktemp "$ROOT/bsd-compatible-XXXXXX" 2>/dev/null || true)
bsd_second=$(mktemp "$ROOT/bsd-compatible-XXXXXX" 2>/dev/null || true)
if [[ -f "$bsd_first" && -f "$bsd_second" && "$bsd_first" != "$bsd_second" \
  && "$(basename "$bsd_first")" != *XXXXXX* \
  && "$(basename "$bsd_second")" != *XXXXXX* ]]; then
  pass 'terminal marker substitutes on repeated platform mktemp calls'
else
  fail 'terminal marker is not compatible with the platform mktemp'
fi

script_path=$(mktemp "$ROOT/interpreter-script-XXXXXX" 2>/dev/null || true)
printf '%s\n' '#!/usr/bin/env bash' 'printf portable-interpreter' > "$script_path"
chmod +x "$script_path"
script_output=$(bash "$script_path" 2>/dev/null || true)
if [[ -x "$script_path" && "$script_output" == portable-interpreter ]]; then
  pass 'suffix-free temporary script retains content, permission and interpreter execution'
else
  fail 'suffix-free temporary script was not runnable by explicit interpreter'
fi

printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
