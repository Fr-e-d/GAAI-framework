---
name: social-adapt
description: Transform a published blog post or content piece into platform-specific social media formats (X thread, LinkedIn post, Reddit post, carousel outline). Activate after CNT-004-edit or CNT-006-geo-optimize produces a final draft.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: content
  track: delivery
  id: SKILL-CNT-007
  updated_at: 2026-02-26
  status: stable
  tags: [content, social-media, repurposing, transformation, platform-adaptation]
inputs:
  - "contexts/artefacts/content/drafts/{id}-final.md (the edited, optimized source content)"
  - "contexts/memory/domains/content-production/voice-guide.md (voice attributes + platform tone variants)"
  - "contexts/memory/domains/content-production/sources/SOC-001.md (platform mechanics — load only relevant AKUs)"
outputs:
  - "contexts/artefacts/content/drafts/{id}-x-thread.md"
  - "contexts/artefacts/content/drafts/{id}-linkedin.md"
  - "contexts/artefacts/content/drafts/{id}-reddit.md"
  - "contexts/artefacts/content/drafts/{id}-carousel-outline.md (optional)"
---

# Social Adapt (CNT-007)

## Purpose

Transform a single source content piece (blog post, milestone report, case study) into platform-specific social media formats, each adapted to the platform's mechanics, tone, and audience expectations.

## When to Activate

Activate when:
- A blog post or content piece has passed editorial review (CNT-004) and is ready for distribution
- A milestone, decision, or metric update warrants social content (build-in-public)
- SKILL-CRS-021 (build-in-public) triggers a distribution cycle after story delivery

Do NOT activate when:
- The source content has not been reviewed (run CNT-004-edit first)
- The content is internal-only (decision logs, memory updates)
- No platform-specific adaptation is needed (e.g., content is already a thread)

---

## Process

### Step 1 — Load context

1. Read the source content piece completely
2. Load `voice-guide.md` — specifically Section VI (Platform Tone Variants) and Section VII (Persona Language Map)
3. Identify the **primary audience** for this piece (P1/P2/P3/P4) from the content's topic and intent

### Step 2 — Extract core elements

From the source content, extract:

- **Core insight** — the single most important takeaway (1 sentence)
- **Hook candidates** — 3-5 provocative/surprising opening angles
- **Key data points** — specific numbers, metrics, before/after comparisons
- **Quotable lines** — sentences that work standalone (for individual tweets or pull quotes)
- **Story arc** — the narrative thread (problem → approach → result → lesson)
- **CTA** — what the reader should do next (follow, read full post, try the tool)

### Step 3 — Generate X/Twitter thread

**Format:** 5-12 tweets. Each tweet self-contained (readable without thread context).

**Structure:**
1. **Hook tweet** — the most surprising/provocative angle. Write 5 versions, select the strongest. Patterns that work: surprising stat, provocative question, bold claim, "I [did X] and [unexpected result]"
2. **Context tweet** — why this matters (1-2 sentences)
3. **Body tweets (3-8)** — one point per tweet. Use the story arc: problem → approach → result. Include data points. One sentence per line where possible.
4. **Lesson tweet** — the transferable insight
5. **CTA tweet** — link to full post + soft ask. CTA in last tweet only.

**Tone rules (from voice guide):**
- Direct, analytical, slightly irreverent. Confident without arrogance.
- No emojis in body. Max 1 emoji in CTA line.
- Number tweets (1/N, 2/N...) if >4 tweets.
- Include 1-2 visuals (screenshots, diagrams, before/after) — note placement in the draft.

**Platform mechanics (from SOC-001):**
- Apply SOC-001 AKU-SOC001 (Hook Primacy) — first tweet determines thread survival
- Apply SOC-001 AKU-SOC003 (Interaction Depth) — design for replies, not just likes
- Apply SOC-001 AKU-SOC005 (Time Decay on X) — front-load engagement triggers

### Step 4 — Generate LinkedIn post

**Format:** Single post, 1200-1800 characters. Professional, reflective tone.

**Structure:**
1. **Opening line** — pattern interrupt or insight statement (visible before "see more")
2. **Context** — what was built/discovered/learned (2-3 short paragraphs)
3. **Key data** — 2-3 specific metrics or outcomes
4. **Reflection** — what this means for the reader's context
5. **Discussion prompt** — genuine professional question (not "agree?" engagement bait — per MTA-001 AKU-PA008)

