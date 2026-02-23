---
name: analytics-query
description: Query PostHog analytics data and surface data-driven growth insights for Callibrate funnels using the PostHog MCP server. Activate when a Discovery Agent session requires funnel diagnosis, activation analysis, lifecycle check, conversion trend analysis, or friction scanning.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-020
  status: stable
  updated_at: 2026-02-23
  tags:
    - analytics
    - posthog
    - growth
    - funnel
inputs:
  - posthog_mcp: PostHog MCP server (configured in .mcp.json — must be connected)
  - analysis_pattern: one of funnel-diagnosis | activation-analysis | lifecycle-check | conversion-trend | friction-scan
  - optional context: date range, segment filter, specific event or funnel to inspect
outputs:
  - inline analysis report (findings, signal strength, recommended action)
  - optional: draft hypothesis for feature flag A/B test
---

# Analytics Query

## Purpose / When to Activate

Activate when a Discovery Agent session requires objective data to inform product decisions.

Use this skill to:
- Diagnose where prospects or experts drop off in a funnel
- Identify which behaviors predict expert retention (activation)
- Check the health of new/returning/dormant user distribution
- Detect conversion rate anomalies over time
- Surface friction signals (rage clicks, dead clicks, high-bounce sessions)

**Prerequisite:** The PostHog MCP server must be connected in Claude Code (configured in `.mcp.json`). If the `posthog` server is not listed in `/mcp`, stop and instruct the human to complete the SETUP.md PostHog MCP section.

**Requires:** PostHog events from E07S02 (satellite client-side) and E07S03 (core API server-side) must have been flowing for at least 48 hours before meaningful funnel data exists.

---

## Analysis Patterns

### `funnel-diagnosis`

**Goal:** Identify the biggest drop-off step in a funnel.

```
1. Query the prospect conversion funnel (or expert activation funnel)
2. Read step-by-step conversion rates
3. Identify the step with the largest absolute drop
4. Run session replays filter: users who dropped at that step
5. Run correlation analysis: which properties correlate with conversion vs drop-off
6. Formulate a hypothesis for the drop-off root cause
```

Consult `references/query-templates.md` → section `funnel-diagnosis` for PostHog MCP tool invocations.
Consult `references/interpretation-guide.md` → section `Prospect Funnel Benchmarks` for thresholds.

---

### `activation-analysis`

**Goal:** Find which event combinations predict expert retention (AARRR Activation).

```
1. Define activation = gcal_connected + profile_updated within 7 days of registration
2. Query: ratio of experts who hit activation milestone vs total registered (last 30 days)
3. Query: cohort retention at 30d for activated vs non-activated experts
4. Identify the "aha moment" event sequence with highest retention correlation
5. Report activation rate + retention delta between activated/non-activated
```

Consult `references/query-templates.md` → section `activation-analysis`.
Consult `references/interpretation-guide.md` → section `Expert Activation Benchmarks`.

---

### `lifecycle-check`

**Goal:** Understand the new/returning/dormant distribution for experts and prospects.

```
1. Query: new experts this week vs last week
2. Query: experts active in last 7 days (has event in window) vs dormant (no event in 30d)
3. Query: prospects submitted this week vs last week
4. Query: prospects who returned to view matches after initial submission
5. Flag any cohort with > 30% dormant rate as a churn risk signal
```

Consult `references/query-templates.md` → section `lifecycle-check`.
Consult `references/interpretation-guide.md` → section `Lifecycle Health Thresholds`.

---

### `conversion-trend`

**Goal:** Time-series conversion rate with anomaly detection.

```
1. Select the key conversion metric (prospect: form_submitted → booking.confirmed; expert: registered → gcal_connected)
2. Query weekly conversion rates for the last 8 weeks
3. Compute mean and standard deviation
4. Flag any week where conversion rate deviates > 1.5σ from mean
5. For flagged weeks: cross-reference with deployment dates (git log staging) or external events
6. Report trend (improving / stable / declining) + any anomalies with hypotheses
```

Consult `references/query-templates.md` → section `conversion-trend`.
Consult `references/interpretation-guide.md` → section `Conversion Benchmarks`.

---

### `friction-scan`

**Goal:** Identify rage clicks, dead clicks, and high-bounce sessions on satellite pages.

```
1. Query session replay list: filter rage_click = true (last 7 days)
2. Query session replay list: filter dead_click = true (last 7 days)
3. Identify which satellite pages have highest bounce rate (single page sessions)
4. Identify which CTA elements have highest rage click count
5. Summarize top 3 friction hotspots with element + page context
6. Recommend: session replay review for each hotspot (provide replay URLs if available)
```

Consult `references/query-templates.md` → section `friction-scan`.
Consult `references/interpretation-guide.md` → section `Friction Thresholds`.

---

## Conversion Optimization Loop (Embedded Playbook)

This skill encodes the core operating rhythm for data-driven optimization:

```
Phase 1: Instrument  ← E07S01-S03 (already done)
Phase 2: Baseline    ← Use lifecycle-check + conversion-trend to establish baselines
Phase 3: Diagnose    ← Use funnel-diagnosis + friction-scan to find the highest-impact drop-off
Phase 4: Hypothesize ← Formulate a specific testable change based on diagnosis
Phase 5: Test        ← Recommend A/B test via PostHog feature flags (human approves)
Phase 6: Compound    ← Ship winner, move to next drop-off, repeat from Phase 3
```

**Important:** This skill produces diagnosis and hypotheses. It does NOT:
- Automatically activate or modify feature flags
- Ingest findings into GAAI memory (invoke `memory-ingest` separately after human review)
- Make product decisions (Discovery Agent or human decides what to test)

---

## Quality Checks

- Analysis pattern selected matches the actual question being asked
- Query templates used are from `references/query-templates.md` (not ad-hoc guesses)
- Findings report explicitly states confidence level (low/medium/high) based on sample size
- Anomalies are cross-referenced with deployment history before attributing causality
- PII never appears in query filters or results (distinctIds are namespaced UUIDs, not emails)
- Rate limits respected: max 5 HogQL queries per analysis run; use structured queries where possible

---

## Outputs

Returns inline to the invoking Discovery session:

```
Pattern: {pattern_name}
Date range: {range}

Findings:
  {numbered list of data-backed observations}

Key signal: {the highest-confidence actionable finding}

Recommended next action: {specific, bounded next step}
  Options:
    - Watch session replays: {filter criteria}
    - Run A/B test: {hypothesis}
    - Investigate deployment: {date/commit}
    - No action needed — metric within healthy range

Confidence: low | medium | high
  Reason: {sample size, data age, or missing event coverage note}
```

---

## Non-Goals

This skill must NOT:
- Make automated product decisions or backlog changes
- Ingest analysis results into GAAI memory without explicit human review
- Modify, enable, or disable feature flags (human approves all flag changes)
- Query PII or attempt to deanonymize users from event data
- Run more than 5 HogQL queries per session (rate limit protection)
- Replace PostHog's built-in Max AI assistant for ad-hoc dashboard exploration

**References:**
- `references/query-templates.md` — concrete PostHog MCP tool invocation examples
- `references/interpretation-guide.md` — benchmarks, event taxonomy, anti-patterns

**No silent assumptions. Every analysis finding becomes explicit and governed.**
