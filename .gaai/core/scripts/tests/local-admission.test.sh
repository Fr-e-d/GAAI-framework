#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTOR="$SCRIPT_DIR/lib/local-admission-executor.mjs"
source "$SCRIPT_DIR/lib/local-admission.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gaai-local-admission-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
REMOTE="$ROOT/remote.git"; REPO="$ROOT/repo"; RECEIPTS="$ROOT/receipts"
POLICY_REL="policy/local-admission.json"; RISK="$ROOT/risk.json"
git init -q --bare "$REMOTE"; git init -q "$REPO"
git -C "$REPO" config user.email fixture@example.invalid
git -C "$REPO" config user.name 'Admission Fixture'
git -C "$REPO" config core.hooksPath /dev/null
git -C "$REPO" switch -qc staging; git -C "$REPO" remote add origin "$REMOTE"
mkdir -p "$REPO/policy" "$REPO/src" "$REPO/checks" "$REPO/docs"
printf 'lockfileVersion: 9\n' > "$REPO/pnpm-lock.yaml"
printf '# docs\n' > "$REPO/docs/readme.md"
printf 'export const value = 1;\n' > "$REPO/src/value.mjs"
cat > "$REPO/checks/unit.sh" <<'EOF'
#!/usr/bin/env bash
printf 'token=do-not-store-me\n'
[[ "${1:-}" == '; touch /tmp/gaai-admission-pwned' ]]
EOF
chmod +x "$REPO/checks/unit.sh"
node - "$REMOTE" > "$REPO/$POLICY_REL" <<'NODE'
const remote = process.argv[2];
process.stdout.write(`${JSON.stringify({
  schema_version:'1.0.0', policy_version:'fixture-v1',
  repository:{remote,base_ref:'staging'},
  limits:{max_policy_bytes:65536,max_diff_bytes:65536,max_changed_paths:32,max_commands:4,
    max_selectors:4,max_identifier_bytes:64,max_arguments_per_command:8,max_argument_bytes:256},
  commands:[{id:'unit',argv:['bash','checks/unit.sh','; touch /tmp/gaai-admission-pwned'],
    timeout_seconds:5,output_limit_bytes:8,config_paths:['checks/unit.sh'],enabled:true}],
  selectors:[{id:'source',path_prefixes:['src'],command_ids:['unit']},
    {id:'checks',path_prefixes:['checks'],command_ids:['unit']}],
  exhaustive_command_ids:['unit'],non_executable_prefixes:['docs'],
  broadening_prefixes:['policy','package.json'],dependency_inputs:['pnpm-lock.yaml'],
  risk_input_policy:{allowed_boolean_keys:['cross_cutting'],exhaustive_when_true:['cross_cutting']},
  required_environment:['GAAI_TEST_PLATFORM']
}, null, 2)}\n`);
NODE
git -C "$REPO" add -A; git -C "$REPO" commit -qm base
git -C "$REPO" push -q origin staging; git -C "$REPO" fetch -q origin staging
BASE_SHA="$(git -C "$REPO" rev-parse origin/staging)"
git -C "$REPO" switch -qc story/test
printf 'export const value = 2;\n' > "$REPO/src/value.mjs"
git -C "$REPO" add -A; git -C "$REPO" commit -qm candidate
printf '{"cross_cutting":false}\n' > "$RISK"
export GAAI_TEST_PLATFORM=fixture
export GAAI_LOCAL_ADMISSION_POLICY_PATH="$POLICY_REL"
export GAAI_LOCAL_ADMISSION_RISK_INPUTS_PATH="$RISK"
export GAAI_LOCAL_ADMISSION_MAX_RECEIPT_BYTES=65536

rm -f /tmp/gaai-admission-pwned
if _run_local_admission pre_qa TST-LA "$REPO" staging "$RECEIPTS" >/dev/null; then
  PRE="$LOCAL_ADMISSION_RECEIPT_PATH"
  if [[ "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(r.publication_admitted))' "$PRE")" == false \
    && "$(node -e 'const r=require(process.argv[1]);process.stdout.write(`${r.results[0].stdout_bytes}|${r.results[0].stdout_truncated}`)' "$PRE")" == '8|true' \
    && ! -e /tmp/gaai-admission-pwned ]] && ! grep -q 'do-not-store-me' "$PRE"; then
    pass 'pre-QA PASS executes injection-shaped argv without shell and stores no output'
  else fail 'pre-QA privacy or argv execution contract'; fi
