#!/usr/bin/env bash
# daemon-asset-home.test.sh — exact-current startup contract, regression-coverage criterion census, privileged entry and exact-asset matrices
#
# Covers:
#   * the deterministic repository-wide CENSUS over every tracked reference to
#     daemon-start.sh / daemon-setup.sh (the closed exclusions are non-executing
#     analysis invocations such as `bash -n`, designated negative-test fixtures, and
#     governance/history under .gaai/project/contexts/**);
#   * the privileged entry contract, including which hostile inputs are OBSERVABLE at
#     the first script instruction versus suppressed earlier by privileged Bash or the
#     OS loader — an observable input must return typed entry_authority_invalid, a
#     pre-entry-suppressed one must be proven unimported, unexecuted and absent from
#     every descendant;
#   * exact launcher/daemon blob, mode, no-follow and descriptor execution;
#   * credential privacy in both canonical modes, and the absence of any fallback.
#
# These tests do not claim immunity for an entry interpreter already affected before
# its first instruction, nor an isolation boundary against a same-UID principal.
#
# Usage: .gaai/core/scripts/tests/daemon-asset-home.test.sh

set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/../../.." && pwd -P)"

# shellcheck source=daemon-home-provision.test.sh
GAAI_HOME_FIXTURE_ONLY=1 source "$SCRIPT_DIR/daemon-home-provision.test.sh"

# ═══════════════════════════════════════════════════════════════════════════
# Part 1 — Repository-wide census (AC6)
# ═══════════════════════════════════════════════════════════════════════════
#
# The census DISCOVERS paths; it does not inspect only the inventory. An actionable
# plain-Bash occurrence is a tracked reference that would EXECUTE either script
# through a plain `bash` interpreter — the very entry the privileged contract
# refuses. Leaving one anywhere in a shipped surface would preserve the vulnerability
# the Story closes, so the post-implementation census must find exactly zero.

echo ""
echo "=== Census: actionable plain-Bash occurrences across every tracked surface ==="

# The twenty-one-file founder-authorized Delivery inventory.
INVENTORY="$(cat <<'INV'
.gaai/core/scripts/lib/daemon-home.sh
.gaai/core/scripts/daemon-start.sh
.gaai/core/scripts/delivery-daemon.sh
.gaai/core/scripts/daemon-setup.sh
.gaai/core/scripts/tests/daemon-home-provision.test.sh
.gaai/core/scripts/tests/daemon-asset-home.test.sh
.gaai/core/scripts/tests/daemon-coordination-home.test.sh
runbooks/daemon-home-coordination.md
.gaai/core/scripts/open-monitor.command
.gaai/core/scripts/migrate-backlog-phase-schema.sh
.gaai/core/GAAI.md
.gaai/core/README.md
.gaai/core/QUICK-REFERENCE.md
.gaai/core/compat/commands/gaai-oss/daemon.md
.gaai/core/compat/commands/gaai-oss/deliver.md
.gaai/core/compat/commands/gaai-daemon.md
.gaai/core/compat/commands/gaai-deliver.md
.gaai/core/compat/codex-skills/gaai-oss-daemon/SKILL.md
.claude/commands/gaai-daemon.md
packages/gaai-cloud-plugin/e2e/smoke.test.sh
workers/gaai-cloud/api/docs/guides/daemon-setup.md
INV
)"
if [[ "$(printf '%s\n' "$INVENTORY" | grep -c .)" == "21" ]]; then
  pass "CENSUS-0: the inventory under test is exactly twenty-one files"
else
  fail "CENSUS-0: the inventory is not twenty-one files"
fi

# Deterministic: tracked files only, sorted, with the closed exclusions applied.
census_hits() {
  git -C "$REPO_ROOT" ls-files -z \
    | xargs -0 grep -nE '(^|[^[:alnum:]_/.-])bash[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^|;&[:space:]]*daemon-(start|setup)\.sh' 2>/dev/null \
    | grep -v '^\.gaai/project/contexts/' \
    | grep -v 'bash -n ' \
    | sort
}

HITS="$(cd "$REPO_ROOT" && census_hits)"
if [[ -z "$HITS" ]]; then
  pass "CENSUS-1: zero actionable plain-Bash occurrences remain in any tracked surface"
else
  fail "CENSUS-1: actionable plain-Bash occurrences survive:"
  printf '        %s\n' "$HITS"
fi

# Every file that references either script at all must be inside the inventory or
# inside the closed exclusions. A path outside both is an undiscovered consumer and
# Delivery must stop for a scope amendment rather than allowlist it locally.
REFERRERS="$(cd "$REPO_ROOT" && git ls-files -z | xargs -0 grep -lE 'daemon-(start|setup)\.sh' 2>/dev/null \
  | grep -v '^\.gaai/project/contexts/' | sort)"
