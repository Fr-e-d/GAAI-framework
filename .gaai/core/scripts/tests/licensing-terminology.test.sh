#!/usr/bin/env bash
# ── licensing-terminology.test.sh ───────────────────────────────────────────
# Hermetic drift test: the public repository's licensing copy must use the
# canonical first-use phrase, must never claim the framework or repository
# is "open source" / "open-source" / "open-sourced", and the tracked ELv2
# license blob must stay byte-for-byte unchanged.
#
# Controlled set (exhaustive): the public repository's root README.md,
# docs/contributing/fork-and-own.md, and tracked LICENSE blob. Those files
# live in digipulse-engineering/GAAI-framework, NOT in this monorepo — see PUBLIC_ROOT
# resolution below. Expanding the controlled set requires a validated
# governance change, not an implicit glob.
#
# Fail-closed (AC4): a missing controlled file inside a *confirmed* public
# layout, or a missing/mismatched LICENSE, is a hard failure naming the
# exact path — never silently treated as no-drift. Layout *absence*
# (this monorepo has no docs/contributing/) is a distinct, legitimate
# "not applicable" state, never a violation — see public_layout_present().
#
# Run (bare, inside gaai-platform): bash .gaai/core/scripts/tests/licensing-terminology.test.sh
# Run (against the real public repo):
#   GAAI_LICENSING_ROOT=/path/to/GAAI-framework bash .../licensing-terminology.test.sh
# Exit 0 = all pass.

set -uo pipefail
PASS_COUNT=0; FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Four '..' from .gaai/core/scripts/tests/ resolves to the repository root.
# In the synced public repo this is digipulse-engineering/GAAI-framework's own root
# (correct target). In gaai-platform it resolves to this monorepo's own
# root (deliberate — public_layout_present() turns that into a pass-through
# "not applicable" result instead of a false failure or a silently-skipped
# check). GAAI_LICENSING_ROOT overrides for a specific checkout.
PUBLIC_ROOT="${GAAI_LICENSING_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"

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
# Constants (exact governing wording, exhaustive controlled set)
# ---------------------------------------------------------------------------

CANONICAL_PHRASE="source-available under the Elastic License 2.0 (ELv2)"

# Covers: "open source", "open-source", "open sourced", "open-sourced".
# Deliberately conservative — over-catching this near-identical variant is
# safe, under-catching a real active claim is not.
FORBIDDEN_RE='open[- ]source(d)?'

# Pinned to the current tracked ELv2 license blob (verified against the
# synced public-repo clone during Story planning). Only a separately
# authorized relicensing DEC updates this constant — this Story's own
# verification (Steps 2/5 of the execution plan) proves it is unchanged.
EXPECTED_LICENSE_SHA256="984a67ddf871f12c144d86077520a0b2db361db9778aafeadb5952dacc4b9f98"

