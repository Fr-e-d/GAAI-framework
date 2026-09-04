#!/usr/bin/env bash
set -euo pipefail

############################################################
# migrate-backlog-phase-schema.sh — GAAI
#
# Purpose:
#   One-shot migration that adds `phase_status` and
#   `delivery_pipeline` fields to every item in
#   active.backlog.yaml. Required before E134S02+
#   (3-phase daemon dispatch) can be activated.
#
# Usage:
#   bash .gaai/core/scripts/migrate-backlog-phase-schema.sh
#
# Pre-condition:
#   The delivery daemon MUST be stopped before running this
#   script to ensure no concurrent writes to the backlog.
#   Stop the daemon first, through the privileged executable
#   entry (a plain `bash <script>` entry is refused):
#     .gaai/core/scripts/daemon-start.sh --stop
#
# Idempotency:
#   Safe to run multiple times. Entries that already have
#   both `phase_status` and `delivery_pipeline` are skipped.
#   Entries with only one field get the missing field added.
#
# Backup:
#   Creates active.backlog.yaml.bak before any mutation.
#   On YAML parse failure after write, automatically restores
#   the backup and exits 1.
#
# Exit codes:
#   0 — migration complete (or nothing to do)
#   1 — error (daemon running, file not found, YAML corrupt)
############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BACKLOG="$PROJECT_DIR/.gaai/project/contexts/backlog/active.backlog.yaml"

# ── Runtime boundary ─────────────────────────────────────────
# The parser is repository-controlled: there is no ambient availability probe and
# nothing to install. An unavailable or untrusted runtime is a typed hard failure
# from the boundary itself.
# shellcheck source=lib/yaml-runtime.sh
if ! source "$SCRIPT_DIR/lib/yaml-runtime.sh"; then
  echo "ERROR: the repository-controlled YAML runtime boundary is unavailable" >&2
  exit 1
fi
YAML_RUNTIME_ROLE=migration

# ── Pre-condition: backlog file must exist ───────────────────
if [[ ! -f "$BACKLOG" ]]; then
  echo "ERROR: backlog file not found: $BACKLOG" >&2
  exit 1
fi

# ── Pre-condition: daemon must be stopped ────────────────────
# The daemon writes to this same backlog file. Concurrent
# writes during migration would corrupt the YAML. The backup
# provides recovery but prevention is preferable.
# NOTE: this ambient process scan is a migration PRECONDITION only. It is not, and
# must never become, daemon ownership evidence: process ownership is proven by the
# durable owner record and the private tmux server that `daemon-start.sh` maintains,
# never inferred from a pgrep match. A false negative here costs a backup restore;
# treating it as authority would reintroduce exactly the ambient-state inference
# that the exact-current startup contract removed.
if pgrep -f "delivery-daemon.sh" > /dev/null 2>&1; then
  echo "ERROR: delivery-daemon.sh is running. Stop it first, through the" >&2
  echo "       privileged executable entry (a plain \`bash <script>\` entry is refused):" >&2
  echo "  .gaai/core/scripts/daemon-start.sh --stop" >&2
  exit 1
fi

# ── Backup ───────────────────────────────────────────────────
cp "$BACKLOG" "${BACKLOG}.bak"
echo "Backup created: ${BACKLOG}.bak"

# ── Read pass: extract (id, status) via YAML parser ─────────
# yaml.safe_load normalises `status: "done"` → Python `done`
# so the migration map lookup works for both quoted/unquoted.
# Output: TSV file  id<TAB>status  one line per item.
MIGRATION_MAP_FILE=$(mktemp)
trap 'rm -f "$MIGRATION_MAP_FILE"' EXIT

yaml_runtime_run "$BACKLOG" "$MIGRATION_MAP_FILE" << 'PYEOF'
import sys, yaml

backlog_path = sys.argv[1]
map_file = sys.argv[2]

with open(backlog_path, 'r') as f:
    doc = yaml.safe_load(f)

items = doc.get('items', []) if doc else []
with open(map_file, 'w') as out:
    for item in items:
        item_id = item.get('id', '')
        status = str(item.get('status', 'draft')).strip()
        out.write(f"{item_id}\t{status}\n")
PYEOF

# ── Write pass: line-by-line insertion ───────────────────────
# No yaml.dump() — preserves comments, quotes, and indentation
# exactly. Inserts phase_status and delivery_pipeline after the
# status: line in each item block.
#
# Single-quoted heredoc prevents bash from expanding $variables
# inside the Python code. BACKLOG path is passed as argv[1],
# migration map TSV path as argv[2].
read -r -d '' WRITE_PASS_PY << 'PYEOF' || true
import sys, re

