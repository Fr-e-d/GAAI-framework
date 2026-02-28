---
type: memory
category: summaries
id: SUMMARY-DECISIONS-60-89
tags:
  - decisions
  - summary
  - compacted
created_at: 2026-02-27
source: decisions/_log.md (DEC-60 through DEC-89, plus DEC-2026-02-23-01, DEC-2026-02-23-02)
---

# Decisions Summary — DEC-60 to DEC-89

> Compacted from `decisions/_log.md` on 2026-02-27.
> Full original text in `archive/decisions-60-89.archive.md`
> Only DEC-90+ remain in the active log.

---

## Infrastructure & Scaling

| ID | Decision | Date |
|---|---|---|
| DEC-60 | Scoring/Matching scalability path documented (4 phases: in-memory → SQL pre-filter → DO → pgvector) | 2026-02-22 |
| DEC-60 (REVISED) | Scalable matching engine: implement now (9 stories E06S18–E06S26, ~$7-8/mo CF cost) | 2026-02-22 |
| DEC-61 | D1 as edge serving layer — Supabase source of truth, D1 read cache, cron sync */5, fallback chain Cache API → D1 → Hyperdrive | 2026-02-22 |
| DEC-62 | Vectorize + Workers AI for semantic matching — bge-base-en-v1.5 (768 dims), blended 0.7×exact + 0.3×vector, graceful fallback | 2026-02-22 |
| DEC-63 | Turnstile invisible CAPTCHA on `POST /api/prospects/submit` — free, zero-friction bot protection | 2026-02-22 |
| DEC-64 | CF Rate Limiting binding replaces manual KV rate limiter — 30 req/min per IP, zero storage overhead | 2026-02-22 |
| DEC-65 | Analytics Engine dataset `matching-metrics` — fire-and-forget observability, free 100K events/day | 2026-02-22 |
| DEC-66 | Hyperdrive + postgres.js replaces Supabase JS for all DB queries — 6× latency improvement, TCP pooling, Supabase JS retained only for auth | 2026-02-22 |
| DEC-69 | KV eliminated from expert pool read path — D1 replaces KV (SQL filtering, sub-5ms, 10 Go limit), E06S19 merged into E06S23 | 2026-02-22 |

## Billing & Monetization

| ID | Decision | Date |
|---|---|---|
| DEC-67 | Dynamic lead pricing — budget tier × qualification modifier. 4 tiers (49€–229€) + premium +15%. `max_lead_price` expert control. Match score ≠ price factor. | 2026-02-22 |
| DEC-68 | LS usage-based subscription + internal credit accounting. $0/mo card on file, 7-day flag window, deferred usage reporting, 100€ welcome credit, `spending_limit` control. | 2026-02-22 |

## Process & Governance

| ID | Decision | Date |
|---|---|---|
| DEC-70 | Artefact directory structure — one dedicated subdirectory per type, canonical routing table in artefacts.rules.md | 2026-02-24 |
| DEC-71 | Mandatory PR merge to staging at end of delivery cycle — 19 PR incident root cause: accumulation + stacked branches + hotspot files | 2026-02-24 |
| DEC-2026-02-23-02 | PR-based delivery + preview deployments + model selection — agent creates PR (never merges), preview URLs, Sonnet default | 2026-02-23 |
| DEC-2026-02-23-01 | OpenAI function calling as canonical pattern for structured AI extraction (E06S12 impl) | 2026-02-23 |

## Strategy & Vision

