---
title: "My girlfriend banned my laptop for 6 weeks. I came back with a governance framework for AI agents."
published: false
tags: [AI, Claude, AgentGovernance, BuildInPublic]
canonical_url: [to be set after blog setup]
cover_image: [to be created]
---

**My girlfriend banned my laptop for 6 weeks. I came back with a governance framework for AI agents.**

39 stories. 79 decisions. 260 tests. 16,000 lines of code. 4 days.

The enforced pause is what made the results possible. Here's how.

---

## Who I Am (Not a CV)

I'm Frédéric Geens. Belgian. Program manager by day, builder by obsession.

Ten-plus years of coding alone at night — hundreds of hours, most of it never shipped. A dozen projects started, a handful finished, almost none made it to production. Not failure. Training. The kind you don't get from tutorials.

In 2015, I co-founded a transport company in Wallonia with a friend. I built the booking platform between rides, laptop on knees in the car. It was one of the first online booking systems for on-demand transport in the region. We ran it for four years. I handed it over in 2019. It survived COVID. It still runs today.

Somewhere in there I fell in love with SaaS. Read Rob Walling's *The SaaS Playbook* and something clicked: bootstrap everything, no VC, start small and stay small. Build something people need badly enough to pay for. Painkillers, not vitamins.

I'm an IT Program Manager now — 30 hours a week, remote. The rest of the time, I build. I describe myself as a Swiss Army knife: not the deepest expert in any single thing, but deeply curious, fast to learn, and obsessively focused on building things that actually solve problems.

I'm not someone who discovered "vibe coding" last month. The distinction matters for everything that follows.

---

## The Vietnam Digital Detox (The Part That Started Everything)

My partner is my guardrail. She watches over my balance, pulls me out of the cave, forces me to live things that have nothing to do with screens. She's been watching me build project after project for years, most of them destined for the drawer. She knows when I need a break even when I don't.

So she imposed a rule before our trip to Vietnam: no laptop. Six weeks.

I agreed. I shouldn't have been surprised. I also shouldn't have been surprised at how much it bothered me, because the AI ecosystem was exploding in exactly those six weeks.

The OpenClaw security crisis hit — 800+ malicious skills published, 30,000+ Claude Cowork instances exposed. Claude Cowork launched publicly. New models arrived weekly. The whole field of agentic coding was shifting in real time, and I was on a beach in Southeast Asia with no way to respond.

The itch was unbearable.

So instead of coding, I started thinking. From a painfully slow iPhone 8 — the kind where you watch the progress bar and go make coffee — I read scientific papers. Papers on separating reflection from execution, on context engineering, on persistent memory in agent systems, on isolation between cognitive and operational roles. I followed every Anthropic release: new skill formats, sub-agent architectures, agent-team patterns.

I used Gemini 3 via Google NotebookLM to condense the state of the art. NotebookLM is genuinely good at this — feed it 15 papers and a handful of forum threads and ask it to synthesize. It did the work my slow phone couldn't.

Then I used ChatGPT 5.2 to brutally challenge every idea I was forming. No complacency. I'd draft a concept, feed it to ChatGPT, and tell it to find every hole. It found plenty. That friction made the framework tighter.

I connected Notion via MCP server to ChatGPT and captured everything: concepts, patterns, decisions, rough outlines. Piece by piece, the architecture took shape. It built on an earlier open-source project of mine — AI-Governor-Framework — which I'd created months before when AI-generated code was less reliable and I needed something to keep agents from going sideways.

The ideas came faster than the iPhone could render them.

There's an irony here I want to name explicitly: a governance framework for AI agents, born because a human imposed governance on the builder. The same person who gives me the energy to keep building is the one who forced the pause that made the breakthrough possible. She doesn't need a framework to keep me on track. But apparently AI agents do.

---

## What I Built: .gaai in Four Concepts

The framework is called `.gaai`. It lives in a `.gaai/` folder at the root of the project and governs every session.

Four ideas hold it together:

**1. Dual-Track (think ≠ do)**

There are two agents, and they never mix roles. The Discovery Agent thinks: it clarifies intent, asks questions, creates artefacts, defines what to build. The Delivery Agent executes: it reads the backlog, picks a validated story, builds it, tests it, opens a PR. An agent that discovers is never also the one that codes — like separating the architect from the construction crew.

This isn't just conceptual cleanliness. It's what prevents scope creep, rogue decisions, and the particular failure mode where an agent decides to "improve" something while building something else entirely.

**2. Persistent Memory**

