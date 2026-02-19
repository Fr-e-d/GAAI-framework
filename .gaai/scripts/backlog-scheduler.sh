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
#   Also supports: listing all ready items, showing a
#   dependency graph, and detecting priority conflicts.
#
# Usage:
#   ./scripts/backlog-scheduler.sh [options] <backlog-active-yaml>
#
# Options:
#   --next          Select next ready item (default)
#   --list          List all ready items sorted by priority
#   --graph         Show dependency graph for all active items
#   --conflicts     Show priority conflicts (high-priority items
#                   blocked by lower-priority dependencies)
#
# Inputs:
#   positional — path to active.backlog.yaml
#
# Outputs:
#   stdout — ID of the next ready backlog item (--next),
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --next)      MODE="next";      shift ;;
    --list)      MODE="list";      shift ;;
    --graph)     MODE="graph";     shift ;;
    --conflicts) MODE="conflicts"; shift ;;
    -*)
      >&2 echo "Unknown option: $1"
      >&2 echo "Usage: $0 [--next|--list|--graph|--conflicts] <backlog-active-yaml>"
      exit 1
      ;;
    *)
      BACKLOG_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$BACKLOG_FILE" ]]; then
  >&2 echo "Usage: $0 [--next|--list|--graph|--conflicts] <backlog-active-yaml>"
  >&2 echo "Example: $0 .gaai/contexts/backlog/active.backlog.yaml"
  exit 1
fi

if [[ ! -f "$BACKLOG_FILE" ]]; then
  >&2 echo "Error: backlog file '$BACKLOG_FILE' not found"
  exit 2
fi

if ! command -v python3 &>/dev/null; then
  >&2 echo "Error: python3 is required for backlog-scheduler.sh"
  exit 3
fi

python3 - "$BACKLOG_FILE" "$MODE" << 'PYEOF'
import sys
import re

backlog_file = sys.argv[1]
mode = sys.argv[2]

with open(backlog_file, 'r') as f:
    content = f.read()

# ── YAML block parser ──────────────────────────────────────
items = []
current = {}
in_depends = False
in_criteria = False

for line in content.splitlines():
    stripped = line.strip()

    if stripped.startswith('- id:'):
        if current:
            items.append(current)
        current = {
            'id': stripped.split(':', 1)[1].strip(),
            'title': '',
            'status': 'draft',
            'priority': 'low',
            'complexity': 1,
            'depends_on': [],
        }
        in_depends = False
        in_criteria = False

    elif current:
        if stripped.startswith('title:'):
            current['title'] = stripped.split(':', 1)[1].strip().strip('"\'')
        elif stripped.startswith('status:'):
            current['status'] = stripped.split(':', 1)[1].strip()
            in_depends = False
        elif stripped.startswith('priority:'):
            current['priority'] = stripped.split(':', 1)[1].strip()
            in_depends = False
        elif stripped.startswith('complexity:'):
            try:
                current['complexity'] = int(stripped.split(':', 1)[1].strip())
            except ValueError:
                pass
            in_depends = False
        elif stripped.startswith('depends_on:'):
            val = stripped.split(':', 1)[1].strip()
            if val and val not in ('[]', ''):
                # inline list: depends_on: [BL-001, BL-002]
                ids = re.findall(r'[\w-]+', val)
                current['depends_on'].extend(ids)
                in_depends = False
            else:
                in_depends = True
        elif in_depends and stripped.startswith('- '):
            dep = stripped[2:].strip()
            if dep:
                current['depends_on'].append(dep)
        elif stripped and not stripped.startswith('#') and not stripped.startswith('- '):
            in_depends = False

if current:
    items.append(current)

# ── Helpers ────────────────────────────────────────────────
priority_order = {'high': 0, 'medium': 1, 'low': 2}

done_ids = {i['id'] for i in items if i.get('status') in ('done', 'cancelled')}
all_ids  = {i['id'] for i in items}