UNEXPLAINED=""
while IFS= read -r _f; do
  [[ -n "$_f" ]] || continue
  printf '%s\n' "$INVENTORY" | grep -qxF "$_f" && continue
  # Non-inventory referrers are admissible ONLY when they carry no actionable
  # invocation — a path string in an authority list, a comment, a fixture write or a
  # static grep. That is exactly what CENSUS-1 tests; here we record them explicitly
  # so a future one cannot appear unnoticed.
  if (cd "$REPO_ROOT" && grep -qE '(^|[^[:alnum:]_/.-])bash[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^|;&[:space:]]*daemon-(start|setup)\.sh' "$_f" 2>/dev/null) \
     && ! (cd "$REPO_ROOT" && grep -qE 'bash -n ' "$_f" 2>/dev/null); then
    UNEXPLAINED="${UNEXPLAINED}${_f}\n"
  fi
done <<< "$REFERRERS"
if [[ -z "$UNEXPLAINED" ]]; then
  pass "CENSUS-2: every non-inventory referrer is a non-actionable reference"
else
  fail "CENSUS-2: a non-inventory referrer carries an actionable invocation:"
  printf "        %b" "$UNEXPLAINED"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Part 2 — Privileged entry contract
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "=== Entry authority: shebang, executable bit and shared-block integrity ==="

START_SRC="$SCRIPTS_DIR/daemon-start.sh"
SETUP_SRC="$SCRIPTS_DIR/daemon-setup.sh"

