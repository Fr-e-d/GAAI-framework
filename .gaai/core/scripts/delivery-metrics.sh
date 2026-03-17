#!/usr/bin/env bash
set -euo pipefail

############################################################
# GAAI Delivery Metrics — DORA-like aggregation
#
# Description:
#   Aggregates delivery metrics from the backlog (active + done/)
#   to produce lead time, failure rate, cost, and velocity stats.
#
# Usage:
#   .gaai/core/scripts/delivery-metrics.sh                # all time
#   .gaai/core/scripts/delivery-metrics.sh --month 2026-03 # specific month
#   .gaai/core/scripts/delivery-metrics.sh --json          # machine-readable
#
# Outputs:
#   Markdown table to stdout (default) or JSON (--json)
#
# Exit codes:
#   0 — success
#   1 — no data found
#   3 — python3 not available
############################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BACKLOG_DIR="$PROJECT_DIR/.gaai/project/contexts/backlog"
ACTIVE="$BACKLOG_DIR/active.backlog.yaml"
DONE_DIR="$BACKLOG_DIR/done"

MONTH_FILTER=""
JSON_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --month)  MONTH_FILTER="$2"; shift 2 ;;
    --json)   JSON_MODE=true; shift ;;
    --help|-h)
      sed -n '/^# Description:/,/^# Exit/{ /^# Exit/d; s/^# //; p; }' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required" >&2
  exit 3
fi

# ── Collect all backlog YAML content ─────────────────────────
ALL_YAML=""
if [[ -f "$ACTIVE" ]]; then
  ALL_YAML+="$(cat "$ACTIVE")"$'\n'
fi
if [[ -d "$DONE_DIR" ]]; then
  for f in "$DONE_DIR"/*.yaml; do
    [[ -f "$f" ]] || continue
    if [[ -n "$MONTH_FILTER" ]]; then
      # Only include files matching the month
      basename_f="$(basename "$f")"
      [[ "$basename_f" == *"$MONTH_FILTER"* ]] || continue
    fi
    ALL_YAML+="$(cat "$f")"$'\n'
  done
fi

if [[ -z "$ALL_YAML" ]]; then
  echo "No backlog data found." >&2
  exit 1
fi

# ── Parse and compute metrics ────────────────────────────────
echo "$ALL_YAML" | python3 -c "
import sys, re, json
from datetime import datetime, timedelta

content = sys.stdin.read()
month_filter = '${MONTH_FILTER}'
json_mode = True if '${JSON_MODE}' == 'true' else False

# Parse items
items = []
current = {}
for line in content.splitlines():
    stripped = line.strip()
    if stripped.startswith('- id:'):
        if current:
            items.append(current)
        current = {'id': stripped.split(':', 1)[1].strip()}
    elif current:
        for field in ['status', 'priority', 'complexity', 'cost_usd', 'started_at', 'completed_at']:
            if stripped.startswith(field + ':'):
                val = stripped.split(':', 1)[1].strip().strip('\"')
                current[field] = val
if current:
    items.append(current)

# Filter by month if specified
def parse_dt(s):
    if not s:
        return None
    try:
        # Handle various ISO formats
        s = s.replace('Z', '+00:00')
        for fmt in ('%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d'):
            try:
                return datetime.strptime(s.split('+')[0].split('Z')[0], fmt.replace('%z',''))
            except:
                continue
    except:
        pass
    return None

if month_filter:
    items = [i for i in items if (i.get('completed_at','').startswith(month_filter) or
                                   i.get('started_at','').startswith(month_filter))]

# Classify
done = [i for i in items if i.get('status') in ('done',)]
failed = [i for i in items if i.get('status') in ('failed',)]
in_progress = [i for i in items if i.get('status') in ('in_progress',)]
total_executed = len(done) + len(failed)

# Delivery durations (hours)
delivery_durations = []
for i in done:
    start = parse_dt(i.get('started_at', ''))
    end = parse_dt(i.get('completed_at', ''))
    if start and end:
        minutes = (end - start).total_seconds() / 60
        if minutes > 0:
            delivery_durations.append(minutes)

# Costs
costs = []
for i in done:
    c = i.get('cost_usd', '')
    if c and c != 'null':
        try:
            costs.append(float(c))
        except:
            pass

# Complexity distribution
complexity_dist = {}
for i in done:
    c = i.get('complexity', '?')
    complexity_dist[c] = complexity_dist.get(c, 0) + 1

# Velocity (stories per week)
if done:
    dates = []
    for i in done:
        dt = parse_dt(i.get('completed_at', ''))
        if dt:
            dates.append(dt)
    if len(dates) >= 2:
        span_days = (max(dates) - min(dates)).days or 1
        velocity = len(dates) / (span_days / 7)
    else:
        velocity = None
else:
    velocity = None

# Output
failure_rate = (len(failed) / total_executed * 100) if total_executed > 0 else 0
avg_lead = sum(delivery_durations) / len(delivery_durations) if delivery_durations else None
med_lead = sorted(delivery_durations)[len(delivery_durations)//2] if delivery_durations else None
total_cost = sum(costs) if costs else 0
stories_with_cost = len(costs)
avg_cost = total_cost / stories_with_cost if stories_with_cost else None  # avg over stories with cost data

if json_mode:
    print(json.dumps({
        'period': month_filter or 'all-time',
        'stories_done': len(done),
        'stories_failed': len(failed),
        'stories_in_progress': len(in_progress),
        'failure_rate_pct': round(failure_rate, 1),
        'delivery_duration_avg_min': round(avg_lead, 1) if avg_lead else None,
        'delivery_duration_median_min': round(med_lead, 1) if med_lead else None,
        'cost_total_usd': round(total_cost, 2),
        'cost_avg_usd': round(avg_cost, 2) if avg_cost else None,
        'stories_with_cost_data': stories_with_cost,
        'velocity_stories_per_week': round(velocity, 1) if velocity else None,
        'complexity_distribution': complexity_dist,
    }, indent=2))
else:
    period = month_filter or 'all-time'
    print(f'# GAAI Delivery Metrics — {period}')
    print()
    print(f'| Metric | Value |')
    print(f'|--------|-------|')
    print(f'| Stories done | {len(done)} |')
    print(f'| Stories failed | {len(failed)} |')
    print(f'| Stories in progress | {len(in_progress)} |')
    print(f'| Failure rate | {failure_rate:.1f}% |')
    if avg_lead:
        print(f'| Delivery duration (avg) | {avg_lead:.0f}min |')
        print(f'| Delivery duration (median) | {med_lead:.0f}min |')
    else:
        print(f'| Delivery duration | no timing data |')
    print(f'| Total cost | \${total_cost:.2f} ({stories_with_cost}/{len(done)} stories tracked) |')
    if avg_cost:
        print(f'| Cost per story (avg) | \${avg_cost:.2f} |')
    if velocity:
        print(f'| Velocity | {velocity:.1f} stories/week |')
    print()
    if complexity_dist:
        print(f'**Complexity distribution (done):**')
        for k in sorted(complexity_dist.keys(), key=lambda x: int(x) if str(x).isdigit() else 99):
            print(f'  - complexity {k}: {complexity_dist[k]} stories')
"
