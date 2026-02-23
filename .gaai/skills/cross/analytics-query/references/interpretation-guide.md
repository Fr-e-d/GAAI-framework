---
type: reference
skill: analytics-query
title: Analytics Interpretation Guide
updated_at: 2026-02-23
---

# Analytics Interpretation Guide

Interpretation benchmarks, Callibrate event taxonomy, the diagnose–hypothesize–test–ship loop, and anti-patterns.

---

## Event Taxonomy

All events follow `object.action` convention in snake_case. Internal traffic should be excluded from all analysis via `$set: { is_internal: true }` person property filter.

### Prospect Funnel Events (E07S02 + E07S03)

| Event | Trigger | Key Properties |
|-------|---------|----------------|
| `$pageview` | Satellite landing page load | `satellite_id`, `referrer`, `utm_source`, `utm_campaign`, `utm_medium` |
| `satellite.cta_clicked` | CTA button click on satellite | `satellite_id`, `cta_text` |
| `prospect.form_submitted` | `POST /api/prospects/submit` | `satellite_id`, `utm_source`, `utm_campaign`, `quiz_field_count` |
| `prospect.matches_viewed` | `GET /api/prospects/:id/matches` | `match_count`, `top_score` |
| `prospect.identified` | `POST /api/prospects/:id/identify` | `email_domain` |
| `expert.availability_checked` | `GET /api/experts/:id/availability` | `expert_id`, `slots_available` |
| `booking.held` | `POST /api/bookings/hold` | `expert_id`, `duration_min` |
| `booking.confirmed` | `POST /api/bookings/:id/confirm` | `expert_id`, `prospect_id`, `duration_min` |
| `booking.cancelled` | `POST /api/bookings/:id/cancel` | `expert_id`, `reason` |

### Expert Funnel Events (E07S03)

| Event | Trigger | Key Properties |
|-------|---------|----------------|
| `expert.registered` | `POST /api/experts/register` | `has_headline`, `has_bio`, `rate_min`, `rate_max` |
| `expert.profile_updated` | `PATCH /api/experts/:id/profile` | `fields_updated[]` |
| `expert.gcal_connected` | `GET /api/gcal/callback` (success) | `expert_id` |
| `expert.gcal_disconnected` | `DELETE /api/experts/:id/gcal` | `expert_id` |

### Survey Events (E07S03)

| Event | Trigger | Key Properties |
|-------|---------|----------------|
| `survey.call_experience_submitted` | `POST /api/surveys/call-experience` | `score`, `booking_id` |
| `survey.lead_evaluation_submitted` | `POST /api/surveys/lead-evaluation` | `lead_quality_score`, `conversion_declared` |

### LLM Monitoring (E07S03)

| Event | Trigger | Key Properties |
|-------|---------|----------------|
| `llm.extraction_completed` | `POST /api/extract` | `model`, `tokens_used`, `latency_ms`, `satellite_id` |

### distinctId Namespacing

- Prospect events: `prospect:{uuid}` (UUID from `prospects.id`)
- Expert events: `expert:{uuid}` (UUID from `experts.id`)
- Client-side PostHog auto-assigns session-scoped IDs for anonymous prospects before identification

---

## Prospect Funnel Benchmarks

Benchmarks for an early-stage B2B marketplace. Calibrate as real data accumulates.

| Funnel Step | "Good" Conversion | Watch if Below | Action Threshold |
|-------------|-------------------|----------------|------------------|
| Landing → CTA clicked | > 15% | < 10% | < 5% (copy/UX issue) |
| CTA clicked → form submitted | > 40% | < 25% | < 15% (friction in form) |
| Form submitted → matches viewed | > 85% | < 70% | < 50% (technical issue likely) |
| Matches viewed → identified (email) | > 30% | < 20% | < 10% (value prop unclear) |
| Identified → booking held | > 25% | < 15% | < 8% (expert pool quality) |
| Booking held → booking confirmed | > 60% | < 40% | < 25% (availability or UX) |

**Overall (landing → confirmed):** > 2% is healthy for cold traffic. < 0.5% warrants a Phase 3 Diagnose cycle.

---

## Expert Activation Benchmarks

| Metric | "Good" | Watch if Below | Action Threshold |
|--------|--------|----------------|------------------|
| Activation rate (registered → gcal_connected within 7d) | > 50% | < 30% | < 15% |
| Profile completion (has_headline AND has_bio within 48h) | > 70% | < 50% | < 30% |
| 30-day retention (active vs dormant) | > 60% active | < 40% active | < 20% active |
| Time to gcal_connected (median) | < 24h | > 72h | > 7d |

**Expert activation is the single most important leading indicator for marketplace supply health.**
An expert who connects Google Calendar within 7 days of registration is 3-5× more likely to complete a booking.

---

## Lifecycle Health Thresholds

| Cohort | Healthy | At Risk | Churn Signal |
|--------|---------|---------|--------------|
| Experts active in last 7d | > 40% of total | < 25% | < 10% |
| Experts dormant > 30d | < 20% of total | > 35% | > 50% |
| Week-over-week new expert growth | Stable or growing | Declining 2 weeks | Declining 3+ weeks |
| Prospect return rate (viewed matches after submit) | > 60% | < 40% | < 20% |

---

## Conversion Benchmarks

