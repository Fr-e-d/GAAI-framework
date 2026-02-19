---
type: memory
category: decisions
id: DECISIONS-LOG
tags:
  - decisions
  - governance
created_at: 2026-02-19
updated_at: 2026-02-19
---

# Decision Log

> Append-only. Never delete or overwrite decisions.
> Only the Discovery Agent may add entries (or Bootstrap Agent during initialization).
> Format: one entry per decision, newest at top.

---

### DEC-2026-02-19-23 — Competitive Moat : Data Flywheel + Bi-Directional Value

**Context:** Observation terrain (r/n8n_ai_agents) — un expert sophistiqué a construit sa propre qualification system (Typeform + n8n ROI calculator). Il résout son propre problème, mais les prospects qui ne le matchent pas disparaissent sans valeur. Ça a cristallisé le moat réel de Callibrate.
**Decision:** Le moat de Callibrate repose sur 3 couches : (1) Data flywheel — chaque transaction améliore les weights du matching engine, compounding impossible à répliquer pour un acteur solo. (2) Valeur au prospect rejeté — un prospect qui ne matche pas Expert A est matché avec Expert B ou C ; les "rejets" d'un expert deviennent des revenus pour un autre. Aucun système mono-expert ne peut faire ça. (3) Bi-directionnel comme barrière technique — Upwork/Malt/LinkedIn sont unidirectionnels ou textuels ; Callibrate évalue simultanément expert.preferences vs prospect.requirements dans les deux sens.
**Rationale :** La vraie promesse n'est pas "trouve un expert" — c'est "ne rate pas le bon match parce que tu as atterri sur le mauvais expert en premier." Pour l'expert : reçoit des prospects pré-filtrés sans construire son propre système. Pour le prospect : ne disparaît jamais après un refus — le système trouve qui correspond vraiment.
**Impact :** Reformule la promesse marketing (E01S02/E01S03). Renforce le positionnement "Matching OS" vs annuaire. Le composite score (data accumulée de vrais calls) devient un actif défensif qu'aucun concurrent solo ne peut répliquer. Capturé depuis signal terrain — non hypothétique.
**Date:** 2026-02-19

---

### DEC-2026-02-19-22 — 3-Layer Architecture Précisée (Refinement de DEC-18)

**Context:** DEC-18 définit une architecture domain-agnostic en 3 couches mais sans préciser la structure interne de la couche Interface ni la règle de consommation.
**Decision:** Architecture 3 couches stricte, chaque couche consomme uniquement la couche inférieure. Layer 1 = Data (Supabase). Layer 2 = Services/API (CF Workers, Queues, n8n — domain-agnostic). Layer 3 = Interfaces, divisée en deux tracks : Track 3.1 (Expert dedicated UIs — callibrate.io + toute future UI expert) / Track 3.2 (Prospect dedicated UIs — callibrate.ai + N satellite sites). Chaque track peut accueillir autant de platforms que nécessaire.
**Rationale:** La distinction Track 3.1 / Track 3.2 permet d'ajouter de nouvelles interfaces (ex: app mobile expert, nouveau satellite niche) sans toucher aux couches inférieures. La règle "chaque couche consomme la couche inférieure" interdit les raccourcis (Layer 3 ne touche jamais Layer 1 directement).
**Impact:** Gouvernance architecture : toute nouvelle UI doit s'inscrire dans 3.1 ou 3.2 et ne consommer que la Layer 2 API. Layer 2 est domain-agnostic par principe — pas de logique UI dans les Workers. Remplace la définition de DEC-18.
**Date:** 2026-02-19

---

### DEC-2026-02-19-21 — Expert Lead Evaluation + Conversion Declaration

