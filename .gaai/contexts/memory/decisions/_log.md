---
type: memory
category: decisions
id: DECISIONS-LOG
tags:
  - decisions
  - governance
created_at: 2026-02-19
updated_at: 2026-02-27
---

# Decision Log

> Append-only. Never delete or overwrite decisions.
> Only the Discovery Agent may add entries (or Bootstrap Agent during initialization).
> Format: one entry per decision, newest at top.
>
> **Compacted 2026-02-23:** DEC-01 to DEC-59 (59 entries) archived.
> Full text → `archive/decisions-01-59.archive.md` | Summary → `summaries/decisions-01-59.summary.md`
>
> **Compacted 2026-02-27:** DEC-60 to DEC-89 (plus DEC-2026-02-23-01, DEC-2026-02-23-02) archived.
> Full text → `archive/decisions-60-89.archive.md` | Summary → `summaries/decisions-60-89.summary.md`

---

### DEC-115 — callibrate.io landing page: CF Worker + Hono (same pattern as satellites)

**Context:** The expert-facing landing page at callibrate.io needs a deployment strategy. Three options evaluated: (1) React Router v7 (same as dashboard), (2) CF Worker + Hono (same as satellites), (3) static HTML on CF Pages.
**Decision:** CF Worker + Hono — same pattern as `workers/frontend/satellites/`. The landing page is a marketing page, not an app. It needs to be fast (< 50KB), SEO-optimized, and server-rendered without a client-side framework. Hono provides routing, HTML templating, and middleware (security headers). No build step needed for HTML — inline critical CSS, PostHog JS snippet only. React Router v7 would add unnecessary complexity (SSR hydration, client-side bundle) for a page that has zero interactivity beyond link clicks.
**Workspace:** `workers/frontend/landing/`
**Files:** `.gaai/contexts/artefacts/stories/E02S09.story.md`
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-114 — E02 absorbs Layer 3.1 from E04 and E05

**Context:** E02, E04, and E05 all had Layer 3.1 stories targeting app.callibrate.io. Delivering them as separate epics would mean scaffolding the frontend three times (E02 for profile, E04 for lead page, E05 for billing dashboard). This is architecturally wasteful — one scaffold should serve all expert-facing UI.
**Decision:**
(1) E02 absorbs all Layer 3.1 stories from E04 and E05. E02 scope expanded: signup + onboarding + profile + leads + bookings + billing + analytics.
(2) E04 retains only satellite-side booking UX (Layer 3.2 — booking widget embedded on satellites, booking confirmation page).
(3) E05 Layer 2 stories already delivered (E06S31–S34). E05 Layer 3.1 stories (E05S01–S05) absorbed into E02S05 (leads), E02S07 (billing), E02S08 (analytics).
(4) E02 epic file revised to reflect consolidated scope. Story count: 9 E02 stories + 1 E06S38 (supporting API).
**Files:** `.gaai/contexts/artefacts/epics/E02.epic.md` (revised)
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-113 — Dashboard tech stack: React Router v7 Framework Mode (SSR) on CF Workers

**Context:** Choosing the frontend framework for the expert dashboard (app.callibrate.io). Evaluated: (A) React SPA (Vite + React + TanStack Query + Zustand), (B) React Router v7 Framework Mode (SSR) on CF Workers via Cloudflare Vite plugin, (C) Next.js on CF Workers (via OpenNext), (D) Astro with React islands.
**Decision:** React Router v7 Framework Mode (SSR) on Cloudflare Workers.
**Rationale:**
(1) **Server-side loaders eliminate data waterfalls.** Each route fetches data server-side before rendering — no client-side loading spinners, no TanStack Query boilerplate. Auto-revalidation on form actions replaces manual cache invalidation.
(2) **Server-side auth guard.** Layout loader checks session → redirects to `/login` before any HTML is sent. No flash of unauthenticated content. No client-side AuthGuard component.
(3) **Cloudflare's recommended path.** React Router v7 is "the first full-stack framework to provide full support for Cloudflare Vite plugin." First-class Workers runtime support in dev and production.
(4) **Less code.** Removes TanStack Query, Zustand, and client-side auth state management. URL search params replace client-side state for filters/pagination (RR7 idiom: URL is the state).
(5) **Same React underneath.** Components, hooks, JSX — identical. No learning curve penalty vs SPA.
**Revised scoring:** React Router v7 SSR: 24/25 (vs React SPA 19/25 after correcting initial bias toward simplicity).
**Rejected:** React SPA (more client-side code, auth flash, data waterfalls), Next.js on CF (OpenNext not production-grade), Astro (suboptimal for interactive dashboards).
**Stack:** react-router v7, @cloudflare/vite-plugin, TailwindCSS 4 + shadcn/ui, react-hook-form + zod, recharts, @supabase/supabase-js.
**Files:** `.gaai/contexts/artefacts/stories/E02S01.story.md`, `.gaai/contexts/memory/project/context.md`
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-112 — E03 Discovery: 5 stories refined, delivery order locked