# Byte-identical copy of the tracked LICENSE, base64-encoded to avoid
# transcription risk inside this script. Used only by the hermetic
# false-positive-guard fixture (scenario_compliant_fixture_false_positive_guard)
# to prove EXPECTED_LICENSE_SHA256 matches real ELv2 text, not just that the
# checker is internally self-consistent.
REAL_LICENSE_B64="RWxhc3RpYyBMaWNlbnNlIDIuMCAoRUx2MikKCkNvcHlyaWdodCAyMDI2IEZyw6lkw6lyaWMgR2VlbnMKCiMjIEFjY2VwdGFuY2UKCkJ5IHVzaW5nIHRoZSBzb2Z0d2FyZSwgeW91IGFncmVlIHRvIGFsbCBvZiB0aGUgdGVybXMgYW5kIGNvbmRpdGlvbnMgYmVsb3cuCgojIyBDb3B5cmlnaHQgTGljZW5zZQoKVGhlIGxpY2Vuc29yIGdyYW50cyB5b3UgYSBub24tZXhjbHVzaXZlLCByb3lhbHR5LWZyZWUsIHdvcmxkd2lkZSwKbm9uLXN1YmxpY2Vuc2FibGUsIG5vbi10cmFuc2ZlcmFibGUgbGljZW5zZSB0byB1c2UsIGNvcHksIGRpc3RyaWJ1dGUsIG1ha2UKYXZhaWxhYmxlLCBhbmQgcHJlcGFyZSBkZXJpdmF0aXZlIHdvcmtzIG9mIHRoZSBzb2Z0d2FyZSwgaW4gZWFjaCBjYXNlIHN1YmplY3QKdG8gdGhlIGxpbWl0YXRpb25zIGFuZCBjb25kaXRpb25zIGJlbG93LgoKIyMgTGltaXRhdGlvbnMKCllvdSBtYXkgbm90IHByb3ZpZGUgdGhlIHNvZnR3YXJlIHRvIHRoaXJkIHBhcnRpZXMgYXMgYSBob3N0ZWQgb3IgbWFuYWdlZApzZXJ2aWNlLCB3aGVyZSB0aGUgc2VydmljZSBwcm92aWRlcyB1c2VycyB3aXRoIGFjY2VzcyB0byBhbnkgc3Vic3RhbnRpYWwgc2V0Cm9mIHRoZSBmZWF0dXJlcyBvciBmdW5jdGlvbmFsaXR5IG9mIHRoZSBzb2Z0d2FyZS4KCllvdSBtYXkgbm90IG1vdmUsIGNoYW5nZSwgZGlzYWJsZSwgb3IgY2lyY3VtdmVudCB0aGUgbGljZW5zZSBrZXkgZnVuY3Rpb25hbGl0eQppbiB0aGUgc29mdHdhcmUsIGFuZCB5b3UgbWF5IG5vdCByZW1vdmUgb3Igb2JzY3VyZSBhbnkgZnVuY3Rpb25hbGl0eSBpbiB0aGUKc29mdHdhcmUgdGhhdCBpcyBwcm90ZWN0ZWQgYnkgdGhlIGxpY2Vuc2Uga2V5LgoKWW91IG1heSBub3QgYWx0ZXIsIHJlbW92ZSwgb3Igb2JzY3VyZSBhbnkgbGljZW5zaW5nLCBjb3B5cmlnaHQsIG9yIG90aGVyCm5vdGljZXMgb2YgdGhlIGxpY2Vuc29yIGluIHRoZSBzb2Z0d2FyZS4gQW55IHVzZSBvZiB0aGUgbGljZW5zb3IncyB0cmFkZW1hcmtzCmlzIHN1YmplY3QgdG8gYXBwbGljYWJsZSBsYXcuCgojIyBQYXRlbnRzCgpUaGUgbGljZW5zb3IgZ3JhbnRzIHlvdSBhIGxpY2Vuc2UsIHVuZGVyIGFueSBwYXRlbnQgY2xhaW1zIHRoZSBsaWNlbnNvciBjYW4KbGljZW5zZSwgb3IgYmVjb21lcyBhYmxlIHRvIGxpY2Vuc2UsIHRvIG1ha2UsIGhhdmUgbWFkZSwgdXNlLCBzZWxsLCBvZmZlciBmb3IKc2FsZSwgaW1wb3J0IGFuZCBoYXZlIGltcG9ydGVkIHRoZSBzb2Z0d2FyZSwgaW4gZWFjaCBjYXNlIHN1YmplY3QgdG8gdGhlCmxpbWl0YXRpb25zIGFuZCBjb25kaXRpb25zIGluIHRoaXMgbGljZW5zZS4gVGhpcyBsaWNlbnNlIGRvZXMgbm90IGNvdmVyIGFueQpwYXRlbnQgY2xhaW1zIHRoYXQgeW91IGNhdXNlIHRvIGJlIGluZnJpbmdlZCBieSBtb2RpZmljYXRpb25zIG9yIGFkZGl0aW9ucyB0bwp0aGUgc29mdHdhcmUuIElmIHlvdSBvciB5b3VyIGNvbXBhbnkgbWFrZSBhbnkgd3JpdHRlbiBjbGFpbSB0aGF0IHRoZSBzb2Z0d2FyZQppbmZyaW5nZXMgb3IgY29udHJpYnV0ZXMgdG8gaW5mcmluZ2VtZW50IG9mIGFueSBwYXRlbnQsIHlvdXIgcGF0ZW50IGxpY2Vuc2UKZm9yIHRoZSBzb2Z0d2FyZSBncmFudGVkIHVuZGVyIHRoZXNlIHRlcm1zIGVuZHMgaW1tZWRpYXRlbHkuIElmIHlvdXIgY29tcGFueQptYWtlcyBzdWNoIGEgY2xhaW0sIHlvdXIgcGF0ZW50IGxpY2Vuc2UgZW5kcyBpbW1lZGlhdGVseSBmb3Igd29yayBvbiBiZWhhbGYKb2YgeW91ciBjb21wYW55LgoKIyMgTm90aWNlcwoKWW91IG11c3QgZW5zdXJlIHRoYXQgYW55b25lIHdobyBnZXRzIGEgY29weSBvZiBhbnkgcGFydCBvZiB0aGUgc29mdHdhcmUgZnJvbQp5b3UgYWxzbyBnZXRzIGEgY29weSBvZiB0aGVzZSB0ZXJtcy4KCklmIHlvdSBtb2RpZnkgdGhlIHNvZnR3YXJlLCB5b3UgbXVzdCBpbmNsdWRlIGluIGFueSBtb2RpZmllZCBjb3BpZXMgb2YgdGhlCnNvZnR3YXJlIHByb21pbmVudCBub3RpY2VzIHN0YXRpbmcgdGhhdCB5b3UgaGF2ZSBtb2RpZmllZCB0aGUgc29mdHdhcmUuCgojIyBObyBPdGhlciBSaWdodHMKClRoZXNlIHRlcm1zIGRvIG5vdCBpbXBseSBhbnkgbGljZW5zZXMgb3RoZXIgdGhhbiB0aG9zZSBleHByZXNzbHkgZ3JhbnRlZCBpbgp0aGVzZSB0ZXJtcy4KCiMjIFRlcm1pbmF0aW9uCgpJZiB5b3UgdXNlIHRoZSBzb2Z0d2FyZSBpbiB2aW9sYXRpb24gb2YgdGhlc2UgdGVybXMsIHN1Y2ggdXNlIGlzIG5vdCBsaWNlbnNlZCwKYW5kIHlvdXIgbGljZW5zZXMgd2lsbCBhdXRvbWF0aWNhbGx5IHRlcm1pbmF0ZS4gSWYgdGhlIGxpY2Vuc29yIHByb3ZpZGVzIHlvdQp3aXRoIGEgbm90aWNlIG9mIHlvdXIgdmlvbGF0aW9uLCBhbmQgeW91IGNlYXNlIGFsbCB2aW9sYXRpb24gb2YgdGhpcyBsaWNlbnNlCm5vIGxhdGVyIHRoYW4gMzAgZGF5cyBhZnRlciB5b3UgcmVjZWl2ZSB0aGF0IG5vdGljZSwgeW91ciBsaWNlbnNlcyB3aWxsIGJlCnJlaW5zdGF0ZWQgcmV0cm9hY3RpdmVseS4gSG93ZXZlciwgaWYgeW91IHZpb2xhdGUgdGhlc2UgdGVybXMgYWZ0ZXIgc3VjaApyZWluc3RhdGVtZW50LCBhbnkgYWRkaXRpb25hbCB2aW9sYXRpb24gb2YgdGhlc2UgdGVybXMgd2lsbCBjYXVzZSB5b3VyCmxpY2Vuc2VzIHRvIHRlcm1pbmF0ZSBhdXRvbWF0aWNhbGx5IGFuZCBwZXJtYW5lbnRseS4KCiMjIE5vIExpYWJpbGl0eQoKKkFzIGZhciBhcyB0aGUgbGF3IGFsbG93cywgdGhlIHNvZnR3YXJlIGNvbWVzIGFzIGlzLCB3aXRob3V0IGFueSB3YXJyYW50eSBvcgpjb25kaXRpb24sIGFuZCB0aGUgbGljZW5zb3Igd2lsbCBub3QgYmUgbGlhYmxlIHRvIHlvdSBmb3IgYW55IGRhbWFnZXMgYXJpc2luZwpvdXQgb2YgdGhlc2UgdGVybXMgb3IgdGhlIHVzZSBvciBuYXR1cmUgb2YgdGhlIHNvZnR3YXJlLCB1bmRlciBhbnkga2luZCBvZgpsZWdhbCBjbGFpbS4qCgojIyBEZWZpbml0aW9ucwoKVGhlICoqbGljZW5zb3IqKiBpcyB0aGUgZW50aXR5IG9mZmVyaW5nIHRoZXNlIHRlcm1zLCBhbmQgdGhlICoqc29mdHdhcmUqKiBpcwp0aGUgc29mdHdhcmUgdGhlIGxpY2Vuc29yIG1ha2VzIGF2YWlsYWJsZSB1bmRlciB0aGVzZSB0ZXJtcywgaW5jbHVkaW5nIGFueQpwb3J0aW9uIG9mIGl0LgoKKip5b3UqKiByZWZlcnMgdG8gdGhlIGluZGl2aWR1YWwgb3IgZW50aXR5IGFncmVlaW5nIHRvIHRoZXNlIHRlcm1zLgoKKip5b3VyIGNvbXBhbnkqKiBpcyBhbnkgbGVnYWwgZW50aXR5LCBzb2xlIHByb3ByaWV0b3JzaGlwLCBvciBvdGhlciBraW5kIG9mCm9yZ2FuaXphdGlvbiB0aGF0IHlvdSB3b3JrIGZvciwgcGx1cyBhbGwgb3JnYW5pemF0aW9ucyB0aGF0IGhhdmUgY29udHJvbCBvdmVyLAphcmUgdW5kZXIgdGhlIGNvbnRyb2wgb2YsIG9yIGFyZSB1bmRlciBjb21tb24gY29udHJvbCB3aXRoIHRoYXQgb3JnYW5pemF0aW9uLgoqKmNvbnRyb2wqKiBtZWFucyBvd25lcnNoaXAgb2Ygc3Vic3RhbnRpYWxseSBhbGwgdGhlIGFzc2V0cyBvZiBhbiBlbnRpdHksIG9yCnRoZSBwb3dlciB0byBkaXJlY3QgaXRzIG1hbmFnZW1lbnQgYW5kIHBvbGljaWVzIGJ5IHZvdGUsIGNvbnRyYWN0LCBvcgpvdGhlcndpc2UuIENvbnRyb2wgY2FuIGJlIGRpcmVjdCBvciBpbmRpcmVjdC4KCioqeW91ciBsaWNlbnNlcyoqIGFyZSBhbGwgdGhlIGxpY2Vuc2VzIGdyYW50ZWQgdG8geW91IGZvciB0aGUgc29mdHdhcmUgdW5kZXIKdGhlc2UgdGVybXMuCgoqKnVzZSoqIG1lYW5zIGFueXRoaW5nIHlvdSBkbyB3aXRoIHRoZSBzb2Z0d2FyZSByZXF1aXJpbmcgb25lIG9mIHlvdXIKbGljZW5zZXMuCgoqKnRyYWRlbWFyayoqIG1lYW5zIHRyYWRlbWFya3MsIHNlcnZpY2UgbWFya3MsIGFuZCBzaW1pbGFyIHJpZ2h0cy4K"

