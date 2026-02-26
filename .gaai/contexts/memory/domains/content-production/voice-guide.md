---
type: memory
id: VOICE-GUIDE-001
domain: content
created_at: 2026-02-26
updated_at: 2026-02-26
source: COMMS-001.strategy.md (Parts 0, 1, 3)
usage: Loaded by CNT-003-draft, CNT-004-edit, CNT-007-social-adapt, CNT-009-quality-gate
---

# Content Voice Guide — Callibrate / .gaai / Personal Brand

> Operational reference for content production skills.
> Distilled from COMMS-001. For full strategic context, see the source artefact.
> This file defines HOW we sound. COMMS-001 defines WHERE and WHEN we publish.

---

## I. NARRATIVE POSITIONING

### Who the author IS

- A **builder who shows the work** — screenshots, metrics, decision logs. Not polished marketing.
- **Analytically grounded** — 77+ documented decisions, every claim references data.
- **Honest about failures** — 19 unmerged PRs, bot detection on Reddit, pivots. Failures are content.
- **Opinionated with data backing** — strong claims, always traceable to a validated hypothesis or decision.
- A **practitioner, not a thought leader** — build first, write about what worked.
- **Accessible** — explains complex concepts without condescension.

### Who the author IS NOT

- A guru or influencer (no face cam, no motivational content)
- A corporate marketer (no buzzwords, no "synergy")
- A hype machine (no "this changes everything", no "10x")
- A perfectionist in public (ships imperfect things and iterates visibly)
- Aggressive in acquisition (never cold-DM, never spam, never ask for follows)

### Core positioning statement

Solo founder who governed AI agents to build a real SaaS (Callibrate) — and is open-sourcing the governance framework (.gaai) that made it possible. The proof is in the numbers, not the claims.

---

## II. VOICE ATTRIBUTES

| Attribute | DO | DON'T |
|-----------|-----|-------|
| Specificity | "77 decisions, 39 stories, 260 passing tests" | "Lots of progress" |
| Honesty | "I accumulated 19 PRs and it cost me 2 hours of conflict resolution" | "We learn from every challenge" |
| Confidence | "This is what worked for me and the data behind it" | "I think maybe this could possibly work" |
| Humility | "This is N=1. Your mileage may vary." | "Everyone should do this" |
| Technical depth | "Cache chain: Cache API L1 (60s TTL) → D1 edge SQL → Hyperdrive fallback" | "We use advanced caching" |
| Teasers | "The framework behind this will be open-source soon" | "HUGE ANNOUNCEMENT COMING" |
| CTA | "If this resonates, the code will be on GitHub next month" | "LIKE FOLLOW SUBSCRIBE" |

---

## III. 10 NON-NEGOTIABLE WRITING RULES

1. **Specific beats comprehensive.** "79 decisions in 4 days" not "many decisions made quickly."
2. **Opinion beats hedging.** "This approach is wrong because..." not "While some may argue..."
3. **Kill every AI tell word.** See kill list (Section V). Search-and-destroy before publishing.
4. **Front-load value.** First 25% of any piece delivers 50% of the insight.
5. **Show the work.** Code, screenshots, data, real examples. Not theory.
6. **Write for one reader.** Picture a specific person and write to them.
7. **Match the channel.** HN = technical depth. X = hooks. Reddit = community value. dev.to = tutorials.
8. **The 90/10 rule.** Give value 90% of the time. Promote 10%.
9. **Read it aloud.** If it sounds like a corporate press release, rewrite.
10. **10-15% informality quota.** Contractions, sentence fragments, conversational asides.

---

## IV. WRITING STYLE TECHNIQUES

### Paul Graham style
- Self-riffing: introduce a word, then call attention to it ("That word 'governance' is the key")
- Deliberate chattiness: mix contractions with formal constructions
- Shorten sentences as you approach a key point, then pause

### Julia Evans style
- Narrate the journey from confusion to understanding
- Wonder and curiosity as tone: "I just figured this out and it's wild"
- Specific is better than comprehensive: deep dive on one thing beats survey of 50

### 3-Phase workflow
1. **OBSERVE** — gather raw materials BEFORE writing: decision log entries, backlog data, test results, Reddit quotes, real metrics
2. **DISTILL** — convert into narrative context: what happened, why it matters, what the reader gains
3. **CRYSTALLIZE** — AI drafts with full context loaded, founder edits for voice and personality

---

## V. KILL LIST

### Dead giveaway AI words (eliminate on sight)
delve, tapestry, landscape (as metaphor), beacon, crucible, labyrinth, gossamer, whimsical, enigma, virtuoso, symphony (metaphorical), treasure trove, bustling

### Overused transitions (replace or delete)
- Furthermore → [delete]
- Moreover → [delete]
- Additionally → "Also" or nothing
- In conclusion → [stop writing before you need this]
- It's worth noting that → just state the thing
- Subsequently → "Then"
- Consequently → "So"
- Nevertheless → "But" or "Still"

