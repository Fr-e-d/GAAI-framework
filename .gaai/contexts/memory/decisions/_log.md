---
type: memory
category: decisions
id: DECISIONS-LOG
tags:
  - decisions
  - governance
created_at: 2026-02-19
updated_at: 2026-02-26
---

# Decision Log

> Append-only. Never delete or overwrite decisions.
> Only the Discovery Agent may add entries (or Bootstrap Agent during initialization).
> Format: one entry per decision, newest at top.
>
> **Compacted 2026-02-23:** DEC-01 to DEC-59 (59 entries) archived.
> Full text → `archive/decisions-01-59.archive.md` | Summary → `summaries/decisions-01-59.summary.md`

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
**Decision:** (1) Create SKILL-CNT-011 (content-plan) in `skills/content/content-plan/SKILL.md`. Track: discovery (produces plans, not content). 7-step process: determine GTM phase → inventory content → evaluate underserved dimensions → recommend 2-3 hub pieces on 6 dimensions + BP → budget allocation → output plan file → story draft recommendations. (2) Trigger via `/gaai-status` Section 5 (monthly reminder when no current-month plan exists). Rejected: delivery daemon cron (track violation), new slash command (overkill for 1x/month), manual-only (invisible). (3) Publishing audit results: all channels use manual publish by design (COMMS-001). No publishing tool blocks content production. Social scheduling APIs (Buffer/Typefully) not needed at current cadence (4 posts/month). (4) PostHog audit: E07 stack is code-complete (17 events, 3 dashboards, proxy, MCP skill) but E07S06 has 5 founder actions pending (Personal API Key, shell export, dashboard script, DNS CNAME, Claude Code restart). This blocks the measurement framework (CONTENT-STRATEGY-001 §10) and CMF feedback loop, NOT content production. (5) Identified UTM gap: `utm_content` not captured — cannot attribute conversions to specific content pieces. Needs ~5 lines of code + a backlog story.
**Files:** `skills/content/content-plan/SKILL.md`, `.claude/commands/gaai-status.md` (Section 5 added), `agents/discovery.agent.md` (cross-skills), `domains/content-production/gap-analysis.md` (CNT-011 + T6 + T7)
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

### DEC-2026-02-25-89 — Staging infra audit: 5 missing migrations applied + ADMIN_API_KEY provisioned

**Context:** Comprehensive audit of all human-required actions across the backlog revealed 5 Supabase migrations present in the repo but never applied to staging (`xiilmuuafyapkhflupqx`). Also identified ADMIN_API_KEY (E08S04) not set as a secret post-E06S28.
**Decision:** Applied all 5 migrations via Supabase MCP and set ADMIN_API_KEY via `wrangler secret put --env staging`.
**Applied migrations:** (1) `lead_credit_rpc` (E06S32 — debit/restore RPC functions), (2) `admissibility_criteria` (E06S36 — JSONB column + merge_expert_profile update), (3) `satellite_configs_anon_select` (E08S05 — anon RLS policy), (4) `webhook_events` (E08S05 — L2 idempotency table), (5) `lead_credit_rpc_ownership` (E08S05 — ownership assertions in RPCs). Total staging migrations: 18 (fully synchronized with repo).
**Remaining human actions (prioritized):** (1) D1-D2: Turnstile site key + secret, (2) B3-B5: PostHog Personal API Key + ph.callibrate.io CNAME + dashboards, (3) E1-E3: Google OAuth sensitive scope verification (4-6 week lead time — blocker go-live), (4) C1-C3: Lemon Squeezy setup (Phase 3 only), (5) H1: E08S02 backlog status anomaly (PR merged, status still in_progress), (6) H2: E08S03 failed — booking hold auth needs re-delivery, (7) F1-F3: Build in Public publication status unknown.
**Impact:** Staging DB now fully operational for billing (E06S32-S34), admissibility filters (E06S36), satellite RLS (E08S05), webhook idempotency (E08S05), and admin endpoints (E08S04). No code changes — infrastructure-only session.
**Date:** 2026-02-25

---

### DEC-2026-02-25-88 — Niche-down candidates evaluated: Real Estate #1, trigger = ≥30% domain concentration post-Gate 2

**Context:** After deciding on AI-pure launch (DEC-85) with data-driven niche-down post-Gate 2, needed to pre-identify which IA×Domain combinations are viable candidates so the team knows what to look for in conversion data. 13 industry domains evaluated across 39 combinations (3 AI expertise × 13 domains). Scoring: 6 parameters (/30) — search volume, Reddit/community signals, market size, SMB accessibility, expert supply niche, Callibrate fit.
**Decision:** (1) **#1 candidate: Real Estate × (Chatbot + Workflow) — score 26/30.** Only niche scoring well on ALL axes: SMB-native (agents are independents), habitué à payer pour leads, ROI mesurable (+40% conversion), short decision cycle, 87% adoption, $25K/mo revenue documented. (2) **Sleepers: Accounting (21/30)** — French e-invoicing mandate 2026-2027 creates time-bound urgency, 44% CAGR, but expert supply is near-zero. **Legal (20/30)** — $35K deals proven on r/n8n, confidentiality moat, but 20% SMB adoption and near-zero freelancer supply. (3) **Eliminated: Healthcare (21/30 but SMB accessibility 2/5), Insurance (18/30, enterprise-only), Financial Services (16/30, enterprise), HR (18/30, integrated tools dominate), E-commerce (23/30 but Callibrate fit 2/5 — self-serve tools dominate).** (4) **Trigger:** Niche-down activates when Phase 2 data shows ≥30% of V1/V3 prospects coming from same industry domain. (5) **Key insight:** Big TAM ≠ good Callibrate market. Enterprise-driven niches (healthcare $39B, fintech $30B) are structurally incompatible with 30-min consultation calls. Callibrate fit requires: SMB prospect, accustomed to paying for services, short decision cycle, measurable ROI.
**Rationale:** Pre-identifying candidates avoids starting niche research from scratch post-Gate 2. The 30% concentration trigger prevents premature niche-down while ensuring signal isn't missed. Real Estate's dominance is structural: agents are the archetypal SMB buyer — they already pay for leads (Zillow, Realtor.com) and make fast decisions. The empathy maps reveal that Real Estate experts also match the supply-side ICP: they actively seek client acquisition channels and can charge 4-figure monthly retainers.
**Impact:** MARKET-001 Section 11 created with full scoring matrix, empathy maps (prospect + expert for top 3), elimination rationale, and activation trigger. No backlog changes — niche-down satellites are not authorized until Gate 2 data. Conversion tracking should tag prospect industry domain when available.
**Date:** 2026-02-25

---

### DEC-2026-02-25-87 — Content blueprint knowledge base: 7 sources cataloged, gap analysis complete

**Context:** To design skills for the GAAI content blueprint ("The Content Architect for Blog Post & Social Media"), we needed a state-of-the-art knowledge base covering SEO, GEO, writing methodology, AI authenticity, social media, credibility, and agentic content systems. 7 research reports were collected, analyzed for GAAI compatibility (agent/skill separation, no duplicates, scope filtering), and cataloged.
**Decision:** (1) Knowledge base created at `.gaai/contexts/memory/content/` with 7 sources totaling 118 AKUs. (2) Each source filtered for GAAI compatibility: 8 AKUs excluded (duplicates or incompatible), 5 reframed (agent→skill), 11 flagged as out-of-scope (infrastructure/strategy context only). (3) All sources enriched with GAAI skill mappings and cross-references. (4) Gap analysis completed: 5 skills ready for design (CNT-002, 003, 004, 006, 009), CNT-008-youtube-script has critical gap (blocking), CNT-001/005/007 have partial gaps (high priority), 5 transversal gaps identified. (5) Content blueprint architecture: skills live in `skills/content/`, no new agents (existing sub-agents orchestrate), single backlog with blueprint tags.
**Rationale:** Separating knowledge collection from skill design prevents premature abstraction. Filtering for GAAI compatibility ensures the knowledge base doesn't introduce architectural violations (e.g., "content agents" that break the domain-agnostic agent model). Gap analysis before skill design prevents building on incomplete foundations.
**Impact:** `memory/content/index.md` (source registry), `memory/content/sources/` (7 files), `memory/content/gap-analysis.md`. Next: fill critical gaps (CNT-008 YouTube, CNT-001 research methodology, CNT-007 transformation templates), then design skills for the 5 ready ones.
**Date:** 2026-02-25