**Context:** E03 (Satellite Frontend — prospect UX) had only E03S05 (robots.txt) done. Remaining scope — quiz funnel, match results, booking widget, directory — needed full Discovery.
**Decision:**
(1) 5 story artefacts produced: E03S01 (freetext input, 10 ACs), E03S02 (confirmation + Turnstile, 11 ACs), E03S03 (match results + email gate, 12 ACs), E03S06 (inline booking widget, 12 ACs), E03S04 (directory + profiles, 10 ACs).
(2) **Delivery order:** E03S01 → E03S02 → E03S03 → E03S06 → E03S04. Quiz funnel first (primary conversion path, establishes frontend patterns), booking widget next (reused by S03 + S04), directory last (secondary path, has API gap).
(3) **E03S04 BLOCKED** on public expert listing API (E06S38 — to be created if absent). Delivery flags the gap → Discovery creates the Layer 2 story.
(4) **Two Delivery flags:** (a) E03S02 — verify `POST /api/prospects/submit` accepts pre-extracted requirements via `quiz_answers` field, (b) E03S06 — directory path needs lightweight prospect creation for booking without prior quiz submission.
(5) E03 epic updated to reflect all 6 stories (5 new + S05 done) + revised success metrics (email gate conversion ≥40%, booking rate ≥15%).
**Date:** 2026-02-27

---

### DEC-111 — E03 email gate: after anonymized matches (Option A)

**Context:** Two options for when prospects must provide email: (A) after seeing anonymized match results, before full profiles are revealed; (B) only before booking, with full profiles freely visible.
**Decision:** Option A — email gate after anonymized matches. Weighted evaluation (7 criteria):
- **Disintermediation protection (30%):** A=9/10, B=2/10. Option B is existential risk — prospect sees full expert identity → Googles and contacts directly → platform bypassed. For a marketplace, this is the #1 business threat.
- **Billing alignment (15%):** A=9/10, B=3/10. `POST /identify` = lead creation = credit debit trigger (E06S32). Clean billing boundary.
- **Expert fairness (10%):** A=8/10, B=3/10. Profiles only shown to committed prospects (email = skin in the game).
- **Email capture rate (15%):** A=8/10, B=3/10. Gate at peak intent.
- **Prospect experience (20%):** A=5/10, B=9/10. Mitigated by making anonymized cards info-rich (score breakdown, tier badge, rate range, skills, languages).
- Weighted total: A=7.35, B=4.15.
**Rejected:** Option B — better UX but existential disintermediation risk. A marketplace that shows full supplier profiles before capturing buyer identity is a directory, not a marketplace.
**Mitigation for Option A friction:** info-rich anonymized cards (not just "Expert #1: 87/100"), value-focused CTA copy ("Unlock expert profiles"), single-field form (email only).
**Date:** 2026-02-27

---

### DEC-110 — E03 booking widget: inline in satellite, split from directory (E03S06)

**Context:** Booking experience design for prospect UX. Three options: (a) inline in satellite page, (b) separate `/book/:expert` page, (c) redirect to external page. Also: directory + booking scope in original E03S04 was too large for one story.
**Decision:**
(1) **Inline booking** — prospect picks slot, confirms, gets Meet link without leaving the page. Best UX, highest conversion (no navigation friction at peak intent). Uses E06S11 APIs (availability → hold → confirm).
(2) **Story split** — E03S04 (directory browsing + expert profiles, 10 ACs) + E03S06 (inline booking widget, 12 ACs). Smaller delivery units, clearer ACs, E03S06 is reusable by both E03S03 (match results) and E03S04 (directory profiles).
**Rejected:** (b) Separate booking page — unnecessary navigation at conversion point. (c) External redirect — breaks prospect flow, loses PostHog tracking context. Single-story approach — too many ACs (22+), mixed concerns (SEO server-rendering + interactive booking widget).
**Date:** 2026-02-27

---

### DEC-109 — E03 seeded experts: no E02 dependency for staging/MVP

**Context:** E03 epic lists E02 (Expert Dashboard) as a dependency. E02 not yet in backlog. E02 Discovery launched in parallel. Staging DB designed for mock data.
**Decision:** E03 stories assume experts are seeded via API/DB (seed data from E06S02). E02 dashboard is NOT required for E03 to function — seeded data is sufficient for staging, testing, and MVP validation. E02 and E03 can be delivered in parallel. The real dependency is "experts must exist in DB for matching to work" — satisfied by seed data. E03 epic dependency note updated accordingly.
**Date:** 2026-02-27

---

### DEC-108 — GAAI-Cloud build strategy: Gate 2 technical build, Gate 3 commercial launch

**Context:** Complexity comparison between Callibrate (two-sided marketplace + matching engine) and GAAI-Cloud (file sync + MCP server). Key insight: GAAI-Cloud complexity is infrastructure-only (DO + R2 + MCP + auth + billing) because the AI tool is the client, not the product. No custom algorithm, no two-sided acquisition, no frontend required. Estimated build time: 2–3 months vs 12–18 months for Callibrate.
**Decision:**
(1) **GAAI-Cloud is structurally simpler than Callibrate.** Callibrate builds product value (matching engine, extraction, booking, scoring, feedback loops, satellite sites, two ICPs). GAAI-Cloud builds infrastructure (file storage + MCP interface). The AI (Claude Code / Cowork) is the client — it delivers the governance/discovery/delivery value, not GAAI-Cloud's application code.
(2) **Effort-adjusted value favors earlier GAAI-Cloud build.** Callibrate: €2–15M ARR potential / high complexity / high risk / long timeline. GAAI-Cloud: €500K–1.5M ARR potential / low complexity / low risk / 2–3 month build. The ratio is more favorable than raw MRR numbers suggest.
(3) **Trigger condition refined — two stages:**
  - Gate 2 (`.gaai` OSS public) → **GAAI-Cloud technical build starts.** Low complexity = no resource conflict with Callibrate. OSS community begins forming = early feedback available.
  - Gate 3 (Callibrate ≥10 calls payés, GMV ≥1 500€, ≥3 experts re-payants) → **GAAI-Cloud commercial launch.** Proof-of-work established, GAAI credibility validated, audience exists.