# Production allowlist: empty. No legitimate exception exists after this
# Story's fixes (README.md + docs/contributing/fork-and-own.md). Format per
# entry: "<file-basename>|<line-number>|<exact matched text>" — no wildcard
# syntax is supported by design (see check_forbidden_claims): an entry that
# never matches an exact triple is simply unused, and check_unused_allowlist
# fails the test for it (AC4). A future narrowly-scoped exception (historical
# quotation, third-party text, explicit explanation) gets its own exact
# entry, never a pattern.
declare -a ALLOWLIST=()
CONSUMED_ALLOWLIST=""

# ---------------------------------------------------------------------------
# Core check functions
# ---------------------------------------------------------------------------

# public_layout_present <root>
# True iff $root looks like a checkout of the public GAAI-framework release
# surface (has docs/contributing/, README.md, LICENSE). False for any other
# repo shape (e.g. gaai-platform's own root) — that is a legitimate
# "not applicable" state, never a violation.
public_layout_present() {
  local root="$1"
  [[ -d "$root/docs/contributing" && -f "$root/README.md" && -f "$root/LICENSE" ]]
}

# check_forbidden_claims <file>
# Scans $file for FORBIDDEN_RE hits. Each hit is checked against ALLOWLIST
# for an exact (basename, lineno, matched-text) match; a match is recorded
# into CONSUMED_ALLOWLIST and does not fail. Every other hit fails, printing
# "file:lineno: forbidden active claim: 'matched_text'". Zero hits passes
# with nothing to report.
check_forbidden_claims() {
  local file="$1" base lineno matched allow_entry a_file a_line a_text found rc=0
  base="$(basename "$file")"
  while IFS=: read -r lineno matched; do
    [[ -z "$lineno" ]] && continue
    found=0
    for allow_entry in "${ALLOWLIST[@]:-}"; do
      [[ -z "$allow_entry" ]] && continue
      IFS='|' read -r a_file a_line a_text <<< "$allow_entry"
      if [[ "$a_file" == "$base" && "$a_line" == "$lineno" && "$a_text" == "$matched" ]]; then
        found=1
        CONSUMED_ALLOWLIST="${CONSUMED_ALLOWLIST}"$'\n'"${allow_entry}"
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "$file:$lineno: forbidden active claim: '$matched'"
      rc=1
    fi
  done < <(grep -inoE "$FORBIDDEN_RE" "$file")
  return $rc
}