---

### DEC-2026-02-25-86 — GAAI modular blueprint architecture: domain skills as extractable packs, not separate frameworks

**Context:** Question arose whether to create a separate framework for content production vs integrating into GAAI. Also whether to formalize the "Playbooks" concept from VISION-GAAI-CLOUD.md.
**Decision:** (1) No separate framework — content is a skill domain within GAAI, not a parallel system. (2) Blueprint architecture: each domain (coding/, content/) gets a folder in `skills/` with a `blueprint.yaml` manifest. (3) Agents remain domain-agnostic — no "content agent." Existing sub-agents (Planning, Implementation, QA) handle all domains. (4) Single backlog with `blueprint:` tag per story. (5) Memory namespaced per blueprint (`memory/content/`, `memory/patterns/`). (6) Future open-source: each blueprint extractable as a `gaai-blueprint-{name}` pack. (7) Minimum Viable Blueprint approach: structure for extractability without building formal plugin system now.
**Rationale:** Creating a separate framework would duplicate GAAI's structure (backlog, memory, agents, skills, artefacts) with no architectural benefit. The "Playbooks" concept from VISION-GAAI-CLOUD.md is the right vision but premature to formalize as a plugin system before Gate 2. Current approach: structure content skills so they're naturally extractable later. PostHog skills confirmed as `coding/` blueprint (output = code commits). Rule of thumb: if delivery produces a commit → `coding/`, if delivery produces a document → corresponding blueprint.
**Impact:** Blueprint architecture defined. `skills/content/` to be created with blueprint.yaml when first skill is designed. No changes to agents, backlog format, or delivery daemon. COMMS-001, GTM-001, and existing content artefacts remain in place — new skills complement, don't replace.
**Date:** 2026-02-25

---

### DEC-2026-02-24-85 — Scope strategy: stay AI-pure at launch, niche-down by domain data-driven post-Gate 2

