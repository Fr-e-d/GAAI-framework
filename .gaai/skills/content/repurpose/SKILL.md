---
name: repurpose
description: Evaluate existing content for refresh, repurposing, or retirement. Activate when content is >90 days old, traffic has declined >20%, or a new content cycle begins. Produces refresh briefs and repurposing plans.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: content
  track: delivery
  id: SKILL-CNT-010
  updated_at: 2026-02-26
  status: stable
  tags: [content, refresh, repurposing, lifecycle, evergreen, cadence]
inputs:
  - "contexts/artefacts/content/published/ (existing published content inventory)"
  - "contexts/memory/content/voice-guide.md (voice consistency reference)"
  - "contexts/memory/content/sources/SRC-001.md (CRED013 — Freshness Trust Chain)"
  - "contexts/memory/content/sources/SEO-001.md (AKU-002 — Trust, timestamp signals)"
  - "contexts/memory/content/sources/KWR-001.md (scoring model for keyword re-evaluation)"
  - "Analytics data (PostHog / GSC — provided by invoking agent)"
outputs:
  - "contexts/artefacts/content/drafts/{id}-refresh-brief.md"
  - "contexts/artefacts/content/drafts/{id}-repurpose-plan.md (optional)"
  - "Content lifecycle audit report (inline to agent)"
---

# Repurpose & Refresh (CNT-010)

## Purpose

Evaluate existing published content against freshness, performance, and accuracy criteria. Produce actionable briefs: refresh (update in place), repurpose (transform into new format), or retire (remove or redirect).

## When to Activate

Activate when:
- A scheduled content review cycle begins (quarterly for evergreen, monthly for fast-moving domains)
- Analytics show traffic decline >20% on a specific piece (provided by invoking agent)
- A domain update invalidates factual claims in existing content (e.g., Google algorithm change, new tool version)
- A new content piece is planned on a topic already covered (cannibalization check via KWR-001 AKU-KWR006)
- The invoking agent requests a content lifecycle audit

Do NOT activate when:
- Content was published <30 days ago (too early for meaningful signals)
- The task is to create new content from scratch (use CNT-001 through CNT-006)
- The task is to transform content for social media (use CNT-007-social-adapt)

---

## Process

### Phase 1 — Content inventory scan

1. List all published content in `contexts/artefacts/content/published/`
2. For each piece, extract:
   - Publication date
   - Last modification date (dateModified from structured data or file metadata)
   - Primary keyword / topic cluster
   - Content type (blog post, case study, tutorial, milestone report)
3. Calculate **age** = days since last modification
4. Flag pieces by review urgency:
   - **Urgent** (>180 days unmodified for fast-moving domains like AI/tech)
   - **Due** (>90 days for evergreen, >30 days for news/trends)
   - **Current** (<90 days with no performance signals)

### Phase 2 — Performance assessment

For each flagged piece, evaluate (data provided by invoking agent from PostHog/GSC):

| Signal | Threshold | Action |
|--------|-----------|--------|
| Organic traffic decline >20% over 30 days | Investigate | Check for SERP position loss, new competitors, intent shift |
| Position drop >5 positions for primary keyword | Refresh candidate | Content may be outdated or outcompeted |
| CTR decline with stable position | Meta refresh | Update title tag + meta description (SEO-002 AKU-OP003/OP008) |
| High impressions, low CTR | Snippet optimization | Update featured snippet targeting (GEO-001 AKU-GEO005) |
| Bounce rate >80% | Content quality issue | Review intent alignment (SEO-002 AKU-OP002) |
| No performance data available | Skip | Cannot evaluate without data — mark for future review |

### Phase 3 — Freshness & accuracy audit

For each refresh candidate:

1. **Factual accuracy check:**
   - Are statistics still current? (flag any data >12 months old)
   - Have cited sources been updated or retracted?
   - Have tools/platforms mentioned changed significantly?
   - Are code examples still functional?

2. **Freshness signals check** (per SRC-001 AKU-CRED013):
   - Is dateModified present in structured data?
   - Does the content reference current year/data?
   - Are there dead links?

3. **Competitive gap check:**
   - Has a competitor published superior content on the same topic?
   - Has search intent shifted (informational → transactional, or vice versa)?

### Phase 4 — Decision: Refresh vs Repurpose vs Retire

Apply the decision tree:

```
Content piece flagged
    │
    ├─ Factually wrong or dangerously outdated?
    │   ├─ YES → Can be corrected with <30% rewrite?
    │   │   ├─ YES → REFRESH (update in place)
    │   │   └─ NO  → REWRITE (treat as new content via CNT-001→CNT-006)
    │   └─ NO → continue
    │
    ├─ Traffic declining but content accurate?
    │   ├─ Position drop → REFRESH (update freshness signals + expand coverage)
    │   ├─ CTR drop → META REFRESH (title + meta description only)
    │   └─ Intent shifted → REWRITE or RETIRE + redirect
    │
    ├─ Content performing well but format-limited?
    │   └─ REPURPOSE (transform into new format — see Step 5)
    │
    └─ Content irrelevant (topic abandoned, product pivoted)?
        └─ RETIRE (301 redirect to closest relevant page, or noindex)
```

### Phase 5 — Generate refresh brief

For each REFRESH decision, produce a brief:

```markdown
# Refresh Brief — {content title}

**Original:** {path to published file}
**Published:** {date} | **Last modified:** {date} | **Age:** {days}
**Decision:** REFRESH | META REFRESH | REWRITE | REPURPOSE | RETIRE
**Priority:** High | Medium | Low
**Estimated effort:** {light: <1h | medium: 1-3h | heavy: 3h+}

## What needs updating
- {specific item 1 — e.g., "Statistics in Section 2 are from 2024, need 2025-2026 data"}
- {specific item 2 — e.g., "Dead link to [source] in paragraph 4"}
- {specific item N}

## What stays
- {elements that are still accurate and well-written}

## SEO actions
- [ ] Update dateModified in structured data
- [ ] {keyword-specific action if applicable}
- [ ] {internal link additions if new related content exists}

## After refresh
- Re-run CNT-005-seo-optimize validation
- Re-run CNT-006-geo-optimize validation
- Update dateModified
- Re-distribute via CNT-007-social-adapt if changes are substantial
```

### Phase 6 — Generate repurpose plan (optional)

For content suitable for format transformation beyond social (social = CNT-007):

| Source format | Target format | When |
|--------------|---------------|------|
| Blog post (high-performing) | Lead magnet / PDF guide | When content has consistent traffic + email capture goal |
| Case study | Webinar outline / talk proposal | When content validates a repeatable methodology |
| Tutorial series (3+ related posts) | Comprehensive guide (pillar page) | When cluster is complete (SEO-001 AKU-013) |
| Milestone report | Newsletter issue | When email distribution is active (T5 — currently deferred) |

Produce a repurpose plan only when a clear format opportunity exists. Do not force repurposing.

---

## Outputs

### Inline to agent: Content Lifecycle Audit Report

```
## Content Lifecycle Audit — {date}

| Content | Age | Performance | Decision | Priority | Effort |
|---------|-----|-------------|----------|----------|--------|
| {title} | {days} | {trend} | REFRESH/RETIRE/etc | H/M/L | light/medium/heavy |
| ... | ... | ... | ... | ... | ... |

Summary: {N} pieces audited. {X} refresh, {Y} meta refresh, {Z} retire, {W} current.
Next audit: {date + cadence interval}
```

### File output: Refresh briefs

One `{id}-refresh-brief.md` per piece flagged for refresh, saved to `contexts/artefacts/content/drafts/`.

### File output: Repurpose plans (optional)

One `{id}-repurpose-plan.md` per piece flagged for format transformation.

---

## Cadence Framework

| Content type | Review frequency | Freshness threshold |
|-------------|-----------------|---------------------|
| AI/tech tutorials | Every 30 days | Data >3 months = stale |
| Evergreen guides | Every 90 days | Data >12 months = stale |
| Case studies | Every 180 days | Results >6 months = needs update |
| Milestone reports | Never refresh | Historical record — do not modify |
| News/trend pieces | Every 30 days | >60 days = likely outdated |

---

## Quality Checks

- [ ] Every refresh brief includes specific items to update (not vague "needs updating")
- [ ] Factual accuracy check covers all statistics and external links
- [ ] Decision tree was applied consistently (not arbitrary decisions)
- [ ] dateModified update is included in every refresh brief
- [ ] No refresh brief proposes changes that would alter the content's original SEO target without re-evaluating keywords (KWR-001)
- [ ] Retire decisions include a redirect target (never orphan a URL)
- [ ] Cadence framework is applied (not over-auditing current content)

---

## Non-Goals

This skill must NOT:
- Execute the refresh itself — it produces briefs. The refresh is executed via CNT-003 through CNT-006.
- Create entirely new content — if the decision is REWRITE, route to CNT-001 (research phase).
- Transform content for social media — that is CNT-007-social-adapt.
- Make SEO strategy decisions (which keywords to target, which clusters to build) — that is CNT-001-research.
- Access analytics directly — data must be provided by the invoking agent.

**This skill audits and plans. It does not execute content changes.**