# check_unused_allowlist
# Any ALLOWLIST entry whose exact string never appeared in CONSUMED_ALLOWLIST
# during this run fails, naming the unused entry (AC4).
check_unused_allowlist() {
  local allow_entry rc=0
  for allow_entry in "${ALLOWLIST[@]:-}"; do
    [[ -z "$allow_entry" ]] && continue
    if ! grep -qxF "$allow_entry" <<< "$CONSUMED_ALLOWLIST"; then
      echo "unused allowlist exception (never matched during scan): $allow_entry"
      rc=1
    fi
  done
  return $rc
}

# check_canonical_phrase_and_link <file>
# Fails if CANONICAL_PHRASE (verbatim, case-sensitive) does not appear in
# $file. Otherwise requires a markdown link targeting LICENSE within the
# matched line plus the next 2 lines.
check_canonical_phrase_and_link() {
  local file="$1" lineno window
  lineno="$(grep -nF "$CANONICAL_PHRASE" "$file" | head -1 | cut -d: -f1)"
  if [[ -z "$lineno" ]]; then
    echo "$file: canonical first-use phrase not found: '$CANONICAL_PHRASE'"
    return 1
  fi
  window="$(sed -n "${lineno},$((lineno + 2))p" "$file")"
  if ! grep -qE ']\([^)]*LICENSE\)' <<< "$window"; then
    echo "$file:$lineno: canonical phrase found but not linked to LICENSE"
    return 1
  fi
  return 0
}