(4) **Sequence:** Callibrate Gate 1–2–3 (primary focus) → GAAI OSS public (Gate 2, parallel) → GAAI-Cloud v1 technical build (Gate 2, light parallel) → GAAI-Cloud commercial launch (Gate 3).
(5) **PRD-002 updated:** trigger_condition split into two milestones (technical build vs commercial launch).
**Files:** `.gaai/contexts/artefacts/prd/PRD-002.prd.md`
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-107 — GAAI-Cloud three-level architecture: Organization → User Workspace + Project Workspace

**Context:** Two-workspace model (Org + User) was insufficient for multi-project use. A team or freelancer with N projects would have all their backlogs and memories mixed in one Organization Workspace — architecturally broken.
**Decision:**
(1) **Three levels:** Organization (billing entity) → User Workspace(s) (1 per user, portable) + Project Workspace(s) (N per org, isolated per project).
(2) **Project Workspace:** Contains `contexts/` (memory, backlog, artefacts, rules, reports). Fully isolated per project. Member list per project — users only see their invited projects. 1 Durable Objects instance per Project Workspace.
(3) **User Workspace:** NOT inside a project. Portable identity — travels with the user across all projects and all orgs. When switching projects, agents/skills unchanged. Only the active Project Workspace (DO connection) changes.
(4) **Unlimited Project Workspaces for all tiers.** Revenue lever = seats, not projects. A solo freelancer with 10 client projects pays $9/month. Limiting projects creates friction without protecting Team tier.
(5) **Project management CLI:** `gaai project list|create|switch|archive`.
(6) **MCP routing:** Workers routes each request to the correct DO instance based on the user's active project (stored in KV).
(7) **Migration:** Each OSS `.gaai/` becomes a Project Workspace. Multi-user same-project migration shows merge report for `contexts/`.
(8) **Contractor multi-org:** Caio has his own org (Solo, N personal projects). He's also a seat in Client A's org (Client A pays) and Client B's org (Client B pays). His User Workspace is portable across all — same agents/skills everywhere.
**Files:** `.gaai/contexts/artefacts/prd/PRD-002.prd.md` (revision 4)
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-106 — GAAI-Cloud product decisions: pricing, seat model, feature gating, core/custom structure

**Context:** Discovery session refining GAAI-Cloud commercial model across 6 dimensions: pricing fairness, seat ownership, account sharing defense, contractor/freelancer multi-org use case, device limits, and User Workspace folder structure.
**Decision:**
(1) **Pricing:** Solo $9/month ($84/year, $7/mo effective) | Team $18/seat/month ($168/seat/year, $14/mo effective) | Enterprise custom. Minimum team bill: 2 seats annual = $28/month (impulse-buy threshold). Benchmarks: Obsidian Sync $5 (pure sync anchor), Notion Team $10, Linear Team $8 — GAAI-Cloud Solo above Obsidian (more value), Team below Notion (niche audience, easier adoption).
(2) **Blueprint Packs:** $29 one-time for Solo add-on (impulse-buy threshold, no budget approval needed). Included in Team+ (drives tier upgrade). Content Blueprint already built (CNT-001→CNT-011, 141 AKUs).
(3) **Seat ownership model:** Billing at Organization level, not individual. Each org pays per active member. Contractors/freelancers are a seat in each client's org — each client pays. Contractor's User Workspace covered by any active Team seat — no personal subscription needed.
(4) **User Workspace coverage rule:** Active seat in ≥1 Team workspace → User Workspace included. Solo user (no Team workspace) → $9/month covers User Workspace. No subscription → sync disabled, local cache remains (nothing deleted). Transition notification when leaving last Team workspace.
(5) **Account sharing defense: feature gating only.** No device counting, IP checks, or fingerprinting. Natural defense: Solo = 1 User Workspace shared by all (broken for teams), no team invitation system, no admin roles, concurrent sessions → second session read-only. If a team prefers broken shared experience over $28/month → value problem, not enforcement problem.
(6) **Unlimited devices for Solo.** Conversion trigger is number of USERS (Solo → Team), not devices. Limiting devices creates UX friction without protecting Team tier.
(7) **core/custom split for all User Workspace categories:** `agents/core/`, `agents/custom/`, `skills/core/`, `skills/blueprints/`, `skills/custom/`, `workflows/core/`, `workflows/custom/`, `scripts/core/`, `scripts/custom/`. Priority rule: `custom/` always overrides `core/`. GAAI-Cloud updates `core/` freely without touching user customizations.
(8) **Naming:** GAAI-Cloud = "la plateforme" in the product trilogy (GAAI OSS = framework/PoC, Callibrate = PoW, GAAI-Cloud = la plateforme).
(9) **ELv2 license:** Internal corporate use allowed. Competing managed service forbidden. "Source available", not "open source".
(10) **OSS audience = Claude Code only.** Cowork plugin = thin connector to GAAI-Cloud (no local agents/skills). Cowork users are GAAI-Cloud users, not OSS users.
**Files:** `.gaai/contexts/artefacts/prd/PRD-002.prd.md`
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-105 — GAAI-Cloud architecture: OpenCore model, two-workspace split, MCP-only interface