**Context:** Matching engine quality must improve over time. Experts have the ground-truth data on whether a lead converted.
**Decision:** Experts evaluate their leads J+48 after the call (score 1–10 + notes) and can declare conversion (project started/closed). Both actions are optional but incentivized via trust score contribution.
**Rationale:** Lead quality scoring feeds the engine feedback loop — poor-quality leads (wrong budget, no decision-maker) signal calibration needs. Conversion data is the ultimate signal of expert-prospect fit. No commission required — expert voluntarily shares outcome.
**Impact:** `lead_evaluations` table. E06S09 uses evaluations to recalibrate matching accuracy. Experts contributing data build their composite_score reputation.
**Date:** 2026-02-19

---

### DEC-2026-02-19-20 — Tri-Directional Feedback Loop

**Context:** The matching engine must improve autonomously over time without manual calibration. Single-direction feedback creates bias.
**Decision:** Three feedback streams feed the engine: (1) Prospect rates call experience J+7 (1–5), (2) Prospect rates project satisfaction J+45 (1–10), (3) Expert rates lead quality + declares conversion J+48. All three signals update `experts.composite_score` and inform matching weight recalibration.
**Rationale:** Balances: prospect satisfaction (call quality), expert satisfaction (lead quality), and outcome data (conversion). Together they give a complete picture of match quality. n8n orchestrates time-based survey triggers.
**Impact:** Three survey tables: `call_experience_surveys`, `project_satisfaction_surveys`, `lead_evaluations`. E06S09 score computation worker aggregates signals into composite_score.
**Date:** 2026-02-19

---

### DEC-2026-02-19-19 — Composite Score System (Trust + Engagement + Outcome)

**Context:** Match ranking needs a quality signal beyond criteria overlap — to surface experts who deliver great experiences, not just matching profiles.
**Decision:** `composite_score = call_experience_avg × 0.35 + trust_score × 0.20 + client_satisfaction_avg × 0.20 + hire_rate × 0.10 + recency_score × 0.15`. Used as tiebreaker in match ranking. Starts at 0 — no score inflation before real data.
**Rationale:** Composite weighting prioritizes the call experience (0.35) — the unit of value delivery — while incorporating trust verification (0.20), client satisfaction (0.20), conversion outcome (0.10), and freshness (0.15). All components measurable from day 1.
**Impact:** `experts.composite_score` + `experts.score_updated_at` fields. E06S09 computes on each feedback event. E06S05 uses as tiebreaker. Displayed to prospects as anonymized quality tier.
**Date:** 2026-02-19

---

### DEC-2026-02-19-18 — Domain-Agnostic 3-Layer Architecture

**Context:** MVP focuses on AI experts, but the matching engine and data model should not be hardcoded to AI-specific criteria.
**Decision:** The platform is domain-agnostic at Layer 1 (data + engine). JSONB criteria fields, `satellite_configs.quiz_schema`, and `matching_weights` are all configurable without code changes. New verticals (legal, design, finance) can be added via satellite config, not code.
**Rationale:** Avoids costly refactoring post-MVP if vertical expansion validates. The JSONB + satellite_configs design makes domain-agnosticism essentially free. AI expert scope is an MVP constraint, not an architectural one.
**Impact:** No AI-specific table columns. All domain context lives in JSONB + satellite_configs. Expansion = add satellite config + create satellite site.
**Date:** 2026-02-19

---

### DEC-2026-02-19-17 — AI Freetext Extraction (Project Description → Structured JSONB)

**Context:** Static quiz forms are friction-heavy and miss nuanced project context. Prospects understand their problem but not the technical vocabulary to fill in structured fields.
**Decision:** Prospects describe their project in natural language (freetext). Claude (claude-haiku-4-5) extracts structured `ProspectRequirements` JSONB. Low-confidence fields (< 0.7) trigger 2–3 targeted confirmation questions. High-confidence fields skip confirmation entirely.
**Rationale:** Freetext-first reduces funnel friction dramatically. AI extraction is more accurate for nuanced needs than forced-choice options. Targeted confirmation only where needed — not a full form re-fill.
**Impact:** E06S08: AI extraction service (`POST /api/extract`). Satellite funnel: freetext field + optional confirmation step. Extraction quality tracked in `engine_feedback_log`.
**Date:** 2026-02-19

