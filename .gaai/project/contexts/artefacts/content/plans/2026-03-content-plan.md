# Content Plan — March 2026

**Date:** 2026-02-26 (rev. 2026-02-26 — cold-start correction)
**GTM Phase:** Phase 0-1 (Implementation) — Gate 1 imminent (47/53 stories done, E06 35/36 done)
**Budget:** 5h/week (20h total for the month)
**Content inventory:** 0 published, 0 in drafts

---

## Previous Month Review

Pas de plan précédent. Premier mois de content planning formalisé.

Contenu informel existant :
- E01S01 Reddit engagement (in_progress) — observations marché, pas de publication
- E01S05 (done) — COMMS-001 strategy produite, pas de contenu publié
- CRS-021 drafts : aucun dans `drafts/` (drafts probablement non sauvegardés par sessions antérieures)

---

## Phase Assessment

**Phase actuelle : 0-1 (Implementation)**
- 47 stories done, 35/36 E06 infra stories done
- Gate 1 potentiellement atteignable en mars (1 E06 story restante + stories non-E06)
- E01S01 (community listening) : in_progress
- E07S06 (PostHog setup) : résolu (session 2026-02-26)

**Contenu autorisé (CONTENT-STRATEGY-001 §3) :**
- Décisions techniques, architecture, trade-offs (Phase Implementation)
- BIP threads continus (GTM-001 : BUILD IN PUBLIC transversal)
- **Interdit :** Revenue claims, user testimonials, case studies

**Si Gate 1 passe en mars :**
- Débloque Phase 2 (BIP flagship)
- Autorise : flagship blog post, Show HN, milestone content, .gaai tease

**Audience ratio Phase 0-1 (CONTENT-STRATEGY-001 §4) :**
- 80% Builder (P3 + P4)
- 20% Supply (P1)
- 0% Demand (P2)

---

## Gap Analysis

| Dimension | État actuel | Gap |
|-----------|------------|-----|
| **Layer** | Rien publié | Total — aucun layer couvert |
| **Phase** | Implementation (autorisé) | Pas de contenu Phase 0-1 produit |
| **Audience** | P1 Reddit engagement (E01S01) | P3/P4 non addressés (80% du ratio cible) |
| **Channel** | Aucun actif | X et Reddit prioritaires (COMMS-001 cadence) |
| **Objective** | Aucun | Credibility et Trust prioritaires pré-Gate 1 |
| **BP** | N/A | Phase 0-1 target : 40% BP-0, 40% BP-1, 20% BP-2 |

---

## Strategic Principle — Distribution Before Content

> Cold start rule: build distribution FIRST, produce hub content SECOND.
> A flagship blog post with 0 readers = wasted effort.
> Reddit karma + X followers = distribution that the platforms give you for free.
>
> March is a distribution-building month. Hub content is preparation only.
> References: Justin Welsh (atomic content first), Rand Fishkin (60 days community before self-promo), Pieter Levels (90% replies, 10% threads for first 30 days).

---

## Priority #1 — Reddit Engagement (P1 + P3)

**Objective:** Become a recognized, valuable community member. Build P1 trust for Gate 2 expert recruitment.

### r/aisolobusinesses + r/freelance_forhire (P1 — Supply track)
- **Layer:** L4 (market observations) + L2 (process, when relevant)
- **Mode:** Réponses > posts. Apporter de la valeur. Zero self-promotion.
- **Topics P1-relevant :** lead gen pain, pricing AI services, marketplace frustration, client qualification, freelancer-to-agency transition, niche positioning
- **Interdit :** Mentionner Callibrate, linker vers le projet, pitcher quoi que ce soit
- **Goal:** 2-3 interactions/semaine. Construire la reconnaissance du username.
- **Time-box :** 30 min/interaction

### r/ClaudeAI + r/cursor + r/LocalLLaMA (P3 — Builder track)
- **Layer:** L2 (process) + L3 (framework, as context)
- **Topics P3-relevant :** persistent memory, context engineering, AI agent governance, multi-agent architectures, Claude Code workflows
- **Mode:** Répondre avec une expérience concrète (chiffres, résultats, leçons). Pas de pitch .gaai.
- **Goal:** 1-2 interactions/semaine.
- **Time-box :** 30 min/interaction