def is_ready(item):
    if item.get('status') != 'refined':
        return False
    unresolved = [d for d in item.get('depends_on', []) if d and d not in done_ids]
    return len(unresolved) == 0

def unresolved_deps(item):
    return [d for d in item.get('depends_on', []) if d and d not in done_ids]

def sort_key(item):
    return (priority_order.get(item.get('priority', 'low'), 2), item.get('complexity', 1))

ready_items = sorted([i for i in items if is_ready(i)], key=sort_key)

# ── Mode: next ─────────────────────────────────────────────
if mode == 'next':
    if ready_items:
        print(ready_items[0]['id'])
    else:
        print('NO_ITEM_READY')
    sys.exit(0)

# ── Mode: list ─────────────────────────────────────────────
if mode == 'list':
    if not ready_items:
        print('No items ready. Check backlog for refined items with resolved dependencies.')
        sys.exit(0)
    print(f'Ready items ({len(ready_items)}):')
    print()
    for item in ready_items:
        priority = item.get('priority', 'low').upper()
        complexity = item.get('complexity', '?')
        title = item.get('title', '(no title)')
        print(f'  [{priority}] {item["id"]} — {title} (complexity: {complexity})')
    sys.exit(0)

# ── Mode: graph ────────────────────────────────────────────
if mode == 'graph':
    active_items = [i for i in items if i.get('status') not in ('done', 'cancelled')]
    if not active_items:
        print('No active items.')
        sys.exit(0)
    print('Dependency graph (active items):')
    print()
    for item in sorted(active_items, key=sort_key):
        status  = item.get('status', '?')
        priority = item.get('priority', 'low')
        title   = item.get('title', '(no title)')
        deps    = item.get('depends_on', [])

        # Status indicator
        if is_ready(item):
            indicator = '✅'
        elif status == 'in-progress':
            indicator = '🔄'
        elif deps:
            indicator = '🔒'
        else:
            indicator = '⏳'

        print(f'  {indicator} {item["id"]} [{priority}] — {title}')
        for dep in deps:
            dep_status = next((i.get('status','?') for i in items if i['id'] == dep), 'unknown')
            resolved = '✓' if dep in done_ids else '✗'
            print(f'       └─ {resolved} depends on {dep} (status: {dep_status})')
    print()
    print('Legend: ✅ ready  🔄 in-progress  🔒 blocked  ⏳ not yet refined')
    sys.exit(0)

# ── Mode: conflicts ────────────────────────────────────────
if mode == 'conflicts':
    conflicts = []
    active_items = [i for i in items if i.get('status') not in ('done', 'cancelled')]

    for item in active_items:
        if item.get('status') != 'refined':
            continue
        unres = unresolved_deps(item)
        if not unres:
            continue
        # check if any dep has lower priority
        item_prio = priority_order.get(item.get('priority', 'low'), 2)
        for dep_id in unres:
            dep = next((i for i in items if i['id'] == dep_id), None)
            if dep is None:
                conflicts.append({
                    'item': item,
                    'dep_id': dep_id,
                    'type': 'missing',
                    'detail': 'dependency not found in backlog'
                })
                continue
            dep_prio = priority_order.get(dep.get('priority', 'low'), 2)
            if dep_prio > item_prio:
                conflicts.append({
                    'item': item,
                    'dep_id': dep_id,
                    'type': 'priority_inversion',
                    'detail': f'{item["id"]} ({item.get("priority")}) is blocked by {dep_id} ({dep.get("priority")})'
                })

    if not conflicts:
        print('No priority conflicts detected.')
        sys.exit(0)

    print(f'Priority conflicts ({len(conflicts)}):')
    print()
    for c in conflicts:
        print(f'  ⚠️  {c["detail"]}')
        if c["type"] == "priority_inversion":
            print(f'      → Consider raising priority of {c["dep_id"]} or lowering {c["item"]["id"]}')
        elif c["type"] == "missing":
            print(f'      → {c["dep_id"]} is listed as a dependency but not found in backlog')
    sys.exit(0)

PYEOF
