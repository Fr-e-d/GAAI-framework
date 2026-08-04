#!/usr/bin/env bash
# Regression coverage for scalar and safe flow-sequence --set-field values.

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  PASS: $1"; PASS_COUNT=$(( PASS_COUNT + 1 )); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER="$SCRIPT_DIR/../backlog-scheduler.sh"
FIXTURE_DIR=$(mktemp -d)
FIXTURE="$FIXTURE_DIR/active.backlog.yaml"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

write_fixture() {
  cat > "$FIXTURE" << 'YAML_EOF'
items:
- id: TST-ONE
  status: draft
  phase_status: not_started
  related_decs: [REF-1]
  notes: "original"
- id: TST-TWO
  status: draft
  phase_status: not_started
YAML_EOF
}

yaml_field_is_list() {
  python3 -c "
import yaml
with open('$FIXTURE') as fh:
    data = yaml.safe_load(fh)
item = next(row for row in data['items'] if row['id'] == '$1')
value = item['$2']
assert isinstance(value, list), type(value)
assert value == $3, value
"
}

echo "backlog-scheduler --set-field tests"
echo ""

echo "T1: replaces a list field with a canonical safe flow sequence"
write_fixture
OUT=$(bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-2,REF-3,  REF-4]' "$FIXTURE" 2>&1)
if grep -q '^  related_decs: \[REF-2, REF-3, REF-4\]$' "$FIXTURE" && \
   yaml_field_is_list TST-ONE related_decs "['REF-2', 'REF-3', 'REF-4']"; then
  pass "T1: safe list is normalized, bare, and parsed as a YAML sequence"
else
  fail "T1: list replacement is not canonical or not a YAML sequence: $OUT"
fi

echo "T2: inserts a new list field without changing adjacent items"
write_fixture
bash "$SCHEDULER" --set-field TST-TWO related_decs '[REF-2, REF-3]' "$FIXTURE" >/dev/null
if yaml_field_is_list TST-TWO related_decs "['REF-2', 'REF-3']" && \
   grep -q '^  related_decs: \[REF-1\]$' "$FIXTURE"; then
  pass "T2: list insertion is item-scoped"
else
  fail "T2: list insertion changed the wrong item or emitted a scalar"
fi

echo "T3: rejects unsafe or nested flow syntax without modifying the file"
write_fixture
BEFORE=$(cksum "$FIXTURE")
if bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-2, "REF:3"]' "$FIXTURE" >/dev/null 2>&1; then
  fail "T3a: unsafe quoted/colon value was accepted"
else
  AFTER=$(cksum "$FIXTURE")
  if [[ "$BEFORE" == "$AFTER" ]]; then
    pass "T3a: unsafe sequence fails closed before writing"
  else
    fail "T3a: rejected sequence still modified the file"
  fi
fi
if bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-2, [REF-3]]' "$FIXTURE" >/dev/null 2>&1; then
  fail "T3b: nested sequence was accepted"
else
  pass "T3b: nested sequence is rejected"
fi

echo "T4: preserves existing scalar formatting behavior"
write_fixture
bash "$SCHEDULER" --set-field TST-ONE notes 'contains: punctuation' "$FIXTURE" >/dev/null
bash "$SCHEDULER" --set-field TST-ONE status refined "$FIXTURE" >/dev/null
bash "$SCHEDULER" --set-field TST-TWO notes 'ordinary text]' "$FIXTURE" >/dev/null
if grep -q '^  notes: "contains: punctuation"$' "$FIXTURE" && \
   grep -q '^  status: refined$' "$FIXTURE" && \
   grep -q '^  notes: "ordinary text]"$' "$FIXTURE" && \
   python3 -c "import yaml; yaml.safe_load(open('$FIXTURE'))"; then
  pass "T4: strings remain quoted and snake_case values remain bare"
else
  fail "T4: scalar formatting regressed"
fi

echo "T5: refuses same-indent block-list rewrites without relying on PyYAML"
write_fixture
python3 -c "
from pathlib import Path
path = Path('$FIXTURE')
text = path.read_text().replace('  related_decs: [REF-1]', '  related_decs:\n  - REF-1\n  - REF-2')
path.write_text(text)
"
BEFORE=$(cksum "$FIXTURE")
OUT=$(bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-3, REF-4]' "$FIXTURE" 2>&1 || true)
AFTER=$(cksum "$FIXTURE")
if [[ "$BEFORE" == "$AFTER" ]] && \
   echo "$OUT" | grep -q 'uses block-style YAML' && \
   python3 -c "import yaml; yaml.safe_load(open('$FIXTURE'))"; then
  pass "T5a: same-indent block list fails at the explicit guard without corruption"