---

### DEC-2026-02-19-16 — Dual-Mode Platform: Directory + Matching Engine

**Context:** Pure matching engine is a "power feature" requiring full context to use. An expert directory provides SEO value, discovery, and trust-building for prospects not yet ready to fill a form.
**Decision:** Callibrate operates in two modes: (1) Directory mode — browse profiles, trust scores, SEO-friendly URLs. (2) Engine mode — freetext description + AI extraction → ranked match results. Both modes coexist on callibrate.ai and satellite sites.
**Rationale:** Directory = top-of-funnel SEO/GEO traffic. Engine = conversion-optimized flow. Tagline: "Browse like a directory. Match like magic." The directory builds the audience the engine converts.
**Impact:** callibrate.ai has two entry points: `/experts` (directory) + `/match` (engine funnel). Expert profiles are public and indexable. Directory uses `experts.composite_score` for ranking.
**Date:** 2026-02-19

---

### DEC-2026-02-19-15 — Progressive Email Gate (Email at Booking, Not Before Reveal)

**Context:** Gating anonymized match results behind an email form creates unnecessary friction and kills conversion before the prospect has experienced value.
**Decision:** No email gate before revealing anonymized match results. Email is captured only at the Cal.com booking step (Cal.com captures email/name natively). No pre-reveal email form.
**Rationale:** The match reveal is the key "aha moment" — if blocked behind an email gate, prospects may abandon before experiencing value. Cal.com booking captures email with higher intent. Reduces friction by one full step.
**Impact:** E06S07: `GET /api/prospects/:id/matches` returns anonymized top-3 without email. Email captured at booking via Cal.com webhook → `prospects.email` updated on booking.
**Date:** 2026-02-19

---

### DEC-2026-02-19-14 — Pay-Per-Call Only (No Subscription)

**Context:** Monthly subscription plans (900€/5 leads, 1500€/10 leads) were initially considered. They create a committed monthly burden with uncertain ROI at MVP stage.
**Decision:** Revenue model is pure pay-per-call. Expert pays 100–200€ per booked call, only when a prospect books. No monthly subscription, no upfront commitment.
**Rationale:** Lower adoption barrier for early experts — no sunk cost before seeing lead quality. Aligns platform incentives with expert success. Easier to explain and justify. Subscriptions can be introduced post-M3 once lead quality is proven and experts demand volume.
**Impact:** E05 rewritten for pay-per-call only. Subscription bundles removed. Lemon Squeezy configured for one-time checkout per call, not recurring subscription.
**Date:** 2026-02-19

---

### DEC-2026-02-19-13 — JSONB + GIN Flexible Data Model for Matching Engine

**Context:** Bi-directional matching requires flexible criteria that will evolve based on M0/M1 validation. Hardcoding criteria fields creates costly migrations when criteria change.
**Decision:** Use PostgreSQL JSONB columns with GIN indexes for all matching criteria (expert `profile`, expert `preferences`, prospect `requirements`). Core stable fields remain typed columns.
**Rationale:** JSONB + GIN is the industry standard for MVP-stage flexible matching (used by Airbnb, Notion, Linear). Adds criteria without migrations. Queryable natively via PostgreSQL operators. Migratable to normalized criteria table post-validation.
**Impact:** Core tables: `experts`, `prospects`, `matches`, `bookings`, `leads`, `satellite_configs`. Matching engine reads JSONB, scores are stored in `score_breakdown JSONB`. `satellite_configs.quiz_schema` drives funnel logic per niche.
**Date:** 2026-02-19

---

### DEC-2026-02-19-12 — n8n for Business Automation + CF Workflows for Technical Pipelines

