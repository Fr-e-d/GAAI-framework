#!/usr/bin/env bash
set -euo pipefail

############################################################
# Backlog Scheduler — GAAI
#
# Description:
#   Selects the next ready Story from the active backlog.
#   Reads active.backlog.yaml, finds items with status: refined,
#   sorts by priority, checks dependencies, and returns the
#   first actionable item.
#
#   Also supports: listing all ready items, outputting ready
#   IDs, showing a dependency graph, detecting priority
#   conflicts, and updating story status in-place.
#
# Usage:
#   ./scripts/backlog-scheduler.sh [options] <backlog-active-yaml>
#   echo "$yaml" | ./scripts/backlog-scheduler.sh --stdin [options]
#
# Options:
#   --next          Select next ready item (default)
#   --list          List all ready items sorted by priority
#   --ready-ids     Output ready story IDs, one per line
#   --graph         Show dependency graph for all active items
#   --conflicts     Show priority conflicts (high-priority items
#                   blocked by lower-priority dependencies)
#   --set-status <id> <status>  Update a story's status in the
#                   YAML file. Requires file path (not --stdin).
#   --set-field <id> <field> <value>  Set any field on a backlog
#                   item. Updates if exists, inserts after delivery
#                   metadata fields if not. Numbers and null/true/
#                   false stay bare; strings are auto-quoted.
#                   Requires file path (not --stdin).
#   --stdin         Read YAML from stdin instead of file
#
# Inputs:
#   positional — path to active.backlog.yaml (unless --stdin)
#
# Outputs:
#   stdout — ID of the next ready backlog item (--next),
#            ready IDs one per line (--ready-ids),
#            or formatted list/graph/conflicts report
#
# Exit codes:
#   0 — success
#   1 — usage error
#   2 — file not found
#   3 — python3 not available
############################################################

MODE="next"
BACKLOG_FILE=""
FROM_STDIN=false
SET_STATUS_ID=""
SET_STATUS_VAL=""
SET_FIELD_ID=""
SET_FIELD_NAME=""
SET_FIELD_VAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --next)       MODE="next";       shift ;;
    --list)       MODE="list";       shift ;;
    --ready-ids)  MODE="ready-ids";  shift ;;
    --graph)      MODE="graph";      shift ;;
    --conflicts)  MODE="conflicts";  shift ;;
    --set-status)
      MODE="set-status"
      SET_STATUS_ID="${2:-}"
      SET_STATUS_VAL="${3:-}"
      if [[ -z "$SET_STATUS_ID" || -z "$SET_STATUS_VAL" ]]; then
        >&2 echo "Error: --set-status requires <id> and <status>"
        >&2 echo "Usage: $0 --set-status <id> <status> <backlog-active-yaml>"
        exit 1
      fi
      shift 3
      ;;
    --set-field)
      MODE="set-field"
      SET_FIELD_ID="${2:-}"
      SET_FIELD_NAME="${3:-}"
      SET_FIELD_VAL="${4:-}"
      if [[ -z "$SET_FIELD_ID" || -z "$SET_FIELD_NAME" ]]; then
        >&2 echo "Error: --set-field requires <id> <field> <value>"
        >&2 echo "Usage: $0 --set-field <id> <field> <value> <backlog-active-yaml>"
        exit 1
      fi
      shift 4
      ;;
    --stdin)      FROM_STDIN=true;   shift ;;
    -*)
      >&2 echo "Unknown option: $1"
      >&2 echo "Usage: $0 [--next|--list|--ready-ids|--graph|--conflicts|--set-status <id> <status>|--set-field <id> <field> <value>] [--stdin] [<backlog-active-yaml>]"
      exit 1
      ;;
    *)
      BACKLOG_FILE="$1"
      shift
      ;;
  esac
done