# check_names_elv2_and_links_license <file>
# Lighter AC2 check (fork/contribution guidance): fails if $file does not
# contain "ELv2" or does not contain a markdown link targeting LICENSE,
# naming the missing half.
check_names_elv2_and_links_license() {
  local file="$1" has_elv2=1 has_link=1
  grep -qF 'ELv2' "$file" || has_elv2=0
  grep -qE ']\([^)]*LICENSE\)' "$file" || has_link=0
  if [[ $has_elv2 -eq 0 && $has_link -eq 0 ]]; then
    echo "$file: missing both 'ELv2' and a markdown link to LICENSE"
    return 1
  elif [[ $has_elv2 -eq 0 ]]; then
    echo "$file: missing 'ELv2'"
    return 1
  elif [[ $has_link -eq 0 ]]; then
    echo "$file: missing a markdown link to LICENSE"
    return 1
  fi
  return 0
}

# check_license_hash <file>
# Fails loud (never silently passes) if $file does not exist, or its
# sha256 does not equal EXPECTED_LICENSE_SHA256 — reports both hashes.
check_license_hash() {
  local file="$1" actual
  if [[ ! -f "$file" ]]; then
    echo "LICENSE file not found: $file"
    return 1
  fi
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$EXPECTED_LICENSE_SHA256" ]]; then
    echo "$file: LICENSE hash mismatch — expected $EXPECTED_LICENSE_SHA256, got $actual"
    return 1
  fi
  return 0
}

