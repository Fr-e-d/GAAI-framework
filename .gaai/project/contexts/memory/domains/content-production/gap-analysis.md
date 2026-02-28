# Content Knowledge Base — Gap Analysis

> **Date:** 2026-02-26
> **Scope:** Coverage assessment of 10 sources (141 AKUs) against 10 planned content blueprint skills
> **Purpose:** Identify remaining knowledge gaps and resolution paths before skill design
> **Framework context:** `domain-knowledge-research` (SKILL-CRS-023) + Capability Readiness rule
> now provide on-demand gap resolution. Pre-requisite knowledge collection is no longer the
> only path — the framework self-heals knowledge gaps during story refinement.

---

## SKILL COVERAGE MATRIX

| Skill | Coverage | Primary Sources | Gaps | Resolution Path |
|-------|----------|-----------------|------|-----------------|
| CNT-001-research | **GOOD** | AGT-001, SRC-001, SEO-001, KWR-001 | Minor: voice-of-customer mining, competitive gap analysis not formalized | Auto: Capability Readiness triggers `domain-knowledge-research` (surface) if needed at refinement |
| CNT-002-outline | GOOD | WRT-001, AGT-001, SRC-001 | Minor: artefact template | Skill design concern, not knowledge gap |
| CNT-003-draft | GOOD | WRT-001, HMN-001, AGT-001, SRC-001 | Minor: prompt engineering methodology | Develops during skill design (T2) |
| CNT-004-edit | EXCELLENT | HMN-001, WRT-001 | None | — |
| CNT-005-seo-optimize | **GOOD** | SEO-001, SEO-002 | Minor: alt text checklist implicit | Auto: `domain-knowledge-research` (surface) if needed |
| CNT-006-geo-optimize | EXCELLENT | GEO-001, SRC-001 | None | — |
| CNT-007-social-adapt | **DESIGNED** | SOC-001, MTA-001, voice-guide.md | Skill created (SKILL-CNT-007). Templates built into skill process. | Skill ready at `skills/domains/content-production/social-adapt/SKILL.md` |
| CNT-008-youtube-script | **DEFERRED** | SOC-001 (3 AKUs only) | Near-total: YT algorithm, script structure, Shorts vs long-form, YT SEO, AI search citation | Planned: `domain-knowledge-research` (comprehensive) when CNT-008 is prioritized. Not a day-1 use case |
| CNT-009-quality-gate | GOOD | AGT-001, HMN-001, SRC-001, GEO-001 | Minor: readability score targets by content type | Auto: `domain-knowledge-research` (surface) if needed |
| CNT-010-repurpose | **DESIGNED** | SRC-001, SEO-001, SEO-002, KWR-001 | Skill created (SKILL-CNT-010). Cadence framework + decision tree built into skill. | Skill ready at `skills/domains/content-production/repurpose/SKILL.md` |
| CNT-011-content-plan | **DESIGNED** | CONTENT-STRATEGY-001, GTM-001, COMMS-001 | Skill created (SKILL-CNT-011). Monthly planning from 6-dimension model. | Skill ready at `skills/domains/content-production/content-plan/SKILL.md` |

---

## TRANSVERSAL GAPS