# ── Validate inputs ──────────────────────────────────────────
if [[ "$MODE" == "set-status" ]]; then
  # set-status always operates on a file (not stdin)
  if [[ -z "$BACKLOG_FILE" ]]; then
    >&2 echo "Error: --set-status requires a backlog file path"
    >&2 echo "Usage: $0 --set-status <id> <status> <backlog-active-yaml>"
    exit 1
  fi
  if [[ ! -f "$BACKLOG_FILE" ]]; then
    >&2 echo "Error: backlog file '$BACKLOG_FILE' not found"
    exit 2
  fi
elif [[ "$MODE" == "set-field" ]]; then
  # set-field always operates on a file (not stdin)
  if [[ -z "$BACKLOG_FILE" ]]; then
    >&2 echo "Error: --set-field requires a backlog file path"
    >&2 echo "Usage: $0 --set-field <id> <field> <value> <backlog-active-yaml>"
    exit 1
  fi
  if [[ ! -f "$BACKLOG_FILE" ]]; then
    >&2 echo "Error: backlog file '$BACKLOG_FILE' not found"
    exit 2
  fi
elif ! $FROM_STDIN; then
  if [[ -z "$BACKLOG_FILE" ]]; then
    >&2 echo "Usage: $0 [--next|--list|--ready-ids|--graph|--conflicts] [--stdin] [<backlog-active-yaml>]"
    >&2 echo "Example: $0 .gaai/contexts/backlog/active.backlog.yaml"
    exit 1
  fi
  if [[ ! -f "$BACKLOG_FILE" ]]; then
    >&2 echo "Error: backlog file '$BACKLOG_FILE' not found"
    exit 2
  fi
fi

if ! command -v python3 &>/dev/null; then
  >&2 echo "Error: python3 is required for backlog-scheduler.sh"
  exit 3
fi

# ── set-status mode: modify file in-place ────────────────────
if [[ "$MODE" == "set-status" ]]; then
  python3 -c "
import sys, re

file_path, target_id, new_status = sys.argv[1], sys.argv[2], sys.argv[3]

with open(file_path, 'r') as f:
    lines = f.readlines()

in_target = False
modified = False

for i, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r'-\s+id:\s+' + re.escape(target_id) + r'\s*$', stripped):
        in_target = True
        continue
    if in_target:
        if re.match(r'-\s+id:\s+', stripped):
            break
        m = re.match(r'^(\s+status:\s+)\S+', line)
        if m:
            lines[i] = m.group(1) + new_status + '\n'
            modified = True
            break

if not modified:
    print(f'Error: could not update status for {target_id}', file=sys.stderr)
    sys.exit(1)

with open(file_path, 'w') as f:
    f.writelines(lines)

print(f'{target_id} -> {new_status}')
" "$BACKLOG_FILE" "$SET_STATUS_ID" "$SET_STATUS_VAL"
  exit $?
fi

# ── set-field mode: set any field on a backlog item ──────────
if [[ "$MODE" == "set-field" ]]; then
  python3 -c "
import sys, re

file_path, target_id, field_name, field_value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(file_path, 'r') as f:
    lines = f.readlines()

# Find target item block boundaries
block_start = -1
block_end = len(lines)

for i, line in enumerate(lines):
    stripped = line.strip()
    if re.match(r'-\s+id:\s+' + re.escape(target_id) + r'\s*$', stripped):
        block_start = i
        continue
    if block_start >= 0 and re.match(r'-\s+id:\s+', stripped):
        block_end = i
        break

if block_start < 0:
    print(f'Error: item {target_id} not found', file=sys.stderr)
    sys.exit(1)

# Format value: numbers stay bare, null/true/false/[] stay bare, strings get quoted
try:
    float(field_value)
    formatted = field_value
except ValueError:
    if field_value in ('null', 'true', 'false', '[]'):
        formatted = field_value
    else:
        # Escape inner double quotes and wrap
        formatted = '\"' + field_value.replace('\\\\', '\\\\\\\\').replace('\"', '\\\\\"') + '\"'

# Look for existing field within the block
field_found = False
for i in range(block_start + 1, block_end):
    m = re.match(r'^(\s+)' + re.escape(field_name) + r':\s', lines[i])
    if m:
        indent = m.group(1)
        lines[i] = f'{indent}{field_name}: {formatted}\n'
        field_found = True
        break