# run_licensing_scan <root>
# The single function both the real scan and the fixtures call, so
# fail-closed paths are exercised through the real code, not re-implemented.
run_licensing_scan() {
  local root="$1" readme fork license missing=0 rc=0
  if ! public_layout_present "$root"; then
    echo "not applicable — public layout absent at $root"
    return 0
  fi
  readme="$root/README.md"
  fork="$root/docs/contributing/fork-and-own.md"
  license="$root/LICENSE"
  [[ -f "$readme" ]] || { echo "controlled file missing: $readme"; missing=1; }
  [[ -f "$fork" ]] || { echo "controlled file missing: $fork"; missing=1; }
  [[ -f "$license" ]] || { echo "controlled file missing: $license"; missing=1; }
  if [[ $missing -eq 1 ]]; then
    return 1
  fi

  CONSUMED_ALLOWLIST=""
  check_forbidden_claims "$readme" || rc=1
  check_forbidden_claims "$fork" || rc=1
  check_canonical_phrase_and_link "$readme" || rc=1
  check_names_elv2_and_links_license "$fork" || rc=1
  check_license_hash "$license" || rc=1
  check_unused_allowlist || rc=1
  return $rc
}

# ---------------------------------------------------------------------------
# E — Fixture scenarios (synthetic files, hermetic — always pass regardless
# of environment)
# ---------------------------------------------------------------------------

scenario_forbidden_claims_fixture() {
  local tmp fixture out
  tmp="$(new_sandbox)"
  fixture="$tmp/forbidden.md"
  cat > "$fixture" <<'EOF'
This project is proudly open source and welcomes contributions.
We recently open-sourced the entire framework for community use.
EOF
  ALLOWLIST=()
  CONSUMED_ALLOWLIST=""
  if out="$(check_forbidden_claims "$fixture" 2>&1)"; then
    fail "E1: expected two unallowlisted forbidden-claim lines to FAIL, but check passed"
  else
    if echo "$out" | grep -q "forbidden active claim" && [[ "$(echo "$out" | wc -l | tr -d ' ')" -ge 2 ]]; then
      pass "E1: two unallowlisted forbidden-claim lines correctly flagged"
    else
      fail "E1: unexpected failure output: $out"
    fi
  fi
}

scenario_forbidden_claims_allowlisted() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/forbidden-allowlisted.md"
  cat > "$fixture" <<'EOF'
This project is open source in spirit, though ELv2 governs redistribution.
EOF
  ALLOWLIST=("forbidden-allowlisted.md|1|open source")
  CONSUMED_ALLOWLIST=""
  if check_forbidden_claims "$fixture" >/tmp/gaai_lt_fca_$$ 2>&1; then
    pass "E2: allowlisted forbidden-claim line passes when an explicit exact exception matches"
  else
    fail "E2: allowlisted line unexpectedly failed: $(cat /tmp/gaai_lt_fca_$$)"
  fi
  rm -f /tmp/gaai_lt_fca_$$
  ALLOWLIST=()
}

scenario_unused_allowlist_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/clean.md"
  cat > "$fixture" <<'EOF'
This project is source-available under the Elastic License 2.0 (ELv2).
EOF
  ALLOWLIST=("clean.md|1|open source")
  CONSUMED_ALLOWLIST=""
  if check_forbidden_claims "$fixture" >/tmp/gaai_lt_ua1_$$ 2>&1; then
    : # expected: clean file, nothing found
  else
    fail "E3: expected clean fixture to pass check_forbidden_claims, got: $(cat /tmp/gaai_lt_ua1_$$)"
  fi
  if check_unused_allowlist >/tmp/gaai_lt_ua2_$$ 2>&1; then
    fail "E3: expected a stale (never-matched) allowlist entry to FAIL check_unused_allowlist"
  else
    pass "E3: unused allowlist exception correctly flagged: $(cat /tmp/gaai_lt_ua2_$$)"
  fi
  rm -f /tmp/gaai_lt_ua1_$$ /tmp/gaai_lt_ua2_$$
  ALLOWLIST=()
}

scenario_canonical_phrase_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"

  # (a) Equal to today's actual pre-fix README text — must FAIL. Doubles as
  # a regression proof that this checker would have caught the Story's own
  # starting state.
  fixture="$tmp/pre-fix.md"
  cat > "$fixture" <<'EOF'