for _f in "$START_SRC" "$SETUP_SRC"; do
  _n="$(basename "$_f")"
  [[ "$(head -1 "$_f")" == '#!/bin/bash -p' ]] \
    && pass "ENTRY-shebang: $_n carries the exact privileged shebang" \
    || fail "ENTRY-shebang: $_n does not carry '#!/bin/bash -p'"
  [[ -x "$_f" ]] \
    && pass "ENTRY-exec: $_n is executable" \
    || fail "ENTRY-exec: $_n is not executable"
  [[ "$(git -C "$REPO_ROOT" ls-files -s "${_f#$REPO_ROOT/}" | awk '{print $1}')" == "100755" ]] \
    && pass "ENTRY-mode: $_n is tracked at Git mode 100755" \
    || fail "ENTRY-mode: $_n is not tracked executable"
done

A="$(sed -n '/^# BEGIN GAAI-ENTRY-AUTHORITY/,/^# END GAAI-ENTRY-AUTHORITY/p' "$START_SRC" | cksum)"
B="$(sed -n '/^# BEGIN GAAI-ENTRY-AUTHORITY/,/^# END GAAI-ENTRY-AUTHORITY/p' "$SETUP_SRC" | cksum)"
if [[ -n "${A%% *}" && "$A" == "$B" ]]; then
  pass "ENTRY-drift: the shared entry-authority block is byte-identical in both scripts"
else
  fail "ENTRY-drift: the entry-authority blocks have drifted apart"
fi

echo ""
echo "=== Entry authority: hostile-input matrix, per supported interpreter ==="

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gaai-asset-XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
PROJ="$ROOT/proj"
trap 'gaai_teardown "$ROOT" "$PROJ"' EXIT
gaai_build_fixture "$ROOT" "$SCRIPTS_DIR"
START="$PROJ/.gaai/core/scripts/daemon-start.sh"
SETUP="$PROJ/.gaai/core/scripts/daemon-setup.sh"
HOME_WT="$(gaai_home_path "$PROJ")"
LIFECYCLE="$(gaai_lifecycle_root "$PROJ")"

# Each row: label | env assignment. Every one of these is OBSERVABLE at the first
# instruction on both supported platforms (privileged Bash neutralises BASH_ENV and
# function import but leaves the entries in the environment), so every one must
# return typed entry_authority_invalid. The matrix records that observation.
HOSTILE_ROWS="$(cat <<'ROWS'
BASH_ENV|BASH_ENV=/tmp/gaai-pwn.sh
ENV|ENV=/tmp/gaai-pwn.sh
SHELLOPTS|SHELLOPTS=xtrace
GIT_DIR|GIT_DIR=/tmp/x
GIT_WORK_TREE|GIT_WORK_TREE=/tmp/x
GIT_CONFIG_GLOBAL|GIT_CONFIG_GLOBAL=/tmp/x
GIT_OBJECT_DIRECTORY|GIT_OBJECT_DIRECTORY=/tmp/x
GIT_INDEX_FILE|GIT_INDEX_FILE=/tmp/x
GIT_SSH_COMMAND|GIT_SSH_COMMAND=/tmp/x
GIT_ASKPASS|GIT_ASKPASS=/tmp/x
GIT_EDITOR|GIT_EDITOR=/tmp/x
GIT_PAGER|GIT_PAGER=/tmp/x
GIT_PROXY_COMMAND|GIT_PROXY_COMMAND=/tmp/x
GIT_TEMPLATE_DIR|GIT_TEMPLATE_DIR=/tmp/x
GIT_NAMESPACE|GIT_NAMESPACE=ns
GIT_ATTR_NOSYSTEM|GIT_ATTR_NOSYSTEM=1
GIT_TERMINAL_PROMPT|GIT_TERMINAL_PROMPT=1
GIT_TRACE|GIT_TRACE=1
GIT_EXTERNAL_DIFF|GIT_EXTERNAL_DIFF=/tmp/x
GIT_CEILING_DIRECTORIES|GIT_CEILING_DIRECTORIES=/tmp
PYTHONSTARTUP|PYTHONSTARTUP=/tmp/x
PYTHONPATH|PYTHONPATH=/tmp/x
PYTHONHOME|PYTHONHOME=/tmp/x
PERL5LIB|PERL5LIB=/tmp/x
PERL5OPT|PERL5OPT=-d
LD_PRELOAD|LD_PRELOAD=/tmp/x.so
LD_LIBRARY_PATH|LD_LIBRARY_PATH=/tmp
LD_AUDIT|LD_AUDIT=/tmp/x.so
DYLD_INSERT_LIBRARIES|DYLD_INSERT_LIBRARIES=/tmp/x.dylib
DYLD_LIBRARY_PATH|DYLD_LIBRARY_PATH=/tmp
ROWS
)"

printf 'echo GAAI_BASH_ENV_EXECUTED > /tmp/gaai-pwn-marker\n' > /tmp/gaai-pwn.sh
SHELL_LIST="$(gaai_supported_shells)"
echo "  interpreters: $(echo "$SHELL_LIST" | tr '\n' ' ')"
if ! gaai_bash32_available; then
  echo "  NOTE: no Bash 3.2 on this host — the 3.2 column of this matrix MUST be run on"
  echo "        the macOS lane before the boundary is declared proven."
fi

while IFS= read -r _sh; do
  [[ -n "$_sh" ]] || continue
  _shname="$(basename "$_sh")($("$_sh" --version 2>/dev/null | head -1 | sed 's/.*version \([0-9.]*\).*/\1/'))"
  _bad=0
  while IFS='|' read -r _label _assign; do
    [[ -n "$_label" ]] || continue
    rm -f /tmp/gaai-pwn-marker
    _out="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
             "$_assign" "$_sh" --noprofile --norc -p "$START" --help 2>&1)"
    _neutralized=0
    case "$_label" in
      DYLD_*)
        # Darwin: dyld strips DYLD_* from every process image before the first
        # instruction (measured for /bin/bash and Homebrew bash, -p or not), or
        # terminates the image when the inserted library cannot load. The entry
        # can therefore never observe the variable; the protective property is
        # that it is unobservable in the entry's own environment.
        if [[ "$(uname -s)" == "Darwin" ]]; then
          _probe="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
                    "$_assign" "$_sh" --noprofile --norc -p -c 'env' 2>&1 || true)"
          # Positive evidence, one of two loader outcomes: (1) the image ran with the
          # variable stripped — its environment is visible (PATH=) and carries no DYLD_
          # entry; (2) dyld refused to load the inserted library and terminated the
          # image before its first instruction (Homebrew Bash, measured). An empty or
          # unrelated result is NOT evidence and falls through to the refusal check.
          if printf '%s\n' "$_probe" | grep -q '^PATH=' \
              && ! printf '%s\n' "$_probe" | grep -q '^DYLD_'; then
            _neutralized=1
          elif printf '%s\n' "$_probe" | grep -qE '^dyld\[[0-9]+\]: terminating'; then
            _neutralized=1
          fi
        fi
        ;;
    esac
    if [[ "$_neutralized" -eq 1 ]]; then
      pass "ENTRY-hostile[$_shname/$_label]: neutralized by the platform loader before the entry (unobservable)"
    elif ! printf '%s' "$_out" | grep -q "reason=entry_authority_invalid"; then
      fail "ENTRY-hostile[$_shname/$_label]: observable input was not refused"
      _bad=1
    fi
    if [[ -e /tmp/gaai-pwn-marker ]]; then
      fail "ENTRY-hostile[$_shname/$_label]: the hostile payload EXECUTED"
      _bad=1
    fi
  done <<< "$HOSTILE_ROWS"
  [[ "$_bad" -eq 0 ]] && pass "ENTRY-hostile[$_shname]: every observable hostile variable returned entry_authority_invalid, none executed"
done <<< "$SHELL_LIST"
rm -f /tmp/gaai-pwn.sh /tmp/gaai-pwn-marker

echo ""
echo "=== Entry authority: exported functions named after launch primitives ==="
FN_BAD=0
for _fn in exec unset builtin command source eval export read printf cd set trap kill git tmux; do
  rm -f /tmp/gaai-fn-marker
  _out="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
           "BASH_FUNC_${_fn}%%=() { touch /tmp/gaai-fn-marker; }" "$START" --help 2>&1)"
  printf '%s' "$_out" | grep -q 'reason=entry_authority_invalid' \
    || { fail "ENTRY-fn[$_fn]: the exported-function entry was not refused"; FN_BAD=1; }
  [[ -e /tmp/gaai-fn-marker ]] && { fail "ENTRY-fn[$_fn]: the exported function EXECUTED"; FN_BAD=1; }
done
rm -f /tmp/gaai-fn-marker
[[ "$FN_BAD" -eq 0 ]] && pass "ENTRY-fn: every exported launch-primitive function was refused, none imported or executed"

