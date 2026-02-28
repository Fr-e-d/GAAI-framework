---
type: artefact
artefact_type: strategy
id: CONTENT-STRATEGY-001
track: discovery
created_at: 2026-02-26
updated_at: 2026-02-26
---

# CONTENT-STRATEGY-001: Content Strategy Map

> **Principe directeur :** Chaque pièce de contenu occupe une position explicite dans un espace à 6 dimensions.
> Pas de contenu orphelin — si une pièce ne peut pas être placée dans la matrice, elle n'est pas produite.
>
> **Relations :** GTM-001 (phases/gates), COMMS-001 (empathy maps, channel strategy, writing style), MARKET-001 (verticals, niche strategy)
> **Knowledge base :** `memory/domains/content-production/` (10 sources, 141 AKUs, 9 research domains)
> **Skills :** `skills/domains/content-production/` (CNT-001 → CNT-010)

---

## 1. Modèle 6 Dimensions

Chaque pièce de contenu est définie par 6 coordonnées :

```
PIÈCE DE CONTENU = f(Layer, Phase, Audience, Channel, Objective, ARL)

Exemples :
  "How .gaai memory works"       = L3 × BIP × P3 × Blog × Credibility × ARL-2
  "I governed AI to build a SaaS" = L1 × BIP × P3+P4 × HN × Awareness × ARL-0
  "Finding the right AI expert"   = L1 × Growth × P2 × Reddit × Education × ARL-1
```

Les dimensions sont **indépendantes mais contraignantes** : chaque combinaison doit être cohérente. Une pièce L4 (Domain) sur HN (qui attend de la profondeur technique) ciblant P2 (PME non-technique) est une contradiction — la matrice l'empêche.

---

## 2. Dimension 1 — Layer (Quoi)

L'arbre de contenu. Chaque layer est le "how" du layer au-dessus.

```
L1  PRODUCT (Callibrate)
│   Quoi : le produit, sa valeur, ses résultats
│   Angle : problème → solution → résultats mesurables
│   Exemples : "Comment trouver un expert AI en 48h", case studies, conversion metrics
│
├── L2  PROCESS (Build Journey)
│   Quoi : comment on construit le produit
│   Angle : décisions, trade-offs, échecs, métriques de delivery
│   Exemples : "19 PRs sans merge — ne faites jamais ça", "39 stories en 4 jours"
│
│   ├── L3  FRAMEWORK (.gaai)
│   │   Quoi : le framework de gouvernance AI
│   │   Angle : architecture, patterns, résultats reproductibles
│   │   Exemples : "Dual-Track: séparer la réflexion de l'exécution", "memory engineering"
│   │
│   │   └── L4  DOMAIN (Blueprints)
│   │       Quoi : domaines spécifiques au sein du framework
│   │       Angle : méthodologie, knowledge base, application domain-specific
│   │       Exemples : "Content Architect: 10 skills, 141 AKUs", "SEO for AI-generated content"
│   │
└── (cross-link) L2 → L3 : "here's the framework that made this possible"
```

### Règles de navigation inter-layers