| ID | Gap | Impacts | Severity | Resolution |
|----|-----|---------|----------|------------|
| T1 | Voice guide (voice-guide.md) | CNT-003, CNT-004, CNT-007 | **RESOLVED** | Created 2026-02-26 at `memory/domains/content-production/voice-guide.md` from COMMS-001 Parts 0, 1, 3 |
| T2 | Prompt engineering for pipeline | All skills | RESOLVED | Develops during skill design. Each skill encodes its own prompts |
| T3 | Visual content creation | CNT-003, CNT-007, CNT-008 | OUT OF SCOPE | Text-first pipeline. Address when visual skill is added |
| T4 | Content measurement / analytics | CNT-009, CNT-010 | RESOLVED | PostHog integration exists in Callibrate. Framework built alongside first publication cycle |
| T5 | Distribution beyond social | CNT-007 scope | OUT OF SCOPE | Marketing/GTM concern, not content production |
| T6 | UTM content attribution (`utm_content`) | CNT-010, CONTENT-STRATEGY-001 §10 | **RESOLVED** | Fixed 2026-02-26: `utm_content` added to satellite `page_view` event, prospect form body parsing, DB INSERT, PostHog `prospect.form_submitted` event, `ProspectRow` type, `database.ts` types. Migration `prospects_utm_content` applied to staging. Content-piece-level attribution now possible when UTM links include `utm_content={piece-id}`. |
| T7 | PostHog measurement stack (E07S06) | CNT-010, CONTENT-STRATEGY-001 §10, analytics-query skill | **RESOLVED** | Verified 2026-02-26: MCP PostHog connected, 3 dashboards live (Prospect Conversion #543054, Expert Activation #543055, Business Overview #543056), proxy `ph.callibrate.io` HTTP 200, Personal API Key loaded. Measurement framework and CMF feedback loop fully operational. |

---

## PRIORITIZED ACTIONS

### All pre-requisites resolved
1. ~~**T1 — Voice guide:** Transform COMMS-001 → `memory/domains/content-production/voice-guide.md`~~ → **RESOLVED** (created 2026-02-26)

### Content Strategy Map — RESOLVED
8. ~~**Content Strategy Map:** Formalize 6-dimension model as artefact~~ → **RESOLVED** (DEC-95). Artefact: `artefacts/strategy/CONTENT-STRATEGY-001.md`. 6 gaps from industry research applied: bottom-up sequencing (BP > ARL), Business Potential scoring, Content-Market Fit feedback loop, dual-audience tracks, transparency policy, measurement per objective.

### Resolved (no action needed)
2. ~~**CNT-001** — keyword research methodology~~ → **RESOLVED** by KWR-001
3. ~~**CNT-005** — on-page checklist~~ → **RESOLVED** by SEO-002
4. ~~**CNT-007** — transformation templates~~ → **RESOLVED** by Capability Readiness (`domain-knowledge-research` on-demand)
5. ~~**CNT-008** — YouTube knowledge~~ → **DEFERRED** — `domain-knowledge-research` (comprehensive) when prioritized
6. ~~**CNT-010** — repurposing methodology~~ → **RESOLVED** by Capability Readiness (`domain-knowledge-research` on-demand)
7. ~~**T2** — prompt engineering~~ → **RESOLVED** by skill design practice

---

## SKILLS READY FOR DESIGN

### Immediate (sufficient knowledge base now)

1. CNT-001-research
2. CNT-002-outline
3. CNT-003-draft
4. CNT-004-edit
5. CNT-005-seo-optimize
6. CNT-006-geo-optimize
7. CNT-009-quality-gate

### Designed (skill files created)

8. CNT-007-social-adapt — `skills/domains/content-production/social-adapt/SKILL.md` (SKILL-CNT-007)
9. CNT-010-repurpose — `skills/domains/content-production/repurpose/SKILL.md` (SKILL-CNT-010)
10. CNT-011-content-plan — `skills/domains/content-production/content-plan/SKILL.md` (SKILL-CNT-011)

### Deferred (not day-1 priority)

10. CNT-008-youtube-script — `domain-knowledge-research` (comprehensive) when prioritized

---

## KNOWLEDGE BASE SOURCES

| ID | Domain | AKUs | Status |
|----|--------|------|--------|
| SEO-001 | SEO | 15 + 3 UZ | Stable |
| SEO-002 | SEO (On-Page) | 10 | Stable |
| WRT-001 | WRT | 20 + 4 UZ + 7 WF | Stable |
| AGT-001 | AGT | GAAI-filtered | Stable |
| GEO-001 | GEO | 18 + intervention ranking | Stable |
| HMN-001 | HMN | 18 + 4-layer model | Stable |
| SOC-001 | SOC | 20 + protocol | Stable |
| SRC-001 | SRC | 17 | Stable |
| MTA-001 | MTA | 17 | Stable |
| KWR-001 | KWR | 13 | Stable |
| **Total** | **9 domains** | **~141 AKUs** | — |