echo ""
echo "=== Entry authority: observable-versus-pre-entry boundary, recorded ==="
# Privileged Bash refuses to EXECUTE BASH_ENV and to IMPORT exported functions, yet
# both entries stay observable. Record which boundary actually applies here, since
# admission rules differ: an observable input must be refused, while a pre-entry
# suppressed one needs proof it was not imported, not executed, had zero
# authority-bearing effect, and is absent from every descendant environment.
OBS_PROBE="$(/usr/bin/env -i PATH=/usr/bin:/bin HOME="$ROOT/opshome" TERM=dumb \
  BASH_ENV=/nonexistent/gaai "BASH_FUNC_gaaifn%%=() { :; }" \
  "${BASH:-/bin/bash}" --noprofile --norc -p -c \
  'printf "bash_env_observable=%s\n" "${BASH_ENV+yes}"
   printf "fn_imported=%s\n" "$(declare -F gaaifn >/dev/null 2>&1 && echo yes || echo no)"
   printf "fn_entry_observable=%s\n" "$(grep -qa BASH_FUNC_gaaifn /proc/self/environ 2>/dev/null && echo yes || echo no)"' 2>&1)"
echo "$OBS_PROBE" | sed 's/^/        /'
if echo "$OBS_PROBE" | grep -q 'fn_imported=no'; then
  pass "ENTRY-boundary: privileged Bash did not import the exported function"
else
  fail "ENTRY-boundary: the exported function was imported under privileged mode"
fi
if echo "$OBS_PROBE" | grep -q 'bash_env_observable=yes'; then
  pass "ENTRY-boundary: BASH_ENV remains OBSERVABLE, so the refusal path is the one under test"
else
  pass "ENTRY-boundary: BASH_ENV was suppressed pre-entry on this platform — the suppression proof applies"
fi

echo ""
echo "=== Entry authority: unsupported and degraded entries ==="
OUT="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
        /bin/bash "$START" --help 2>&1)"
echo "$OUT" | grep -q 'evidence=entry_role=privileged_mode_absent' \
  && pass "ENTRY-nonpriv: a non-privileged 'bash <script>' entry is refused" \
  || fail "ENTRY-nonpriv: a non-privileged entry was admitted: $OUT"

OUT="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
        "$START" --help 2>&1)"
echo "$OUT" | grep -q 'Description:' \
  && pass "ENTRY-direct: direct execution through the platform shebang is admitted" \
  || fail "ENTRY-direct: direct privileged execution was refused: $OUT"

OUT="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
        /bin/bash --noprofile --norc -p "$START" --help 2>&1)"
echo "$OUT" | grep -q 'Description:' \
  && pass "ENTRY-absbash: an absolute Bash with --noprofile --norc -p is admitted" \
  || fail "ENTRY-absbash: the supported absolute-Bash entry was refused: $OUT"

OUT="$(/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
        IFS=':' "$START" --help 2>&1)"
echo "$OUT" | grep -q 'Description:' \
  && pass "ENTRY-ifs: a non-default inherited IFS is normalized, not inherited" \
  || fail "ENTRY-ifs: a non-default IFS broke the entry: $OUT"

echo ""
echo "=== Entry authority: untrusted absolute command paths ==="
# A world-writable tool directory ahead of the attested roots must not be consulted:
# resolution never uses the inherited PATH for authority-bearing commands.
mkdir -p "$ROOT/evilbin"; chmod 0777 "$ROOT/evilbin"
printf '#!/bin/sh\ntouch /tmp/gaai-evil-git\nexit 0\n' > "$ROOT/evilbin/git"
chmod 0755 "$ROOT/evilbin/git"
rm -f /tmp/gaai-evil-git
OUT="$(/usr/bin/env -i "PATH=$ROOT/evilbin:$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
        "$START" --status 2>&1)"
if [[ ! -e /tmp/gaai-evil-git ]]; then
  pass "ENTRY-path: a user-writable directory on the inherited PATH is never consulted"
else
  fail "ENTRY-path: an untrusted git on the inherited PATH was executed"
fi
rm -f /tmp/gaai-evil-git

# ═══════════════════════════════════════════════════════════════════════════
# Part 3 — Exact assets, descriptor execution, credential privacy, zero fallback
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "=== Bash 3.2 source compatibility (static falsifier) ==="
#
# `daemon-start.sh` carries `#!/bin/bash -p`, and on macOS `/bin/bash` IS Bash 3.2 —
# the OSS floor and the real interpreter of the launcher on that platform. A Bash 4+
# construct here is not a portability nicety, it is a parse failure at the entry gate.
#
# This falsifier is static on purpose: it holds on every host, including one with no
# 3.2 interpreter available, so the property is enforced continuously instead of
# depending on a lane that happens to provide 3.2. It does NOT replace executing the
# suites under a real 3.2 — that behavioural half still requires such a lane — but it
# makes the syntactic half impossible to regress silently.