- **Top-down tease :** Chaque contenu L(n) doit teaser L(n+1) — "voici le framework derrière" ou "voici le détail technique"
- **Bottom-up proof :** Chaque contenu L(n) utilise L(n-1) comme preuve — "voici le produit construit avec ce framework"
- **Max 2 layers par pièce :** Un blog post peut couvrir L2+L3, jamais L1+L2+L3+L4. Le multi-layer dilue le message
- **L4 requiert L3 établi :** Ne pas publier sur les blueprints domain-specific avant que le framework soit compris (ARL-2 minimum pour l'audience)

---

## 3. Dimension 2 — Phase (Quand)

Alignée sur les phases GTM-001. Chaque phase autorise un type de contenu.

| Phase | GTM | Contenu autorisé | Contenu interdit |
|-------|-----|------------------|-----------------|
| **Ideation** | Phase 0 — Signal | Observations marché, questions ouvertes, engagement communautaire | Claims produit, métriques (rien à mesurer) |
| **Implementation** | Phase 1 — Fondations | Décisions techniques, architecture, trade-offs | Revenue claims, user testimonials (pas encore d'users) |
| **BIP** (Build-in-Public) | Gate 1 → Phase 2 | Métriques delivery, milestones, flagship posts, .gaai tease | Pricing, conversion funnel details |
| **Growth** | Phase 2 → Phase 3 | Case studies, user stories, revenue metrics, .gaai OSS | Rien d'interdit si les données existent |

### Règle de phase

> Le contenu ne peut pas anticiper la phase. Pas de case study avant un vrai case. Pas de revenue sharing avant du revenu. Le build-in-public montre le présent, pas le futur.

---

## 4. Dimension 3 — Audience (Pour qui)

4 personas (détaillées dans COMMS-001 Part 1 — Empathy Maps) :

| Persona | Qui | Besoin principal | Contenu prioritaire |
|---------|-----|-----------------|---------------------|
| **P1** Expert AI/Automation | Caio Valadares archetype | Leads qualifiés, pipeline prévisible | L1 (produit), L2 (process — social proof) |
| **P2** Prospect PME | Dir. Ops SaaS 30 personnes | Trouver le bon expert sans perdre 3 mois | L1 (produit — éducation), L2 (transparence) |
| **P3** Developer/AI Builder | Solo dev Claude Code | Persistent memory, governance, framework | L2 (process), L3 (framework), L4 (domain) |
| **P4** AI Industry/Recruiters | DevRel Anthropic archetype | Preuve d'exécution, depth of thinking | L2 (process), L3 (framework) |

### Dual-Audience Tracks (Supply vs Demand)

> Callibrate est une marketplace. Les deux côtés du marché ont des besoins de contenu structurellement différents.

```
SUPPLY TRACK (P1 — Experts)              DEMAND TRACK (P2 — Prospects)
──────────────────────────────            ──────────────────────────────
"Comment obtenir des leads               "Comment trouver le bon expert
 qualifiés sans hustle"                    AI sans y passer 3 mois"

"Maximiser son taux horaire              "Quoi attendre d'un spécialiste
 avec des clients pré-filtrés"             IA — guide pour décideurs"

Success stories d'experts                 Comparatifs : Upwork vs niche
                                          vs Callibrate

Cadence supply-side : récurrente          Cadence demand-side : SEO-driven
(pipeline motivation)                     (intent capture)
```

**Ratio par phase (supply-first strategy — NFx) :**

| Phase | Supply (P1) | Demand (P2) | Builder (P3+P4) |
|-------|-------------|-------------|-----------------|
| Phase 0-1 (J0-J21) | 20% | 0% | 80% |
| Phase 2 (J21-J45) | 40% | 20% | 40% |
| Phase 3 (J45-J90) | 30% | 30% | 40% |
| Post-J90 | Rééquilibrer selon données conversion |

**Rationale :** Avant Gate 1, pas de produit à vendre → contenu 100% build-in-public (P3+P4). Supply-first en Phase 2 : résoudre le chicken-and-egg en attirant d'abord les experts (ils sont plus engagés, chaque expert sert N prospects). Demand-side scale en Phase 3 quand le supply est prouvé.

---

## 5. Dimension 4 — Channel (Où)

Chaque channel impose des **contraintes hard** : format, longueur, ton, algorithme. Le channel n'est pas un point de distribution — c'est un moule.

| Channel | Format | Longueur | Ton (voice-guide.md §VI) | Audience | Fréquence |
|---------|--------|----------|--------------------------|----------|-----------|
| **Blog** (Substack) | Long-form, données, code | 1500-3000 mots | Analytique, Paul Graham depth | P3, P4, P1 | 1x/mois |
| **X/Twitter** | Threads 5-12 tweets | 280 chars/tweet | Direct, irrévérencieux, hooks | P3, P4 | 2-3x/semaine |
| **Reddit** | Self-post, TL;DR first | 300-800 mots | Authentique, casual, jamais pitch | P1, P2, P3 | 3-4 interactions/sem |
| **HN** | Link + first comment | Titre factuel, comments illimités | Zéro hype, technique, factuel | P3, P4 | 3-4 Show HN TOTAL |
| **dev.to** | Tutorial, code blocks | 1000-2000 mots | Accessible, step-by-step | P3 | 1x/mois (cross-post) |
| **LinkedIn** | Post unique | 1200-1800 chars | Professionnel, réflexif, "I" | P1, P2, P4 | DIFFÉRÉ → lancement |
| **GitHub** | README, examples | Variable | Documentation technique | P3, P4 | DIFFÉRÉ → Gate 2 |

### Hub vs Native

| Type | Définition | Pipeline | Exemple |
|------|-----------|----------|---------|
| **Hub** | Blog post source qui génère des dérivés | CNT-001 → CNT-006 → CNT-007 (adapt) | Blog post → X thread + Reddit + LinkedIn |
| **Native** | Contenu né sur la plateforme, spontané | Pas de pipeline formel | Reply Reddit, tweet réactif, commentaire HN |

**Règle :** Le Hub est planifié (backlog). Le Native est spontané (time-boxé à 30 min max par interaction). Les deux comptent dans le budget 5h/semaine (COMMS-001 constraint).

---

## 6. Dimension 5 — Objective (Pourquoi)

Chaque pièce de contenu sert un objectif explicite dans le funnel.

### Funnel d'objectifs

```
AWARENESS      "Ce problème existe et quelqu'un le résout"
    ↓
CREDIBILITY    "Cette personne sait de quoi elle parle"
    ↓
TRUST          "Je fais confiance à cette approche"
    ↓
EDUCATION      "Je comprends comment ça marche"
    ↓
CONVERSION     "Je veux essayer / m'inscrire / contacter"
    ↓
RETENTION      "Je reviens, je recommande, je reste engagé"
```

### Business Potential Score (BP)

Chaque pièce de contenu reçoit un score **Business Potential (0-3)** inspiré du framework BREW (Ahrefs) :

| Score | Définition | Exemple |
|-------|-----------|---------|
| **BP-3** | Le produit est la solution indispensable au problème traité | "How Callibrate matches AI experts in 48h" |
| **BP-2** | Le produit aide significativement mais n'est pas le sujet central | "How I built a marketplace solo — .gaai governed AI agents" |
| **BP-1** | Le produit est mentionnable mais pas central | "Best practices for AI agent memory management" |
| **BP-0** | Aucun lien produit. Crédibilité pure ou communauté. | "Why most AI governance frameworks fail (opinion)" |

### Règle de priorisation

> **Publier en priorité les pièces à BP élevé, quel que soit l'ARL cible.**
> Le BP détermine la priorité de production. L'ARL détermine le prérequis d'éducation du lecteur — pas l'ordre de publication.
>
> En pratique : un article BP-3 ciblant ARL-3 (le lecteur connaît déjà le problème et les solutions existantes) peut et doit être publié avant un article BP-0 ciblant ARL-0, car il convertit immédiatement auprès d'un public restreint mais prêt.

**Scoring cible par phase :**

| Phase | BP-3 | BP-2 | BP-1 | BP-0 |
|-------|------|------|------|------|
| Phase 0-1 | 0% | 20% | 40% | 40% |
| Phase 2 | 20% | 30% | 30% | 20% |
| Phase 3 | 30% | 30% | 20% | 20% |

---

## 7. Dimension 6 — ARL (Audience Readiness Level)

L'ARL mesure l'état de connaissance du lecteur par rapport au sujet. Adapté des 5 Stages of Awareness de Schwartz.

| ARL | État du lecteur | Contenu type | Schwartz equiv. |
|-----|----------------|-------------|-----------------|
| **ARL-0** | Ne sait pas que le problème existe | Thought leadership, provocations, "did you know?" | Unaware |
| **ARL-1** | Conscient du problème, pas des solutions | Problem-focused content, pain amplification, education | Problem Aware |
| **ARL-2** | Connaît les solutions possibles, pas la nôtre | Comparatifs, "how I solved X", frameworks | Solution Aware |
| **ARL-3** | Connaît notre solution, évalue | Demo, case studies, social proof, pricing transparency | Product Aware |
| **ARL-4** | Prêt à agir, cherche la confirmation finale | Testimonials, guarantees, onboarding guides, "start here" | Most Aware |

### ARL = classification, PAS séquençage

> **Règle critique :** L'ARL classifie le prérequis de connaissance du lecteur. Il ne dicte PAS l'ordre de publication.
>
> Un solo founder n'a pas le luxe d'éduquer le marché pendant 6 mois avant de convertir. L'approche Pain Point SEO (Grow & Convert) prouve que le contenu bottom-of-funnel (ARL-3/4, BP-3) convertit immédiatement — même sans audience ARL-0 préalable.

**Matrice ARL × Objective :**

| | Awareness | Credibility | Trust | Education | Conversion | Retention |
|---|---|---|---|---|---|---|
| **ARL-0** | PRIMARY | possible | — | — | — | — |
| **ARL-1** | possible | PRIMARY | possible | PRIMARY | — | — |
| **ARL-2** | — | possible | PRIMARY | PRIMARY | possible | — |
| **ARL-3** | — | — | possible | possible | PRIMARY | possible |
| **ARL-4** | — | — | — | — | PRIMARY | PRIMARY |

PRIMARY = l'objectif naturel pour ce niveau ARL. possible = peut servir cet objectif. — = incohérent.

---

## 8. Règles de publication

### 8.1 Séquençage — Bottom-up par Business Potential

```
PRIORITÉ DE PRODUCTION (dans l'ordre) :

1. BP-3 + ARL-2/3  → contenu à conversion directe (ex: "Callibrate vs Upwork pour trouver un expert AI")
2. BP-2 + ARL-1/2  → contenu à crédibilité + product awareness
3. BP-1 + ARL-0/1  → thought leadership + awareness
4. BP-0             → communauté pure, goodwill

Exception : le contenu BP-0 natif (Reddit replies, X engagement) ne suit pas cette hiérarchie
car il coûte <30 min et alimente la présence communautaire en continu.
```

### 8.2 Pré-requis de publication

| Pré-requis | Condition | Vérification |
|-----------|-----------|-------------|
| **Phase gate** | Le contenu ne peut pas anticiper la phase GTM | Check dim. Phase avant publication |
| **Données existent** | Toute claim quantitative doit être traçable | Source dans la pièce ou en note |
| **Voice check** | Conforme à voice-guide.md | CNT-004-edit ou CNT-009-quality-gate |
| **Kill list** | Aucun mot de la kill list (COMMS-001 §0) | Automated check dans CNT-009 |
| **Channel fit** | La pièce respecte les contraintes du channel | Check dim. Channel |
| **Founder review** | Chaque pièce publiée est reviewée manuellement | Hard rule — pas d'auto-publish |

### 8.3 Cadence budget

Budget total : **5h/semaine** (COMMS-001 constraint). Répartition indicative :

| Activité | Temps | Type |
|---------|-------|------|
| Hub content production (1 pièce/mois) | 2h | Planifié (CNT pipeline) |
| Social adaptation (CNT-007 sur le hub) | 30 min | Planifié |
| Native content (Reddit, X, engagement) | 1h30 | Spontané (time-boxed) |
| Review & publication | 30 min | Planifié |
| Community engagement (réponses) | 30 min | Spontané |

---

## 9. Transparency Policy (Build-in-Public)

> Le build-in-public n'est pas "tout partager" — c'est "partager stratégiquement avec authenticité".

### 3 niveaux de transparence

| Niveau | Quoi | Exemples |
|--------|------|---------|
| **Always share** | Architecture decisions, tool choices, dev metrics (stories/week, test coverage), market research findings, delivery process, trade-offs, échecs | DEC log entries, "why I chose Cloudflare Workers over Vercel", "19 PRs sans merge" |
| **Share with delay** | Revenue metrics (après validation), growth tactics (après preuve), conversion rates | "Month 3: €1,500 GMV" (seulement post-Gate 3) |
| **Never share** | User PII, security configs, API keys, competitive intelligence sources, pricing strategy pre-lancement, expert identities pre-consent | DB schemas with PII fields, Turnstile secrets, expert contact details |

### Règle de temporalité

> Le BIP montre le passé et le présent. Jamais le futur non-livré. "Voici ce qu'on a construit" ≠ "voici ce qu'on va construire" (hype sans substance).

---

## 10. Measurement Framework

### Metrics par Objective

| Objective | Primary Metric | Secondary Metric | Source | Seuil minimum (J+30) |
|-----------|---------------|-----------------|--------|----------------------|
| **Awareness** | Organic impressions | New unique visitors | GSC / PostHog | >500 impressions/mois |
| **Credibility** | Domain mentions / backlinks | Social shares (non-self) | GSC / manual | >5 mentions/mois |
| **Trust** | Return visitor rate | Email subscribers | PostHog | >15% return rate |
| **Education** | Time on page / scroll depth | Content completion rate | PostHog | >3 min avg / >60% scroll |
| **Conversion** | Lead form submissions (prospect quiz) | Expert registration starts | PostHog | >5 submissions/mois |
| **Retention** | Repeat engagement (2+ visits/30d) | Referral traffic | PostHog | >10% repeat rate |

### Content-Market Fit Validation

> Pas de métriques globales. Chaque pièce est évaluée individuellement.

**Feedback loop :**

```
PUBLIER → MESURER (J+7, J+30, J+90) → DÉCIDER → AGIR

Mesurer :
  - J+7  : engagement initial (shares, comments, saves)
  - J+30 : trafic organique + position keyword (si SEO-targeted)
  - J+90 : conversion attribution (si BP-2/3)

Décider (via CNT-010-repurpose) :
  - Metrics au-dessus du seuil    → SCALE (plus de distribution, repurpose)
  - Metrics au seuil               → HOLD (attendre J+90)
  - Metrics sous le seuil          → DIAGNOSE

Diagnostiquer :
  - High impressions, low CTR      → Meta refresh (titre + description)
  - Low impressions                 → Distribution problem (pas un content problem)
  - High traffic, low engagement   → Intent mismatch (ARL mal calibré)
  - High engagement, no conversion → Conversion path absent (BP-0 déguisé en BP-2)
```

**Seuil de pivot stratégique :**

> Si après 3 pièces Hub publiées (≥J+90 chacune), aucune ne dépasse les seuils minimums de sa catégorie Objective : réévaluer l'angle stratégique complet. Ne pas itérer indéfiniment sur la même approche.

---

## 11. Content Production Pipeline

### Pipeline Hub (planifié)

```
CNT-001-research      Keyword research + topic validation + BP scoring
    ↓
CNT-002-outline       Structure + heading hierarchy + sources
    ↓
CNT-003-draft         First draft (voice-guide.md loaded)
    ↓
CNT-004-edit          Editorial review + kill list + voice check
    ↓
CNT-005-seo-optimize  On-page SEO (title, meta, headings, internal links, structured data)
    ↓
CNT-006-geo-optimize  GEO optimization (AI search extractability, citations)
    ↓
CNT-007-social-adapt  X thread + LinkedIn + Reddit + carousel (platform derivatives)
    ↓
CNT-009-quality-gate  Final check before publication

POST-PUBLICATION :
CNT-010-repurpose     Review cycle (J+30/J+90) → refresh/retire/repurpose decision
```

### Pipeline Native (spontané)

```
Pas de pipeline formel.
Voice-guide.md chargé mentalement (founder connaît les règles).
Time-box : 30 min max par interaction.
Pas de CNT-009 quality gate (coût/bénéfice insuffisant pour du natif).
```

---

## 12. Exemples — Matrice appliquée

### Premiers contenus par phase

**Phase 1 (J0-J21) — Implementation :**

| Titre | Layer | Phase | Audience | Channel | Objective | ARL | BP |
|-------|-------|-------|----------|---------|-----------|-----|-----|
| "Decision of the week" threads | L2 | Impl | P3, P4 | X | Credibility | ARL-1 | BP-1 |
| Engagement Reddit r/ClaudeAI | L3 | Impl | P3 | Reddit | Awareness | ARL-0 | BP-0 |
| Engagement Reddit r/aisolobusinesses | L1 | Impl | P1 | Reddit | Trust | ARL-1 | BP-0 |

**Phase 2 — BIP + Premier cohort :**

| Titre | Layer | Phase | Audience | Channel | Objective | ARL | BP |
|-------|-------|-------|----------|---------|-----------|-----|-----|
| Flagship post "77 decisions" | L2+L3 | BIP | P3, P4 | Blog → HN → dev.to | Awareness + Credibility | ARL-0 | BP-2 |
| "Finding the right AI expert in 48h" | L1 | Growth | P2 | Blog → Reddit | Education | ARL-1 | BP-3 |
| "Why experts leave Upwork" | L1 | Growth | P1 | Reddit → Blog | Trust | ARL-2 | BP-3 |
| ".gaai: persistent memory for Claude Code" | L3 | BIP | P3 | Blog → X → HN | Credibility | ARL-1 | BP-1 |

**Phase 3 — Monétisation :**

| Titre | Layer | Phase | Audience | Channel | Objective | ARL | BP |
|-------|-------|-------|----------|---------|-----------|-----|-----|
| Case study complet (10 experts, X bookings) | L1 | Growth | P1, P2 | Blog → LinkedIn | Conversion | ARL-3 | BP-3 |
| ".gaai OSS — here's how to govern your AI agents" | L3 | BIP | P3 | GitHub → HN → Blog | Conversion | ARL-2 | BP-2 |
| Revenue report transparent (GMV, conversion, NPS) | L1+L2 | Growth | P4 | Blog → X | Trust | ARL-2 | BP-2 |

---

## 13. Anti-patterns

| Anti-pattern | Pourquoi c'est un problème | Comment l'éviter |
|-------------|---------------------------|-----------------|
| Publier L4 avant L3 | L'audience ne comprend pas le framework → le domain-specific est incompréhensible | Vérifier ARL-2 minimum pour P3 avant L4 |
| BP-0 majoritaire | Crédibilité sans conversion = hobby, pas business | Maintenir ≥40% BP-2/3 en Phase 2+ |
| Contenu ARL-0 uniquement | Éduquer sans convertir = audience qui ne paie jamais | Appliquer le séquençage bottom-up par BP |
| Multi-layer dans une pièce | L1+L2+L3 dans un post = aucun message clair | Max 2 layers adjacents par pièce |
| Claims sans données | "Notre matching est excellent" sans chiffres = hype | Phase gate : pas de claim avant la donnée |
| Channel mismatch | Tutorial sur X (trop court) ou hook tweet sur blog (tonalité) | Vérifier dim. Channel avant production |
| Supply/Demand mélangés | Parler aux experts ET prospects dans la même pièce | 1 persona primaire par pièce, max 1 secondaire |
| Over-production | >5h/semaine = burnout founder solo | Respecter le budget. Le natif est time-boxé. |

---

## 14. Gouvernance

### Revue stratégique

| Fréquence | Action | Déclencheur |
|-----------|--------|-------------|
| **Hebdomadaire** | Budget check : ≤5h ? Ratio BP respecté ? | Chaque dimanche soir |
| **Mensuelle** | Metrics review par Objective (§10). Prochain Hub planifié. | 1er du mois |
| **Trimestrielle** | Content lifecycle audit (CNT-010-repurpose). ARL recalibration. | Après chaque Gate |
| **Ad hoc** | Pivot si 3 Hub sous seuil (§10). Niche-down trigger ≥30% (DEC-88). | Signal data |

### Ce document NE couvre PAS

- Le style d'écriture détaillé → voice-guide.md
- Les empathy maps et channel playbooks → COMMS-001
- Les phases GTM et gates → GTM-001
- Les verticales et niche strategy → MARKET-001
- La knowledge base technique → domains/content-production/index.md
- L'exécution des skills individuels → skills/domains/content-production/CNT-*.md

Ce document est la **carte de navigation**. Les autres documents sont les **instruments de bord**.