**Context:** Discovery session evaluating GAAI framework commercialization. Session progressed through OSS vs OpenCore analysis, Claude Cowork plugin system evaluation, Cloudflare infrastructure options, and converged on a clean architecture.
**Decision:**
(1) **OpenCore model:** GAAI OSS (local, free, complete for solo/single-device) is the distribution vector for GAAI-Cloud (paid cloud sync). OSS is not stripped down — it solves single-device use completely. Cloud adds genuine new value (multi-device, team real-time collaboration).
(2) **Two-workspace split:**
  - *Organization Workspace* (team-scoped): `contexts/` only — memory, backlog, artefacts, rules, reports. Always fetched live from GAAI-Cloud per MCP request. Durable Objects for real-time concurrent writes without conflict. This is the primary differentiator vs Dropbox/Git.
  - *User Workspace* (user-scoped): agents, skills, workflows, scripts (advanced). Cloud = source of truth. Local = versioned cache. Hash-manifest sync on MCP connect (cloud sends manifest with file hashes → client pulls only changed files → serves from cache during session). No bidirectional sync — no conflicts.
(3) **MCP-only interface:** GAAI-Cloud exposes a single MCP server endpoint. No web UI required for workflow execution — AI is the interface. GAAI-Cloud does NOT proxy external tools (Notion, Drive, Slack) — those are configured at AI tool level directly.
(4) **Cloudflare stack:** DO (Org Workspace + delivery locks) + R2 (User Workspace files) + D1 (hash manifests, metadata) + KV (auth sessions, token cache) + Workers (MCP server) + CF Workflows (Delivery agent — future).
(5) **LLM inference stays local:** always runs in user's AI tool (Claude Code, Cowork, etc.). GAAI-Cloud is pure storage + MCP — not an inference provider.
(6) **Scripts security:** disabled by default, explicit opt-in, hash-verified against signed manifest before execution on each device.
(7) **Monetization tiers:** Solo $7/month (multi-device sync), Team $20/user/month (+ DO real-time collaboration + agent consistency lock + shared skill library), Enterprise (custom + SSO + audit + private deploy). Blueprint Packs $49–149 one-time or included in Team+.
(8) **Cowork plugin structure:** `agents/` + core `skills/` stay LOCAL (installed with plugin). `contexts/` is MCP-mounted (no local files). `.mcp.json` points to GAAI-Cloud endpoint.
(9) **Trigger condition:** GAAI-Cloud execution begins only after Callibrate Gate 3 PASS. Artefact: PRD-002.
**Files:** `.gaai/contexts/artefacts/prd/PRD-002.prd.md`
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-104 — Discord added to channel map: AI Agency Alliance (Phase 0-1, P1 engagement)

**Context:** During content strategy review, two Discord servers were evaluated against COMMS-001 and OPS-002. AI Hub (537k members) rejected — audience is creative AI (voice cloning, RVC), no overlap with P1/P3 personas. AI Agency Alliance (~12 800 members, focus: automation agencies, prompt engineering, sales) validated as relevant for P1 expert persona.
**Decision:** (1) AI Agency Alliance added to COMMS-001 as active Discord channel, P1 audience, 1-2 interactions/week cadence. (2) Channel map overview updated. (3) Strategy: weeks 1-2 observation only, weeks 3+ substantive replies (same logic as Reddit). (4) Handraiser detection rule added: P1 experts complaining about lead gen → log to `memory/contacts/leads.md`. (5) No promotional use before launch. (6) Discord remains secondary channel — Reddit stays primary for P1. (7) Webhook/MCP automation deferred — no automation before signal is validated (consistent with OPS-002 API keys policy).
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-27

---

### DEC-103 — E01S02 refined: LinkedIn → X/Discord/Communities (channel pivot + new post copy)

**Context:** E01S02 (expert hand raiser) was deferred since project start due to LinkedIn constraint. E01S01 AC4 (promise draft, DEC-102) now delivered — dependency resolved. Channels mapped in DEC-100.
**Decision:** (1) Story ACs rewritten: AC1 = ≥2 weeks warm engagement (replaces LinkedIn connections), AC2 = X hand raiser with DEC-102 vocabulary, AC3 = 2 communities (n8n Discord + 1 other), AC4 = log commenters 48h, AC5 = gate ≥10, AC6 = LinkedIn deferred. (2) 6 hand raiser post versions produced, all grounded in validated vocabulary ("tire kickers", "decent leads", "confirmed budgets", "found time", "90%", "5-7h/week"): X Version A (pain direct), X Version B (feast-or-famine), X Version C (outcome framing), n8n Discord (conversational question-first), X Community (short), Reddit (TL;DR + data-backed). (3) All posts QA'd against voice guide (content-production domain memory): kill list clean, P1 persona vocabulary used, channel tone variants respected, Reddit TL;DR added. (4) LinkedIn versions preserved as DEFERRED section in artefact. (5) Backlog status: `deferred` → `refined`. (6) Prerequisite: ≥2 weeks warm engagement before posting — no cold hand raisers.
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-26