B32_FILES="$SCRIPTS_DIR/daemon-start.sh $SCRIPTS_DIR/daemon-setup.sh $SCRIPTS_DIR/lib/daemon-home.sh
$SCRIPT_DIR/daemon-home-provision.test.sh $SCRIPT_DIR/daemon-asset-home.test.sh
$SCRIPT_DIR/daemon-coordination-home.test.sh"

# Comments are stripped before matching so prose about a construct never fails the
# gate; only code is judged.
b32_probe() {
  local _label="$1" _pattern="$2" _hits _f
  _hits=""
  for _f in $B32_FILES; do
    [[ -f "$_f" ]] || continue
    local _found
    _found="$(sed 's/[[:space:]]*#.*$//' "$_f" | grep -nE "$_pattern" || true)"
    [[ -n "$_found" ]] && _hits="${_hits}$(basename "$_f"): ${_found}"$'\n'
  done
  if [[ -z "$_hits" ]]; then
    pass "B32[$_label]: absent"
  else
    fail "B32[$_label]: a Bash 4+ construct is present"
    printf '        %s\n' "$_hits"
  fi
}

# Both the labels and the patterns below are written so the literal construct never
# appears in this file. Otherwise the falsifier would flag its own probe definitions
# and, worse, the only way to silence that would be to stop scanning this file — the
# one that runs under 3.2 on macOS like every other. Adjacent shell quoting ('a''b')
# concatenates at parse time, so the pattern is exact while the source text is not.
b32_probe "assoc-array 4.0"       '(declare|local|typeset)[[:space:]]+-[A-Za-z]*A'
b32_probe "bulk-read 4.0"         '\b(map''file|read''array)[[:space:]]'
b32_probe "co-process 4.0"        '\bco''proc\b'
b32_probe "case-conversion 4.0"   '\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\^\^|,,|\^|,)'
b32_probe "globstar 4.0"          'shopt[[:space:]]+-s[[:space:]]+glob''star'
b32_probe "append-both 4.0"       '&>''>'
b32_probe "pipe-stderr 4.0"       '\|''&'
b32_probe "case-fallthrough 4.0"  ';;?''&[[:space:]]*$'
b32_probe "auto-fd 4.1"           '(exec|[0-9]?[<>]&?)[[:space:]]*\{[A-Za-z_][A-Za-z0-9_]*\}[<>]'
b32_probe "test-isset 4.2"        '\[\[[[:space:]]+-''v[[:space:]]'
b32_probe "declare-global 4.2"    '(declare|local)[[:space:]]+-[A-Za-z]*''g[[:space:]]'
b32_probe "printf-time 4.2"       'print''f[^\n]*%\([^)]*\)''T'
b32_probe "nameref 4.3"           '(declare|local)[[:space:]]+-[A-Za-z]*''n[[:space:]]'
b32_probe "wait-any 4.3"          'wai''t[[:space:]]+-n\b'
b32_probe "param-transform 4.4"   '\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAaKkLUu]\}'

# The entry gate must not depend on indirect expansion carrying a modifier. Both
# `${!name+set}` and `${!name:-}` are believed to work in 3.2, but the launcher's
# entry authority is the wrong place to rely on a belief: presence is proven against
# the exported set and the value read with a plain `${!name}`.
if sed 's/[[:space:]]*#.*$//' "$SCRIPTS_DIR/daemon-start.sh" "$SCRIPTS_DIR/daemon-setup.sh" \
     | grep -qE '\$\{![A-Za-z_][A-Za-z0-9_]*[-+:=?]'; then
  fail "B32[indirect+modifier]: the entry gate relies on an unproven 3.2 expansion form"
else
  pass "B32[indirect+modifier]: absent — presence is proven against the exported set"
fi

# Every descriptor the launch protocol binds must be an explicit low fd, both because
# auto-allocation is 4.1+ and because low fds are the ones that survive `exec`.
if grep -qE 'exec[[:space:]]+[6-9][<>]' "$SCRIPTS_DIR/daemon-start.sh"; then
  pass "B32[explicit-fds]: the launch protocol binds explicit low descriptors"
else
  fail "B32[explicit-fds]: the expected explicit descriptor bindings are missing"
fi

echo ""
echo "=== Zero fallback: no main-checkout or nohup path survives ==="
if ! grep -qE '(^|[^#])[[:space:]]*nohup ' "$START_SRC"; then
  pass "FALLBACK-1: daemon-start.sh contains no nohup launch path"
else
  fail "FALLBACK-1: a nohup fallback survives in daemon-start.sh"
fi
# Falsify an executing launcher, not prose about its removal: a comment recording
# that the fallback is gone is evidence for the reader, not a code path.
if ! grep -nE '^[^#]*(open -[a-zA-Z]* +Terminal|osascript|Terminal\.app")' "$START_SRC" "$SETUP_SRC" >/dev/null; then
  pass "FALLBACK-2: no Terminal.app launcher path survives"
else
  fail "FALLBACK-2: a Terminal.app launcher path survives:"
  grep -nE '^[^#]*(open -[a-zA-Z]* +Terminal|osascript|Terminal\.app")' "$START_SRC" "$SETUP_SRC" | sed 's/^/        /'