Every session starts with loaded context. The agent knows what was decided three days ago, what the billing model is, why Cal.com was replaced, what Reddit told us about expert pricing sensitivity. Pattern: `memory-retrieve` runs before any action. Result: no repeated mistakes, no re-litigating decisions.

Without persistent memory, every session starts from scratch. The agent re-discovers what you already know, re-invents what was already decided, and re-makes mistakes that were already caught. Persistent memory is the compound interest of agent sessions.

**3. Decision Trail**

Every non-trivial choice gets a decision log entry in `DEC-NNN` format. The entry records: what was decided, why, what it replaces, what it impacts. 79 decisions logged at time of writing. Each one is a future mistake prevented.

When something breaks or needs to change, you open the log and find the entry. When you pivot, you know exactly what you're replacing and why. When an external API closes (Cal.com closed its API to new signups mid-project), you find the DEC entry, understand what depended on it, and pivot in minutes instead of hours.

**4. Skill-Based Execution**

Agents do only what their skill authorizes. No improvisation. No scope creep. The backlog authorizes execution; the skill defines how to execute. The agent reads both before touching a file. This is the constraint that makes the whole system predictable.

[VISUAL PLACEHOLDER 1: Dual-Track flow diagram — Discovery and Delivery as parallel tracks, showing how Reddit validation ran alongside code delivery. Dark theme. Created via Google NotebookLM.]

Here's a concrete Dual-Track example from the project: while Delivery was building the matching engine (story E06S05), Discovery was simultaneously running listening sessions on Reddit — 27 posts across 20 subreddits, non-revealing engagement. The budget data that came back from Reddit directly changed the pricing model (DEC-67). Two tracks, running in parallel, from day 1.

---

## The Test: Callibrate

I flew home to Belgium. Opened the laptop. Started the first real implementation with Claude Code under .gaai governance. The results were well beyond what I'd expected.

Not just speed. Confidence. The kind where you push to production and actually sleep afterward, because you know the agent didn't make up decisions in the dark.

But I didn't want to write about an untested framework. I needed it to hold up on something real and complex — not a toy project, not a demo. So I ran it on Callibrate.

Callibrate is an AI expert matching marketplace. Businesses with automation needs — SMBs trying to implement n8n, companies building internal AI tools, startups who need someone who actually understands their business logic — get matched with vetted AI consultants. Not LinkedIn. Not Upwork. Specialized, curated, pre-qualified on both sides. The unit of value isn't a profile view or a message. It's a booked call.

Here's what .gaai governance shipped in 4 days:

- 39 stories delivered, 46 total stories planned
- 79 decisions documented (20 active, 59 archived)
- 260 vitest tests passing
- 16,246 lines of TypeScript across 97 files
- 4 Cloudflare Workers: Core API, Matching Engine, PostHog Proxy, Satellite frontend
- 7 epics spanning auth, billing, matching, AI extraction, Google Calendar, analytics, content
- 4 days, 6 hours of calendar time (2026-02-19 to 2026-02-24)
- Total API cost: $198.29 for 458 million tokens — 96.9% cache reads

That last number deserves a sentence: 96.9% of all tokens were cache reads. The persistent context system meant the agents weren't regenerating knowledge from scratch every session. They were re-reading what was already established and building forward.

[VISUAL PLACEHOLDER 2: Metrics dashboard — card layout showing 39 stories / 79 decisions / 260 tests / 16K LoC / 4 days. Dark theme, minimal infographic.]

---

## How I Validated the Problem Before Writing a Line of Code

The matching engine existed before anyone asked for it. That's the usual failure mode of solo builders: we fall in love with solutions before confirming problems.

The Discovery Agent ran a parallel track while Delivery was building. 27 posts across 20 subreddits. Non-revealing — the product name never appeared in any of them. Just questions, observations, engagement. Community conversations about real pain.

The posts are still getting comments weeks later.

Here's what the community actually said:

On expert lead quality: *"90% of inbound is just tire kickers looking for a $50 fix."* — Littlecutsie, r/n8n_ai_agents

On time cost: *"Half my week just finding decent leads."* — Wide_Brief3025, r/aisolobusinesses

On finding good experts as a buyer: *"Took me about 3 months to find someone who actually got our specific business logic."* — Present-Access-2260, r/AiForSmallBusiness

On the scarcity of real expertise: *"Real workflow architects who understand business logic are maybe 10-15% of that pool."* — PathStoneAnalytics, r/AiForSmallBusiness