---

### DEC-102 — Promise draft produced (AC4 of E01S01)

**Context:** E01S01 required a "promise draft" (AC4) — one sentence per side (expert + prospect), grounded in observed language. Data: 109 comments, 15 Reddit posts, 13 hypotheses (9 validated, 3 indirect signal). AC4 was the last blocker before E01S02 (expert hand raiser) could start.
**Decision:** (1) **Expert promise:** "Stop filtering tire kickers. Get matched only with prospects who have confirmed budgets, real timelines, and a problem worth solving." Grounded in: 90% tire kicker ratio (Littlecutsie), 5-7h/week filtering (JJCookieMonster), budget = #1 drop-off (Academic-Highlight10), total channel fragmentation (SilentButDeadlySquid). (2) **Prospect promise:** "Find a real workflow architect who gets your business logic — in days, not months." Grounded in: 3-month search (Present-Access-2260), 10-15% real experts (PathStoneAnalytics), "prompt engineer with a Zapier account" as anti-pattern. (3) Validated vocabulary: "tire kickers", "decent leads", "found time", "confirmed budget" (expert side); "workflow architect", "business logic", "gets our specific business logic" (prospect side). (4) Promises are internal positioning anchors — not copy-ready taglines. They inform landing page, hand raiser posts, engagement language, and onboarding pitches. (5) Artefact: `.gaai/contexts/artefacts/marketing/E01S01-promise-draft.md`. (6) H3/H5 (willingness to pay) not addressed by promise — require E01S02 direct engagement for validation.
**Decided by:** Founder + Discovery Agent
**Date:** 2026-02-26

---

### DEC-101 — Distribution channels activated (Phase 0-1)

**Context:** March 2026 cold-start plan (DEC-98) requires Reddit 42% + X 32% + flagship 21%. All Phase 0-1 distribution channels needed to be configured before content execution begins.
**Decision:** (1) X/Twitter personal account `@frederic_geens` created as primary BIP channel (professional type, Google auth, notifications OFF, DMs open). (2) X/Twitter brand account `@callibrate_io` reserved and protected — dormant until Phase 3+. (3) Substack `fredericgeens` created for long-form blog (personal email, not ops@ — personal asset). (4) dev.to `Fr-e-d` created via GitHub for cross-posting (canonical_url → Substack for SEO). (5) Reddit `Fr-e-d` already active + r/AIAgentGovernance owned (DEC-99). (6) Personal brand first: all Phase 0-1 content under Frédéric Geens, not Callibrate. Brand content deferred to Phase 3+. (7) No API keys configured — manual posting in Phase 0-1, reassess if volume > 3 posts/week. (8) Channel registry documented in `memory/ops/channels.md` (OPS-002).
**Decided by:** Founder
**Date:** 2026-02-26

---

### DEC-100 — Community seeding for E01S02 hand raiser (X + Discord + Skool)

**Context:** E01S02 (expert hand raiser) was deferred due to LinkedIn constraint (founder employed at key position). Reddit signal analysis (109 comments, 15 posts) validated H1-H12 but H3/H5 (willingness to pay) require direct engagement. X/Twitter identified as viable alternative to LinkedIn for WTP validation.
**Decision:** (1) X/Twitter replaces LinkedIn as primary hand raiser channel. Gate unchanged: ≥10 qualified expert hand raisers. (2) Communities prioritized by ICP density:
- **Tier S:** n8n Discord (74k, expert-heavy, Jobs channel active), n8n Community Forum (200k+), Liam Ottley Skool (297k, downgraded from S to B after review — audience is beginners, not established experts)
- **Tier A:** AI Agency Alliance Discord (13k, business-focused, JOINED 2026-02-26), AI Automation Society Skool (1.1k), 2 X Communities (AI Agents/Automation/N8N + AI Automation Agencies)
- **Tier B:** Reddit (already active), Indie Hackers, Online Geniuses Slack (53k)
(3) n8n Discord rules: no spam, no self-promo, no cold DMs. Engagement must be public and organic. (4) Skool signup: fred+skool@callibrate.io, Discord: fred+discord@callibrate.io. LinkedIn provided for Skool anti-bot gate (low risk — verification only, not public). (5) 3-phase engagement: Phase 1 seed (join + lurk), Phase 2 warm engagement (reply to existing threads with Reddit-sourced insights), Phase 3 hand raiser post (promise draft). (6) X profiles identified for follow/engagement: @knoxtwts, @gkotte1, @romanbuildsaas (Tier 1), @liamottley_, @n8n_io, Nadia Privalikhina (Tier 2), @BrOrlandi, @NoahEpstein_ (Tier 3). (7) Reddit contacts with strongest signal: heyiamnickk, Littlecutsie, Academic-Highlight10 (no X profiles found — engage via Reddit DM if needed post-hand raiser).
**Files:** No codebase files. External: discord.com/invite/n8n, skool.com/ai-automation-agency-hub, x.com/i/communities/1902201901417922832
**Date:** 2026-02-26

---

### DEC-99 — Created r/AIAgentGovernance subreddit (topical land grab)