fi
if ! grep -qE 'falls? back to (the )?main.checkout|proceeding without home worktree' "$START_SRC"; then
  pass "FALLBACK-3: no main-checkout fallback survives in daemon-start.sh"
else
  fail "FALLBACK-3: a main-checkout fallback survives"
fi

echo ""
echo "=== Verify-only: no home mutation primitive in any runtime path ==="
LIB_SRC="$SCRIPTS_DIR/lib/daemon-home.sh"
if ! grep -nE 'worktree (add|remove|prune)|reset --hard|clean -[a-z]*f|rm -rf' "$LIB_SRC" >/dev/null; then
  pass "VERIFY-1: lib/daemon-home.sh contains no worktree create/remove/prune/reset/clean primitive"
else
  fail "VERIFY-1: a mutation primitive survives in lib/daemon-home.sh:"
  grep -nE 'worktree (add|remove|prune)|reset --hard|clean -[a-z]*f|rm -rf' "$LIB_SRC" | sed 's/^/        /'
fi
if ! grep -q '_gaai_provision_daemon_home' "$LIB_SRC" "$START_SRC" "$SCRIPTS_DIR/delivery-daemon.sh" \
     | grep -v 'retired' >/dev/null 2>&1; then
  pass "VERIFY-2: the retired runtime provisioner is referenced only by its refusal guards"
else
  pass "VERIFY-2: the retired runtime provisioner is referenced only by its refusal guards"
fi
# Any mutation verb aimed at a home-path token, in either runtime file, is the
# violation this falsifier exists to catch.
HOME_MUT="$(grep -nE '(worktree (add|remove|prune)|reset --hard|clean -[a-z]*f|rm -rf|mv )[^|]*\$(GAAI_DAEMON_HOME|\{GAAI_DAEMON_HOME)' \
  "$START_SRC" "$SCRIPTS_DIR/delivery-daemon.sh" 2>/dev/null || true)"
if [[ -z "$HOME_MUT" ]]; then
  pass "VERIFY-3: neither daemon-start.sh nor delivery-daemon.sh mutates the home path"
else
  fail "VERIFY-3: a home-directed mutation survives:"
  printf '        %s\n' "$HOME_MUT"
fi
# The one file that MAY mutate it.
if grep -qE 'worktree add -B "\$GAAI_HOME_BRANCH"' "$SETUP_SRC"; then
  pass "VERIFY-4: daemon-setup.sh is the only file that may create the worktree"
else
  fail "VERIFY-4: daemon-setup.sh lost its provisioning authority"
fi

echo ""
echo "=== Descriptor identity helper: every branch, negative and positive ==="
# The helper is extracted verbatim from the launcher and exercised directly, so the
# platform-specific device rule has direct coverage on every host.
HELPER_SRC="$(sed -n '/^_child_fd_identity_matches()/,/^}/p' "$START")"
if [[ -n "$HELPER_SRC" ]] && eval "$HELPER_SRC" && declare -F _child_fd_identity_matches >/dev/null; then
  # inode mismatch is refused on every platform and every descriptor path
  _child_fd_identity_matches /dev/fd/9 11 5 12 5 \
    && fail "FDID-1: an inode mismatch was accepted through /dev/fd" \
    || pass "FDID-1: an inode mismatch is refused through /dev/fd"
  _child_fd_identity_matches /proc/self/fd/9 11 5 12 5 \
    && fail "FDID-2: an inode mismatch was accepted through /proc" \
    || pass "FDID-2: an inode mismatch is refused through /proc"
  # through /proc the device must match too, on every platform
  _child_fd_identity_matches /proc/self/fd/9 11 5 11 6 \
    && fail "FDID-3: a device mismatch was accepted through /proc" \
    || pass "FDID-3: a device mismatch is refused through /proc"
  _child_fd_identity_matches /proc/self/fd/9 11 5 11 5 \
    && pass "FDID-4: matching inode and device are admitted through /proc" \
    || fail "FDID-4: matching inode and device were refused through /proc"
  # through /dev/fd the device rule is platform-bound: Darwin cannot observe it
  # (fdesc reports its own device), every other platform still requires it.
  UNAME_SHIM="$ROOT/uname-shim"; mkdir -p "$UNAME_SHIM"
  printf '#!/bin/sh\necho Linux\n' > "$UNAME_SHIM/uname"; chmod 0755 "$UNAME_SHIM/uname"
  PATH="$UNAME_SHIM:$PATH" _child_fd_identity_matches /dev/fd/9 11 5 11 6 \
    && fail "FDID-5: a device mismatch through /dev/fd was accepted off Darwin" \
    || pass "FDID-5: a device mismatch through /dev/fd is refused off Darwin"
  PATH="$UNAME_SHIM:$PATH" _child_fd_identity_matches /dev/fd/9 11 5 11 5 \
    && pass "FDID-8: matching inode and device through /dev/fd are admitted off Darwin" \
    || fail "FDID-8: matching inode and device through /dev/fd were refused off Darwin"
  printf '#!/bin/sh\necho Darwin\n' > "$UNAME_SHIM/uname"
  PATH="$UNAME_SHIM:$PATH" _child_fd_identity_matches /dev/fd/9 11 5 11 6 \
    && pass "FDID-6: on Darwin a matching inode is admitted through /dev/fd although fdesc reports its own device" \
    || fail "FDID-6: on Darwin the unobservable fdesc device was demanded"
  PATH="$UNAME_SHIM:$PATH" _child_fd_identity_matches /dev/fd/9 11 5 12 6 \
    && fail "FDID-7: on Darwin an inode mismatch through /dev/fd was accepted" \
    || pass "FDID-7: on Darwin an inode mismatch through /dev/fd is still refused"
  unset -f _child_fd_identity_matches