else fail "pre-QA expected PASS, got $LOCAL_ADMISSION_OUTCOME"; fi

if _run_local_admission final TST-LA "$REPO" staging "$RECEIPTS" >/dev/null; then
  FINAL="$LOCAL_ADMISSION_RECEIPT_PATH"
  node --input-type=module - "$EXECUTOR" "$FINAL" <<'NODE'
import { createHash } from 'node:crypto';
const { canonicalJson, sealReceipt } = await import(process.argv[2]);
const receipt = JSON.parse(await (await import('node:fs/promises')).readFile(process.argv[3], 'utf8'));
const claimed = receipt.receipt_digest; delete receipt.receipt_digest;
if (claimed !== createHash('sha256').update(canonicalJson(receipt)).digest('hex')) process.exit(1);
const plan={status:'rejected',summary:{}};
const forged=JSON.parse(sealReceipt({boundary:'pre_qa',storyId:'T',plan,results:[],
  resultsDigest:createHash('sha256').update('[]').digest('hex'),outcome:'blocked:command_failed',
  publicationAdmitted:true,maxBytes:65536}));
if (forged.publication_admitted) process.exit(2);
const binding={head_sha:'0'.repeat(40)};
const resolved={status:'resolved',binding,binding_digest:createHash('sha256').update(canonicalJson(binding)).digest('hex'),
  selected_commands:[{id:'unit',descriptor_digest:'d',configuration_digest:'c',output_limit_bytes:8}],summary:{}};
try {
  sealReceipt({boundary:'final',storyId:'T',plan:resolved,results:[],
    resultsDigest:createHash('sha256').update('[]').digest('hex'),outcome:'pass',
    expectedBindingDigest:resolved.binding_digest,maxBytes:65536});
  process.exit(3);
} catch (error) { if (error.message !== 'evidence_invalid') process.exit(4); }
NODE
  if [[ $? -eq 0 && "$FINAL" != "$PRE" \
    && "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(r.publication_admitted))' "$FINAL")" == true ]]; then
    pass 'final receipt alone admits publication and its canonical self-digest verifies'
  else fail 'final receipt boundary or digest'; fi
else fail "final expected PASS, got $LOCAL_ADMISSION_OUTCOME"; fi

SAVED_FINAL="$FINAL"
unset GAAI_LOCAL_ADMISSION_RISK_INPUTS_PATH
if ! _run_local_admission final TST-LA "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:risk_inputs_missing && ! -e "$SAVED_FINAL" ]]; then
  pass 'an early failure removes any prior PASS receipt for that boundary'
else fail 'stale final receipt survived an early failure'; fi
export GAAI_LOCAL_ADMISSION_RISK_INPUTS_PATH="$RISK"

GAAI_DAEMON_EXECUTOR=claude _run_local_admission pre_qa TST-C "$REPO" staging "$RECEIPTS" >/dev/null
C_BINDING="$(node -e 'const r=require(process.argv[1]);process.stdout.write(r.binding_digest)' "$LOCAL_ADMISSION_RECEIPT_PATH")"
GAAI_DAEMON_EXECUTOR=codex _run_local_admission pre_qa TST-D "$REPO" staging "$RECEIPTS" >/dev/null
D_BINDING="$(node -e 'const r=require(process.argv[1]);process.stdout.write(r.binding_digest)' "$LOCAL_ADMISSION_RECEIPT_PATH")"
[[ "$C_BINDING" == "$D_BINDING" ]] && pass 'Claude/Codex choice is admission-neutral' \
  || fail 'executor choice changed the binding'