### r/AIAgentGovernance (owned — land grab, DEC-99)
- **Layer:** L2 + L3 (governance in practice)
- **Mode:** Passive en mars. Seed 1 post/mois max (cross-post depuis engagement r/ClaudeAI ou X). Ne pas investir de temps actif à faire croître le sub.
- **Goal:** Le sub existe et a du contenu quand .gaai sera OSS (Gate 2).
- **Time-box :** 0h dédié. Les cross-posts sont un sous-produit de l'engagement P3.

---

## Priority #2 — X/Twitter Cold Start (P3 + P4)

**Objective:** Build follower base to ~100+ before publishing threads. The algorithm doesn't distribute threads from 0-follower accounts.

### Semaine 1-3 : Engagement pur (pas de threads)
- Follow 50-100 comptes dans les niches : AI governance, build-in-public, Claude Code, solo SaaS, AI automation
- Répondre à 3-5 posts/jour avec des observations substantielles (pas des "great post!")
- **Cibles :** comptes P3 (devs AI) + P4 (DevRel Anthropic, AI industry) + P1 (AI freelancers partageant leur expérience)
- **Angle des replies :** Partager une expérience concrète, un chiffre, un trade-off. "I did this and here's what happened."
- **Time-box :** 15 min/jour = ~1h45/semaine

### Semaine 4 : Premier thread (si ~50+ followers)
- **Sujet :** DEC-71 "19 PRs sans merge — here's what happened" (L2, BP-1, P3)
- **Format :** 5-8 tweets. Hook concret → erreur → conséquences → leçon → .gaai mention subtile
- **Fallback si <50 followers :** Report le thread à avril. Continuer l'engagement pur.
- **Time-box :** 30 min

---

## Priority #3 — Flagship Preparation (draft partiel, pas de rédaction complète)

### Hub 1: "I governed AI agents to build a SaaS solo — here's what 77+ decisions taught me"