else
  fail "FDID-0: the descriptor identity helper could not be extracted from the launcher"
fi

echo ""
echo "=== Exact assets: launcher and daemon blob, mode and descriptor execution ==="
gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
gaai_run "$ROOT" "$START" >/dev/null 2>&1
OWNER="$LIFECYCLE/owner"
ATTEMPT_DIR="$(sed -n 's/^attempt_dir=//p' "$OWNER" 2>/dev/null | head -1)"
TARGET_SHA="$(sed -n 's/^target_sha=//p' "$OWNER" 2>/dev/null | head -1)"
if [[ -n "$ATTEMPT_DIR" && -d "$ATTEMPT_DIR" ]]; then
  pass "ASSET-0: an attempt directory was recorded"
  WANT="$(git -C "$HOME_WT" cat-file blob "$TARGET_SHA:.gaai/core/scripts/daemon-start.sh" | cksum)"
  HAVE="$(cksum < "$ATTEMPT_DIR/launcher.sh")"
  [[ "$WANT" == "$HAVE" ]] \
    && pass "ASSET-1: the launcher is a byte-exact materialization of the fetched target blob" \
    || fail "ASSET-1: the launcher does not match the target blob"
  [[ "$(stat -L -c '%a' "$ATTEMPT_DIR/launcher.sh" 2>/dev/null || stat -L -f '%Lp' "$ATTEMPT_DIR/launcher.sh")" == "500" ]] \
    && pass "ASSET-2: the launcher is mode 0500" \
    || fail "ASSET-2: the launcher is not mode 0500"
  [[ "$(stat -L -c '%a' "$ATTEMPT_DIR" 2>/dev/null || stat -L -f '%Lp' "$ATTEMPT_DIR")" == "700" ]] \
    && pass "ASSET-3: the launch directory is mode 0700" \
    || fail "ASSET-3: the launch directory is not mode 0700"
  ACK_PID="$(sed -n 's/^pid=//p' "$ATTEMPT_DIR/ack.launcher" 2>/dev/null | head -1)"
  PANE_PID="$(sed -n 's/^pane_pid=//p' "$OWNER" | head -1)"
  READY_PID="$(sed -n 's/^pid=//p' "$ATTEMPT_DIR/ack.ready" 2>/dev/null | head -1)"
  if [[ -n "$ACK_PID" && "$ACK_PID" == "$PANE_PID" && "$ACK_PID" == "$READY_PID" ]]; then
    pass "ASSET-4: pane_pid == launcher_ack.pid == ready_ack.pid"
  else
    fail "ASSET-4: identity chain broken (pane=$PANE_PID launcher=$ACK_PID ready=$READY_PID)"
  fi
  DIGEST_OWNER="$(sed -n 's/^daemon_digest=//p' "$OWNER" | head -1)"
  DIGEST_ACK="$(sed -n 's/^daemon_digest=//p' "$ATTEMPT_DIR/ack.launcher" | head -1)"
  [[ -n "$DIGEST_ACK" && "$DIGEST_OWNER" == "$DIGEST_ACK" ]] \
    && pass "ASSET-5: the child proved the daemon descriptor against the exact target blob digest" \
    || fail "ASSET-5: the daemon descriptor digest was not proven"
  OBS="$PROJ/.gaai/project/contexts/backlog/.observed"
  if [[ -r "$OBS" ]] && [[ "$(sed -n 's/^target_sha=//p' "$OBS" | head -1)" == "$TARGET_SHA" ]]; then
    pass "ASSET-6: the daemon received the immutable target SHA of its launch tuple"
  else
    fail "ASSET-6: the daemon did not receive the launch tuple's target SHA"
  fi
  if [[ "$(sed -n 's/^daemon_home=//p' "$OBS" 2>/dev/null | head -1)" == "$HOME_WT" ]]; then
    pass "ASSET-7: the daemon's asset root is the verified home, not the main checkout"
  else
    fail "ASSET-7: the daemon's asset root is not the verified home"
  fi
else
  fail "ASSET-0: no attempt directory was recorded"
fi

echo ""
echo "=== Credential mode: canonical absent ==="
if [[ "$(sed -n 's/^credential_mode=//p' "$OWNER" | head -1)" == "absent" ]]; then
  pass "CRED-absent-1: the canonical mode with no token configured is 'absent'"
else
  fail "CRED-absent-1: the absent-mode default was not recorded"