if not field_found:
    # Determine indentation from existing fields
    indent = '    '
    for i in range(block_start + 1, block_end):
        m2 = re.match(r'^(\s+)\w', lines[i])
        if m2:
            indent = m2.group(1)
            break

    # Insertion order: after the last delivery-metadata field present,
    # or after status: if none exist
    DELIVERY_FIELDS = ['status', 'cost_usd', 'human_md_estimate', 'human_cost_usd', 'started_at', 'completed_at', 'pr_url', 'pr_number', 'pr_status']
    insert_after = -1
    for i in range(block_start + 1, block_end):
        fm = re.match(r'^\s+(\w+):', lines[i])
        if fm and fm.group(1) in DELIVERY_FIELDS:
            insert_after = i

    if insert_after < 0:
        # Fallback: insert after the id line
        insert_after = block_start

    new_line = f'{indent}{field_name}: {formatted}\n'
    lines.insert(insert_after + 1, new_line)

with open(file_path, 'w') as f:
    f.writelines(lines)

print(f'{target_id}.{field_name} = {formatted}')
" "$BACKLOG_FILE" "$SET_FIELD_ID" "$SET_FIELD_NAME" "$SET_FIELD_VAL"
  exit $?
fi

# ── Read backlog content ─────────────────────────────────────
if $FROM_STDIN; then
  BACKLOG_CONTENT=$(cat)
else
  BACKLOG_CONTENT=$(cat "$BACKLOG_FILE")
fi

# ── Python parser + all read modes ───────────────────────────
# The Python script is stored in a variable to avoid quoting issues
# with python3 -c. Content is piped via stdin, mode via argv.
read -r -d '' PYTHON_PARSER << 'PYEOF' || true
import sys
import re

mode = sys.argv[1]
content = sys.stdin.read()

# -- YAML block parser --
items = []
current = {}
in_depends = False

for line in content.splitlines():
    stripped = line.strip()

    if stripped.startswith("- id:"):
        if current:
            items.append(current)
        current = {
            "id": stripped.split(":", 1)[1].strip(),
            "title": "",
            "status": "draft",
            "priority": "low",
            "complexity": 1,
            "depends_on": [],
        }
        in_depends = False

    elif current:
        if stripped.startswith("title:"):
            current["title"] = stripped.split(":", 1)[1].strip().strip("\"'")
        elif stripped.startswith("status:"):
            current["status"] = stripped.split(":", 1)[1].strip()
            in_depends = False
        elif stripped.startswith("priority:"):
            current["priority"] = stripped.split(":", 1)[1].strip()
            in_depends = False
        elif stripped.startswith("complexity:"):
            try:
                current["complexity"] = int(stripped.split(":", 1)[1].strip())
            except ValueError:
                pass
            in_depends = False
        elif stripped.startswith("depends_on:") or stripped.startswith("dependencies:"):
            val = stripped.split(":", 1)[1].strip()
            if val and val not in ("[]", ""):
                ids = re.findall(r"[\w-]+", val)
                current["depends_on"].extend(ids)
                in_depends = False
            else:
                in_depends = True
        elif in_depends and stripped.startswith("- "):
            dep = stripped[2:].strip()
            if dep:
                current["depends_on"].append(dep)
        elif stripped and not stripped.startswith("#") and not stripped.startswith("- "):
            in_depends = False

if current:
    items.append(current)

# -- Helpers --
priority_order = {"critical": -1, "high": 0, "medium": 1, "low": 2}
done_ids = {i["id"] for i in items if i.get("status") in ("done", "cancelled", "superseded")}

def is_ready(item):
    if item.get("status") != "refined":
        return False
    return all(d in done_ids for d in item.get("depends_on", []) if d)

def unresolved_deps(item):
    return [d for d in item.get("depends_on", []) if d and d not in done_ids]

