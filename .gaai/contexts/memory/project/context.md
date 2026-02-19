---
type: memory
category: project
id: PROJECT-001
tags:
  - product
  - vision
  - scope
created_at: 2026-02-19
updated_at: 2026-02-19
---

# Project Memory

> Loaded at the start of every session. Keep it concise and high-signal.

---

## Project Overview

**Name:** Callibrate (callibrate.io + callibrate.ai)

**Purpose:** Matching OS — moteur de qualification et matching bi-directionnel configurable par domaine. MVP focalisé sur les experts AI. Architecture domain-agnostic : peut accueillir tout type de prestataire de service qualifié. Le call booké est l'unité monétisable. Pas de commission sur les deals.

**Positionnement :** "Browse like a directory. Match like magic."
- Mode directory : exploration, profils, trust scores, SEO-friendly
- Mode engine : freetext + AI extraction → matching bi-directionnel → résultats rankés

**Target Users:**
- **Experts** (paying customers): AI integration consultants et freelancers — paient uniquement par call booké (pay-per-call, pas d'abonnement)
- **Prospects** (product delivered): Entreprises avec un besoin réel — gratuit, accès via satellite sites niches

**Founder profile:** Solo founder, AI-assisted development, minimal manual support target.

---

## Core Problems Being Solved

- Experts waste time on unqualified leads — wrong budget, no decision-maker, no timeline
- Prospects struggle to identify and compare relevant AI experts efficiently
- Existing platforms charge commission on deals (legal complexity, no transparency)
- No platform combines AI-powered qualification with transparent match scoring and direct booking

---

## Success Metrics (90-day MVP)

- **M0 (Day 7):** ≥10 experts raise hand (LinkedIn/X/Facebook) + ≥15 prospects raise hand → offer validated
- **M1 (Day 21):** Full loop working end-to-end without manual intervention (1 test prospect completes form → match → book)
- **M2 (Day 45):** 20 form completions, ≥10 score >65%, ≥5 calls booked, expert lead quality ≥7/10, conversion ≥35%
- **M3 (Day 90):** ≥10 calls payés, GMV ≥1 500€, ≥3 experts re-payants, expert satisfaction ≥7/10

**KPIs:**
- Lead-to-RDV conversion: >35%
- Expert re-purchase rate (≥2 leads payés): >40%
- Call experience score moyen: >4/5
- Lead eval rate (experts notant leurs leads): >60%
- Lead→RDV time: <72h

---

## Tech Stack & Conventions

- **Database / Auth / Storage:** Supabase (PostgreSQL + Auth + Storage)
- **Edge compute:** Cloudflare Workers (full-stack — NOT Pages, deprecated)
- **Async / Background jobs:** Cloudflare Queues + Workflows (technical pipelines)
- **Business automation:** n8n (integrations tierces, notifications, onboarding sequences)
- **Cache / Session:** Cloudflare KV
- **Email transactionnel:** Resend (via Cloudflare Queues)
- **Calendar / Booking:** Cal.com — managed users API, Google Calendar + Google Meet + Teams
- **Payment / MoR:** Lemon Squeezy (Merchant of Record — gestion taxes internationales)
- **Frontend platform:** Next.js 15 (App Router) — callibrate.io + callibrate.ai
- **Satellite sites:** Astro (SSG, SEO-first) ou WordPress headless
- **Dev tooling:** Cloudflare MCP server (`docs.mcp.cloudflare.com/mcp`)
- **Language:** TypeScript (Workers + Next.js)
- **Key conventions:** To be defined once first Story is in Delivery

---

## Monetization

- **Pay-per-call:** 100–200€ per booked call — no subscription, no monthly commitment
- **Logic:** Expert pays only when a prospect books a call. Platform earns only when both sides get value.
- **Premium options (post-MVP):** Visibility boost, Top Match badge
- **Subscriptions:** Explicitly deferred to post-M3 — only if experts demand volume bundles after lead quality is proven

---

## Acquisition Strategy (Milestone 0)

- **Pre-step (Day 1–3):** Reddit + Slack/Discord — listen, sharpen promise language
- **Hand Raiser (Day 3–7):** LinkedIn (primary) + X/Twitter + Facebook Groups
- Hand Raiser mechanic: public post with measurable result promise + "commentez 'moi'" CTA
- No video closing at Milestone 0 stage
- One promise. Multiple surfaces. Same gates apply.
- **X/Twitter:** compte `@Fr-e-d` (cohérent avec GitHub), cold start + $20 promoted tweet

## Acquisition Strategy (Milestone 1+)

- **Apollo.io** — prospection B2B, identification profils experts + prospects, export qualifié
- **PhantomBuster** — automatisation LinkedIn/X (follow, connect, message) avec contrôle du rythme
- Cold email écarté : risque GDPR (marché FR) + efficacité réduite par nouvelles features Gmail

---

## System Architecture

3-layer architecture. Each layer consumes the layer below it.

**Layer 1 — Data**
- Supabase (PostgreSQL): experts, prospects, matches, bookings, leads, satellite_configs + feedback tables
- Source of truth for all structured data. No business logic at this layer.

**Layer 2 — Services / API**
- Cloudflare Workers: all API endpoints, business logic, matching engine, AI extraction, score computation
- Cloudflare Queues: async workers (email, billing, matching, score)
- n8n: time-based workflows (survey triggers, onboarding sequences)
- This layer is domain-agnostic — no UI concerns, no platform-specific assumptions

**Layer 3 — Interfaces**
Two tracks. Each track can host as many platforms as needed. All platforms in Layer 3 consume Layer 2 exclusively.

*Track 3.1 — Expert dedicated UIs*
- **callibrate.io**: registration, profile, dashboard, lead pipeline, analytics, billing

*Track 3.2 — Prospect dedicated UIs*
- **callibrate.ai**: directory browsing + matching engine funnel (main prospect app)
- **Satellite sites** (N domains, niche-specific): SEO/GEO inbound funnels per vertical — conversational quiz, embedded booking widget, content — data centralized in Layer 2

## Architectural Boundaries

- **AI extraction:** Freetext description → Claude (haiku-4-5) → ProspectRequirements JSONB (CF Worker, stateless — `POST /api/extract`)
- **Qualification engine:** Quiz funnel (satellite) → requirements JSONB → Supabase (CF Worker)
- **Matching engine:** Expert profile JSONB vs prospect requirements JSONB → scored matches + composite_score tiebreaker (CF Worker)
- **Booking layer:** Cal.com managed users — Google Calendar + Meet + Teams
- **Lead billing trigger:** booking confirmed → Lemon Squeezy one-time checkout → lead billed (pay-per-call)
- **Score computation:** Feedback events (call_experience + satisfaction + lead_eval) → composite_score (CF Queue consumer)
- **Feedback loop:** n8n triggers J+7 and J+45 survey emails → submissions → score worker → match re-ranking
- **Expert dashboard:** Profile, criteria, lead pipeline, analytics, composite_score tier
- **Notification layer:** Cloudflare Queues → Resend (email) / n8n (complex workflows, time-based triggers)

---

## Known Constraints

- Solo founder — UX must be simple, support must be minimal
- No commission on deals — revenue only from lead access fees
- GAAI governance active: all execution via backlog
- Cloudflare Workers (not Pages) for all deployment
- AI augments the product — does not replace it

---

## Competitive Moat

**Moat primaire — Data flywheel**
Chaque transaction (quiz, match score, booking, feedback) améliore les weights du matching engine. Plus de volume → meilleure calibration → meilleurs matchs → plus de volume. Impossible à répliquer pour un acteur solo ou un système mono-expert.

**Différenciateur clé — Valeur au prospect "rejeté"**
Un système mono-expert (Typeform ROI, filtre Upwork) : le prospect qui ne matche pas disparaît sans valeur.
Callibrate : le prospect qui ne matche pas Expert A est matché avec Expert B ou C. Les "rejets" d'un expert deviennent des revenus pour un autre. **Aucune plateforme existante ne fait ça.**

**Barrière technique — Matching bi-directionnel**
Upwork / Malt / LinkedIn = unidirectionnel ou textuel. Callibrate évalue simultanément `expert.preferences` vs `prospect.requirements` dans les deux sens. Le composite score (data de vrais calls) est un actif défensif qui se renforce dans le temps.

**La vraie promesse :** "Ne rate pas le bon match parce que tu as atterri sur le mauvais expert en premier."
- Expert : reçoit des prospects pré-filtrés sans construire son propre système de qualification
- Prospect : n'est jamais perdu après un refus — le système trouve qui correspond vraiment

*Signal terrain : r/n8n_ai_agents — expert sophistiqué qui a construit son propre Typeform ROI + n8n filter. Preuve que le besoin existe et que la solution solo ne scale pas. (DEC-23)*

---

## Strategic Options (Post-M3 — not decided, not scoped)

> Ces options ne sont pas dans le backlog. Elles ne seront considérées qu'après Gate 3 PASS.
> Chacune est flaggée avec ses risques et trade-offs.

### Option A — API Licensing / Partner Model (Track 3.2 tiers)

**Idée :** Permettre à des tiers de construire leurs propres interfaces prospect (Track 3.2) en consommant la Layer 2 API de Callibrate. Le partenaire est rémunéré sur les calls validés qu'il génère.

**Opportunité :** Multiplication des canaux d'acquisition sans coût de build côté Callibrate. Verticals niches adressés par des opérateurs qui connaissent leur audience. Modèle "Matching OS as a Platform".

**Risques :**
- **Fraude affiliate** : partenaire génère des faux bookings (faux prospects, acteurs scriptés) pour collecter des fees. Le déclencheur doit être le call *complété et validé*, pas le booking. Nécessite un système Trust & Safety dédié.
- **Dilution de la qualité** : des partenaires mal alignés dégradent l'expérience expert → churn côté experts payants.
- **Complexité contractuelle** : SLA, conditions d'utilisation API, responsabilité des données prospects (RGPD), partage de revenus — overhead légal significatif pour un solo founder.
- **Dépendance partenaire** : si un partenaire génère 50% du volume, il a un levier de négociation.

**Trade-offs :**
- Volume × qualité : plus de partenaires = plus de volume mais moins de contrôle qualité
- Build vs. buy : construire le partner portal + payout system = plusieurs semaines de dev post-M3
- Timing : ne fait sens qu'une fois le core loop prouvé (Gate 3 PASS) et le volume justifié

**Prérequis avant d'envisager :**
- Gate 3 PASS (≥10 calls payés, ≥3 experts re-payants)
- `partner_id` sur `bookings` + `leads` (traçabilité source)
- Validated lead definition formalisée (call complété ≥15min + expert confirme)
- Escrow + payout system Lemon Squeezy

---

## Out of Scope (MVP)

- Mobile native app
- Multi-language (FR first, EN later)
- Custom CRM integration (beyond Airtable/HubSpot webhook)
- White-label version