**Context:** Content plan mars 2026 identifies Reddit as priority #1 channel for distribution-building. COMMS-001 maps 8 subreddit clusters (15+ subs) but all are existing communities where we participate. No owned sub-channel existed for the core .gaai topic: AI agent governance in practice.
**Decision:** (1) Create r/AIAgentGovernance as a topical (not branded) subreddit. Land grab on an emerging topic — subreddit names are unique and permanent. Cost: 5 min, $0. (2) Positioning: practical governance of AI agents (decision logging, memory, context engineering, multi-agent coordination, observability) — NOT policy/regulation (that's r/AIgovernance, 10 members, different angle). (3) Do NOT invest active time growing it in Phase 0-1. It's a free option, not a priority. Seed 1 post/month max via cross-posts. (4) Becomes primary venue when .gaai goes OSS (Gate 2). (5) Rejected: r/AgenticGovernance (taken), r/AgenticOps (taken), r/AIAgentOps (taken), names with underscores (hard to type/remember). (6) 4 rules configured: civility (default), stay on topic, share what actually happened, no spam/self-promo (tools OK with substantive writeup). (7) Rejected AI disclosure rule — premature on a 1-member sub, undermines founder credibility during cold start.
**Files:** No codebase files. External: reddit.com/r/AIAgentGovernance
**Date:** 2026-02-26

---

### DEC-98 — Content plan cold-start correction: distribution before content

**Context:** March 2026 content plan (rev.1) allocated 52% of budget to a flagship blog post gated on Gate 1 (can't publish yet) while Reddit engagement (the only activity serving Gate 2 expert recruitment) received 19%. Evaluated against cold-start best practices: Justin Welsh (atomic content first), Rand Fishkin (60 days community before self-promo), Pieter Levels (90% replies, 10% threads for 30 days), Grow & Convert (Pain Point SEO).
**Decision:** (1) Invert the plan — distribution-building FIRST, hub content production SECOND. A flagship with 0 readers = wasted effort. (2) Reddit budget 2h → 4h (33%). Split: P1 supply track (r/aisolobusinesses, r/freelance_forhire) + P3 builder track (r/ClaudeAI, r/cursor). (3) X strategy: weeks 1-3 = engagement pur (replies + follows, no threads). First thread only in week 4 IF ~50+ followers. Algorithm doesn't distribute threads from 0-follower accounts. (4) Flagship: 5h30 → 2h (outline + angle notes only). Full draft deferred to April, informed by 4 weeks of atomic content feedback. New AC: "angle validated by ≥2 atomic content tests showing engagement." (5) Engagement workflow: batch 2x/day (morning triage 15min + evening proactive 15min). No real-time notifications. AI-assisted triage per COMMS-001 Part 5 (tier classification + draft responses). (6) CONTENT-STRATEGY-001 evaluation: 5/6 dimensions validated (Layer, Phase, Audience, Channel, Objective). ARL (dim 6) flagged as premature — no audience to classify yet. Measurement framework (§10) correct but inopérant until first publication. Strategy document overall sound — the plan was the problem, not the strategy.
**Files:** `artefacts/content/plans/2026-03-content-plan.md` (rev.2 — rewritten)
**Date:** 2026-02-26

---

### DEC-97 — Framework validation: Capability Readiness + Domain Memory tested and confirmed

**Context:** After implementing DEC-90 (Capability Readiness rule), DEC-93 (domain sub-agents), and DEC-94 (domain memory namespace), ran 3 structured tests to compare theory vs practice — verify the framework changes work in real agent execution, not just on paper.
**Decision:** All 3 tests PASS. Framework changes validated:

**Test 3 — Domain memory retrieval (post-rename):** Triggered `domain-knowledge-research` skill on a keyword research intent. Agent correctly located and loaded SEO-001, SEO-002, KWR-001 from the renamed `domains/content-production/sources/` path. Domain memory namespace (DEC-94) works.

**Test 1 v1 — Capability Readiness (strategic intent):** Triggered Discovery with "should we add referral/sponsorship?" Agent correctly performed strategic analysis and concluded "not now" WITHOUT creating a Story → no Capability Readiness check triggered. This is correct behavior: the rule applies at `refined` status, not at feasibility analysis. Validates that the rule doesn't over-fire.

**Test 1 v2 — Capability Readiness (production intent):** Triggered Discovery with "create a pilot content for AI Chatbot satellite blog." Agent explicitly: (1) identified architectural conflict (no blog on satellite Worker), (2) checked phase gates against CONTENT-STRATEGY-001, (3) performed full Capability Readiness check — listed all 8 required skills with status (6/8 "Non conçu") and knowledge readiness (GOOD/EXCELLENT), (4) proposed 3 resolution approaches, (5) stopped before `refined` to ask 3 clarifying questions. Validates that Discovery surfaces skill gaps before proceeding.

**Conclusion:** The Capability Readiness mechanism works as designed. Discovery checks skills before `refined`, surfaces gaps with knowledge readiness assessment, and keeps the human in the loop. Domain memory retrieval works after the `content/` → `domains/content-production/` rename.
**Files:** No files modified — validation only.
**Date:** 2026-02-26

---

### DEC-96 — content-plan skill (SKILL-CNT-011) + publishing audit + PostHog blocker

**Context:** CONTENT-STRATEGY-001 defines a 6-dimension model with BP scoring, measurement framework, and phase-gated content authorization. But no mechanism existed to operationalize it — no planning trigger, no monthly cadence, no verification that publishing tools work. Audited the full E07 PostHog analytics stack, all publishing channels, and MCP configuration.
**Decision:** (1) Create SKILL-CNT-011 (content-plan) in `skills/domains/content-production/content-plan/SKILL.md`. Track: discovery (produces plans, not content). 7-step process: determine GTM phase → inventory content → evaluate underserved dimensions → recommend 2-3 hub pieces on 6 dimensions + BP → budget allocation → output plan file → story draft recommendations. (2) Trigger via `/gaai-status` Section 5 (monthly reminder when no current-month plan exists). Rejected: delivery daemon cron (track violation), new slash command (overkill for 1x/month), manual-only (invisible). (3) Publishing audit results: all channels use manual publish by design (COMMS-001). No publishing tool blocks content production. Social scheduling APIs (Buffer/Typefully) not needed at current cadence (4 posts/month). (4) PostHog audit: E07 stack is code-complete (17 events, 3 dashboards, proxy, MCP skill) but E07S06 has 5 founder actions pending (Personal API Key, shell export, dashboard script, DNS CNAME, Claude Code restart). This blocks the measurement framework (CONTENT-STRATEGY-001 §10) and CMF feedback loop, NOT content production. (5) Identified UTM gap: `utm_content` not captured — cannot attribute conversions to specific content pieces. Needs ~5 lines of code + a backlog story.
**Files:** `skills/domains/content-production/content-plan/SKILL.md`, `.claude/commands/gaai-status.md` (Section 5 added), `agents/discovery.agent.md` (cross-skills), `domains/content-production/gap-analysis.md` (CNT-011 + T6 + T7)
**Date:** 2026-02-26

---

### DEC-95 — Content Strategy Map: 6-dimension model with industry gap resolutions

**Context:** Designed a multi-dimensional content strategy model (Layer × Phase × Audience × Channel × Objective × ARL) for build-in-public across Callibrate, .gaai, and personal brand. Before formalizing, conducted industry research against 14 named frameworks (Schwartz's Stages of Awareness, BREW/Ahrefs, Pain Point SEO/Grow & Convert, Content-Market Fit/Vouillon, NFx marketplace tactics, ABC(L)/Seer Interactive, Content Atomization/Bluetext, Progressive Transparency). Identified 6 gaps in our approach and resolved them in the artefact.
**Decision:** Formalize as `CONTENT-STRATEGY-001.md` with 6 dimensions and 6 gap resolutions integrated:
1. **GAP-1 — Bottom-up sequencing:** ARL is a classification tool, not a publication order. Prioritize by Business Potential (BP), not ARL level. Pain Point SEO proves BOFU content converts immediately.
2. **GAP-2 — Business Potential scoring:** Added BP 0-3 scale (BREW-inspired) as an attribute on every content piece. BP drives production priority.
3. **GAP-3 — Content-Market Fit validation:** Added explicit feedback loop (Publish → Measure J+7/J+30/J+90 → Decide → Act) with per-Objective seuils minimums and pivot trigger after 3 failed Hubs.
4. **GAP-4 — Dual-audience tracks:** Formalized supply (P1) vs demand (P2) content tracks with phase-based ratios (80% builder Phase 0-1, supply-first Phase 2, balanced Phase 3). NFx marketplace tactic.
5. **GAP-5 — Transparency policy:** 3 levels (always share / share with delay / never share) replacing implicit BIP behavior.
6. **GAP-6 — Measurement per Objective:** Mapped primary + secondary metrics to each of the 6 objectives with PostHog/GSC sources and J+30 minimum thresholds.
**Relationship to existing artefacts:** CONTENT-STRATEGY-001 is the navigation map; COMMS-001 is the instrument panel (empathy maps, channel playbooks, writing style); GTM-001 provides the phase gates; MARKET-001 provides the vertical strategy. No overlap — each document has a distinct scope.
**Files:** `artefacts/strategy/CONTENT-STRATEGY-001.md`
**Date:** 2026-02-26

---

### DEC-94 — Domain memory namespace: `memory/domains/{domain}/`

**Context:** Content knowledge base existed at `memory/content/` but was (1) not registered in the master index, (2) missing YAML frontmatter, (3) ambiguously named ("content" = domain? product content? generic content?). With DEC-93 adopting domain sub-agents, memory structure must support domain-scoped retrieval.
**Decision:** Introduce `memory/domains/` namespace. First domain: `domains/content-production/`. Convention: each domain with ≥5 skills + own knowledge base gets `domains/{domain-name}/` with its own `index.md` (standard YAML frontmatter). Shared memory stays flat at root (project/, decisions/, patterns/, ops/). No cross-domain folder needed — multi-domain Stories spawn multiple domain sub-agents, each loading its own domain memory. Master index gains a `## Domain Memory` section. `memory-ingest` gains a dual-index rule (update master + domain index).
**Rejected alternatives:** (a) `knowledge/domains/content-production/` + `knowledge/cross-domain/` — "knowledge" frames domain memory as research-only, but domains can contain patterns (voice-guide), ops, and conventions. (b) `content/` flat alongside shared categories — ambiguous name, no namespace convention for future domains.
**Files changed:** `memory/content/` → `memory/domains/content-production/`, `index.md`, `README.memory.md`, `memory-ingest/SKILL.md`, content skills input paths, source file references.
**Date:** 2026-02-26

---

### DEC-93 — Domain Sub-Agent architecture for skill overload prevention

**Context:** Framework audit brought skills to 40, with content blueprint adding 7+ more. Evaluated risk of skill overload: agent definition bloat, skill selection ambiguity, cross-cutting sprawl (25/40 = 62.5% in flat `cross/`), no lifecycle/archival mechanism. Framework is well-designed for execution governance but NOT for its own growth governance.
**Decision:** Adopt a domain sub-agent architecture to solve skill overload structurally:
1. **Skill namespacing** in `cross/` (memory/, governance/, analysis/, content/, delivery-support/) — validated, implement now
2. **Domain sub-agents** for Discovery and Delivery — a domain sub-agent is spawned when a Story belongs to a specific functional domain (content, analytics, etc.). In Delivery, it replaces `compose-team` for its domain and dispatches plan/impl/QA with domain-scoped context bundles + skills. In Discovery, it executes domain-specific skills and produces artefacts for Discovery to validate.
3. **Domain specialist registry** extending the existing specialist pattern per domain/blueprint (functional level), complementary to existing technical specialists (db-migration, api-integration, etc.)
4. **Activation rule:** domain sub-agent justified when domain has ≥5 skills AND its own memory. Below that, skills stay in cross/.
5. **Backward compatible:** non-domain stories (backend, infra) use the current flow unchanged.
**Rejected alternatives:** (a) Skill lifecycle with `deprecated` + auto-pruning — treats symptoms, operational overhead, false positives on rarely-used skills. (b) Agent skill cap at 20 — arbitrary, forces artificial grouping. Both become unnecessary with domain sub-agents.
**Implementation trigger:** When content blueprint enters Delivery (first domain ≥5 skills).
**Risk:** Orchestration depth +1 level — mitigated if domain sub-agent stays a "compose-team spécialisé", not a second orchestrator.
**Date:** 2026-02-26

---

### DEC-92 — Framework-wide skill audit: 40 skills reviewed, all gaps fixed

**Context:** After creating `domain-knowledge-research` (DEC-91) with high epistemic rigor, applied the same level of scrutiny to all 40 existing skills.
**Decision:** Audit all skills via 14 parallel sub-agents, fix all identified gaps via 8 parallel sub-agents, then normalize metadata across remaining files.
**Results:** 8 SOLID (no changes), 4 SIGNIFICANT rewrites (browser-journey-test, refine-scope, memory-compact, summarization), 16 MINOR content fixes (generate-stories, generate-epics, create-prd, remediate-failures, compose-team, coordinate-handoffs, decision-extraction, memory-retrieve, delivery-readiness-audit, risk-analysis, consistency-check + 5 others), 21 metadata normalizations (`status` field, `## Outputs` heading, `updated_at`). skills-index.yaml regenerated — all 40 entries now have `status` (35 stable, 3 experimental, 1 future).
**Rationale:** Skills are the execution backbone. Inconsistent quality, missing output specs, or vague processes undermine agent determinism. One-time investment, high compounding returns.
**Date:** 2026-02-26

---

### DEC-91 — domain-knowledge-research skill (SKILL-CRS-023) — epistemic rigor from manual prompts

**Context:** Need for a governed skill to research industry best practices, extract structured knowledge (AKUs), and filter for GAAI compatibility. Three manual Google Notebook LM prompts (source collection, best practices extraction, knowledge architect) existed but were ungoverned.
**Decision:** Create a single skill `domain-knowledge-research` (v2.0) that integrates all three prompts into a 5-phase process with GAAI governance. Key design: 6 mandatory epistemic rules (correlation≠causation, preserve quantified data, flag data sparsity), AKU format with `causality` + `evidence_type` + `mechanism` + `guardrails` + `directional_trend`, 5-filter GAAI compatibility pass, confidence calibration layer, safe generation protocol (7 rules for LLM consumption).
**Rejected alternative:** 4 separate skills (persist-source-catalog, persist-akus, generate-skill-blueprint, validate-skill-scope) — redundant with existing skills and fragmented governance.
**Files:** `.gaai/skills/cross/domain-knowledge-research/SKILL.md`, `.gaai/agents/discovery.agent.md` (cross-skills list)
**Date:** 2026-02-26

---

### DEC-90 — Capability Readiness: split knowledge (Discovery) / skills (Delivery)

**Context:** No mechanism existed to verify that agents have both the competencies and current best-practice knowledge needed before executing a mission.
**Decision:** Split responsibility: (1) Discovery verifies **knowledge readiness** — best practices exist and are current for the domain before marking stories `refined`. Uses `approach-evaluation` (narrow, single problem) or `domain-knowledge-research` (broad, full domain). (2) Delivery verifies **skill coverage** during `evaluate-story` — checks skills-index.yaml against identified domains, blocks on critical gaps with escalation to Discovery.
**Rejected alternative:** Single readiness check in Delivery between evaluate-story and compose-team. Fatal flaw: Delivery can't run `memory-ingest` (orchestration rules), so any knowledge gap forces escalation back to Discovery = unnecessary ping-pong.
**Files:** `.gaai/contexts/rules/orchestration.rules.md` (new section), `.gaai/skills/delivery/evaluate-story/SKILL.md` (Step 4 + skill_gaps output)
**Date:** 2026-02-26

---
<!-- Add decisions above this line, newest first -->