**Tone rules (from voice guide):**
- Professional and reflective. More measured than X.
- "I" not "we". First-person narrative.
- No employer mentions (COMMS-001 constraint — DEC-31)
- No hashtags in body. Max 3 hashtags at the end.

**Platform mechanics (from SOC-001):**
- Apply SOC-001 AKU-SOC004 (Dwell Time) — write for reading time, not scanning
- Apply MTA-001 AKU-PA008 (Conversation Contribution) — end with genuine discussion prompt

### Step 5 — Generate Reddit post

**Format:** Self-post (text), 300-800 words. Community-first tone.

**Structure:**
1. **TL;DR** — 2-3 sentences at the top
2. **Context** — the problem, what was tried (community-relevant framing)
3. **What was learned** — the substance, adapted for the subreddit audience
4. **Questions** — genuinely ask for feedback or shared experiences
5. **Link** — at the END, after providing value. "Full writeup here: [link]"

**Tone rules (from voice guide):**
- Authentic, casual, question-driven. NEVER pitch.
- Deliberately imperfect style — shorter sentences, contractions, conversational.
- Disclose affiliation: "Full disclosure: I built this"
- 90/10 rule: 90% community value, 10% own work

**Subreddit targeting:**
- Identify 1-2 best-fit subreddits based on topic and persona
- Adapt framing per subreddit culture (technical depth for r/ClaudeAI, business value for r/aisolobusinesses)

### Step 6 — Generate carousel outline (optional)

Only if the source content contains a clear step-by-step, comparison, or framework.

**Format:** 8-12 slides outline.

**Structure:**
1. **Slide 1** — hook statement + topic
2. **Slides 2-N** — one point per slide, minimal text (≤30 words), visual-first
3. **Last slide** — CTA + handle

**Note:** This skill produces the text outline only. Visual design is out of scope (T3 — visual content gap).

### Step 7 — Cross-platform consistency check

Verify across all generated formats:
- The **core insight** is consistent (not contradictory between platforms)
- **Data points** are identical (same numbers everywhere)
- **Claims are traceable** to the source content (no fabricated data)
- **Voice attributes** match voice-guide.md per platform
- **Kill list words** are absent from all outputs

---

## Outputs

For each format, produce a markdown file in `contexts/artefacts/content/drafts/`:

**`{id}-x-thread.md`**
```
# X Thread — {title}
Target: {persona}
Hook version: {selected from 5 candidates}

[1/N] {hook tweet}

[2/N] {tweet}

...

[N/N] {CTA tweet}

---
Visuals needed: {list of screenshots/diagrams to prepare}
Best posting time: Tue/Wed/Thu 10am-12pm ET
```

**`{id}-linkedin.md`**
```
# LinkedIn Post — {title}
Target: {persona}

{full post text}

---
Hashtags: #tag1 #tag2 #tag3
Best posting time: Tue-Thu 8am-10am local
```

**`{id}-reddit.md`**
```
# Reddit Post — {title}
Target subreddit(s): r/{sub1}, r/{sub2}
Target persona: {persona}

{full post text including TL;DR}

---
Stagger: post to r/{sub1} first, r/{sub2} 24h later
Affiliation disclosure: included
```

**`{id}-carousel-outline.md`** (if applicable)
```
# Carousel Outline — {title}
Slides: {N}

Slide 1: {text}
Slide 2: {text}
...
```

---

## Quality Checks

- [ ] Hook tweet has been selected from ≥5 candidates
- [ ] Each tweet in the X thread is self-contained (readable without context)
- [ ] X thread length is 5-12 tweets (not under, not over)
- [ ] LinkedIn post is ≤1800 characters
- [ ] Reddit post includes TL;DR at top and link at END
- [ ] Reddit post includes affiliation disclosure
- [ ] All data points match the source content exactly
- [ ] No kill list words appear in any output (voice-guide.md Section V)
- [ ] Platform tone matches voice-guide.md Section VI
- [ ] No employer mentions in any output (COMMS-001 constraint)
- [ ] "I" not "we" in all outputs

---

## Non-Goals

This skill must NOT:
- Create visual assets (images, carousels, thumbnails) — out of scope (T3)
- Schedule or publish posts — founder manual review required
- Generate YouTube scripts — see CNT-008 (deferred)
- Write email newsletters — out of scope (T5)
- Decide which platforms to publish on — COMMS-001 defines the channel strategy
- Modify the source content — adaptation only, never alteration of facts or data

**This skill transforms. It does not create original content.**
