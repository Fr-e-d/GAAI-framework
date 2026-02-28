---
type: reference
skill: analytics-query
title: PostHog MCP Query Templates
updated_at: 2026-02-23
---

# PostHog MCP Query Templates

Concrete MCP tool invocation examples for each `analytics-query` analysis pattern.

All templates target the PostHog EU instance. Replace `$PROJECT_ID` with your PostHog project ID (visible in Settings → Project → Project ID).

---

## `funnel-diagnosis`

### 1. Prospect conversion funnel

```
Tool: query_insight
Parameters:
  insight_type: funnels
  events:
    - { event: "prospect.form_submitted" }
    - { event: "prospect.matches_viewed" }
    - { event: "prospect.identified" }
    - { event: "booking.held" }
    - { event: "booking.confirmed" }
  date_from: -30d
  date_to: now
```

Expected output: conversion rate at each step. Largest drop = the diagnosed bottleneck.

### 2. Expert activation funnel

```
Tool: query_insight
Parameters:
  insight_type: funnels
  events:
    - { event: "expert.registered" }
    - { event: "expert.profile_updated" }
    - { event: "expert.gcal_connected" }
  date_from: -30d
  date_to: now
```

### 3. Session replays for drop-off step

```
Tool: list_session_recordings
Parameters:
  filter_by_events:
    - { event: "prospect.form_submitted" }  # had this event
  filter_not_events:
    - { event: "prospect.matches_viewed" }  # but NOT this (dropped here)
  date_from: -7d
  limit: 20
```

### 4. Correlation analysis (HogQL)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      properties.utm_source as source,
      properties.satellite_id as satellite,
      count() as sessions,
      countIf(event = 'booking.confirmed') as conversions,
      round(100 * countIf(event = 'booking.confirmed') / count(), 1) as conversion_pct
    FROM events
    WHERE event IN ('prospect.form_submitted', 'booking.confirmed')
      AND timestamp >= now() - interval 30 day
    GROUP BY source, satellite
    ORDER BY sessions DESC
    LIMIT 20
```

---

## `activation-analysis`

### 1. Expert activation rate (last 30 days)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      count(DISTINCT person_id) as total_registered,
      countIf(
        event = 'expert.gcal_connected'
        AND timestamp <= min_register_time + interval 7 day
      ) as activated_within_7d,
      round(100 * activated_within_7d / total_registered, 1) as activation_rate_pct
    FROM (
      SELECT
        person_id,
        minIf(timestamp, event = 'expert.registered') as min_register_time,
        max(event) as event
      FROM events
      WHERE event IN ('expert.registered', 'expert.gcal_connected')
        AND timestamp >= now() - interval 30 day
      GROUP BY person_id
    )
```

### 2. Aha moment sequence analysis

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      event,
      count() as event_count,
      count(DISTINCT person_id) as unique_experts,
      round(100 * count(DISTINCT person_id) /
        (SELECT count(DISTINCT person_id) FROM events WHERE event = 'expert.registered'
         AND timestamp >= now() - interval 30 day), 1) as pct_of_registered
    FROM events
    WHERE person_id IN (
      SELECT DISTINCT person_id FROM events
      WHERE event = 'expert.registered'
        AND timestamp >= now() - interval 30 day
    )
    AND event IN ('expert.profile_updated', 'expert.gcal_connected', 'expert.registered')
    AND timestamp >= now() - interval 37 day
    GROUP BY event
    ORDER BY unique_experts DESC
```

### 3. 30-day retention: activated vs non-activated

```
Tool: query_insight
Parameters:
  insight_type: retention
  target_entity: { event: "expert.registered" }
  returning_entity: { event: "$pageview" }
  breakdown: { property: "gcal_connected", type: "person" }
  date_from: -60d
  period: Week
```

---

## `lifecycle-check`

### 1. New experts this week vs last week

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      toStartOfWeek(timestamp) as week,
      count(DISTINCT person_id) as new_experts
    FROM events
    WHERE event = 'expert.registered'
      AND timestamp >= now() - interval 14 day
    GROUP BY week
    ORDER BY week
```