ADVANCE="$ROOT/advance"
git clone -q --branch staging "$REMOTE" "$ADVANCE"
git -C "$ADVANCE" config user.email fixture@example.invalid
git -C "$ADVANCE" config user.name 'Admission Fixture'
printf '# advanced during check\n' >> "$ADVANCE/docs/readme.md"
git -C "$ADVANCE" add -A; git -C "$ADVANCE" commit -qm base-advance
git -C "$REPO" switch -q staging; git -C "$REPO" reset -q --hard origin/staging
git -C "$REPO" switch -qC story/base-advance
cat > "$REPO/checks/unit.sh" <<'EOF'
#!/usr/bin/env bash
git -C "$GAAI_ADVANCE_REPO" push -q origin HEAD:staging
EOF
chmod +x "$REPO/checks/unit.sh"
git -C "$REPO" add -A; git -C "$REPO" commit -qm advancing-command
export GAAI_ADVANCE_REPO="$ADVANCE"
if ! _run_local_admission final TST-BASE "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:stale_evidence ]]; then
  pass 'second fetch rejects a base advanced while checks execute'
else fail "base-currentness outcome=$LOCAL_ADMISSION_OUTCOME"; fi
git -C "$REPO" push -q --force origin "$BASE_SHA:staging"
git -C "$REPO" fetch -q origin staging
unset GAAI_ADVANCE_REPO

git -C "$REPO" switch -q staging; git -C "$REPO" reset -q --hard origin/staging
git -C "$REPO" switch -qC story/unresolved
mkdir -p "$REPO/unknown"; printf 'unknown\n' > "$REPO/unknown/surface.txt"
git -C "$REPO" add -A; git -C "$REPO" commit -qm unresolved-surface
if ! _run_local_admission pre_qa TST-RESOLVE "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:unknown_executable_surface \
    && -s "$LOCAL_ADMISSION_RECEIPT_PATH" \
    && "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(r.publication_admitted))' "$LOCAL_ADMISSION_RECEIPT_PATH")" == false ]]; then
  pass 'resolver rejection emits a bounded non-publication receipt'
else fail "resolver-rejection outcome=$LOCAL_ADMISSION_OUTCOME"; fi

git -C "$REPO" switch -q staging; git -C "$REPO" reset -q --hard origin/staging
git -C "$REPO" switch -qC story/fail
printf '#!/usr/bin/env bash\nexit 9\n' > "$REPO/checks/unit.sh"; chmod +x "$REPO/checks/unit.sh"
git -C "$REPO" add -A; git -C "$REPO" commit -qm failing-command
if ! _run_local_admission final TST-FAIL "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:command_failed \
    && "$(node -e 'const r=require(process.argv[1]);process.stdout.write(String(r.publication_admitted))' "$LOCAL_ADMISSION_RECEIPT_PATH")" == false ]]; then
  pass 'failed command yields a bounded non-publication receipt'
else fail "failed command outcome=$LOCAL_ADMISSION_OUTCOME"; fi

git -C "$REPO" reset -q --hard origin/staging; git -C "$REPO" switch -qC story/mutate
printf '#!/usr/bin/env bash\nprintf mutation >> src/mutated.txt\n' > "$REPO/checks/unit.sh"; chmod +x "$REPO/checks/unit.sh"
git -C "$REPO" add -A; git -C "$REPO" commit -qm mutating-command
if ! _run_local_admission final TST-STALE "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:stale_evidence ]]; then
  pass 'command-side candidate mutation invalidates evidence'
else fail "mutation outcome=$LOCAL_ADMISSION_OUTCOME"; fi
git -C "$REPO" reset -q --hard HEAD
rm -f "$REPO/src/mutated.txt"