ELv2 — see [LICENSE](LICENSE)
EOF
  if check_canonical_phrase_and_link "$fixture" >/tmp/gaai_lt_cpl_a_$$ 2>&1; then
    fail "E4a: expected today's actual pre-fix README wording to FAIL (no canonical phrase) — regression proof"
  else
    pass "E4a: pre-fix wording correctly flagged as missing the canonical phrase"
  fi
  rm -f /tmp/gaai_lt_cpl_a_$$

  # (b) Canonical phrase present, no nearby LICENSE link — must FAIL.
  fixture="$tmp/no-link.md"
  cat > "$fixture" <<'EOF'
This framework is source-available under the Elastic License 2.0 (ELv2).

Other unrelated content follows here with no license link nearby at all.
EOF
  if check_canonical_phrase_and_link "$fixture" >/tmp/gaai_lt_cpl_b_$$ 2>&1; then
    fail "E4b: expected canonical phrase without a nearby LICENSE link to FAIL"
  else
    pass "E4b: canonical phrase without a LICENSE link correctly flagged"
  fi
  rm -f /tmp/gaai_lt_cpl_b_$$

  # (c) Canonical phrase plus a same-line LICENSE link — must PASS.
  fixture="$tmp/compliant.md"
  cat > "$fixture" <<'EOF'
**source-available under the Elastic License 2.0 (ELv2)** — see [LICENSE](LICENSE) for the full terms.
EOF
  if check_canonical_phrase_and_link "$fixture"; then
    pass "E4c: canonical phrase with a same-line LICENSE link passes"
  else
    fail "E4c: compliant canonical-phrase fixture unexpectedly failed"
  fi
}

scenario_names_elv2_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"

  # (a) Today's actual pre-fix fork-and-own.md wording — must FAIL (no
  # LICENSE link). Regression proof.
  fixture="$tmp/pre-fix-fork.md"
  cat > "$fixture" <<'EOF'
GAAI is ELv2 licensed. You can do anything with your fork — the only restriction is you may not offer it as a competing hosted or managed service.
EOF
  if check_names_elv2_and_links_license "$fixture" >/tmp/gaai_lt_nel_a_$$ 2>&1; then
    fail "E5a: expected today's actual pre-fix fork-and-own.md wording to FAIL (no LICENSE link) — regression proof"
  else
    pass "E5a: pre-fix wording correctly flagged as missing a LICENSE link"
  fi
  rm -f /tmp/gaai_lt_nel_a_$$

  # (b) Post-fix wording — must PASS.
  fixture="$tmp/post-fix-fork.md"
  cat > "$fixture" <<'EOF'
GAAI is source-available under the Elastic License 2.0 (ELv2) — see [LICENSE](../../LICENSE) for the governing terms.
EOF
  if check_names_elv2_and_links_license "$fixture"; then
    pass "E5b: post-fix wording naming ELv2 and linking LICENSE passes"
  else
    fail "E5b: post-fix fork-and-own.md fixture unexpectedly failed"
  fi
}

scenario_license_hash_fixture() {
  local tmp fixture
  tmp="$(new_sandbox)"
  fixture="$tmp/LICENSE"
  cat > "$fixture" <<'EOF'
This is not the real ELv2 license text.
EOF
  if check_license_hash "$fixture" >/tmp/gaai_lt_lh_$$ 2>&1; then
    fail "E6: expected non-matching LICENSE content to FAIL the hash check"
  else
    if grep -q "expected $EXPECTED_LICENSE_SHA256" /tmp/gaai_lt_lh_$$ && grep -q "got " /tmp/gaai_lt_lh_$$; then
      pass "E6: LICENSE hash mismatch correctly flagged, both hashes reported"
    else
      fail "E6: hash mismatch reason missing expected/actual detail: $(cat /tmp/gaai_lt_lh_$$)"
    fi
  fi
  rm -f /tmp/gaai_lt_lh_$$
}