| Dimension | Value |
|-----------|-------|
| Layer | L2 (Process) + L3 (Framework) |
| Phase | BIP — **publication gated on Gate 1 PASS** |
| Audience | P3 (devs/builders) primary + P4 (industry) secondary |
| Channel | Blog (Substack) → HN (Show HN) → dev.to (cross-post) → X (thread dérivé) |
| Objective | Credibility + Awareness |
| BP | BP-2 (le produit aide significativement mais n'est pas le sujet central) |
| Effort | 2h en mars (outline + angle validation from atomic content feedback) |
| Pipeline | CNT-001 (keyword validation) → CNT-002 (outline) — STOP. Full draft in April. |

**Mars deliverable : Outline structuré + 5 angles candidats testés via X replies et Reddit interactions.**

**Rationale (corrigée) :**
- Le flagship est la pièce fondatrice du BIP — mais l'écrire sans feedback audience est un pari aveugle
- Mars = tester des angles atomiques (threads, replies) pour identifier ce qui résonne
- L'outline en mars + full draft en avril = flagship informé par 4 semaines de signal réel
- Si Gate 1 passe mi-mars : 4-6h surge budget pour accélérer le draft (outline → draft rapide)

---

## Budget Breakdown

| Activity | W1 | W2 | W3 | W4 | Total |
|----------|-----|-----|-----|-----|-------|
| Reddit P1 (r/aisolobusinesses) | 30min | 30min | 30min | 30min | 2h |
| Reddit P3 (r/ClaudeAI etc.) | 30min | 30min | 30min | 30min | 2h |
| X engagement (replies) | 45min | 45min | 45min | 45min | 3h |
| X first thread | — | — | — | 30min | 30min |
| Flagship outline + angle notes | — | 1h | — | 1h | 2h |
| **Weekly total** | **1h45** | **2h45** | **1h45** | **3h15** | **9h30** |

**Sous budget** (9h30 vs 20h disponibles). Marge large intentionnelle — c'est le premier mois, le cold start est imprévisible. Le surplus absorbe :
- Gate 1 PASS mid-month → surge 4-6h pour accelerer le flagship draft
- Reddit thread viral → surge 2h pour capitaliser
- Rien → le budget non-utilisé n'est pas un échec

---

## Gate 1 Contingency

**Si Gate 1 passe en mars :**

1. Flagship outline → accélérer en full draft (4-6h surge, absorbed from surplus)
2. Publier flagship dès que draft + review founder terminés
3. Allocate 4-6h pour HN Show HN engagement (one-time)
4. Phase 2 content unlocked : .gaai tease, milestone post, expert recruitment messaging

**Si Gate 1 ne passe PAS en mars :**

1. Outline + angle notes prêts pour avril
2. 4 semaines de signal Reddit + X pour informer le flagship
3. Distribution construite (followers, karma) pour que le flagship ait des lecteurs à la publication
4. Zero wasted effort

---

## Story Drafts for Backlog

### Story Draft: Flagship Blog Post — "77+ decisions"

**Type:** Content production
**Blueprint:** content
**Pipeline:** CNT-001 → CNT-002 (mars) — CNT-003 → CNT-009 (avril, post Gate 1)

**User Story:**
As a developer building with AI coding tools (P3), I want to read a detailed account of how governed AI agents built a real SaaS so that I understand that AI governance is practical, not theoretical.

**Acceptance Criteria:**
- [ ] Content positioned: L2+L3 × BIP × P3+P4 × Blog × Credibility × ARL-0 × BP-2
- [ ] 1500-3000 words (CONTENT-STRATEGY-001 §5 blog constraint)
- [ ] Follows COMMS-001 Beats 1-7 narrative arc (first third = origin story)
- [ ] Contains ≥5 concrete data points (stories count, decisions count, test count, cost, timeline)
- [ ] Angle validated by ≥2 atomic content tests (X/Reddit) showing engagement
- [ ] Voice check passed (voice-guide.md compliance)
- [ ] Kill list cleared (COMMS-001 §0 — zero AI tell words)
- [ ] On-page SEO optimized (title tag, meta description, heading hierarchy)
- [ ] GEO optimized (AI search extractability)
- [ ] Social adaptations generated via CNT-007 (X thread + Reddit + LinkedIn draft)
- [ ] Quality gate passed (CNT-009)
- [ ] **Publication gated on Gate 1 PASS** — draft complete, publication blocked until Gate 1
- [ ] Final draft reviewed by founder before publication
- [ ] Published and moved to `published/` directory
- [ ] UTM links include `utm_content=flagship-77-decisions` for attribution tracking

**Estimated effort:** 2h in March (outline + angles), 4h in April (draft + edit + publish)
**Dependencies:** Gate 1 PASS for publication. Atomic content feedback for angle selection.

---

## Success Criteria — March 2026

Not vanity metrics. Observable signals that distribution is being built:

| Signal | Target | How to measure |
|--------|--------|----------------|
| Reddit karma gained | >100 combined | Reddit profile |
| Reddit interactions with P1 (AI freelancers) | ≥8 meaningful replies | Manual count |
| X followers (organic) | >50 | X profile |
| X replies with engagement (likes/replies) | ≥5 that got >2 interactions | X analytics |
| Flagship outline complete | Yes/No | File in drafts/ |
| Angles tested via atomic content | ≥3 distinct angles | Manual review |

---

## Governance Notes

- **First content plan ever** — distribution-first, content-second approach. The monthly review (April 1st) will assess whether distribution was actually built.
- **Correction applied:** Original plan over-indexed on flagship production (52% of budget) at expense of distribution building. Corrected to 21% flagship / 42% Reddit / 32% X engagement.
- **Measurement starts at publication :** Metrics from CONTENT-STRATEGY-001 §10 apply J+7/J+30/J+90 after first Hub published.
- **No ARL tracking this month.** ARL classification becomes useful when you have a measurable audience. For now, focus on building that audience.
