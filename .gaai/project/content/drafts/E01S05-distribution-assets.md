# E01S05 — Distribution Assets

> Generated for: E01S05 flagship post
> Status: DRAFT — human review required before posting
> Publish day: J1 (Tuesday or Wednesday, 10am ET recommended)

---

## 1. Hacker News Submission

**Title (Show HN):**
```
79 decisions, 39 stories, 4 days: building a SaaS with governed AI agents
```

**First comment (backstory — post immediately after submitting):**

Six weeks ago, I was on a beach in Vietnam with a rule: no laptop. My partner imposed it. The AI ecosystem was exploding the entire time — the OpenClaw security crisis (800+ malicious skills, 30,000+ Claude Cowork instances exposed), Cowork launching publicly, new models every week. I was watching all of it from an iPhone 8.

Instead of coding, I started reading. Scientific papers on separating reflection from execution in agent systems, context engineering, persistent memory architectures. I used Gemini 3 via NotebookLM to synthesize the research. I used ChatGPT 5.2 to challenge every idea I was forming. I captured everything through a Notion MCP connection. And piece by piece, a governance framework for Claude Code took shape — called .gaai.

.gaai is a `.gaai/` folder structure that governs AI agent sessions. It separates Discovery (thinking, clarifying, planning) from Delivery (building, testing, shipping) via two distinct agent roles that never mix. It enforces persistent memory across sessions (the agent reads what was decided yesterday before touching a file today). It logs every non-trivial decision in a `DEC-NNN` format that creates a queryable trail. And it gates execution behind a skill file — agents do only what their authorized skill defines.

I came home to Belgium and ran the framework on a real, complex project: Callibrate, an AI expert matching marketplace. The results: 39 stories delivered in 4 days, 260 tests passing, 16,246 lines of TypeScript, 79 decisions documented, $198.29 in API costs for 458M tokens. 96.9% cache reads — because persistent context means the agents aren't regenerating knowledge from scratch.

The post covers the full story — Vietnam to Belgium, the governance patterns that held up, the Reddit validation that ran in parallel with the code, and three concrete governance failures the system caught (including one 19-PR accumulation disaster that cost 2+ hours to clean up, now fixed by one rule).

.gaai will be open-sourced on GitHub shortly. Happy to answer questions about the architecture, the Dual-Track pattern, or the specifics of the Cloudflare Workers stack underneath.

---

## 2. Reddit Posts

### r/ClaudeAI

**Title:**
```
The framework I designed on an iPhone 8 in Vietnam now governs my Claude Code agents — 39 stories in 4 days
```

**Body:**