On expert billing sophistication: *"Money upfront. Card on file. Auto billing enabled."* — MachadoEsq, r/gohighlevel

Zero competitors named across all 27 posts.

One anti-signal worth sharing: someone asked *"Do you use AI to write all your posts or are you a bot?"* — mycall, r/digitalnomad. The format was too polished. Reddit needs rougher writing. Lesson noted, applied.

The signals directly changed the architecture. Budget was the #1 filter in every expert conversation — they didn't want leads who couldn't pay. That became DEC-67: a dynamic pricing model based on declared prospect budget (€49 for sub-5k prospects, €263 for 50k+ projects). Expert time waste became the case for making the matching engine the critical path, not a nice-to-have. Expert sophistication signals — "card on file", "modular or nothing", "if they want me to build the brain inside GHL, it's a hard no" — became admissibility controls in expert profiles (DEC-80).

One quote changed the entire positioning framing: *"We stopped selling 'n8n workflows' and started selling 'found time'."* — Littlecutsie, r/n8n_ai_agents. Outcome-based positioning. Not what you build. What you save.

The Dual-Track proof: Discovery (Reddit) was running in parallel with Delivery (code) from day 1. By the time the matching engine was done, the pricing model and admissibility logic it runs on had already been validated by real people with real opinions.

---

## Why Agents Need Governance

The OpenClaw crisis is the clearest example of what happens without it.

800+ malicious skills published. 30,000+ Claude Cowork instances exposed. The attack surface wasn't that Claude Cowork existed — it was that skills could be published and executed without any behavioral governance. MCP solves tool access. It doesn't solve behavior. The problem isn't what agents *can* do. It's what they *do when you're not watching*.

.gaai addresses that gap. But governance matters at smaller scales too. Here are three concrete examples from this project:

**The 19-PR disaster (DEC-71).** Nineteen story branches accumulated unmerged over multiple delivery cycles. When they were finally batch-merged, cascading conflicts required three rounds of resolution — 60 conflict files, more than two hours of remediation work. The root cause: the delivery process had no mandatory merge step. Fix: one rule added to `conventions.md`. Every PR gets merged immediately after QA passes. Never accumulate. One process change, problem gone.

**The billing pivot (DEC-68).** The original billing model was per-lead checkout — one Lemon Squeezy checkout per lead. Analysis showed the friction was real and the refund cost was structural (LS keeps fees on refunds). The new model: usage-based subscription with internal credit accounting and a 7-day flag window. Experts flag a bad lead, credits restore instantly. After seven days of silence, usage gets reported to LS and auto-charged. Six stories, four decision log entries. Without the trail, this architecture problem would have been discovered in production.

**The Cal.com pivot (DEC-41).** Cal.com closed its API to new signups on 2025-12-15. Discovered in 30 seconds via the decision trail — the dependency was logged, the impact was clear, the pivot path was obvious. Google Calendar OAuth instead. Time lost: near zero.

[VISUAL PLACEHOLDER 3: Decision log screenshot — 3-4 DEC- entries visible in terminal, dark theme, annotated to explain the format. Shows real density of governance.]

The memory system completes the picture. Session 1 establishes that postgres.js replaces Supabase JS for all DB queries (DEC-66). Session 2 doesn't re-evaluate it. Session 3 doesn't re-implement a Supabase client because the agent "forgot." The decision exists in memory, the agent reads it, and builds forward. Without persistent memory, every session starts from scratch — reinventing decisions, repeating mistakes, rebuilding what was already built.

---

## What's Next

.gaai will be open-sourced on GitHub. The framework held up on a real, complex project over four days of continuous delivery. It's ready to share. The repository will go live soon — follow to get notified.

Callibrate is launching. The matching marketplace — the product .gaai built — will be live for AI experts and businesses shortly. If you're an AI consultant tired of unqualified leads, or a company that's spent months trying to find someone who actually understands your business logic, it was built for you.

This post is the first public artefact. The build log already exists — 79 decisions, 39 stories, all documented. It just needs to be made public in pieces.

Follow on X ([@Fr-e-d](https://x.com/Fr-e-d)) for build-in-public updates — threads on specific governance decisions, architecture choices, and what the data actually shows.

Subscribe on Substack for the monthly milestone posts — deeper dives, less frequent, built for reading not scrolling.

If you're using Claude Code and wrestling with unstructured sessions — agents making decisions you didn't authorize, context lost between sessions, no way to understand what happened or why — the framework might be exactly what you need.

The digital detox was my partner's idea. This post exists because of her.