scenario_compliant_fixture_false_positive_guard() {
  local tmp
  tmp="$(new_sandbox)"
  mkdir -p "$tmp/docs/contributing"

  cat > "$tmp/README.md" <<'EOF'
![License: ELv2](https://img.shields.io/badge/license-ELv2-green)

# Demo Project

---

**source-available under the Elastic License 2.0 (ELv2)** — see [LICENSE](LICENSE) for the full terms.

---
EOF

  cat > "$tmp/docs/contributing/fork-and-own.md" <<'EOF'
## What We Ask

GAAI is source-available under the Elastic License 2.0 (ELv2) — see [LICENSE](../../LICENSE) for the governing terms.
EOF

  base64 -d <<< "$REAL_LICENSE_B64" > "$tmp/LICENSE" 2>/dev/null || base64 -D <<< "$REAL_LICENSE_B64" > "$tmp/LICENSE"

  ALLOWLIST=()
  local out
  if out="$(run_licensing_scan "$tmp" 2>&1)"; then
    pass "E7: fully compliant fixture passes the real scan end-to-end (false-positive guard; also proves EXPECTED_LICENSE_SHA256 matches real ELv2 text)"
  else
    fail "E7: fully compliant fixture unexpectedly failed: $out"
  fi
}

# ---------------------------------------------------------------------------
# F — Fail-closed scenarios (AC4)
# ---------------------------------------------------------------------------

scenario_missing_controlled_file() {
  local tmp out
  tmp="$(new_sandbox)"
  mkdir -p "$tmp/docs/contributing"
  echo "dummy readme" > "$tmp/README.md"
  echo "dummy license" > "$tmp/LICENSE"
  # fork-and-own.md deliberately absent inside docs/contributing/ — a
  # recognized public layout with one controlled file missing.
  if out="$(run_licensing_scan "$tmp" 2>&1)"; then
    fail "F1: expected missing fork-and-own.md inside a recognized public layout to FAIL, but scan passed"
  else
    if echo "$out" | grep -qF "controlled file missing: $tmp/docs/contributing/fork-and-own.md"; then
      pass "F1: missing controlled file inside a recognized public layout is a hard failure naming the exact path"
    else
      fail "F1: failure did not name the missing file exactly: $out"
    fi
  fi
}

scenario_missing_license_file() {
  local tmp out
  tmp="$(new_sandbox)"
  if out="$(check_license_hash "$tmp/does-not-exist-LICENSE" 2>&1)"; then
    fail "F2: expected check_license_hash on a nonexistent path to FAIL"
  else
    if echo "$out" | grep -q "LICENSE file not found"; then
      pass "F2: missing LICENSE path fails loud, never silently passes"
    else
      fail "F2: unexpected failure reason: $out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# G — Real-file scan: proves the actual Story edits are correct AND guards
# regression on every future edit to these 3 controlled files.
# ---------------------------------------------------------------------------

scenario_real_file_scan() {
  local out
  ALLOWLIST=()
  if out="$(run_licensing_scan "$PUBLIC_ROOT" 2>&1)"; then
    pass "G: real-file scan against PUBLIC_ROOT ($PUBLIC_ROOT): $out"
  else
    fail "G: real-file scan against PUBLIC_ROOT ($PUBLIC_ROOT):"$'\n'"$out"
  fi
}

# ---------------------------------------------------------------------------
echo "GAAI licensing-terminology.test.sh — hermetic ELv2 terminology drift test"
echo "============================================================================"
echo ""
echo "=== E1: unallowlisted forbidden active claims ==="
scenario_forbidden_claims_fixture
echo ""
echo "=== E2: allowlisted forbidden-claim exception ==="
scenario_forbidden_claims_allowlisted
echo ""
echo "=== E3: unused allowlist exception fails ==="
scenario_unused_allowlist_fixture
echo ""
echo "=== E4: canonical first-use phrase + LICENSE link ==="
scenario_canonical_phrase_fixture
echo ""
echo "=== E5: fork/contribution guidance names ELv2 + links LICENSE ==="
scenario_names_elv2_fixture
echo ""
echo "=== E6: LICENSE hash mismatch ==="
scenario_license_hash_fixture
echo ""
echo "=== E7: fully compliant fixture (false-positive guard) ==="
scenario_compliant_fixture_false_positive_guard
echo ""
echo "=== F1: missing controlled file inside a recognized public layout ==="
scenario_missing_controlled_file
echo ""
echo "=== F2: missing LICENSE file fails loud ==="
scenario_missing_license_file
echo ""
echo "=== G: real-file scan (PUBLIC_ROOT=$PUBLIC_ROOT) ==="
scenario_real_file_scan

echo ""
echo "============================================================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "❌ licensing-terminology.test.sh FAILED"
  exit 1
else
  echo "✅ licensing-terminology.test.sh PASSED"
  exit 0
fi