### 2. Active vs dormant expert distribution

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      multiIf(
        max(timestamp) >= now() - interval 7 day, 'active_7d',
        max(timestamp) >= now() - interval 30 day, 'active_30d',
        'dormant_30d+'
      ) as lifecycle_status,
      count(DISTINCT person_id) as experts
    FROM events
    WHERE person_id IN (
      SELECT DISTINCT person_id FROM events WHERE event = 'expert.registered'
    )
    AND timestamp >= now() - interval 60 day
    GROUP BY lifecycle_status
```

### 3. Prospect return rate (viewed matches after form submission)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      count(DISTINCT person_id) as submitted,
      countIf(returned = 1) as returned_to_view,
      round(100 * countIf(returned = 1) / count(DISTINCT person_id), 1) as return_rate_pct
    FROM (
      SELECT
        person_id,
        1 as returned
      FROM events
      WHERE event = 'prospect.matches_viewed'
        AND timestamp >= now() - interval 30 day
    )
    RIGHT JOIN (
      SELECT DISTINCT person_id
      FROM events
      WHERE event = 'prospect.form_submitted'
        AND timestamp >= now() - interval 30 day
    ) USING person_id
```

---

## `conversion-trend`

### 1. Weekly prospect → booking conversion rate (last 8 weeks)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      toStartOfWeek(timestamp) as week,
      countIf(event = 'prospect.form_submitted') as submissions,
      countIf(event = 'booking.confirmed') as bookings,
      round(100 * countIf(event = 'booking.confirmed') /
        nullIf(countIf(event = 'prospect.form_submitted'), 0), 1) as conversion_pct
    FROM events
    WHERE event IN ('prospect.form_submitted', 'booking.confirmed')
      AND timestamp >= now() - interval 56 day
    GROUP BY week
    ORDER BY week
```

### 2. Expert registration → gcal connected conversion (weekly trend)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      toStartOfWeek(timestamp) as week,
      countIf(event = 'expert.registered') as registered,
      countIf(event = 'expert.gcal_connected') as gcal_connected,
      round(100 * countIf(event = 'expert.gcal_connected') /
        nullIf(countIf(event = 'expert.registered'), 0), 1) as activation_pct
    FROM events
    WHERE event IN ('expert.registered', 'expert.gcal_connected')
      AND timestamp >= now() - interval 56 day
    GROUP BY week
    ORDER BY week
```

### 3. Anomaly detection (compute in reasoning after query)

After retrieving weekly data:
1. Compute mean and standard deviation of conversion_pct across weeks
2. Flag any week where `|conversion_pct - mean| > 1.5 * stddev`
3. For flagged weeks, cross-reference with: `git log staging --since=WEEK_START --until=WEEK_END --oneline`

---

## `friction-scan`

### 1. Sessions with rage clicks (last 7 days)

```
Tool: list_session_recordings
Parameters:
  filter_rage_click: true
  date_from: -7d
  limit: 30
  order_by: rage_click_count DESC
```

### 2. Sessions with dead clicks

```
Tool: list_session_recordings
Parameters:
  filter_dead_click: true
  date_from: -7d
  limit: 30
```

### 3. High-bounce satellite sessions (HogQL)

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      properties.satellite_id as satellite,
      count(DISTINCT session_id) as total_sessions,
      countIf(
        session_duration < 10
        AND events_count = 1
      ) as bounce_sessions,
      round(100 * countIf(session_duration < 10 AND events_count = 1) /
        count(DISTINCT session_id), 1) as bounce_rate_pct
    FROM sessions
    WHERE timestamp >= now() - interval 7 day
    GROUP BY satellite
    ORDER BY bounce_rate_pct DESC
```

### 4. CTA click rate per satellite

```
Tool: query_hogql
Parameters:
  query: |
    SELECT
      properties.satellite_id as satellite,
      properties.cta_text as cta,
      count() as clicks,
      count(DISTINCT person_id) as unique_clickers
    FROM events
    WHERE event = 'satellite.cta_clicked'
      AND timestamp >= now() - interval 7 day
    GROUP BY satellite, cta
    ORDER BY clicks DESC
```

---

## Notes on Query Limits

- **HogQL queries:** 120/hour. Each `query_hogql` call counts as 1.
- **Structured queries (query_insight):** 2400/hour. Prefer these for standard funnel/retention analysis.
- If rate limit hit: wait 15 minutes, then resume with remaining queries.
- For bulk analysis runs: sequence HogQL queries with a pause between each.
