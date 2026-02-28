---
name: generate-build-in-public-content
description: Generate build-in-public content drafts from completed delivery artefacts. Applies the Golden Circle (WHY → HOW → WHAT) to transform stories, decisions, and metrics into ready-to-review content pieces (X threads, blog snippets, metrics posts). Activate automatically after each story reaches `done` status.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-021
  tags:
    - content
    - build-in-public
    - marketing
    - automation
  updated_at: 2026-02-26
  status: stable
inputs:
  - completed story artefact (story.md)
  - impl-report or micro-delivery-report (if available)
  - qa-report (if available)
  - decision log entries referenced by the story
  - backlog entry (status, dates, ai_cost_usd, human_md_estimate, human_cost_usd)
  - current project metrics (test count, story count, decision count)
outputs:
  - contexts/artefacts/content/drafts/{id}-thread.md (X/Twitter thread draft)
  - contexts/artefacts/content/drafts/{id}-blog-snippet.md (blog paragraph, optional)
  - contexts/artefacts/content/drafts/{id}-metrics.md (weekly metrics post, if milestone)
---

# Generate Build-in-Public Content

## Purpose / When to Activate

Activate **automatically** at the end of the delivery cycle, after:
- A story is marked `done` (QA PASS, PR merged)
- A significant decision is logged (DEC- entry with architectural or strategic impact)
- A milestone is reached (Gate PASS, epic completed, round number — e.g., 100th test, 50th decision)

Do NOT activate for:
- Cancelled stories
- Trivial bug fixes or config changes
- Stories marked done but with no meaningful user-facing or architectural change

---

## The Golden Circle Framework (Simon Sinek)

Every content piece follows WHY → HOW → WHAT. This is non-negotiable.

### WHY (lead with this — it's what makes people stop scrolling)
- What problem were we solving? What pain exists in the world?
- Why does this matter beyond our project?
- Extract from: story **Context** section, related **DEC- entries** (Context field)

### HOW (the differentiator — what makes our approach interesting)
- How did we approach it differently? What governance/framework made this possible?
- What did the AI agents do? What did the human do? How did Dual-Track help?
- Extract from: **DEC- entries** (Decision + Rationale fields), execution plan, agent composition

### WHAT (the proof — concrete, specific, no fluff)
- What exactly was shipped? Numbers, not adjectives.
- Extract from: **backlog entry** (dates, cost), **qa-report** (test count), **impl-report** (files changed, ACs met)

---

## Process

### Step 1 — Gather inputs (automatic)

Load the minimum context needed:

```
1. Read the completed story artefact → extract Context, User Story, AC count
2. Read the backlog entry → extract started_at, completed_at, ai_cost_usd, human_cost_usd
3. Read referenced DEC- entries (from story notes) → extract Context + Decision + Rationale
4. Count current project metrics:
   - Total stories done (grep status: done in backlog)
   - Total decisions (count in _log.md + archived)
   - Total tests (latest vitest count from qa-report or CI)
   - Total epics
```

### Step 2 — Generate X/Twitter thread draft

Format: 5-7 tweets. First tweet is the hook (WHY). Last tweet is the CTA.

```markdown
# Thread: {story title}
## Generated from: {story_id} | Date: {completed_at}

**Tweet 1 (WHY — hook):**
[One provocative or insightful statement about the problem this solves.
No "I just shipped..." — start with the insight.]

**Tweet 2 (WHY — context):**
[Expand on the problem. Real data if available. Industry context.]

**Tweet 3 (HOW — approach):**
[How we solved it. What the AI agents did. What made this different.
Mention Dual-Track, governance, decision log — but naturally, not as jargon.]

**Tweet 4 (WHAT — result):**
[Concrete numbers. ACs met, tests passing, time taken, cost.
Screenshot suggestion: [describe what to screenshot]]

**Tweet 5 (WHAT — proof):**
[Show, don't tell. Paste a real excerpt: a decision entry, a backlog snippet,
a test output. Raw artifacts > polished prose.]

**Tweet 6 (reflection):**
[One honest learning. What surprised you. What you'd do differently.
Vulnerability > perfection.]

**Tweet 7 (CTA):**
[Forward hook. What's next. Invite engagement.
"Follow for more" or "The framework will be open-sourced soon."]
```

### Step 3 — Generate blog snippet (optional, for milestone stories)

Only for stories that are:
- Gate completions
- Epic completions
- Architectural decisions with broad implications
- Stories that generated 2+ DEC- entries

Format: 300-500 words. One section of the monthly blog post. Includes the Golden Circle structure as prose (not labeled sections).

### Step 4 — Generate metrics post (weekly cadence)

If this is the last story of the week (or Saturday/Sunday), generate:

```markdown
# Week {N} — Build in Public Metrics

Stories shipped this week: {count}
Total stories done: {total}
Decisions documented: {total}
Tests passing: {count}
Notable: {one-line highlight of the week}
```

### Step 5 — Save to content queue

All drafts saved to `contexts/artefacts/content/drafts/` with naming:

```
{story_id}-thread.md      → X/Twitter thread
{story_id}-blog.md        → Blog snippet (if applicable)
week-{N}-metrics.md       → Weekly metrics
```

Drafts are **NOT published automatically**. They are queued for human review.
The founder reviews drafts in batch (10-15 min/week), edits if needed, then publishes.

After publication, move from `drafts/` to `published/`.

---

## Content Principles (Non-Negotiable)

1. **WHY first, always.** Nobody cares what you shipped. They care why it matters.
2. **Numbers, not adjectives.** "260 tests pass" > "comprehensive test coverage."
3. **Show raw artifacts.** A screenshot of a real decision log entry is more compelling than 500 words of explanation.
4. **One insight per piece.** Don't cram everything. One story = one thread = one idea.
5. **Honest > impressive.** Share failures, pivots, surprises. DEC-41 (Cal.com platform closed) is more interesting than DEC-02 (basic setup).
6. **No jargon without context.** "Dual-Track" means nothing to most people. Explain it the first time, then use it.
7. **Respect the audience's time.** If a thread can be 4 tweets instead of 7, make it 4.

---

## Quality Checks

- [ ] Every draft follows WHY → HOW → WHAT order
- [ ] Every draft contains at least 1 concrete number
- [ ] Every draft suggests at least 1 screenshot/visual
- [ ] No draft exceeds 7 tweets (threads) or 500 words (blog snippets)
- [ ] Tone check: sounds like a real person sharing their journey, not a corporate blog
- [ ] No sensitive data (API keys, internal URLs, customer data)
- [ ] No self-congratulation ("amazing", "incredible", "game-changer")

---

## Non-Goals

This skill must NOT:
- Publish content directly (human review is mandatory)
- Generate video scripts or face-cam content
- Create content for stories that are trivial or cancelled
- Fabricate metrics or round numbers for effect
- Generate content in French (English first — global AI audience)
- Add hashtags (they reduce engagement on X)
- Use emojis excessively (1-2 max per thread, if natural)

---

## Integration with Delivery Workflow

This skill is triggered by the Delivery Orchestrator as the **final step** after:

```
QA PASS → PR merged → backlog updated to done → memory-delta saved
  → generate-build-in-public-content (this skill)
  → drafts saved to content queue
```

It does NOT block the delivery cycle. If content generation fails, the story is still done.
Content is a byproduct, not a dependency.