**Context:** After selecting Tier 1 verticals (DEC-84), question arose: should Callibrate limit to AI expertise domains, niche-down (AI × industry domain), niche-up (broad IT consulting), or expand to non-AI expertise? Four approaches evaluated across 6 coherence dimensions.
**Decision:** (1) **Phase 2 (launch): Approach B — AI-pure.** 3 satellites (V3 AI Chatbot, V1 Workflow Auto, V8 AI Integration). Positionnement: "la marketplace des experts en IA et automatisation". No dilution. (2) **Phase 3 (post Gate 2 PASS): B→A — Niche-down data-driven.** When conversion data reveals which prospect domains convert best (e.g., 60% V3 prospects are healthcare → launch "AI Chatbot for Healthcare"). Niche-down is a consequence of data, not an a priori hypothesis. (3) **Post M3 (vision): B→A→eventually C.** Domain expansion only if Matching OS is proven as defensive asset (data flywheel, composite scores). (4) **Explicit exclusions:** No Salesforce/CRM/Shopify satellites (gap compétitif = 0, matching engine not valorized). No 30 micro-satellites IA×Domain at launch (combinatorial chicken-and-egg). No broad IT consulting (no differentiation vs Upwork/Toptal/Clutch).
**Rationale:** Coherence test across 6 dimensions: Matching OS valorization (prospect doesn't know which tool), supply availability, competitive gap, positioning coherence, solo founder scalability, hype cycle resilience. AI-pure scores 5/6. AI×Domain scores 4/6 (fails on supply granularity + scalability). Broad domains scores 1/6 (fails on 5 dimensions). Non-AI domains scores 1/6. The Matching OS's structural advantage — tool-agnostic matching for confused prospects — only works in verticals where the prospect genuinely doesn't know which tool they need. CRM/Shopify/data prospects already know their tool → matching engine is overqualified for a directory problem. AI vulnerability to hype cycle is real but mitigated by phased expansion: prove the engine on AI, then deploy it where the same structural advantage exists in non-AI domains.
**Impact:** MARKET-001 updated with Section 10 (Scope Strategy). GTM-001 Phase 2 vertical references unchanged (already correct). project/context.md satellite section unchanged (already scoped to Tier 1). This decision constrains all satellite development until Gate 2 data is available.
**Date:** 2026-02-24

---

### DEC-2026-02-24-84 — Satellite vertical selection: V3 (AI Chatbot) + V1 (Workflow Auto) + V8 (AI Integration) as Tier 1 launch verticals

**Context:** Callibrate needs to choose which business verticals to address first via satellite sites. The marketplace is two-sided: experts (supply) and prospects (demand). Selection must satisfy both sides simultaneously — enough expert pain to attract supply, enough prospect search volume to generate demand, and a competitive gap wide enough for a new entrant.
**Decision:** (1) Evaluated 8 candidate verticals across 3 axes: expert pain scoring (7 parameters, /35), prospect-side keyword volumes (US + FR), and competitive gap analysis. (2) **Tier 1 (launch):** V3 AI Chatbot (27/35), V1 Workflow Automation (26/35), V8 AI Integration for SaaS (26/35). (3) **Tier 2 (post-traction):** V2 CRM, V5 Marketing Automation. (4) **Skip:** V4 E-commerce, V6 Data Pipeline, V7 RPA. (5) Common winning trait: prospect doesn't know which tool they need → Callibrate's tool-agnostic matching is the killer feature. (6) Supply overlap: one expert can serve all 3 Tier 1 verticals (e.g., Caio = n8n + Python + Claude + React). (7) French market = blue ocean for all 3 (quasi-zero competition on transactional keywords).
**Rationale:** Tier 1 verticals score highest on expert pain AND competitive gap AND Callibrate model fit. V2 CRM has highest prospect volume but vendor ecosystems (HubSpot/Salesforce) are impenetrable. V4 E-commerce is served by Storetasker. V6/V7 are enterprise-oriented (wrong model for consultation calls). The 3 Tier 1 verticals share one structural advantage: prospects don't know which tool they need, which is precisely where matching engines beat vendor directories. Expert supply overlap means launch investment is efficient.
**Impact:** New strategy artifact `MARKET-001.md` created with full analysis. GTM-001 updated with vertical selection reference. Memory index updated. Open decisions: URL architecture, content phasage, prospect empathy maps + funnels for V1/V3/V8.
**Date:** 2026-02-24

---

### DEC-2026-02-24-83 — Cost analysis skill + delivery cost baseline established

**Context:** Need to estimate theoretical API pay-per-use cost of GAAI-governed development. 25 delivery logs available (JSONL with per-turn usage data). Claude Code `result` events contain `total_cost_usd` and `modelUsage` breakdowns computed from Anthropic API pricing.
**Decision:** (1) Created SKILL-CRS-022 `cost-analysis` — reusable cross skill with `extract-costs.sh` script (jq-based, supports `--json`). (2) Established delivery cost baseline: $149.90 measured across 24 stories (+ 1 estimated). Average $6.02/story. 99% Sonnet 4.6. Estimated total project cost ~$325 (incl. non-tracked stories + Discovery). (3) Updated 15 backlog entries with actual `cost_usd` values (were all 0). (4) Updated `ops/platform.md` with complete cost breakdown.
**Rationale:** Enables ongoing cost tracking and value-per-dollar evaluation. Script approach chosen over manual calculation — reusable and auditable. Delivery logs are the only reliable cost source (session files don't contain result events, Discovery sessions aren't captured).
**Impact:** New skill `cost-analysis` in `.gaai/skills/cross/cost-analysis/`. Skills index updated (39 total). Backlog `cost_usd` fields populated. `ops/platform.md` cost section rewritten with measured data.
**Date:** 2026-02-24

---

### DEC-2026-02-24-82 — Phase 2 proof of quality visibility required before payment activation

**Context:** Discovery field data (E01S01 rounds 1-3) reveals structural skepticism toward paid platforms among AI automation experts. Key signals: Rich-Emu-1561 (r/Upwork) — "serious leads come from niche communities or partnerships, not open marketplaces". SilkLoverX — "vague AI automation claims are a red flag" (prefers niche communities). Own_Constant_2331 (Top 1% Upwork) — 3 weeks to find ONE good client. No explicit "I paid for leads and it failed" but strong implicit reluctance toward paid generalist platforms. The counter-pattern: experts tolerate paid platforms only when they can SEE quality before paying.
**Decision:** Phase 2 (J21-J45) must demonstrate matching quality BEFORE activating credit billing (Phase 3). Concrete requirement: the first expert cohort (10 experts, Gate 2) operates in "proof of quality" mode — they receive matched leads for free, see the matching rationale, and rate lead quality. Only when average lead rating >= 4/5 (Gate 2 criterion) does Phase 3 activate billing. GTM-001 Phase 2 updated with explicit proof-of-quality prerequisite. This is NOT a free tier — it's a time-limited proof phase for the first cohort only.
**Rationale:** The field data shows that the barrier to adoption is not price — it's trust. Experts have been burned by platforms that charge for low-quality leads. Starting with free + visible quality metrics addresses the trust deficit before asking for payment. The credit billing infrastructure (E06S31-S34) is ready — the activation timing is what matters.
**Impact:** GTM-001 Phase 2 updated (proof-of-quality mode for first cohort). No code change. No schema change. Affects go-to-market sequencing only.
**Date:** 2026-02-24

---

### DEC-2026-02-24-81 — Outcome-based framing validated — expert profiles must be outcome-oriented

**Context:** Discovery field data reveals a critical framing insight. Littlecutsie (r/n8n_ai_agents): "stopped selling n8n workflows, started selling found time" — outcome-based framing converts better than tool-based framing. r/AiForSmallBusiness: "prompt engineers with a Zapier account" — tool lists are a negative signal. "Good consultants interrogate requirements" — brief quality = matching quality. Current expert profiles are tool-oriented (skills TEXT[]) without mechanism to express or match on outcomes delivered.
**Decision:** Create E06S37 — add `outcome_tags TEXT[]` to expert profiles (short outcome phrases: "25h/week saved on RFP processing", "automated lead qualification pipeline"). Extend AI extraction (ProspectRequirements) with `desired_outcomes`. Add `scoreOutcomeAlignment()` scoring dimension using Workers AI semantic similarity. Initial weight: 0.10 (conservative, taken from skill_weight). Weight tuning post-Gate 2 with real data.
**Rationale:** The matching engine currently scores on what experts KNOW (skills, industry) but not what they DELIVER (outcomes). Field data proves that outcomes are the real differentiator for qualified prospects. Adding this dimension makes matching more relevant without changing the existing scoring architecture — it's an additive scoring dimension with graceful degradation (null when data missing).
**Impact:** E06S37 created (refined, E06 backlog). Schema: `outcome_tags TEXT[]` on experts. Extraction: `desired_outcomes` in ProspectRequirements. Matching: `scoreOutcomeAlignment()` new dimension. Dependencies: E06S22, E06S08/E06S12, E06S02.
**Date:** 2026-02-24

---

### DEC-2026-02-24-80 — Expert admissibility criteria extended beyond budget based on field data

**Context:** Discovery field data (E01S01 rounds 1-3) reveals that expert filtering criteria are more sophisticated than initially modeled in DEC-67/68. Budget is filter #1 (implemented via E06S34 `applyBillingFilters`), but field data shows two additional critical filters: (1) Methodology alignment — heyiamnickk (r/gohighlevel): "modular or nothing", experts reject projects without structured scoping phases. (2) Architecture/stack preferences — experts refuse projects on incompatible stacks. (3) Payment security — "card on file" (MachadoEsq) — already covered by credit billing. Current matching filters on billing only (budget/balance/spending limit), missing the methodology and architecture dimensions.
**Decision:** Create E06S36 — add `admissibility_criteria JSONB` to expert profiles with structured fields: `required_methodology`, `excluded_verticals`, `min_project_duration_days`, `min_budget`, `required_stack_overlap_min`, `custom_rules`. New `applyAdmissibilityFilters()` function runs after billing filters, before scoring. Same fire-and-forget notification pattern as billing exclusions. Follows E06S34 architecture exactly.
**Rationale:** Matching quality depends on filtering out not just financially incompatible experts but also methodologically incompatible ones. The field data shows experts self-select harder on methodology than on price — "modular or nothing" is a deal-breaker, not a preference. Adding these filters reduces wasted leads and improves expert trust in the platform (DEC-82).
**Impact:** E06S36 created (refined, E06 backlog). Schema: `admissibility_criteria JSONB` on experts. Matching: `applyAdmissibilityFilters()` new filter stage. Dependencies: E06S34 (pattern), E06S02 (schema).
**Date:** 2026-02-24

---

### DEC-2026-02-24-79 — .gaai origin story as narrative backbone for all content

**Context:** Le founder a partagé l'histoire d'origine de .gaai : 6 semaines au Vietnam en digital detox (sa compagne a interdit le laptop), mais l'écosystème AI explosait (OpenClaw, Cowork, B-Mad, Ralph Wiggum). Depuis un iPhone 8 (très lent), il a lu des papiers scientifiques, suivi les releases Anthropic, condensé le state-of-the-art avec Gemini 3 via NotebookLM, fait challenger ses idées brutalement par ChatGPT 5.2, consigné tout dans Notion via MCP server. Construit sur AI-Governor-Framework (son premier OSS). Retour en Belgique → premier test avec Claude Code → résultats bien au-dessus des attentes → décision de valider sur un vrai projet (Callibrate) avant d'open-sourcer. Background : 10+ ans de dev autodidacte (des centaines d'heures de nuits), co-fondateur transport company 2015, program manager, "Swiss Army knife", persévérance + curiosité + painkillers not vitamins.
**Decision:** Cette origin story devient le **narrative backbone** de tout le contenu (COMMS-001 mis à jour). Structure en 7 beats : qui suis-je → digital detox → research phase → assemblage → retour + premier test → décision de validation → les preuves. Nouvel Angle D ajouté à E01S05 DC1 : "My girlfriend banned my laptop for 6 weeks. I came back with a governance framework for AI agents." Nouveau DC7 : structurer le narrative arc en Discovery. Nouveau AC2b : origin story section = premier tiers du blog post (Golden Circle: WHY first).
**Rationale:** L'histoire est le différenciateur ultime : authentique (iPhone 8, digital detox, girlfriend), impossible à copier, mémorable, et elle établit la crédibilité (10+ ans de dev, pas du vibe coding) tout en humanisant le builder. Chaque channel peut réutiliser cette histoire à des longueurs différentes. L'Angle D est probablement le hook le plus fort pour HN/Reddit — intrigant, humain, pas clickbait.
**Impact:** E01S05 mis à jour (origin story dans Context, Angle D dans DC1, DC7 ajouté, AC2b ajouté). COMMS-001 mis à jour (nouvelle section "Storytelling Backbone" avec 7 beats + usage par canal).
**Date:** 2026-02-24

---

### DEC-2026-02-24-78 — Communication & Publication Strategic Plan (COMMS-001)

**Context:** Le build-in-public orchestré (DEC-77) et le flagship blog post (DEC-76, E01S05) nécessitent un plan de communication complet et actionnable. Besoin de définir : empathy maps pour tous les personas, stratégie canal par canal, axes éditoriaux, personal branding, stratégie de réponse aux commentaires, pipeline d'automatisation contenu, et gestion des risques — le tout dans un budget de 5h/semaine.
**Decision:** Créer l'artefact COMMS-001.strategy.md — plan stratégique de communication en 7 parties : (1) Empathy maps pour 4 personas (P1 expert, P2 prospect PME, P3 dev/AI builder, P4 industry/recruteurs), grounded dans les hypothèses validées (H1, H2, H5, H7, H8 de E01S01). (2) Channel strategy matrix — X/Twitter (2-3 threads/semaine), Reddit (3-4 interactions/semaine), blog perso (Substack, 1x/mois), dev.to (cross-post), HN (3-4 Show HN total), LinkedIn (différé DEC-31), GitHub (différé post Gate 2). (3) Personal brand guidelines — IS/ISN'T, voice rules, mots interdits, bio templates, identité visuelle. (4) Launch orchestration calendar — Phase 1 → Gate 1 (flagship post J1-J7) → Phase 2 → Gate 2 (.gaai OSS) → Phase 3. (5) Comment response strategy — système 3-tier (2h/24h/never), templates par type, AI-assisted triage. (6) Content pipeline — weekly routine exacte (SAT→FRI time blocks), SKILL-CRS-021 flow, métriques à tracker vs vanité. (7) Risk mitigation — viral capacity plan, 3-at-bat rule pour flops, contrainte employeur, copycats.
**Rationale:** Un plan actionnable permet de tenir le rythme 5h/semaine sans réfléchir chaque semaine à quoi poster/où/comment. L'automatisation via SKILL-CRS-021 élimine la création de contenu — le founder ne fait que la curation et la voix. Chaque élément du plan sert le funnel orchestré (DEC-77) en chauffant les 3 audiences en parallèle.
**Impact:** Nouvel artefact `artefacts/strategy/COMMS-001.strategy.md`. Aucun changement code. Cross-référencé dans GTM-001. S'exécute en parallèle du dev Callibrate sans augmenter la charge.
**Date:** 2026-02-24

---

### DEC-2026-02-24-77 — Build-in-public comme stratégie de lancement orchestré + protection copycats

**Context:** Le build-in-public initialement conçu comme contenu de visibilité (DEC-76, E01S05) peut servir un rôle plus stratégique : orchestrer le pré-lancement de TOUS les produits simultanément (Callibrate, .gaai OSS, plugin Cowork, .gaai Cloud). Chaque thread X, chaque blog post tease naturellement les lancements à venir, chauffant l'audience progressivement. Question soulevée sur les copycats : faut-il protéger le framework en restant stealth ?
**Decision:** Le build-in-public devient le **funnel d'acquisition transversal** à toutes les phases du GTM. Même contenu, 3 audiences chauffées en parallèle : (1) tease Callibrate (le produit), (2) tease .gaai (le framework), (3) tease le builder (personal brand). Chaque lancement arrive devant une audience déjà chaude qui a suivi la construction. Sur les copycats : l'obscurité est un risque plus grand. Protections naturelles suffisantes : auteur original (git history), vitesse d'itération, communauté, marque personnelle. Contenu auto-généré par le skill SKILL-CRS-021 (0 effort supplémentaire — sous-produit de la delivery). Le founder review en batch 15 min/semaine.
**Rationale:** Tu ne lances pas un produit à une audience froide. Le build-in-public crée de la traction jour 1 au lieu de jour 90. Le skill d'auto-génération élimine le coût en temps (le contenu est un sous-produit, pas une distraction). Les teasers sont honnêtes et organiques (montrer le travail en cours), pas du marketing forcé. L'audience déduit qu'il y a un produit derrière — plus puissant car authentique.
**Impact:** GTM-001 restructuré — nouvelle section "Build in Public — stratégie de lancement orchestré" avec timeline Phase 1 → Gate 1 → Phase 2 → Gate 2 → Phase 3 → Gate 3. E01S05 mis à jour (AC25 orchestrated teasers, AC26 content auto-generated). Skill SKILL-CRS-021 déjà en place. Aucun effort additionnel requis — le système est auto-alimenté.
**Date:** 2026-02-24

---

### DEC-2026-02-24-76 — Flagship blog post : premier artefact public + career strategy

**Context:** Le founder a zéro visibilité publique dans l'écosystème AI malgré des assets réels (75+ décisions documentées, 35+ stories livrées, framework .gaai fonctionnel, architecture Callibrate complète). Objectifs déclarés : se faire un nom dans l'AI, générer du revenu, ouvrir des opportunités chez les big players (Anthropic en cible naturelle — leur marque est la safety, .gaai est la governance). Contrainte : 30h/semaine disponibles (emploi 30h à côté).
**Decision:** Créer E01S05 — story flagship blog post. Discovery d'abord (valider l'angle, extraire les données réelles, planifier les visuels et la distribution), puis Delivery écrit et publie. Angle principal : expérience réelle + chiffres concrets + Dual-Track expliqué en pratique. Visuels via Google NotebookLM. Distribution : blog perso + dev.to + Show HN + r/ClaudeAI + X/Twitter thread. Langue : anglais (reach international). Timing : quand Gate 1 est atteint ou quasi-atteint.
**Rationale:** Meilleur ROI heure-pour-heure pour la visibilité. 5h d'écriture peuvent générer des milliers de vues. Précède et prépare la publication OSS de .gaai. Sert de portfolio technique et de signal pour les recruteurs AI. La plupart des devs ne savent pas écrire — la capacité d'analyse du founder est un différentiateur.
**Impact:** E01S05 ajouté au backlog (status: refined, priority: high). Dépendance soft sur Gate 1. Prochaine étape : lancer Discovery sur E01S05 pour valider l'angle et le plan de contenu.
**Date:** 2026-02-24

---

### DEC-2026-02-24-75 — Architecture technique .gaai Cloud : 3 couches progressives

**Context:** Question concrète : quelle stack technique et quel runtime pour .gaai Cloud ? Claude Code en background ? Recherche sur l'état de l'art : Claude Agent SDK (TS + Python, c'est le moteur sous Claude Code exposé comme librairie), Cowork Plugins (file-based, cross-compatible Code/Cowork, marketplace), hosted MCP platforms (UCL "Vercel for MCP", Composio, Microsoft Foundry).
**Decision:** Architecture en 3 couches progressives, chaque couche valide la suivante :

- **Couche 1 — Plugin Cowork (MVP, 0 infra).** .gaai est déjà structurellement un plugin Cowork (skills + agents + slash commands = même format fichier). Packager et publier sur le marketplace. Valide si des non-devs adoptent le Dual-Track. Faisable en jours. Limites : locké Anthropic, pas multi-tenant, pas de dashboard web.
- **Couche 2 — Agent SDK Backend (SaaS multi-tenant).** .gaai Core (TS library open-source) = protocole de gouvernance. Agent Runtime = Claude Agent SDK + OpenAI Agents API (tool-agnostic). Hosted MCP (UCL/Composio) pour les connexions outils. Web app Next.js pour dashboard/approvals/observabilité. Storage Supabase. L'Agent SDK donne les capacités de Claude Code sans le CLI — l'utilisateur interagit via web app, pas terminal.
- **Couche 3 — .gaai Protocol (standard ouvert).** .gaai Core publié comme spec. D'autres runtimes l'adoptent. Même dynamique que MCP.

**Pas de Claude Code en background.** Le Claude Agent SDK est le bon runtime — c'est le moteur de Claude Code sans l'interface CLI. Pour les non-devs, on construit une UX web par-dessus.
**Rationale:** Toutes les briques d'infra existent maintenant (Agent SDK, Cowork plugins, hosted MCP, multi-tenant MCP gateways). Ce qui manque = la couche de gouvernance. Le plugin Cowork est le quick win (jours, pas mois) qui valide l'hypothèse marché avant d'investir dans le SaaS. La séquence progressive minimise le risque à chaque étape.
**Impact:** VISION-GAAI-CLOUD.md mis à jour avec architecture technique 3 couches, composants, stack, et séquence technique révisée. Aucun changement au backlog actif.
**Date:** 2026-02-24

---

### DEC-2026-02-24-74 — Vision .gaai Cloud : SaaS universel de gouvernance d'agents AI

**Context:** Convergence de 3 signaux : (1) Claude Cowork existe publiquement depuis janvier 2026 avec support plugins — c'est le runtime agent grand public. (2) Le framework .gaai est tool-agnostic par design — il peut gouverner n'importe quel agent sur n'importe quel provider via MCP. (3) OpenAI a acqui-hiré le créateur d'OpenClaw pour "the next generation of personal agents" — les grands investissent dans les agents structurés. Insight clé : MCP résout "comment l'agent parle aux outils", mais personne ne résout "comment l'agent structure le travail, retient le contexte, et sépare réflexion/exécution" de manière tool-agnostic. Les deux piliers identifiés : sécurité (permissions progressives par outil et par action) et observabilité (flux d'activité lisible par un non-technique, decision trail, memory inspector, audit trail).
**Decision:** Loguer comme vision stratégique long-terme. Artefact dédié créé : `VISION-GAAI-CLOUD.md`. Callibrate reste le véhicule principal — c'est le proof of concept, le revenu runway, et le case study de .gaai Cloud. La séquence ne change pas : Callibrate lancé → OSS .gaai → case study → formation → .gaai Cloud MVP. Ne PAS pivoter. Ne PAS abandonner Callibrate. La fenêtre de tir est "être le premier protocole de gouvernance tool-agnostic pendant que les grands construisent leurs runtimes propriétaires" — Callibrate donne 3-6 mois pour maturer .gaai gratuitement.
**Rationale:** Le produit d'infrastructure (.gaai Cloud) a un cycle de vente long et nécessite un proof of concept vivant. Callibrate fournit les deux : revenu immédiat + démonstration du framework en production. Sauter directement à .gaai Cloud = 6-12 mois sans revenu, pas de proof of concept, course contre Anthropic/OpenAI sans munitions. L'adaptation par métier se fait via des "Playbooks" (skills + MCPs + rules + memory template) — un runtime unique, marketplace de playbooks.
**Impact:** Nouvel artefact `artefacts/strategy/VISION-GAAI-CLOUD.md`. Aucun changement au backlog actif. Aucun changement à la priorité Callibrate. Vision à revisiter après Gate 3 PASS.
**Date:** 2026-02-24

---

### DEC-2026-02-24-73 — Formation payante .gaai : prématuré, revisiter après Gate 3

**Context:** Idée de créer une formation payante à l'utilisation du framework .gaai, basée sur l'expérience terrain avec Callibrate. Persona cible : devs solo / petites équipes utilisant Claude Code sans gouvernance structurée.
**Decision:** Ne PAS créer de formation maintenant. Revisiter après Gate 3 PASS. La formation est le 3e étage de la fusée — la séquence logique est : (1) Gate 2 → open-source .gaai gratuit (acquisition), (2) Gate 3 → case study Callibrate publié (crédibilité avec chiffres réels), (3) adoption OSS visible → formation payante (monétisation du framework).
**Rationale:** 4 raisons de reporter : (1) Callibrate n'est pas lancé — la crédibilité d'une formation vient du résultat, pas de la théorie. (2) Distraction fatale — créer une formation = un second produit avec son propre GTM, sa propre audience, son propre support, en pleine Phase 1. (3) Le framework bouge encore (DEC-70, DEC-71) — former sur un framework instable = dette de support. (4) Le contenu gratuit (README + blog + vidéo) fait le même travail d'acquisition sans le coût de production. La formation a du potentiel *quand* : des chiffres réels existent (X stories livrées, Y décisions tracées), l'OSS a de l'adoption, et le case study est publié. Bonus : les devs formés à .gaai sont exactement le profil d'experts potentiels pour Callibrate (funnel croisé).
**Impact:** GTM-001 mis à jour — séquence de monétisation .gaai ajoutée après la section OSS. Aucune action immédiate.
**Date:** 2026-02-24

---

### DEC-2026-02-24-72 — Open-sourcing .gaai: defer to post-launch, use as marketing lever

**Context:** Question stratégique : open-sourcer le framework .gaai (gouvernance agents AI, backlog, skills, mémoire) ou le garder comme avantage concurrentiel. Analyse de la valeur défensive vs offensive du framework.
**Decision:** Ne PAS open-sourcer maintenant. Open-sourcer après le lancement quand le framework est stable et validé par l'usage réel. Séquence : (1) Maintenant → itérer librement, lancer la plateforme. (2) Post-lancement → publier .gaai quand stable. (3) Utiliser comme levier marketing → blog post, Show HN, r/ClaudeAI pour acquisition organique.
**Rationale:** .gaai n'est PAS un avantage concurrentiel : c'est un framework de process (pas un produit), la valeur est dans l'exécution (pas le playbook), et c'est reproductible par quelqu'un de motivé en quelques jours. Le vrai moat de Callibrate est le réseau d'experts et la marketplace. En revanche, .gaai a une forte valeur comme outil de visibilité : crédibilité technique, acquisition organique (devs qui adoptent .gaai découvrent Callibrate), positionnement thought-leader. Arguments pour attendre : maintenir un OSS demande du temps (distraction en phase lancement), le framework n'est pas encore assez mature (risque de figer des choix de design prématurément).
**Impact:** GTM-001 mis à jour — nouvelle section "Post-lancement : .gaai open-source comme levier d'acquisition". Pas d'action immédiate sur le code. À revisiter après Gate 2 PASS.
**Date:** 2026-02-24

---

### DEC-2026-02-24-71 — Mandatory PR merge to staging at end of delivery cycle

**Context:** 19 PRs accumulated unmerged on staging over multiple delivery cycles. When batch-merged, cascading conflicts required 3 full rounds of resolution across all branches. Root causes: (1) delivery agent created PRs but never merged them, (2) story branches were stacked on previous stories instead of branching from staging, (3) hotspot files (`index.ts`, `wrangler.toml`, `env.ts`) modified by nearly every story guaranteed conflicts. Total remediation: ~60 conflict files resolved, 3 test fixes, 2+ hours of agent work.
**Decision:** PR merge to staging becomes a mandatory final step of the delivery cycle. The delivery agent must: create PR → pass QA → merge PR → confirm CI. PRs must not be left open. Story branches must be created from `staging`, never from other story branches. A dedicated "merge agent" is NOT needed — this is a process fix within the existing delivery track.
**Rationale:** The problem was not "who merges" but "when." Immediate merge after delivery keeps the conflict surface at exactly 1 PR (the current story) against a fresh staging. Accumulation is the enemy. A 4th sub-agent adds coordination overhead without addressing the root cause (branching strategy + merge timing).
**Impact:** conventions.md updated (5 new rules). Delivery agent flow should be updated to include merge-to-staging as final step. No new agent needed.
**Date:** 2026-02-24

---

### DEC-2026-02-24-70 — Artefact directory structure: one dedicated subdirectory per type

**Context:** Delivery artefacts (impl-report, qa-report, memory-delta) were scattered across wrong locations: root of `artefacts/`, inside `plans/`, and in a hybrid `reports/` catch-all folder. Root cause: all sub-agents (implementation, QA, micro-delivery), skills (coordinate-handoffs, memory-alignment-check), and README.artefacts.md hardcoded `reports/` as the single output directory. The filesystem had evolved to use dedicated subdirectories (`impl-reports/`, `qa-reports/`, `memory-deltas/`) but the agent instructions were never updated. The delivery.agent.md orchestration flow used abbreviated paths (no directory prefix), providing zero guidance.
**Decision:** Canonical artefact routing — one directory per artefact type, no exceptions:

| Artefact type | Directory |
|---|---|
| `{id}.execution-plan.md` | `plans/` |
| `{id}.plan-blocked.md` | `plans/` |
| `{id}.approach-evaluation.md` | `evaluations/` |
| `{id}.impl-report.md` | `impl-reports/` |
| `{id}.specialist-{domain}.md` | `impl-reports/` |
| `{id}.qa-report.md` | `qa-reports/` |
| `{id}.memory-delta.md` | `memory-deltas/` |
| `{id}.micro-delivery-report.md` | `delivery/` |

New rule R7 in `artefacts.rules.md`: no artefact may be written to the root of `contexts/artefacts/`. The hybrid `reports/` directory has been deleted — its contents redistributed to the dedicated subdirectories.
**Rationale:** Separation of concerns eliminates ambiguity. Each type has a single canonical location. Agents no longer have to guess. The routing table in `artefacts.rules.md` is the single source of truth.
**Impact:** 8 files updated (4 sub-agents, 2 skills, delivery.agent.md, README.artefacts.md, artefacts.rules.md). 80+ existing artefacts moved to correct locations. `reports/` deleted. All future deliveries will write to the correct directories.
**Date:** 2026-02-24

---

### DEC-2026-02-22-69 — KV eliminated from expert pool read path; E06S19 merged into E06S23

**Context:** The expert pool cache architecture planned 3 layers: Cache API (L1) → KV (L2) → Hyperdrive (L3). Analysis revealed KV adds no value over D1: KV has a 25 Mo per-value limit (~5,000 experts max), no SQL filtering, ~50ms latency. D1 provides SQL WHERE filtering, sub-5ms edge reads, 10 Go limit, and $0.001/M rows. R2 was also evaluated and rejected — `list()` does not support metadata filtering, making it unsuitable for queryable structured data.
**Decision:** KV removed from expert pool read path. E06S19 (Cache API L1 for KV) cancelled and absorbed into E06S23. New read chain: Cache API (L1, 60s, per-datacenter) → D1 (L2, SQL queryable, edge) → Hyperdrive (L3, source of truth). `EXPERT_POOL` KV namespace retained only if used by other features.
**Rationale:** Simpler architecture (2 cache layers instead of 3), no 25 Mo limit, SQL filtering enables satellite-specific pools without client-side filtering, lower cost ($0.001/M vs $0.50/M). One fewer story to implement.
**Impact:** E06S19 cancelled. E06S23 updated (absorbs Cache API L1 scope, dependency on E06S19 removed). Backlog, epic E06, and memory index updated.
**Date:** 2026-02-22

---

### DEC-2026-02-22-68 — Billing Model — LS Usage-Based Subscription + Internal Credit Accounting

**Context:** Le billing per-lead checkout (un checkout LS par lead) crée de la friction (expert doit cliquer à chaque lead) et des coûts de refund (LS garde ses fees sur les remboursements). Le projet a besoin d'un modèle qui supporte : (1) carte on file avec auto-charge, (2) flag/restore instantané sans frais LS, (3) LS comme MoR pour la gestion fiscale, (4) anti-gaming transparent. Analyse des modèles industrie : Thumbtack et Bark utilisent des crédits prépayés ; Angi (post-pay auto-charge) est le plus controversé (amende FTC $7.2M). LS supporte les usage-based subscriptions ($0/mois, carte on file, charge en fin de cycle basée sur l'usage reporté).
**Decision:** Modèle hybride — LS usage-based subscription pour le billing + credit accounting interne pour le flag/restore temps réel.

**Flux complet :**
1. Expert active son pipeline → souscription LS $0/mois "Lead Pipeline" (entre sa carte une fois)
2. Lead créé → crédits déduits en interne instantanément, prix et breakdown affichés dans le dashboard
3. Expert peut flag "non qualifié" dans les 7 jours → crédits restaurés en interne (zéro transaction LS)
4. Silence ou confirmation explicite après 7 jours → lead confirmé → usage reporté à LS
5. Fin de cycle billing LS → LS charge automatiquement le total usage confirmé → carte on file
6. Carte échoue → LS dunning automatique (retry) → si échec final : leads pausés

**Usage reporting différé de 7 jours :** L'usage n'est reporté à LS qu'après expiration du flag window. Leads flaggés ne sont jamais reportés → jamais chargés → pas de refund nécessaire. Élimine le misalignment flag/billing cycle.

**Crédit d'accueil :** 100€ offerts à l'activation (internal credit, pas de charge LS). Permet à l'expert de tester 1-2 leads sans engagement financier.

**Expert controls :**
- `max_lead_price` — plafond par lead (deal-breaker au matching, DEC-67)
- `spending_limit` — plafond mensuel de dépense. Quand atteint → leads pausés → notification.
- Dashboard affiche : solde crédits temps réel, progression spending limit, nombre de leads manqués (cause : solde insuffisant OU max_lead_price dépassé)

**Anti-gaming — règles transparentes dès l'onboarding (mise à jour DEC-30) :**
- `qualification_rate = leads_confirmed / total_leads` reste composant du composite_score
- Règles communiquées explicitement à l'onboarding : "Les experts qui confirment leurs leads reçoivent de meilleurs leads. Un taux de flag élevé réduit naturellement ta visibilité dans le matching."
- Framing positif uniquement (jamais "si tu triches → sanctions"). Conforme aux principes de communication expert (context.md).
- Dashboard affiche la qualification_rate de l'expert + explication de son impact

**Balance check au matching :** `expert.credit_balance >= lead_price` est un prérequis pour le match. Si insuffisant → expert exclu du match pour ce lead + notification "Ton solde est insuffisant pour recevoir ce lead. Recharge pour réactiver."

**Évolution post-M3 :** Si l'auto-charge instantané (vs fin de cycle) devient critique, migration payment layer vers Stripe (PaymentIntents + saved PaymentMethod). LS reste MoR tant que le volume ne justifie pas Stripe Tax + service de filing fiscal.

**Rationale:** Le modèle usage-based LS préserve le MoR (taxes gérées par LS) tout en offrant carte on file + auto-billing. Le credit accounting interne permet le flag/restore instantané sans LS fees. Le report d'usage différé de 7 jours résout le misalignment flag/cycle. L'anti-gaming communiqué en positif est conforme aux valeurs Transparence et Agentivité.
**Impact:** Mise à jour DEC-30 (flux billing révisé). Nouveau produit LS : "Lead Pipeline" usage-based subscription. Nouvelles structures DB : `experts.credit_balance` INTEGER (centimes), `credit_transactions` table. CF Workflow ou Cron Trigger pour report usage LS après 7j. E05S01/S02 : révisés pour modèle crédits. E06S06 lead-billing consumer : révisé pour debit/restore pattern.
**Date:** 2026-02-22

---

### DEC-2026-02-22-67 — Dynamic Lead Pricing — Budget Tier × Qualification Modifier

**Context:** Le prix du lead était fixé à "100–200€" (context.md, PRD-001) sans grille ni formule. Un prix unique crée une friction : un prospect à 3 000€ de budget et un prospect à 100 000€ ne représentent pas la même valeur pour l'expert. Le pricing doit refléter la valeur potentielle du lead pour l'expert tout en restant transparent et prédictible (calcul ROI).

Benchmarks secteur : appointment setting B2B cold 200–500€/meeting, lead qualifié agence B2B 150–400€/lead, Upwork 20% du premier projet, LinkedIn Sales Navigator ~120€/mois (pas par lead). Un lead Callibrate est chaud, pré-qualifié, auto-initié → vaut structurellement plus qu'un lead froid.

**Decision:** Tarification dynamique basée sur 2 facteurs publiés :

**Facteur 1 — Budget prospect déclaré (primaire).** `budget_range.max` détermine le tier :

| Budget prospect (max déclaré) | Prix base | Ratio coût/valeur attendue (conv. 30%) |
|---|---|---|
| Non déclaré ou < 5 000€ | 49€ | ~3% |
| 5 000 – 20 000€ | 89€ | ~1.5% |
| 20 000 – 50 000€ | 149€ | ~1% |
| 50 000€+ | 229€ | ~0.5% |

**Facteur 2 — Niveau de qualification (modificateur) :**
- Standard (confidence 0.6–0.8) : prix base × 1.0
- Premium (confidence > 0.8 sur tous les champs, budget explicite, timeline précise) : prix base × 1.15

**Grille résultante publiée :**

| Budget prospect | Standard | Premium (+15%) |
|---|---|---|
| Non déclaré / < 5k€ | 49€ | 56€ |
| 5k – 20k€ | 89€ | 102€ |
| 20k – 50k€ | 149€ | 171€ |
| 50k€+ | 229€ | 263€ |

**Match score = filtre + ranking, PAS facteur de prix.** Le même lead coûte le même prix à tous les experts qui le reçoivent. Raisons : (1) le match score varie par expert pour le même prospect → prix différents pour le même lead = confus et injuste, (2) match élevé = prix plus élevé → incentive perverse (expert pénalisé pour être un bon match), (3) aucune plateforme B2B leader n'utilise le match score comme variable de prix.

**Expert `max_lead_price` :** L'expert peut fixer un plafond par lead via `preferences.max_lead_price`. Agit comme deal-breaker au matching : si `final_price > max_lead_price` → expert exclu du match pour ce lead. Pas de limite par défaut (tous les tiers éligibles). Dashboard affiche : nombre de leads manqués à cause du max + estimation du % du pool accessible avec le max actuel. Information factuelle au moment du réglage, jamais manipulatoire.

**Budget non déclaré :** Tier par défaut (49€). Le prospect ne sait pas que son budget influence le prix du lead — pas d'incentive à sous-déclarer. Le prospect déclare son budget pour le matching (être connecté au bon expert), pas pour le pricing. Sous-déclarer dégrade la qualité de son propre match (guard-rail naturel). La déclaration de budget peut être configurée comme obligatoire ou optionnelle par satellite/vertical via `satellite_configs.quiz_schema`.

**Rationale:** Le budget prospect est le seul facteur directement corrélé à la valeur du deal, transparent, prédictible, et conforme aux standards industrie (Thumbtack : prix par valeur du job, Bark : crédits variables par valeur estimée). La qualification en 2 niveaux ajoute une nuance de valeur sans complexifier le calcul ROI. Tous les ratios coût/valeur sont très favorables à l'expert (<3%) → le pricing est un no-brainer à tous les tiers.
**Impact:** Remplacement du range "100–200€" dans context.md et PRD-001. Formule de calcul implémentée dans `processLeadBilling`. `leads.amount` renseigné à la création du lead. Grille publiée dans l'onboarding expert et le dashboard.
**Date:** 2026-02-22

---

### DEC-2026-02-22-66 — Hyperdrive + postgres.js replaces Supabase JS for DB queries

**Context:** All 48 database queries use `@supabase/supabase-js` (PostgREST/HTTP). Each Worker invocation opens a new HTTP connection — no pooling, no caching. The score-computation consumer (7 sequential queries) pays ~210ms in HTTP overhead. Supabase Micro plan has 60 connection limit.
**Decision:** Hyperdrive (free on Workers Paid) for TCP connection pooling + query caching. `postgres` v3.4.4+ (tagged template SQL, zero sub-dependencies, serverless-native) replaces Supabase JS for all DB queries. No ORM (Drizzle) — SQL direct with existing types via `sql<T[]>`. Supabase JS retained ONLY for `supabase.auth.getUser()` in auth middleware. Connection string: Supabase Direct (port 5432, bypasses Supavisor). Config: `prepare: true` for Hyperdrive query cache compatibility.
**Rationale:** 6× latency improvement on multi-query paths. Connection pooling protects against Supabase connection exhaustion. postgres.js tagged templates are injection-safe, zero-config, type-safe with existing interfaces. No RLS dependency (service key bypass). Migration is mechanical (48 queries, 11 files).
**Impact:** E06S18 (foundation story). All subsequent stories (E06S19–E06S26) build on this.
**Date:** 2026-02-22

---

### DEC-2026-02-22-65 — Analytics Engine for matching observability

**Context:** No observability into matching pipeline performance (latency, cache hits, scoring quality).
**Decision:** Analytics Engine dataset `matching-metrics`. Fire-and-forget `writeDataPoint()` (not awaited, try/catch). Tracks: latency_ms, cache_layer, pool_size, vectorize_candidates, top_score, mean_score. No-op if binding missing.
**Rationale:** Free (100K events/day on Workers Paid), zero-latency (fire-and-forget), queryable via CF Dashboard/GraphQL.
**Impact:** E06S26. Binding: `MATCHING_ANALYTICS: AnalyticsEngineDataset`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-64 — CF Rate Limiting binding replaces manual KV rate limiter

**Context:** Current rate limiting uses manual KV-based implementation (10 req/60s per IP). Wastes KV reads/writes on every request.
**Decision:** CF Rate Limiting binding (free on Workers Paid) replaces `src/lib/rateLimit.ts`. 30 req/min per IP on public endpoints. Native binding API — zero storage overhead.
**Rationale:** Native, free, no KV waste, cleaner code. `RATE_LIMITING` KV namespace removable after migration.
**Impact:** E06S20. Removes KV dependency for rate limiting.
**Date:** 2026-02-22

---

### DEC-2026-02-22-63 — Turnstile on public prospect endpoints

**Context:** `POST /api/prospects/submit` is unauthenticated and publicly accessible. No bot protection.
**Decision:** Turnstile invisible CAPTCHA on `POST /api/prospects/submit`. Server-side verification via `challenges.cloudflare.com/turnstile/v0/siteverify`. Test mode in staging/dev (test keys always pass). Missing/invalid token → 422.
**Rationale:** Free, invisible, zero friction for real users. Protects the most critical public endpoint.
**Impact:** E06S20. Requires `TURNSTILE_SECRET_KEY` secret + site key from CF Dashboard.
**Date:** 2026-02-22

---

### DEC-2026-02-22-62 — Vectorize + Workers AI for semantic matching

**Context:** Current matching relies on 30 manual SKILL_ALIASES and 8 INDUSTRY_PROXIMITY pairs. Fails on long tail: "data science" ≠ "machine learning", "medtech" ≠ "biotech".
**Decision:** `@cf/baai/bge-base-en-v1.5` (768 dims) for embeddings. Vectorize cosine similarity for semantic pre-filtering (top-K candidates). `scoreMatch()` deterministic for final ranking. Blended scoring: 0.7 × exact + 0.3 × vector. Graceful fallback if Vectorize unavailable → deterministic-only path.
**Rationale:** Semantic matching captures relationships that alias maps cannot. Vectorize pre-filtering reduces scoring from O(N) to O(K). Workers AI free tier (10K neurons/day) sufficient for registration-time embeddings.
**Impact:** E06S21 (infrastructure) + E06S22 (scoring integration). Bindings: `AI: Ai`, `EXPERT_INDEX: VectorizeIndex`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-61 — D1 as edge serving layer (hybrid Supabase + D1)

**Context:** Expert pool reads are the hottest read path. KV is fast but not queryable. Need edge SQL for filtered reads.
**Decision:** Supabase = source of truth. D1 = edge read cache (denormalized expert_pool table). Cron sync every 5 min via Hyperdrive. Fallback chain: Cache API → D1 → Hyperdrive. D1 is read-only in this architecture.
**Rationale:** D1 provides sub-5ms edge SQL reads. Combined with Cache API L1 (~0ms), origin DB hit rate drops to near-zero for reads. Cron sync keeps D1 fresh within 5 minutes.
**Impact:** E06S23 (D1 + sync) + E06S19 (Cache API L1). Binding: `EXPERT_DB: D1Database`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-60 (REVISED) — Scalable Matching Engine: implement now

**Supersedes:** DEC-2026-02-22-60 (documentation only)
**Context:** Matching engine works but has 5 structural weaknesses: B1 (O(N) match inserts), B2 (KV bypass), B3 (30 manual skill aliases), B4 (8 manual industry pairs), B5 (no scale infrastructure). Analysis confirms: matching IS the core value, Hyperdrive is free, migration is mechanical, risk of connection exhaustion is real.
**Decision:** Implement in 4 phases. Phase 1: Hyperdrive + postgres.js + Smart Placement + bug fixes (E06S18). Phase 2 (parallel): Cache API L1 (E06S19) + Rate Limiting + Turnstile (E06S20) + Vectorize infra (E06S21) + Analytics (E06S26). Phase 3: Semantic scoring (E06S22) + D1 edge (E06S23). Phase 4: Service Bindings (E06S24) + Durable Objects (E06S25). Total additional CF cost: ~$7-8/month.
**Rationale:** The matching engine is the platform's core value proposition. Broken matches = broken trust = lost users. Hyperdrive + postgres.js foundation is $0 and makes every subsequent story faster. Connection pooling is a safety net against Supabase Micro's 60-connection limit.
**Impact:** 9 new stories (E06S18–E06S26) added to backlog. Critical path: E06S18 → E06S21 → E06S22 → E06S24.
**Date:** 2026-02-22

---

### DEC-2026-02-22-60 — Scoring/Matching Scalability Path (documentation only)

**Context:** E06S09 delivered with in-memory scoring for MVP scale (10-50 experts). Need to document the scaling path before it becomes urgent, without implementing anything now.
**Decision:** Scaling path documented in 4 phases:

| Phase | Seuil | Mécanisme | Impact |
|-------|-------|-----------|--------|
| Phase 1 (MVP) | 10-50 experts | In-memory scoring, KV cache pool, pure function | Actuel — sous 100ms |
| Phase 2 | 100-500 experts | SQL pre-filtering via GIN indexes (`profile->'industries' ?| ARRAY[...]`) avant chargement mémoire. KV pool splitté par satellite_id | Réduit le pool scoré de 60-80% |
| Phase 3 | 500-2000 | Durable Object avec expert pool warm en mémoire. Cursor-based KV pagination | Latence stable |
| Phase 4 | 2000+ | pgvector embeddings pour matching sémantique skills. ML re-ranking | Qualité matching + scale |

**Pas d'implémentation maintenant.** Le seuil Phase 2 (100 experts) est un bon signal pour déclencher la prochaine optimisation. Story dédiée à créer quand ce seuil approche.
**Rationale:** Documenter le chemin avant qu'il soit urgent permet de prendre des décisions architecturales informées (ex: GIN indexes déjà en place via E06S02). Chaque phase est un palier autonome — pas de big bang.
**Impact:** Documentation only. No code changes. Informs future story creation when thresholds approach.
**Date:** 2026-02-22

---

### DEC-2026-02-23-02 — PR-based delivery + preview deployments + model selection

**Context:** Le delivery agent mergeait directement sur staging via `git merge --squash`. Aucune revue de code avant staging. L'humain devait tout vérifier en un seul bloc lors du PR staging→production. Tous les outils majeurs d'agentic coding (Copilot, Codex, Devin) imposent un flux PR — l'IA ne merge jamais directement.
**Decision:** 3 changements architecturaux :

1. **PR-based delivery :** Le delivery agent crée une PR `story/{id}` → staging via `gh pr create`. Il ne merge jamais. L'humain review et merge sur GitHub. Le backlog passe à `done` = "PR créée, travail agent terminé".

2. **Preview deployments :** GitHub Action `preview-deploy.yml` sur chaque push `story/*`. Pipeline : tsc + vitest + `wrangler versions upload --env staging --preview-alias <slug>`. Preview URL commentée sur la PR. Format : `https://story-e06s15.callibrate-core-staging.frederic-geens-consulting.workers.dev`. La preview partage les bindings staging (KV, Queues, Supabase) — aperçu code, pas environnement isolé.

3. **Model selection :** `GAAI_CLAUDE_MODEL` env var (default: `sonnet`). Le daemon passe `--model $CLAUDE_MODEL` à Claude Code. Sonnet pour les deliveries (coût-efficace), Opus réservé à Discovery/décisions complexes.

**Rationale:** Industry standard unanime — l'IA crée des PRs, pas des merges. Deux niveaux de preview (story isolée + staging complet) permettent une validation progressive. Sonnet réduit le coût des sessions de delivery (~5× moins cher qu'Opus) sans impact qualité sur l'implémentation.
**Impact:** `delivery-loop.workflow.md` Step 8 réécrit (PR au lieu de merge). `delivery.agent.md` git workflow mis à jour. `delivery-daemon.sh` : `--model` flag ajouté. `deploy-staging.yml` : trigger corrigé (staging au lieu de production). `wrangler.toml` : `preview_urls = true`. Nouveau workflow : `.github/workflows/preview-deploy.yml`.
**Date:** 2026-02-23

---

### DEC-2026-02-23-01 — OpenAI integration pattern: function calling for structured extraction (E06S12 impl)

**Context:** E06S12 completed the Anthropic→OpenAI migration for `POST /api/extract`. DEC-48 (archived) decided the provider swap. This entry captures the implementation pattern established.
**Decision:** OpenAI Chat Completions with `tools` + `tool_choice: { type: "function", function: { name: "..." } }` is the canonical pattern for structured AI extraction in this codebase. Response parsed from `choices[0].message.tool_calls[0].function.arguments` (JSON string). Direct `fetch` to `https://api.openai.com/v1/chat/completions` — no CF AI Gateway for OpenAI calls at this stage.
**Error surface:** `'OpenAI API error'` (non-200), `'Invalid response from OpenAI API'` (JSON parse fail), `'AI service unreachable'` (network failure).
**Rationale:** Forced function calling guarantees structured output. The named `tool_choice` form ensures `tool_calls` is always populated. Direct fetch avoids CF AI Gateway complexity for a single endpoint.
**Impact:** Pattern to follow for any future AI extraction or structured-output endpoint using OpenAI. CF AI Gateway re-addition is a separate story if observability is needed.
**Date:** 2026-02-23

---

<!-- Add decisions above this line, newest first -->