### Inflated importance (deflate or cut)
- "A testament to..." → say what it demonstrates
- "Plays a vital/crucial/pivotal role" → say what it does
- "Transformative" → say what it transformed, from what to what
- "Watershed moment" → be specific about what changed

### Structural tells to avoid
- Negative parallelism overuse ("It's not X, it's Y" — AI uses this every 3rd paragraph)
- Trailing -ing clauses ("...highlighting the importance of..." — cut them)
- "Despite its [positives], [subject] faces challenges..." — name the specific challenges or cut
- The everything sandwich ("In today's fast-paced X..." → DELETE ENTIRE SENTENCE)
- Bolded bullet point headers ("**Scalability:** The system scales..." — let content speak)
- Weasel attribution ("Industry reports suggest..." — name the source or cut)

### Forbidden words/phrases
- "Game-changer", "Revolutionary", "Disruptive", "10x", "Unlock"
- "I'm excited to announce" (just announce)
- "Thought leader" (let others say it)
- "LFG", "ship it", "let's gooo"
- "We" (solo founder — use "I")
- "AI-powered" as generic modifier (specify what the AI does)

### The replacement test
For every AI word, ask "What would I say to a colleague at a whiteboard?"
- "Leverage AI capabilities" → "use AI"
- "Navigate the complex landscape" → "figure out"
- "A robust and scalable solution" → "it handles load well"
- "Embark on a transformative journey" → DELETE

---

## VI. PLATFORM TONE VARIANTS

| Platform | Tone | Key rules |
|----------|------|-----------|
| **Blog** | Analytique long-form. "Stratechery density, Julia Evans accessibility." First-person, honest about failures. | No gating. Canonical URL always on personal blog. Mobile-first formatting. |
| **X/Twitter** | Direct, analytique, légèrement irrévérencieux. Confiant sans arrogance. | Hook tweet is everything (write 10-15 versions). 5-15 tweets optimal. Each tweet = one clear point. 1-2 visuals. CTA in last tweet only. No emojis in body. Max 1 emoji in CTA line. |
| **Reddit** | Authentique, casual, question-driven. NEVER pitch. Style volontairement imparfait. | 90/10 rule. TL;DR at top. Disclose affiliation. Link at END after providing value. Roughen the writing style. |
| **Hacker News** | Factuel, aucun hype. Zero marketing language. | Factual title with concrete detail. Post link + context as first comment. Engage EVERY reply. Tue/Wed 10am-11am ET. |
| **dev.to** | Blog identique, légèrement plus tutorial-oriented. | Cover image mandatory. Canonical URL → blog. 4 tags, lead with most popular. |
| **LinkedIn** | Professionnel, réflexif. (Deferred until launch — DEC-31) | No employer mentions. Professional framing of builder journey. |

---

## VII. PERSONA LANGUAGE MAP

### P1 — Expert AI/Automation (Callibrate paying customer)
**Their words:** "half my week finding decent leads", "tire kickers", "budget is the deal-breaker", "pipeline"
**Resonate with:** time saved, pre-qualification, budget-confirmed leads, control over what they accept
**Avoid:** marketing jargon, platform hype, unproven claims about lead quality

### P2 — Prospect SMB (Callibrate user)
**Their words:** "I don't know what I don't know", "workflow architect not just someone who knows Zapier", "3 months to find the right person"
**Resonate with:** trust, vetted experts, speed of matching, industry understanding
**Avoid:** technical jargon, AI hype, oversimplified promises

### P3 — Developer/AI Builder (.gaai + build-in-public audience)
**Their words:** "context evaporation", "every session is a cold start", "show me the code", "zero overhead"
**Resonate with:** persistent memory, dual-track, decision trail, real numbers, open-source
**Avoid:** marketing speak, theoretical frameworks without implementation proof, "AI governance" without specifics

### P4 — AI Industry/Recruiters (implicit audience)
**Their words:** "show me something they've built", "governance thinking", "body of work"
**Resonate with:** documented decisions, public artefacts, production governance proof, shipping speed
**Avoid:** resume-style claims, surface-level AI safety talk, theoretical positions

---

## VIII. LANGUAGE RULES

- **English** for all public content (international reach > FR niche)
- **Exception:** r/EntreprendreenFrance, LinkedIn FR hand raisers, FR business communities
- **No emojis** in blog posts. No emojis in X thread body. Max 1 emoji in CTA line.
- **Every claim must be traceable** to a decision log entry, validated hypothesis, or metric
- **"I" not "we"** — solo founder
- **Contractions encouraged** — "it's", "don't", "can't" (10-15% informality)

---

## IX. VISUAL IDENTITY

- **Terminal screenshots:** dark theme, monospace, annotated with 1 caption, sensitive info redacted
- **Architecture diagrams:** clean, minimal, black/white or 2-3 colors max, ASCII art or box diagrams
- **Metrics:** plain text or table format, always with date range, show delta since last report
- **X threads:** each tweet self-contained (readable without thread). Numbered (1/7, 2/7...) if >4 tweets.
- **Reddit:** native formatting only. No markdown images (break). Text-only with inline code blocks.
- **Blog:** headers, code blocks, pull quotes for key data points. Mobile-first.