| ID | Decision | Date |
|---|---|---|
| DEC-72 | .gaai open-sourcing deferred to post-launch — use as marketing lever (blog, Show HN, r/ClaudeAI) | 2026-02-24 |
| DEC-73 | Formation payante .gaai — premature, revisit after Gate 3 PASS. Sequence: OSS → case study → formation. | 2026-02-24 |
| DEC-74 | Vision .gaai Cloud: SaaS universel de gouvernance d'agents AI — artefact VISION-GAAI-CLOUD.md. Callibrate = proof of concept + revenue runway. | 2026-02-24 |
| DEC-75 | Architecture technique .gaai Cloud: 3 couches (Plugin Cowork → Agent SDK Backend → .gaai Protocol). No Claude Code in background. | 2026-02-24 |
| DEC-76 | Flagship blog post (E01S05) — experience + chiffres concrets + Dual-Track. Distribution: blog + dev.to + Show HN + r/ClaudeAI + X thread. | 2026-02-24 |
| DEC-77 | Build-in-public as orchestrated launch strategy — same content warms 3 audiences (Callibrate, .gaai, personal brand). Auto-generated via SKILL-CRS-021. | 2026-02-24 |
| DEC-78 | Communication & Publication Strategic Plan (COMMS-001) — 7-part plan: empathy maps, channel strategy, personal brand, launch orchestration, comment response, content pipeline, risk mitigation. 5h/week budget. | 2026-02-24 |
| DEC-79 | .gaai origin story as narrative backbone — 7 beats (digital detox → iPhone 8 research → framework assembly → Callibrate validation). Angle D for HN/Reddit. | 2026-02-24 |

## Expert System & Matching

| ID | Decision | Date |
|---|---|---|
| DEC-80 | Expert admissibility criteria extended beyond budget — `admissibility_criteria JSONB` with methodology, stack, duration, custom rules (E06S36) | 2026-02-24 |
| DEC-81 | Outcome-based framing validated — `outcome_tags TEXT[]` + `desired_outcomes` extraction + `scoreOutcomeAlignment()` semantic dimension (E06S37) | 2026-02-24 |
| DEC-82 | Phase 2 proof of quality visibility required before payment activation — first cohort sees matching quality for free, billing activates when avg lead rating ≥ 4/5 | 2026-02-24 |

## Market & Verticals

| ID | Decision | Date |
|---|---|---|
| DEC-84 | Satellite vertical selection: V3 (AI Chatbot) + V1 (Workflow Auto) + V8 (AI Integration) as Tier 1. Common trait: prospect doesn't know which tool → matching engine killer feature. | 2026-02-24 |
| DEC-85 | Scope strategy: AI-pure at launch, niche-down data-driven post-Gate 2 (trigger: ≥30% domain concentration). No Salesforce/CRM/Shopify. | 2026-02-24 |
| DEC-88 | Niche-down candidates: Real Estate #1 (26/30), Accounting sleeper (21/30), Legal sleeper (20/30). Trigger: ≥30% domain concentration post-Gate 2. | 2026-02-25 |

## Content & Blueprint

| ID | Decision | Date |
|---|---|---|
| DEC-86 | GAAI modular blueprint architecture — domain skills as extractable packs within GAAI, not separate frameworks. `skills/domains/content-production/` with blueprint.yaml. | 2026-02-25 |
| DEC-87 | Content blueprint knowledge base — 7 sources, 118 AKUs, GAAI-filtered. Gap analysis: 5 skills ready, CNT-008 critical gap, 5 transversal gaps. | 2026-02-25 |

## Operations

| ID | Decision | Date |
|---|---|---|
| DEC-83 | Cost analysis skill (SKILL-CRS-022) + delivery cost baseline: $149.90/24 stories, avg $6.02/story, 99% Sonnet | 2026-02-24 |
| DEC-89 | Staging infra audit: 5 missing migrations applied + ADMIN_API_KEY provisioned. 18 migrations total (fully synced). 7 human action items prioritized. | 2026-02-25 |

---

## Key Cross-References

- DEC-60 REVISED supersedes DEC-60 (doc-only → implement now) — both archived
- DEC-67/68 billing model referenced by DEC-80 (admissibility criteria) and DEC-82 (proof of quality) in active log range
- DEC-71 (PR merge timing) and DEC-70 (artefact routing) are process patterns codified in `patterns/conventions.md`
- DEC-78 (COMMS-001) is the communication strategic plan referenced by DEC-95+ in the active log
- DEC-84/85/88 (vertical selection + scope strategy) inform all satellite development decisions
