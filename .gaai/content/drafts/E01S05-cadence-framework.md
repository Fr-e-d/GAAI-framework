# E01S05 — Ongoing Content Cadence Framework

> Status: Active
> Budget: 5h/week maximum (not a distraction from building — a sub-product of building)
> Automation: SKILL-CRS-021 auto-generates drafts in `content/drafts/` after each story `done`

---

## Cadence Table

| Format | Effort | Cadence | Source |
|--------|--------|---------|--------|
| X/Twitter thread | 30 min | 2-3x/week | .gaai decision log entries, backlog milestones, interesting architectural choices |
| Weekly metrics post | 15 min | Weekly (Friday) | Stories shipped, decisions made, tests passing, any notable event |
| Milestone blog post | 4-5h | 1x/month max | Major delivery milestones, architecture decisions, lessons with enough density to justify long-form |
| Screenshot annotations | 10 min | Ad hoc | Terminal (Claude Code in action), backlog view, decision log — ready-made content that takes 10 minutes to caption |
| Reddit engagement | Ongoing | 3-4x/week | Community value first. 90/10 rule: 90% contribute value, 10% mention your work. Never lead with the product. |

**Weekly time budget breakdown:**

| Activity | Time/week |
|----------|-----------|
| SKILL-CRS-021 draft review + approval | 15 min |
| X/Twitter thread (×2) | 60 min |
| Weekly metrics post | 15 min |
| Reddit engagement | 60 min |
| Ad hoc screenshots/captions | 30 min |
| **Total** | **~3h** |

Buffer: 2h remaining for milestone blog posts (amortized monthly, not weekly).

---

## AC26: Auto-Generated Content via SKILL-CRS-021

The delivery workflow (skill SKILL-CRS-021) generates a content draft in `content/drafts/` after each story moves to `done`.

**What the skill produces:**
- 1 X/Twitter thread draft (2-4 tweets, story-specific insight or decision)
- 1 weekly metrics update snippet (ready to paste)
- If the story contains a notable DEC-entry or architectural decision: a short-form blog section draft

**Founder's weekly routine:**
- Saturday morning: open `content/drafts/`, review auto-generated drafts
- Approve/edit/discard in batch (15 min target)
- Queue approved content for the week
- No content creation from scratch — only curation and voice

This is the design intent: **the build log IS the content strategy.** The decision log, the backlog, the test counts — all of it is already documented. The content effort is making it public in digestible pieces, not creating documentation from nothing.

---

## Tease Orchestration Phases

Content is not just content. Each piece is part of the pre-launch funnel for multiple products. Same effort, four audiences warmed in parallel.

**Phase 1 — Now (pre-Gate 1):**
- Tease: Callibrate (the product being built)
- Tease: .gaai framework (the governance layer)
- Signal: the builder's approach (credibility, not promotion)
- No product name in Reddit posts. Mentions of "a matching marketplace" are fine.

**Post Gate 1 (≥10 experts + ≥15 prospects raise hand):**
- Tease: .gaai OSS — "the governance framework will be on GitHub soon"
- Increase specificity on Callibrate features (platform is proven, talking about it becomes concrete)
- LinkedIn activated as simultaneous launch lever (DEC-31 constraint lifted)

**Post Gate 2 (full loop working end-to-end without manual intervention):**
- Tease: Cowork plugin — "a .gaai plugin for Claude Cowork is coming"
- Tease: course/training materials (post-Gate 3 plan, mentioned lightly)
- .gaai OSS published, GitHub link in bio, Show HN if traction warrants it

**Post Gate 3 (≥10 paid calls, GMV ≥€1,500, ≥3 experts re-paying):**
- Tease: .gaai Cloud vision — "the governance layer as a hosted product"
- Case study: Callibrate results with real numbers (conversion rate, expert satisfaction, GMV)
- Formation payante: .gaai training program (if OSS adoption visible)

---

## Content Principles

**90/10 rule on Reddit:** 90% of posts contribute genuine value to the community. Asking real questions, sharing genuine observations, engaging with other people's problems. 10% mention your work, and only when genuinely relevant. Never force it.

**Metrics over opinions:** Weekly metrics posts are the easiest content to write and the most credible. Stories shipped. Decisions made. Tests passing. If something went wrong, say so — the recovery is the interesting part, not the failure itself.

**Anti-polish on Reddit:** The format experiment showed that polished writing reads as AI-generated in many subreddits. Keep it rough. Short sentences. Typos are fine. "Been building a matching thing" is better than "I am developing an AI-powered expert marketplace."

**Decision log as content mine:** Every DEC-NNN entry is a potential thread. "Here's a decision I made and why" — that's the format. Specific, real, not theoretical. The 19-PR disaster became DEC-71 and it's a better thread than any "lessons from building with AI" think-piece.

**The build is the proof:** Don't claim the framework works. Show the numbers. 39 stories. 260 tests. $198.29. These numbers do more work than any adjective.

---

## Channel-Specific Rules

**X/Twitter (@Fr-e-d):**
- Thread format always outperforms single tweets for technical content
- Lead with the tension or result, not the context
- End every thread with a CTA that specifies exactly what to do (follow, subscribe, read)
- Don't over-explain. Let people ask.

**Reddit:**
- Check community rules before posting (some ban self-promotion entirely)
- The comment section is often more valuable than the post — engage genuinely
- r/ClaudeAI: technical users, they want specifics, not stories
- r/artificial: broader audience, governance angle resonates, security context works
- r/aisolobusinesses and r/AiForSmallBusiness: prospect communities, avoid direct promotion

**Hacker News:**
- Show HN for substantial releases only (flagship post, .gaai OSS, major milestone)
- Title must be factual and specific — HN rejects anything that reads like marketing
- First comment with backstory is mandatory — it's the actual content that drives votes
- Engage every comment, especially skeptical ones. Skepticism is engagement.

**Blog (Substack → own domain later):**
- Monthly cadence at most. Don't dilute with low-density posts.
- Every post must pass: "Would I share this with someone I respect?"
- Canonical URL discipline from day 1 — all cross-posts point back to the primary blog