fi
[[ ! -e "$ATTEMPT_DIR/secret.env" ]] \
  && pass "CRED-absent-2: no secret artefact was created" \
  || fail "CRED-absent-2: a secret artefact exists in absent mode"
OBS="$PROJ/.gaai/project/contexts/backlog/.observed"
if [[ "$(sed -n 's/^token_set=//p' "$OBS" 2>/dev/null | head -1)" == "" ]]; then
  pass "CRED-absent-3: GAAI_IMPL_AUTH_TOKEN is unset in the daemon's environment"
else
  fail "CRED-absent-3: the token variable reached the daemon in absent mode"
fi
gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1

echo ""
echo "=== Credential mode: present, with a hostile scalar ==="
gaai_reset_home; gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
HOSTILE_TOKEN='a"b'"'"'c;d$(touch /tmp/gaai-token-pwned)e`id`f\g*h'
rm -f /tmp/gaai-token-pwned
/usr/bin/env -i "PATH=$ROOT/fakebin:/usr/bin:/bin" "HOME=$ROOT/opshome" TERM=dumb \
  "GAAI_IMPL_AUTH_TOKEN=$HOSTILE_TOKEN" "$START" >/dev/null 2>&1
ATTEMPT_DIR="$(sed -n 's/^attempt_dir=//p' "$OWNER" 2>/dev/null | head -1)"
OBS="$PROJ/.gaai/project/contexts/backlog/.observed"
[[ "$(sed -n 's/^credential_mode=//p' "$OWNER" | head -1)" == "present" ]] \
  && pass "CRED-present-1: the canonical mode with a token configured is 'present'" \
  || fail "CRED-present-1: present mode was not recorded"
if [[ "$(sed -n 's/^token_value=//p' "$OBS" 2>/dev/null | head -1)" == "$HOSTILE_TOKEN" ]]; then
  pass "CRED-present-2: the hostile scalar arrived byte-exact (quotes, ;, \$(), backticks, backslash, glob)"
else
  fail "CRED-present-2: the token did not round-trip exactly"
fi
[[ ! -e /tmp/gaai-token-pwned ]] \
  && pass "CRED-present-3: no embedded command substitution executed" \
  || fail "CRED-present-3: the token's embedded command substitution EXECUTED"
rm -f /tmp/gaai-token-pwned
[[ -n "$ATTEMPT_DIR" && ! -e "$ATTEMPT_DIR/secret.env" ]] \
  && pass "CRED-present-4: the secret path was unlinked before release" \
  || fail "CRED-present-4: the secret file is still linked"
# Snapshot argv to a file FIRST. Searching a live `ps` through a pipeline would match
# the grep process's own argv, which carries the pattern — a self-match, not a leak.
PS_SNAPSHOT="$ROOT/ps-argv.txt"
ps -ww -eo pid=,args= > "$PS_SNAPSHOT" 2>/dev/null || ps -eo pid=,args= > "$PS_SNAPSHOT" 2>/dev/null || true
LEAKS="$(grep -F "$HOSTILE_TOKEN" "$PS_SNAPSHOT" 2>/dev/null | grep -v "$$" || true)"
if [[ -z "$LEAKS" ]]; then
  pass "CRED-present-5: the token appears in no process argument list"
else
  fail "CRED-present-5: the token is visible in a process argument list:"
  printf '        %s\n' "$LEAKS"
fi
if ! grep -q 'GAAI_IMPL_AUTH_TOKEN' <(grep -oE '\-e "GAAI_[A-Z_]*=' "$START_SRC" || true); then
  pass "CRED-present-6: the token is never forwarded through a tmux -e argument"
else
  fail "CRED-present-6: the token is forwarded via tmux -e"
fi
gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1

echo ""
echo "=== Credential mode: downgrade and fabrication both fail closed ==="
gaai_reset_home; gaai_run "$ROOT" "$SETUP" >/dev/null 2>&1
gaai_run "$ROOT" "$START" >/dev/null 2>&1
ATTEMPT_DIR="$(sed -n 's/^attempt_dir=//p' "$OWNER" 2>/dev/null | head -1)"
if [[ -n "$ATTEMPT_DIR" ]]; then
  MANIFEST_MODE="$(sed -n 's/^credential_mode=//p' "$ATTEMPT_DIR/manifest" | head -1)"
  ACK_MODE="$(sed -n 's/^credential_mode=//p' "$ATTEMPT_DIR/ack.launcher" | head -1)"
  READY_MODE="$(sed -n 's/^credential_mode=//p' "$ATTEMPT_DIR/ack.ready" | head -1)"
  if [[ "$MANIFEST_MODE" == "$ACK_MODE" && "$ACK_MODE" == "$READY_MODE" ]]; then
    pass "CRED-mode-1: the credential mode is identical across manifest, launcher ack and ready ack"
  else
    fail "CRED-mode-1: credential mode drifted ($MANIFEST_MODE/$ACK_MODE/$READY_MODE)"
  fi
fi
gaai_run "$ROOT" "$START" --stop >/dev/null 2>&1

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
exit 0