| Metric | Healthy | Investigate | Emergency |
|--------|---------|-------------|-----------|
| Week-over-week conversion change | ≤ ±10% | > ±20% | > ±40% |
| Conversion rate std dev / mean | < 25% | 25–50% | > 50% (volatile) |
| LLM extraction latency (p95) | < 2s | > 5s | > 10s |
| LLM extraction error rate | < 1% | > 3% | > 10% |

**Anomaly detection rule:** flag any week where conversion_pct deviates more than 1.5σ from the 8-week rolling mean. Cross-reference anomaly dates with deployment history (`git log staging`) before attributing product causality.

---

## Friction Thresholds

| Signal | Normal | Investigate | Fix Urgently |
|--------|--------|-------------|--------------|
| Bounce rate (< 10s sessions) | < 40% | 40–60% | > 60% |
| Rage click rate (sessions with rage clicks) | < 5% | 5–15% | > 15% |
| Dead click rate (sessions with dead clicks) | < 3% | 3–10% | > 10% |
| CTA click rate on landing page | > 10% | 5–10% | < 5% |

---

## The Diagnose → Hypothesize → Test → Ship Loop

This is the core operating rhythm for data-driven optimization.

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: Baseline                                           │
│   Use lifecycle-check + conversion-trend to establish       │
│   current state. Repeat weekly. Set alerts for drops.       │
└────────────────────────┬────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: Diagnose                                           │
│   1. Run funnel-diagnosis to find biggest drop-off step     │
│   2. Run friction-scan on that step's satellite page        │
│   3. Watch session replays for users who dropped            │
│   4. Run correlation analysis (utm_source, satellite_id)    │
│   → Output: specific drop-off step + probable root cause    │
└────────────────────────┬────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: Hypothesize                                        │
│   State the hypothesis: "If we [change X] then [metric Y]  │
│   will improve by [Z%] because [root cause]"                │
│   → Draft a feature flag A/B test (human approves)          │
└────────────────────────┬────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 5: Test                                               │
│   Human creates feature flag in PostHog                     │
│   Targeting: % of new prospects on affected satellite       │
│   Metric: conversion rate at diagnosed drop-off step        │
│   Duration: min 2 weeks, min 100 prospects per variant      │
└────────────────────────┬────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 6: Compound                                           │
│   If winner: ship → Discovery creates Story → Delivery      │
│   Move to next drop-off step. Repeat from Phase 3.          │
│   If no winner: refine hypothesis or discard                │
└─────────────────────────────────────────────────────────────┘
```

---

## Common Anti-Patterns

### 1. Vanity Metrics

**Pattern:** Tracking total page views or registrations without connecting to revenue outcomes.

**Why it's wrong:** High page views with 0.1% booking conversion is a traffic problem, not a growth signal. Always trace the metric to `booking.confirmed`.

**Correct:** Track funnel conversion rates end-to-end, not individual step volumes.

---

### 2. Analysis Paralysis

**Pattern:** Running 10+ queries before forming a single hypothesis. Waiting for statistical perfection before acting.

**Why it's wrong:** Early-stage data is thin. A 60% confident hypothesis with a 2-week test is worth more than waiting 3 months for 95% confidence.

**Correct:** Run the minimum queries needed to form a specific hypothesis. Run the test. Compound.

---

### 3. Missing Server-Side Events

**Pattern:** Only looking at client-side (satellite) data and missing the conversion steps that happen via API.

**Why it's wrong:** The most important funnel steps (`booking.confirmed`, `expert.gcal_connected`) are server-side events from E07S03. Client-side data alone gives an incomplete picture.

**Correct:** Always cross-reference client-side events (satellite.cta_clicked) with server-side events (prospect.form_submitted, booking.confirmed).

---

### 4. Not Filtering Internal Traffic

**Pattern:** Including founder/dev account activity in funnel analysis.

**Why it's wrong:** A single developer testing the booking flow 10 times inflates booking.confirmed numbers by 10.

**Correct:** All PostHog queries should add `AND NOT person_properties.is_internal = true` as a filter.

---

### 5. Confusing Correlation with Causality

**Pattern:** "utm_source=linkedin shows 3× conversion — let's triple our LinkedIn spend."

**Why it's wrong:** LinkedIn traffic may be higher intent (founder's network) not higher converting from the ad itself.

**Correct:** Form a hypothesis. Run a controlled A/B test. Don't change strategy based on correlation alone.

---

### 6. Over-Segmenting Too Early

**Pattern:** Breaking down every metric by satellite × utm_source × day of week at < 100 sessions/week.

**Why it's wrong:** Small samples produce noisy results. 10 sessions per segment has no statistical meaning.

**Correct:** At early stage (< 500 sessions/week), analyze at the aggregate level first. Segment only when a top-level signal clearly points to a segment.

---

## Rate Limits Reference

| Query Type | Limit | Notes |
|------------|-------|-------|
| HogQL (`query_hogql`) | 120/hour | Each call = 1 query |
| Structured insights (`query_insight`) | 2400/hour | Prefer for standard patterns |
| Session replay list | No explicit hourly limit | Paginated |
| Read dashboards | No explicit hourly limit | Cached 5 min |

**Per-session guideline:** Max 5 HogQL + 3 structured insight queries per analytics-query skill invocation. If more are needed, pause 15 min between batches.