**Context:** Two distinct automation needs: business workflows (notifications, onboarding, integrations) and technical pipelines (matching computation, booking confirmation).
**Decision:** n8n handles business automation (Cal.com webhooks → Resend, Slack, Supabase). Cloudflare Workflows handles technical pipelines (matching, booking confirmation flow). Both coexist.
**Rationale:** n8n has native integrations with all third-party services. CF Workflows is better for durable technical orchestration within the CF ecosystem. Separating concerns keeps each tool focused.
**Impact:** n8n deployed for business automation from MVP. CF Workflows for internal platform pipelines.
**Date:** 2026-02-19

---

### DEC-2026-02-19-11 — Resend via Cloudflare Queues for Transactional Email

**Context:** Transactional email required for booking confirmations, lead notifications, onboarding.
**Decision:** Resend as the email provider, triggered via Cloudflare Queues (async). Not called synchronously from Workers.
**Rationale:** Resend has a clean TypeScript SDK, excellent deliverability, and developer-friendly API. Queues decouples email sending from the request lifecycle — avoids timeouts and enables retry logic.
**Impact:** All transactional email flows through Queues → Resend. No synchronous email calls in Workers.
**Date:** 2026-02-19

---

### DEC-2026-02-19-10 — Cal.com for Calendar and Booking (Managed Users)

**Context:** Booking layer requires calendar integration with Google Calendar + Google Meet + Microsoft Teams. Must support programmatic calendar creation per expert (marketplace model).
**Decision:** Cal.com with managed users API. Experts get a Cal.com managed account created programmatically at registration. Booking widget embedded on satellite sites and callibrate.ai.
**Rationale:** Cal.com managed users allow creating calendar accounts on behalf of experts — critical for a marketplace. Calendly does not support this model. Native Google Calendar sync + auto Meet link generation + Teams support.
**Impact:** At expert registration: Cal.com managed user created via API. Booking trigger: Cal.com webhook → CF Worker → lead billing. Calendly removed from stack.
**Date:** 2026-02-19

---

### DEC-2026-02-19-09 — Lemon Squeezy as Payment Provider (Merchant of Record)

**Context:** International marketplace billing requires VAT/GST collection and remittance across multiple jurisdictions. Stripe requires manual tax registration per country.
**Decision:** Lemon Squeezy as the payment provider. Acts as Merchant of Record — handles all international tax compliance automatically.
**Rationale:** Lemon Squeezy handles VAT/GST collection, remittance, and compliance globally. No per-country tax registration needed. Critical for a marketplace with international experts and prospects. Stripe removed from stack.
**Impact:** Lead billing: booking confirmed → Lemon Squeezy checkout triggered programmatically → expert billed. All tax compliance delegated to Lemon Squeezy.
**Date:** 2026-02-19

---

### DEC-2026-02-19-08 — Three-System Architecture (callibrate.io / callibrate.ai / Satellites)

**Context:** Expert-facing and prospect-facing experiences have different UX needs. Redirecting prospects to an expert platform kills conversion. Niche satellite sites need SEO/GEO independence.
**Decision:** Three distinct systems: (1) callibrate.io = expert platform, (2) callibrate.ai = prospect-facing app, (3) N satellite sites = niche inbound funnels. Satellite booking step = embedded Callibrate widget, not redirect.
**Rationale:** Sending prospects to an expert-facing platform creates UX mismatch and kills conversion. Embedded widget keeps niche context while centralizing booking logic. Separate domains per vertical enable topical SEO authority and better GEO (LLM citation) performance.
**Impact:** Three deployments to maintain. Satellite sites interact with callibrate.io API. Canonical tags: self-referencing on satellites, cross-domain only for exact duplicate content.
**Date:** 2026-02-19

---

### DEC-2026-02-19-07 — Platform Renamed to Callibrate

**Context:** "The AI Integrator Network" is too long, too generic, and domain-hostile. The platform needed a brandable, memorable name encoding both the matching precision and the booking trigger.
**Decision:** Platform renamed to Callibrate. callibrate.io = expert-facing. callibrate.ai = prospect-facing. Both domains available and secured.
**Rationale:** Wordplay on calibrate (precision matching) + call (booking trigger). Unique spelling = brand distinctiveness + domain availability. .io for B2B expert platform, .ai for the AI-native prospect experience.
**Impact:** All future artefacts, code, and communications use "Callibrate". Previous name retired.
**Date:** 2026-02-19

