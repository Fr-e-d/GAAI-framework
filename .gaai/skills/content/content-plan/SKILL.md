---
name: content-plan
description: Generate a monthly content production plan by evaluating current GTM phase, inventorying existing content, and recommending 2-3 hub content pieces positioned on all 6 CONTENT-STRATEGY-001 dimensions (Layer, Phase, Audience, Channel, Objective, ARL) with BP scoring. Activate at the start of each month or when /gaai-status flags that no current-month plan exists.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: content
  track: discovery
  id: SKILL-CNT-011
  updated_at: 2026-02-26
  status: stable
  tags: [content, planning, strategy, monthly-cadence, budget]
inputs:
  - "contexts/artefacts/strategy/CONTENT-STRATEGY-001.md (6-dimension model, BP scoring, ARL, phase gates, anti-patterns)"
  - "contexts/artefacts/strategy/GTM-001.md (current phase determination)"
  - "contexts/artefacts/strategy/COMMS-001.strategy.md (channel strategy, personas, cadence)"
  - "contexts/backlog/active.backlog.yaml (story statuses → GTM phase inference)"
  - "contexts/artefacts/content/drafts/ (existing draft inventory)"
  - "contexts/artefacts/content/published/ (existing published inventory)"
  - "contexts/artefacts/content/plans/ (previous month plan, if exists)"
  - "contexts/memory/domains/content-production/voice-guide.md (voice reference)"
  - "Analytics data (PostHog / GSC — provided by invoking agent, optional)"
outputs:
  - "contexts/artefacts/content/plans/YYYY-MM-content-plan.md (monthly content plan)"
  - "Inline to agent: story draft recommendations ready for Discovery to validate and add to backlog"
---

# Content Plan (CNT-011)

## Purpose

Generate a monthly content production plan that operationalizes CONTENT-STRATEGY-001 into actionable recommendations. Bridges the gap between strategic intent (6-dimension model, BP scoring, phase gates) and execution (stories in the backlog → CNT pipeline → published content).

## When to Activate

Activate when:
- The start of a new calendar month arrives and no current-month plan exists in `plans/`
- `/gaai-status` flags "Content plan due" (Section 5)
- The founder requests a content plan via `/gaai-discover`
- A GTM phase transition occurs (Gate PASS) — the phase change unlocks new content types

Do NOT activate when:
- A current-month plan already exists and is still valid
- Mid-month unless a phase transition invalidates the existing plan
- Content is being produced (use CNT-001 through CNT-009 instead)
- A content audit is needed (use CNT-010-repurpose instead)

---

## Process

### Step 1 — Determine current GTM phase

Read `active.backlog.yaml` and `GTM-001.md`. Determine phase by checking gate criteria:

```
IF all E06 Phase 1 stories are done AND Gate 1 criteria met → Phase 2 (BIP + first cohort)
IF Gate 2 criteria met → Phase 3 (monetisation)
IF Gate 3 criteria met → Post-J90
ELSE → Phase 0-1 (current default)
```

The phase determines (per CONTENT-STRATEGY-001 §3):
- Which content types are **authorized** (no case studies before real cases)
- Which **audience ratios** apply (§4: 80% builder in Phase 0-1, supply-first in Phase 2)
- Which **BP scoring targets** apply (§6: no BP-3 in Phase 0-1)

### Step 2 — Inventory existing content

Scan three directories:

1. **`contexts/artefacts/content/published/`** — what has been published, with dates
2. **`contexts/artefacts/content/drafts/`** — what is in review queue
3. **`contexts/artefacts/content/plans/`** — previous month plan (if exists)

For each piece, extract:
- Title and content type
- 6-dimension coordinates (if tagged in the file)
- BP score
- Publication date