git -C "$REPO" reset -q --hard origin/staging; git -C "$REPO" switch -qC story/late-mutate
node - "$REPO" "$RECEIPTS/.local-admission-TST-LATE-final.json" > "$REPO/checks/unit.sh" <<'NODE'
const [repo, receipt] = process.argv.slice(2);
const worker = `const fs=require('fs');const [repo,receipt]=process.argv.slice(1);const end=Date.now()+5000;(function poll(){if(fs.existsSync(receipt)){fs.writeFileSync(repo+'/src/late.txt','late');return}if(Date.now()<end)setTimeout(poll,5)})()`;
const launcher = `require('child_process').spawn(process.execPath,['-e',${JSON.stringify(worker)},${JSON.stringify(repo)},${JSON.stringify(receipt)}],{detached:true,stdio:'ignore'}).unref()`;
process.stdout.write(`#!/usr/bin/env bash\nnode -e ${JSON.stringify(launcher)}\n`);
NODE
chmod +x "$REPO/checks/unit.sh"; git -C "$REPO" add -A; git -C "$REPO" commit -qm late-mutating-command
if ! _run_local_admission final TST-LATE "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:stale_evidence && -z "$LOCAL_ADMISSION_RECEIPT_PATH" ]]; then
  pass 'post-seal re-resolution removes evidence changed by an escaped late helper'
else fail "late-mutation outcome=$LOCAL_ADMISSION_OUTCOME"; fi
rm -f "$REPO/src/late.txt"
git -C "$REPO" reset -q --hard origin/staging; git -C "$REPO" switch -qC story/size
printf 'export const value = 3;\n' > "$REPO/src/value.mjs"
git -C "$REPO" add -A; git -C "$REPO" commit -qm size-candidate

GAAI_LOCAL_ADMISSION_MAX_RECEIPT_BYTES=32
if ! _run_local_admission final TST-SIZE "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:receipt_too_large && -z "$LOCAL_ADMISSION_RECEIPT_PATH" ]]; then
  pass 'post-digest receipt size overflow is non-authorizing'
else fail "receipt size outcome=$LOCAL_ADMISSION_OUTCOME"; fi
export GAAI_LOCAL_ADMISSION_MAX_RECEIPT_BYTES=65536

node --input-type=module - "$EXECUTOR" "$ROOT" <<'NODE'
import { writeFile, readFile } from 'node:fs/promises';
const { executeCommand } = await import(process.argv[2]);
const root = process.argv[3];
const pidFile = `${root}/child.pid`;
const strayFile = `${root}/stray.pid`;
const normal = await executeCommand({ id:'normal', argv:['bash','-c',`sleep 30 >/dev/null 2>&1 & echo $! > '${strayFile}'`],
  timeout_seconds:5,output_limit_bytes:8,descriptor_digest:'d',configuration_digest:'c' }, { cwd:root });
if (normal.outcome !== 'passed') process.exit(4);
const stray = Number((await readFile(strayFile, 'utf8')).trim());
try { process.kill(stray, 0); process.exit(5); } catch {}
const timed = await executeCommand({ id:'timeout', argv:['bash','-c',`sleep 30 & echo $! > '${pidFile}'; wait`],
  timeout_seconds:1,output_limit_bytes:8,descriptor_digest:'d',configuration_digest:'c' }, { cwd:root });
if (timed.outcome !== 'timed_out') process.exit(1);
const pid = Number((await readFile(pidFile, 'utf8')).trim());
try { process.kill(pid, 0); process.exit(2); } catch {}
const controller = new AbortController();
setTimeout(() => controller.abort(), 50);
const cancelled = await executeCommand({ id:'cancel',argv:['sleep','30'],timeout_seconds:5,
  output_limit_bytes:8,descriptor_digest:'d',configuration_digest:'c' }, { cwd:root,signal:controller.signal });
if (cancelled.outcome !== 'cancelled') process.exit(3);
NODE
[[ $? -eq 0 ]] && pass 'normal completion and timeout kill the process group; cancellation stays distinct' \
  || fail 'timeout/cancellation executor contract'

unset GAAI_LOCAL_ADMISSION_RISK_INPUTS_PATH
if ! _run_local_admission pre_qa TST-NORISK "$REPO" staging "$RECEIPTS" >/dev/null \
  && [[ "$LOCAL_ADMISSION_OUTCOME" == blocked:risk_inputs_missing ]]; then
  pass 'missing risk input fails before execution'
else fail "missing-risk outcome=$LOCAL_ADMISSION_OUTCOME"; fi

printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