---

### DEC-2026-02-19-06 — Acquisition Channel Strategy for Milestone 0

**Context:** Milestone 0 requires validating offer demand on both sides of the marketplace before building.
**Decision:** Reddit + Slack/Discord for 2–3 days of listening and language sharpening (pre-step). LinkedIn (primary) + X/Twitter + Facebook Groups for Hand Raiser posts. Gates measured on LinkedIn/X/Facebook only.
**Rationale:** Reddit is anti-sales culture — unsuitable for direct Hand Raiser. LinkedIn/X provide real professional identities and public engagement signals. Facebook Groups work for entrepreneur/business owner segments.
**Impact:** Milestone 0 execution plan. No direct outreach via Reddit — observation only.
**Date:** 2026-02-19

---

### DEC-2026-02-19-05 — Hand Raiser Method Adopted for Milestone 0 Validation

**Context:** Needed a low-cost, unbiased method to validate offer demand before any development investment.
**Decision:** Hand Raiser method selected: add targets on LinkedIn/X/Facebook, publish a result-oriented post, count public "raises". No video closing at this stage.
**Rationale:** Public engagement is an honest signal (no politeness bias). Fast (7 days). Zero development cost. Validates the promise language directly. If nobody raises their hand → rewrite the promise before building.
**Impact:** M0 gate: ≥10 expert hand raisers + ≥15 prospect hand raisers required before Milestone 1 starts.
**Date:** 2026-02-19

---

### DEC-2026-02-19-04 — Cloudflare Workers (Not Pages) for All Deployment

**Context:** Cloudflare recommends Workers over Pages for all new projects.
**Decision:** All frontend and backend deployment uses Cloudflare Workers exclusively. No Cloudflare Pages.
**Rationale:** Aligned with Cloudflare's current architectural recommendation. Consistent full-stack Workers approach. Founder is experienced with the Cloudflare Workers ecosystem.
**Impact:** All deployment, routing, and edge logic runs on Workers. Stack: Workers + Queues + Workflows + KV + D1 (if needed).
**Date:** 2026-02-19

---

### DEC-2026-02-19-03 — No Commission Model — Lead Access Fee Only

**Context:** Common marketplace models charge commission on closed deals, creating legal complexity and tracking overhead.
**Decision:** Revenue model is lead access fee only (pay-per-qualified-lead + subscription). No commission on deals.
**Rationale:** Simpler legal structure, no deal tracking required, clearer value proposition for experts (pay for the lead, not the outcome). Aligns with solo founder / minimal-support constraint.
**Impact:** Monetization: 100–200€/booked call, subscription bundles. No deal tracking infrastructure needed.
**Date:** 2026-02-19

---

### DEC-2026-02-19-02 — Claude Code Selected as AI Tooling

**Context:** The project needed an AI coding agent for governed AI-assisted development.
**Decision:** Claude Code (claude-sonnet-4-6) selected as the AI tooling.
**Rationale:** Native GAAI integration via CLAUDE.md and .claude/commands/. Primary supported adapter in GAAI v1.0.0.
**Impact:** All slash commands operate within Claude Code. Active model: claude-sonnet-4-6.
**Date:** 2026-02-19

---

### DEC-2026-02-19-01 — GAAI Governance Framework Adopted

**Context:** Needed structured approach to AI-assisted development to prevent drift and enable predictable delivery.
**Decision:** GAAI v1.0.0 installed as the governance framework.
**Rationale:** Dual-track model, explicit memory management, governed backlog lifecycle, skills-based execution — appropriate for a MicroSaaS project requiring disciplined AI usage with a solo founder.
**Impact:** All AI execution governed by GAAI rules. Backlog is the single source of execution authority.
**Date:** 2026-02-19

---

<!-- Add decisions above this line, newest first -->
