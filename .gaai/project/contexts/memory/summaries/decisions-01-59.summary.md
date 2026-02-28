---
type: memory
category: summaries
id: SUMMARY-DECISIONS-01-59
tags:
  - decisions
  - summary
  - compacted
created_at: 2026-02-23
source: decisions/_log.md (DEC-01 through DEC-59)
---

# Decisions Summary — DEC-01 to DEC-59

> Compacted from `decisions/_log.md` on 2026-02-23.
> Full original text in `archive/decisions-01-59.archive.md`
> Only DEC-60+ remain in the active log.

---

## Platform Identity & Naming

| ID | Decision | Date |
|---|---|---|
| DEC-01 | GAAI governance framework adopted | 2026-02-19 |
| DEC-02 | Claude Code selected as AI tooling | 2026-02-19 |
| DEC-04 | CF Workers only (not Pages) for all deployment | 2026-02-19 |
| DEC-07 | Platform renamed to Callibrate (callibrate.io) | 2026-02-19 |
| DEC-38 | callibrate.io domain acquired and confirmed | 2026-02-20 |
| DEC-39 | callibrate.ai removed; final: callibrate.io + app.callibrate.io + satellites + api.callibrate.io | 2026-02-20 |
| DEC-49 | "Callibrate" naming confirmed + dual taglines validated | 2026-02-20 |

## Architecture

| ID | Decision | Date |
|---|---|---|
| DEC-08 | Three-system architecture → partially superseded by DEC-39 (callibrate.ai removed) | 2026-02-19 |
| DEC-13 | JSONB + GIN flexible data model for matching engine | 2026-02-19 |
| DEC-18 | Domain-agnostic 3-layer architecture (data / services / interfaces) | 2026-02-19 |
| DEC-22 | 3-layer refined — Track 3.1 (expert UIs) + Track 3.2 (prospect/satellites) | 2026-02-19 |
| DEC-54 | Satellite sites: multi-tenant CF Worker (not Astro SSG) — hostname routing + KV config cache | 2026-02-21 |

## Matching Engine

| ID | Decision | Date |
|---|---|---|
| DEC-16 | Dual mode: directory (SEO) + matching engine (conversion) | 2026-02-19 |
| DEC-17 | AI freetext extraction (prospect description → structured JSONB) | 2026-02-19 |
| DEC-19 | Composite score: call_exp×0.35 + trust×0.20 + satisfaction×0.20 + hire_rate×0.10 + recency×0.15 | 2026-02-19 |
| DEC-24 | Match results: ranked list complet (no top-3 limit) | 2026-02-19 |
| DEC-25 | Qualification relative per expert — no universal standard | 2026-02-19 |
| DEC-27 | Matching criteria: vertical-extensible via satellite_configs + expert.preferences JSONB | 2026-02-19 |
| DEC-33 | matching-jobs queue removed — matching is synchronous at search time | 2026-02-20 |
| DEC-40 | Synchronous scoreMatch() at POST /api/prospects/submit | 2026-02-20 |
| DEC-50 | Scoring phase 1: normalization, industry/timeline proximity, budget configurable | 2026-02-20 |
| DEC-51 | Reliability modifier: composite_score as scoring modifier (not just tiebreaker) | 2026-02-20 |
| DEC-52 | Hybrid prospect flow: freetext → AI extraction → targeted confirmation | 2026-02-20 |

## Expert System

| ID | Decision | Date |
|---|---|---|
| DEC-21 | Expert lead eval J+48 + conversion declaration (optional, incentivized via trust) | 2026-02-19 |
| DEC-26 | Expert onboarding = market positioning profiling (not raw criteria form) | 2026-02-19 |
| DEC-28 | 3-layer expert criteria: hard constraints / soft preferences / learned | 2026-02-19 |
| DEC-29 | Preferences: system suggests, expert approves — never auto-apply | 2026-02-19 |

## Feedback Loop

| ID | Decision | Date |
|---|---|---|
| DEC-20 | Tri-directional: prospect J+7 call, prospect J+45 satisfaction, expert J+48 lead eval | 2026-02-19 |

## Billing & Monetization

| ID | Decision | Date |
|---|---|---|
| DEC-03 | No commission — lead access fee only | 2026-02-19 |
| DEC-14 | Pay-per-call only at MVP (no subscription) | 2026-02-19 |
| DEC-30 | 7-day flag window + qualification_rate anti-gaming → billing model revised by DEC-68 | 2026-02-19 |