Six weeks in Vietnam, no laptop (partner's rule), AI ecosystem exploding. I ended up reading papers from an iPhone 8 and assembling a governance framework for Claude Code called .gaai.

The core idea is Dual-Track: one agent thinks (Discovery — clarifies intent, creates artefacts, never touches code), one agent builds (Delivery — reads the backlog, implements, opens a PR, never makes architectural decisions). They never mix. Add persistent memory across sessions and a decision log for every non-trivial choice, and you get something that behaves predictably over days of continuous delivery.

Ran it on a real project — Callibrate, an AI expert matching marketplace. 39 stories, 79 decisions documented, 260 tests passing, 16K lines of TypeScript. 4 days.

The framework will be open-sourced soon. For now I wrote the full story — how it came together, how it held up, what governance failures it caught, and how the Reddit discovery track (27 posts across 20 subreddits, running in parallel with code delivery) changed the architecture.

Full post here: [link]

Happy to talk through the Dual-Track pattern or the decision log format if anyone's curious — both are things I wish existed when I started using Claude Code seriously.

---

### r/artificial

**Title:**
```
AI agents shipped 39 stories in 4 days. Here's why they didn't go rogue.
```

**Body:**

The OpenClaw crisis earlier this year was a useful reminder: MCP solves tool access, but it doesn't solve behavior. 800+ malicious skills published, 30,000+ Claude Cowork instances exposed. The problem isn't what agents *can* do — it's what they do when you're not watching.

I spent six weeks in Vietnam (no laptop — partner imposed a digital detox) reading papers and building a governance framework for Claude Code in my head. Called it .gaai. Core patterns: Dual-Track separation (Discovery never codes, Delivery never decides), persistent memory across sessions, a decision trail for every non-trivial choice, and skill-based execution gates that prevent improvisation.

Came home and ran it on a real project — an AI expert matching marketplace called Callibrate. Results: 39 stories in 4 days, 16K lines of TypeScript, 260 tests, 79 decisions logged, $198 in API costs for 458M tokens.

Three specific governance failures the system caught: a 19-PR accumulation that cost 2+ hours to resolve (fixed by one process rule), a billing architecture problem that would have hit production (caught by the decision trail), and an external API closure (Cal.com) that pivoted in 30 seconds instead of hours.

Full writeup: [link]

.gaai will be open-sourced on GitHub. It's not a safety framework in the EU AI Act sense — it's a behavioral governance layer for Claude Code sessions. Still relevant given where agent frameworks are heading.

---

## 3. X/Twitter Thread (7 Tweets)

**Tweet 1 — Hook:**
```
My girlfriend banned my laptop for 6 weeks.

I came back with a governance framework for AI agents.

Here's what happened: 🧵
```

**Tweet 2 — The numbers:**
```
The framework shipped this, in 4 days:

39 stories delivered
79 decisions documented
260 tests passing
16,246 lines of TypeScript
97 files across 4 Cloudflare Workers
$198.29 in API costs — 458M tokens, 96.9% cache reads

This is a governed system, not a vibe-coded sprint.
```

**Tweet 3 — Vietnam:**
```
Vietnam. 6 weeks. No laptop (partner's rule).

The AI ecosystem was exploding:
OpenClaw crisis. Cowork launch. New models weekly.

I was watching it from an iPhone 8.

So instead of coding I read papers and built the framework in my head.

The irony: a governance framework for AI agents,
born because a human imposed governance on the builder.
```

**Tweet 4 — What .gaai is:**
```
.gaai is a folder structure that governs Claude Code sessions.

4 patterns:

→ Dual-Track: Discovery thinks. Delivery builds. They never mix.
→ Persistent Memory: agents read yesterday's decisions before today's code
→ Decision Trail: every non-trivial choice gets a DEC-NNN entry
→ Skill Gates: agents execute only what their skill authorizes

No improvisation. No scope creep. No repeated mistakes.
```

**Tweet 5 — The 19-PR disaster:**
```
Concrete governance example:

19 PRs accumulated unmerged across delivery cycles.

Batch-merged → cascading conflicts → 60 conflict files → 3 rounds of resolution → 2+ hours lost.

Root cause: no mandatory merge step in the process.

Fix: one rule in conventions.md. Every PR merged immediately after QA PASS.

The framework caught the process debt. One rule, problem gone.
```

**Tweet 6 — Reddit validation:**
```
While Delivery was building the matching engine, Discovery was on Reddit.

27 posts. 20 subreddits. Non-revealing — never mentioned the product.

Real quotes:
→ "90% are tire kickers looking for a $50 fix" — r/n8n_ai_agents
→ "Half my week just finding decent leads" — r/aisolobusinesses
→ "3 months to find someone who got our business logic" — r/AiForSmallBusiness

Budget data from Reddit directly changed the pricing model (DEC-67).

Two tracks, running in parallel, from day 1.
```

**Tweet 7 — CTA:**
```
.gaai will be open-sourced on GitHub soon.

The framework ran a full production project. It's ready to share.

Callibrate — the marketplace it built — is launching shortly.

Full story (Vietnam → Belgium → 4 days → 39 stories):
[link]

Follow for build-in-public updates.
Subscribe for monthly milestone posts: [substack link]
```