def sort_key(item):
    return (priority_order.get(item.get("priority", "low"), 2), item.get("complexity", 1))

ready_items = sorted([i for i in items if is_ready(i)], key=sort_key)

# -- Mode: next --
if mode == "next":
    if ready_items:
        print(ready_items[0]["id"])
    else:
        print("NO_ITEM_READY")
    sys.exit(0)

# -- Mode: ready-ids --
if mode == "ready-ids":
    for item in ready_items:
        print(item["id"])
    sys.exit(0)

# -- Mode: list --
if mode == "list":
    if not ready_items:
        print("No items ready. Check backlog for refined items with resolved dependencies.")
        sys.exit(0)
    print(f"Ready items ({len(ready_items)}):")
    print()
    for item in ready_items:
        priority = item.get("priority", "low").upper()
        complexity = item.get("complexity", "?")
        title = item.get("title", "(no title)")
        print(f'  [{priority}] {item["id"]} \u2014 {title} (complexity: {complexity})')
    sys.exit(0)

# -- Mode: graph --
if mode == "graph":
    active_items = [i for i in items if i.get("status") not in ("done", "cancelled")]
    if not active_items:
        print("No active items.")
        sys.exit(0)
    print("Dependency graph (active items):")
    print()
    for item in sorted(active_items, key=sort_key):
        status   = item.get("status", "?")
        priority = item.get("priority", "low")
        title    = item.get("title", "(no title)")
        deps     = item.get("depends_on", [])

        if is_ready(item):
            indicator = "\u2705"
        elif status in ("in_progress", "in-progress"):
            indicator = "\U0001f504"
        elif deps:
            indicator = "\U0001f512"
        else:
            indicator = "\u23f3"

        print(f'  {indicator} {item["id"]} [{priority}] \u2014 {title}')
        for dep in deps:
            dep_status = next((i.get("status","?") for i in items if i["id"] == dep), "unknown")
            resolved = "\u2713" if dep in done_ids else "\u2717"
            print(f'       \u2514\u2500 {resolved} depends on {dep} (status: {dep_status})')
    print()
    print("Legend: \u2705 ready  \U0001f504 in-progress  \U0001f512 blocked  \u23f3 not yet refined")
    sys.exit(0)

# -- Mode: conflicts --
if mode == "conflicts":
    conflicts = []
    active_items = [i for i in items if i.get("status") not in ("done", "cancelled")]

    for item in active_items:
        if item.get("status") != "refined":
            continue
        unres = unresolved_deps(item)
        if not unres:
            continue
        item_prio = priority_order.get(item.get("priority", "low"), 2)
        for dep_id in unres:
            dep = next((i for i in items if i["id"] == dep_id), None)
            if dep is None:
                conflicts.append({
                    "dep_id": dep_id,
                    "item_id": item["id"],
                    "type": "missing",
                    "detail": f'{dep_id} listed as dependency of {item["id"]} but not found in backlog'
                })
                continue
            dep_prio = priority_order.get(dep.get("priority", "low"), 2)
            if dep_prio > item_prio:
                conflicts.append({
                    "dep_id": dep_id,
                    "item_id": item["id"],
                    "type": "priority_inversion",
                    "detail": f'{item["id"]} ({item.get("priority")}) is blocked by {dep_id} ({dep.get("priority")})'
                })

    if not conflicts:
        print("No priority conflicts detected.")
        sys.exit(0)

    print(f"Priority conflicts ({len(conflicts)}):")
    print()
    for c in conflicts:
        print(f'  \u26a0\ufe0f  {c["detail"]}')
        if c["type"] == "priority_inversion":
            print(f'      \u2192 Consider raising priority of {c["dep_id"]} or lowering {c["item_id"]}')
        elif c["type"] == "missing":
            print(f'      \u2192 {c["dep_id"]} is listed as a dependency but not found in backlog')
    sys.exit(0)
PYEOF

echo "$BACKLOG_CONTENT" | python3 -c "$PYTHON_PARSER" "$MODE"