## Booking Layer

| ID | Decision | Date |
|---|---|---|
| DEC-10 | ~~Cal.com managed users~~ → SUPERSEDED by DEC-41 | 2026-02-19 |
| DEC-34 | ~~cal.setup home~~ → SUPERSEDED by DEC-41 | 2026-02-20 |
| DEC-41 | Google Calendar API direct — headless booking engine (OAuth2 + freebusy + events.insert) | 2026-02-20 |
| DEC-42 | OAuth expert-only — prospect receives native Google Calendar invitation | 2026-02-20 |
| DEC-43 | Calendar event: inline requirement summary + prep link | 2026-02-20 |
| DEC-44 | Reminders: prospect mandatory (J-1 + H-1), expert optional (dashboard toggle) | 2026-02-20 |
| DEC-45 | Google OAuth sensitive scope verification: submit at E06S10 staging (not at launch) | 2026-02-20 |
| DEC-46 | Prep card: bi-directional matching + scoring visible by both parties | 2026-02-20 |

## UX & Acquisition

| ID | Decision | Date |
|---|---|---|
| DEC-05 | Hand Raiser method for M0 validation | 2026-02-19 |
| DEC-06 | Channels: Reddit (listen), LinkedIn/X/FB (hand raiser) | 2026-02-19 |
| DEC-15 | Progressive email gate — email at booking, not before reveal | 2026-02-19 |
| DEC-23 | Competitive moat: data flywheel + bi-directional value + rejected prospect matched elsewhere | 2026-02-19 |
| DEC-31 | GTM resequenced: LinkedIn deferred, Reddit+X now, simultaneous launch | 2026-02-19 |

## Providers & Infrastructure

| ID | Decision | Date |
|---|---|---|
| DEC-09 | Lemon Squeezy as MoR (international tax handling) | 2026-02-19 |
| DEC-11 | Resend via CF Queues for transactional email | 2026-02-19 |
| DEC-12 | ~~n8n for business + CF Workflows for technical~~ → SUPERSEDED by DEC-59 | 2026-02-19 |
| DEC-32 | CF naming convention: `{scope}-{entity}-{resource}-{env}` | 2026-02-20 |
| DEC-35 | Single Supabase DB (staging shared with dev) | 2026-02-20 |
| DEC-37 | Publishable key (SDK) vs anon key (REST direct) | 2026-02-20 |
| DEC-47 | Staging-first deploy + tag convention `v0.{EPIC}.{STORY}` | 2026-02-20 |
| DEC-48 | GPT-4o-mini replaces Anthropic Haiku for /api/extract | 2026-02-20 |
| DEC-53 | Crawler policy: SEO bots allowed, training bots blocked, answer bots restricted on profiles | 2026-02-21 |
| DEC-55 | Email: send.callibrate.io subdomain + DMARC + dual-stream architecture | 2026-02-21 |
| DEC-59 | n8n removed — CF Workflows for all async (step.sleep for J+7/J+45) | 2026-02-21 |

## GAAI Framework

| ID | Decision | Date |
|---|---|---|
| DEC-36 | Parallel /gaai-deliver authorized (independent stories, disjoint files, human-orchestrated) | 2026-02-20 |
| DEC-56 | Hybrid skill/agent discoverability: frontmatter + derived index | 2026-02-21 |
| DEC-57 | specialists.registry.yaml moved from contexts/ to agents/ | 2026-02-21 |
| DEC-58 | Skills design rules R8-R12: "Hardcode the framework. Discover the project." | 2026-02-21 |

---

## Superseded Decisions

| Original | Superseded by | Reason |
|---|---|---|
| DEC-10 (Cal.com managed users) | DEC-41 | Cal.com Platform closed to new signups 15/12/2025 |
| DEC-12 (n8n for business) | DEC-59 | CF Workflows covers all use cases, no external infra |
| DEC-34 (cal.setup) | DEC-41 | Cal.com removed from stack |
| DEC-08 (callibrate.ai) | DEC-39 | callibrate.ai removed; satellites = sole prospect channel |

## Key Cross-References

- DEC-30 core logic (7-day flag, qualification_rate) preserved — billing model revised by **DEC-68** (active log)
- DEC-19 composite score formula unchanged — implemented in E06S09
- DEC-60 REVISED supersedes DEC-60 (doc-only → implement now) — both in active log