PHASE_STATUS_MAP = {
    'draft':       'not_started',
    'refined':     'not_started',
    'in_progress': 'not_started',
    'done':        'done',
    'failed':      'failed',
    'deferred':    'deferred',
    'blocked':     'not_started',
    'cancelled':   'cancelled',
    'superseded':  'superseded',
    'escalated':   'escalated',
}
PIPELINE_LEGACY = {'in_progress', 'done', 'failed', 'deferred',
                   'blocked', 'cancelled', 'superseded', 'escalated'}

file_path = sys.argv[1]
map_file = sys.argv[2]

# Build id->status dict from TSV
id_to_status = {}
with open(map_file) as f:
    for line in f:
        line = line.strip()
        if '\t' in line:
            parts = line.split('\t', 1)
            id_to_status[parts[0]] = parts[1]

with open(file_path, 'r') as f:
    lines = f.readlines()

# Parse into item blocks: list of (start_idx, end_idx, item_id)
blocks = []
item_start = -1
current_id = None

for idx, line in enumerate(lines):
    stripped = line.strip()
    m = re.match(r'^-\s+id:\s+(\S+)\s*$', stripped)
    if m:
        if item_start >= 0 and current_id:
            blocks.append((item_start, idx, current_id))
        item_start = idx
        current_id = m.group(1)

if item_start >= 0 and current_id:
    blocks.append((item_start, len(lines), current_id))

migrated_count = 0
skipped_count = 0
new_lines = list(lines)
offset = 0  # tracks insertion offsets as we add lines

for (blk_start, blk_end, item_id) in blocks:
    s = blk_start + offset
    e = blk_end + offset
    block = new_lines[s:e]

    has_phase_status = any(re.match(r'^\s+phase_status:', ln) for ln in block)
    has_pipeline     = any(re.match(r'^\s+delivery_pipeline:', ln) for ln in block)

    if has_phase_status and has_pipeline:
        skipped_count += 1
        continue

    # Look up status from migration map (unknown values get safe defaults)
    raw_status = id_to_status.get(item_id, 'draft')
    if raw_status not in PHASE_STATUS_MAP:
        sys.stderr.write(f'WARNING: unknown status "{raw_status}" for {item_id}, defaulting to not_started/legacy\n')
    phase_status_val = PHASE_STATUS_MAP.get(raw_status, 'not_started')
    pipeline_val = 'legacy' if raw_status in PIPELINE_LEGACY else '3phase'

    # Detect indentation from the status: line in this block
    indent = '  '
    status_idx_in_block = -1
    for j, ln in enumerate(block):
        m2 = re.match(r'^(\s+)status:\s+', ln)
        if m2:
            indent = m2.group(1)
            status_idx_in_block = j
            break

    if status_idx_in_block < 0:
        # No status: line found in this block — skip gracefully
        sys.stderr.write(f'WARNING: no status: line for {item_id}, skipping\n')
        skipped_count += 1
        continue

    # Insert missing fields immediately after the status: line
    insert_pos = s + status_idx_in_block + 1
    to_insert = []
    if not has_phase_status:
        to_insert.append(f'{indent}phase_status: {phase_status_val}\n')
    if not has_pipeline:
        to_insert.append(f'{indent}delivery_pipeline: {pipeline_val}\n')

    for k, line_to_insert in enumerate(to_insert):
        new_lines.insert(insert_pos + k, line_to_insert)

    offset += len(to_insert)
    migrated_count += 1

with open(file_path, 'w') as f:
    f.writelines(new_lines)

print(f'Entries migrated: {migrated_count}')
print(f'Entries skipped (already had fields): {skipped_count}')
PYEOF

python3 -c "$WRITE_PASS_PY" "$BACKLOG" "$MIGRATION_MAP_FILE"

# ── YAML validation post-write ───────────────────────────────
if ! yaml_runtime_validate_file "$BACKLOG"; then
  echo "ERROR: YAML parse failed after migration. Restoring backup." >&2
  cp "${BACKLOG}.bak" "$BACKLOG"
  echo "Backup restored." >&2
  exit 1
fi

# ── Summary: phase_status breakdown ─────────────────────────
yaml_runtime_run "$BACKLOG" << 'PYEOF'
import sys, yaml
from collections import Counter

with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f)

items = doc.get('items', []) if doc else []
ps_counts = Counter(i.get('phase_status', '(missing)') for i in items)
pp_counts = Counter(i.get('delivery_pipeline', '(missing)') for i in items)
missing = [i.get('id') for i in items
           if 'phase_status' not in i or 'delivery_pipeline' not in i]

print()
print(f"  Total items: {len(items)}")
print(f"  phase_status breakdown: {dict(ps_counts)}")
print(f"  delivery_pipeline breakdown: {dict(pp_counts)}")
if missing:
    print(f"  WARNING: missing fields on: {missing}")
else:
    print(f"  All entries have both fields.")
PYEOF

echo ""
echo "Migration complete. Run again to verify idempotency (should show 0 migrated, all skipped)."