If a previous month plan exists, assess execution:
- What was planned vs. what was produced/published
- What was abandoned and why (inform this month's planning)

### Step 3 — Evaluate underserved dimensions

Cross-reference the content inventory against CONTENT-STRATEGY-001 targets:

| Dimension | Check |
|-----------|-------|
| **Layer** | Are all relevant layers covered? Is L3 (.gaai) established enough for L4? |
| **Phase** | Are we producing content authorized by the current phase? |
| **Audience** | Does the ratio match the phase target? (§4: supply/demand/builder ratios) |
| **Channel** | Are all active channels being fed? (COMMS-001 cadence targets) |
| **Objective** | Any funnel stage with zero content? |
| **ARL** | Are we only targeting ARL-0, or is there ARL-2/3 content for ready audiences? |
| **BP** | Is BP ≥ 2 content present? (§8.1: bottom-up sequencing priority) |

Flag gaps explicitly. These drive recommendations.

### Step 4 — Recommend 2-3 hub content pieces

For each recommendation:

1. **Title** — working title (will evolve during CNT-001 research)
2. **Position on 6 dimensions:**
   - Layer: L1/L2/L3/L4
   - Phase: Ideation/Implementation/BIP/Growth
   - Audience: P1/P2/P3/P4 (primary + optional secondary)
   - Channel: Hub channel → derivative channels
   - Objective: Awareness/Credibility/Trust/Education/Conversion/Retention
   - ARL: 0-4
3. **BP score** (0-3) with justification
4. **Rationale** — why this piece, why now, which gap it fills
5. **Pipeline** — which CNT skills it will traverse (e.g., CNT-001 → CNT-003 → CNT-004 → CNT-005 → CNT-007)
6. **Estimated effort** — light (<1h) / medium (1-2h) / heavy (2-3h)

**Validation per piece:**
- Does it respect the current phase gate? (§3)
- Does it pass the anti-pattern check? (§13)
- Is the channel fit valid? (§5: format, length, tone constraints)
- Is max 2 adjacent layers respected?

### Step 5 — Native content guidance

Provide brief guidance for spontaneous native content:
- Which platforms to prioritize this month
- Suggested angles aligned with current themes
- Time-box reminder (30 min/interaction)
- Reddit subreddit rotation suggestions

### Step 6 — Generate budget allocation

Map all recommendations against the 5h/week budget (COMMS-001 constraint):

```
Weekly budget allocation:
  Hub content production:    2h
  Social adaptation (CNT-007): 30 min
  Native content:            1h30
  Review & publication:      30 min
  Community engagement:      30 min
  ────────────────────────────
  Total:                     5h
```

Verify the plan respects these constraints. If recommendations exceed budget, reduce scope or defer.

### Step 7 — Generate story draft recommendations

For each hub content piece, produce a story-shaped recommendation that Discovery can validate:

```markdown
## Story Draft: {title}

**Type:** Content production
**Blueprint:** content
**Pipeline:** {CNT skills sequence}

**User Story:**
As [persona], I want to read [content type] about [topic] so that [value delivered].

**Acceptance Criteria:**
- [ ] Content positioned on 6 dimensions: {coordinates}
- [ ] BP-{score} justified in the piece
- [ ] Voice check passed (voice-guide.md compliance)
- [ ] Kill list cleared (COMMS-001 §0)
- [ ] Channel constraints met (format, length, tone per §5)
- [ ] Final draft reviewed by founder before publication
- [ ] Published and moved to published/ directory
- [ ] Social adaptations generated via CNT-007
```

These are **recommendations**. Discovery validates and adds to the backlog. This skill does NOT add stories directly.

---

## Output Format

```markdown
# Content Plan — {YYYY-MM}

**Date:** {plan creation date}
**GTM Phase:** {current phase}
**Budget:** 5h/week ({total}h for the month)
**Content inventory:** {N} published, {M} in drafts

## Previous Month Review
| Planned | Status | Notes |
|---------|--------|-------|
| {title} | published / in-draft / abandoned | {outcome or reason} |

## Gap Analysis
{dimensions underserved, ratios off-target, funnel gaps}

## Hub Recommendations

### Hub 1: {title}
| Dimension | Value |
|-----------|-------|
| Layer | {value} |
| Phase | {value} |
| Audience | {primary} + {secondary} |
| Channel | {hub} → {derivatives} |
| Objective | {value} |
| ARL | {value} |
| BP | {value} |
| Effort | {light/medium/heavy} |
| Pipeline | CNT-{...} → CNT-{...} → ... |

**Rationale:** {why this piece, why now}

### Hub 2: {title}
{same format}

## Native Content Guidance
- {platform}: {angles, subreddits, time-box}

## Budget Breakdown
| Activity | Week 1 | Week 2 | Week 3 | Week 4 | Total |
|----------|--------|--------|--------|--------|-------|
| Hub production | ... | ... | ... | ... | ... |
| Social adapt | ... | ... | ... | ... | ... |
| Native | ... | ... | ... | ... | ... |
| Review | ... | ... | ... | ... | ... |
| Community | ... | ... | ... | ... | ... |

## Story Drafts for Backlog
{story-shaped recommendations per Step 7}
```

---

## Quality Checks

- [ ] All hub recommendations are positioned on all 6 dimensions
- [ ] BP score is assigned and justified for each piece
- [ ] No piece violates the current GTM phase gate (no claims without data)
- [ ] No anti-pattern from CONTENT-STRATEGY-001 §13 is present
- [ ] Total estimated effort respects the 5h/week budget
- [ ] At least 1 piece has BP ≥ 2 (if Phase ≥ 2)
- [ ] Audience ratio matches the phase-appropriate target (§4)
- [ ] Each piece specifies the complete CNT pipeline
- [ ] Previous month review is included (if a prior plan exists)
- [ ] Story drafts have explicit acceptance criteria
- [ ] Native content guidance is included with time-box reminder
- [ ] Max 2-3 hub recommendations (not more — budget constraint)

---

## Non-Goals

This skill must NOT:
- Execute any content production step (that is CNT-001 through CNT-009)
- Make GTM phase advancement decisions (that is the founder + GTM-001 gates)
- Override the 5h/week budget constraint
- Plan native/spontaneous content in detail (that is inherently unplanned)
- Access analytics directly (data must be provided by the invoking agent if available)
- Add stories to the backlog directly (it recommends; Discovery validates)
- Replace CONTENT-STRATEGY-001 (this skill operationalizes it, does not modify it)
- Decide which keywords to target (that is CNT-001-research)

**This skill plans. It does not produce content.**
