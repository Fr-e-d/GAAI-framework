---
name: cost-analysis
description: "Analyze API usage costs from delivery logs and produce a per-story and per-period cost report. Activate when estimating theoretical pay-per-use costs, evaluating value produced, or tracking project spend."
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-022
  updated_at: 2026-02-24
  status: stable
  tags: [cost, analytics, billing, reporting]
inputs:
  - delivery_logs_dir: "Path to .gaai/project/contexts/backlog/.delivery-logs/ (default: auto-detected from project root)"
  - backlog_file: "Path to active.backlog.yaml (optional, for enriching with story metadata)"
  - period: "Filter by date range (optional, format: YYYY-MM-DD..YYYY-MM-DD)"
outputs:
  - cost_report: "Formatted table to terminal — per-story cost, per-model breakdown, period summary"
  - cost_data_json: "Optional JSON output for programmatic consumption (--json flag)"
---

# Cost Analysis

## Purpose / When to Activate

Activate when:
- Estimating the theoretical API pay-per-use cost of GAAI-governed delivery
- Evaluating the value produced per dollar spent
- Tracking project spend over a period
- Comparing cost across stories, epics, or delivery phases
- Auditing cost efficiency of the Claude Code + GAAI workflow

This skill reads delivery log JSONL files and extracts the `result` event which contains `total_cost_usd` and `modelUsage` breakdowns computed by Claude Code from Anthropic API pricing.

---

## Prerequisites

- `.gaai/project/contexts/backlog/.delivery-logs/` directory must exist with `*.log` JSONL files
- Delivery logs must contain `result` type events (sessions that completed normally)
- `jq` must be installed (v1.6+)

---

## Data Source

Each delivery log is a JSONL file where each line is a JSON event. The key event is `type: "result"` (typically the last or near-last line), which contains:

```json
{
  "type": "result",
  "total_cost_usd": 4.02,
  "duration_ms": 638355,
  "num_turns": 71,
  "modelUsage": {
    "claude-sonnet-4-6": {
      "inputTokens": 63,
      "outputTokens": 37868,
      "cacheReadInputTokens": 5003015,
      "cacheCreationInputTokens": 89025,
      "costUSD": 4.00
    },
    "claude-haiku-4-5-20251001": {
      "inputTokens": 9759,
      "outputTokens": 794,
      "costUSD": 0.01
    }
  }
}
```

The `total_cost_usd` reflects theoretical Anthropic API pay-per-use pricing (what would be charged without a subscription plan).

---

## Process

### Step 1 — Locate delivery logs

Scan `.gaai/project/contexts/backlog/.delivery-logs/*.log` for available data. Count files, check for `result` events.

### Step 2 — Extract cost data

For each log file, extract the `result` event and capture:
- `total_cost_usd`
- `duration_ms` / `num_turns`
- `modelUsage` per-model breakdown (costUSD, inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens)

Use the reference script `references/extract-costs.sh` or equivalent jq pipeline.

### Step 3 — Enrich with backlog metadata (optional)

If `active.backlog.yaml` is provided, enrich each story with:
- Epic ID
- Title
- `started_at` / `completed_at` dates

### Step 4 — Aggregate

Compute:
- Per-story: cost, duration, turns, model breakdown
- Per-epic: sum of story costs
- Per-model: total cost, percentage
- Per-period: total cost, story count, average cost
- Grand total with min/max/avg/median

### Step 5 — Format and output

Produce a Markdown table to terminal. Optionally output JSON for programmatic use.

### Step 6 — Identify gaps

Report stories without delivery logs or without result events. Estimate missing costs based on comparable stories if requested.

---

## Quality Checks

- Every `result` event is extracted exactly once per log file
- Multi-session stories (multiple result events in one log) are summed correctly
- Model names are mapped to human-readable labels
- Cost totals match sum of per-story costs
- Missing data is explicitly flagged, never silently omitted

---

## Outputs

- **Terminal**: Formatted Markdown report with per-story table, per-model breakdown, period summary, and identified gaps
- **JSON** (optional): Structured data at `references/last-report.json` for programmatic consumption

---

## Known Limitations

1. **Discovery sessions are not captured** — only Delivery logs exist. Discovery cost must be estimated separately.
2. **Sessions without result events** — interrupted sessions lose their cost data. The skill flags these.
3. **Thinking tokens** — included in `total_cost_usd` but not broken out separately in `modelUsage.outputTokens`. Extended thinking is a significant cost component (~40% on Sonnet 4.6).
4. **Pre-logging stories** — stories delivered before the delivery log system was active have no data.

---

## Non-Goals

This skill must NOT:
- Modify delivery logs or backlog files
- Make recommendations about cost optimization (that is a human or Discovery decision)
- Access external APIs or billing dashboards
- Estimate future costs or produce forecasts
- Compare costs to subscription pricing (the user decides how to interpret the data)

**No silent assumptions. Every cost figure is traced to a specific result event or explicitly marked as estimated.**