else
  fail "T5a: same-indent block-list guard did not fail closed: $OUT"
fi

mkdir -p "$FIXTURE_DIR/no-yaml"
cat > "$FIXTURE_DIR/no-yaml/yaml.py" << 'PY_EOF'
raise ImportError("PyYAML intentionally unavailable for this test")
PY_EOF
BEFORE=$(cksum "$FIXTURE")
OUT=$(PYTHONPATH="$FIXTURE_DIR/no-yaml" bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-3, REF-4]' "$FIXTURE" 2>&1 || true)
AFTER=$(cksum "$FIXTURE")
if [[ "$BEFORE" == "$AFTER" ]] && echo "$OUT" | grep -q 'uses block-style YAML'; then
  pass "T5b: block-list guard remains fail-closed without PyYAML"
else
  fail "T5b: no-PyYAML path modified the block list or missed the guard: $OUT"
fi

echo "T6: refuses block-scalar rewrites before data can be orphaned"
write_fixture
python3 -c "
from pathlib import Path
path = Path('$FIXTURE')
text = path.read_text().replace('  notes: \"original\"', '  notes: |-\n    first line\n    second line')
path.write_text(text)
"
BEFORE=$(cksum "$FIXTURE")
OUT=$(bash "$SCHEDULER" --set-field TST-ONE notes 'replacement' "$FIXTURE" 2>&1 || true)
AFTER=$(cksum "$FIXTURE")
if [[ "$BEFORE" == "$AFTER" ]] && echo "$OUT" | grep -q 'uses block-style YAML'; then
  pass "T6: block scalar fails closed without silent data loss"
else
  fail "T6: block-scalar guard did not fail closed: $OUT"
fi

echo "T7: preserves the empty-list special case"
write_fixture
bash "$SCHEDULER" --set-field TST-ONE related_decs '[]' "$FIXTURE" >/dev/null
if grep -q '^  related_decs: \[\]$' "$FIXTURE" && \
   yaml_field_is_list TST-ONE related_decs '[]'; then
  pass "T7: empty list remains a YAML sequence"
else
  fail "T7: empty list formatting regressed"
fi

echo "T8: treats bracket-delimited safe values as lists and preserves partial brackets as strings"
write_fixture
bash "$SCHEDULER" --set-field TST-ONE tags '[TODO]' "$FIXTURE" >/dev/null
bash "$SCHEDULER" --set-field TST-TWO notes '[WIP] waiting on review' "$FIXTURE" >/dev/null
if yaml_field_is_list TST-ONE tags "['TODO']" && \
   grep -q '^  notes: "\[WIP\] waiting on review"$' "$FIXTURE"; then
  pass "T8: documented bracket behavior is explicit and backward-compatible"
else
  fail "T8: bracket-delimited list or partial-bracket string behavior is wrong"
fi

echo "T9: permits a genuinely null field followed only by a comment"
write_fixture
python3 -c "
from pathlib import Path
path = Path('$FIXTURE')
text = path.read_text().replace('  notes: \"original\"', '  notes:\n    # pending value')
path.write_text(text)
"
if bash "$SCHEDULER" --set-field TST-ONE notes 'replacement' "$FIXTURE" >/dev/null && \
   grep -q '^  notes: replacement$' "$FIXTURE"; then
  pass "T9: comments do not create a false block-style refusal"
else
  fail "T9: null field plus comment was incorrectly rejected"
fi

echo "T10: rejects unsafe nested syntax without modifying the file"
write_fixture
BEFORE=$(cksum "$FIXTURE")
if bash "$SCHEDULER" --set-field TST-ONE related_decs '[REF-2, [REF-3]]' "$FIXTURE" >/dev/null 2>&1; then
  fail "T10: nested sequence was accepted"
else
  AFTER=$(cksum "$FIXTURE")
  if [[ "$BEFORE" == "$AFTER" ]]; then
    pass "T10: nested sequence rejection is also write-free"
  else
    fail "T10: rejected nested sequence modified the file"
  fi
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo "All tests PASSED."
  exit 0
fi

echo "SOME TESTS FAILED."
exit 1
