---
type: artefact
artefact_type: strategy
id: MARKET-001
track: discovery
created_at: 2026-02-24
updated_at: 2026-02-24
---

# MARKET-001: Analyse Marché — Sélection des Verticals Satellite

> Recherche data-driven pour déterminer les business verticals de lancement.
> Méthodologie : croisement de 3 axes — keyword volumes (prospect-side), expert pain scoring, gap compétitif.
> Référence décision : DEC-2026-02-24-84

---

## 1. Verticals évalués

8 business verticals candidats analysés :

| Code | Vertical | Description |
|------|----------|-------------|
| V1 | Workflow Automation | n8n, Make.com, Zapier — consultants en automatisation |
| V2 | CRM Integration | HubSpot, Salesforce, Zoho — setup, migration, customization |
| V3 | AI Chatbot / Conversational AI | Custom GPT, Voiceflow, Botpress — chatbots business |
| V4 | E-commerce Automation | Shopify, WooCommerce — automatisation e-commerce |
| V5 | Marketing Automation | Email, social, ad automation — Klaviyo, ActiveCampaign, Marketo |
| V6 | Data Pipeline & Analytics | ETL, BI dashboards — Snowflake, dbt, Power BI |
| V7 | Document Processing / RPA | UiPath, Power Automate — automatisation documentaire |
| V8 | AI Integration for SaaS | LLM/API integration — OpenAI, Claude, RAG, fine-tuning |

---

## 2. Scoring Expert Pain (7 paramètres, /35)

| Paramètre | Description | Poids |
|-----------|-------------|-------|
| Lead Gen Pain | Difficulté à trouver des clients qualifiés | 5 = très douloureux |
| Race-to-Bottom | Pression prix via Upwork/Fiverr | 5 = forte compression |
| Education Burden | Expert doit éduquer le prospect avant de vendre | 5 = très lourd |
| Incumbent Lock-in | Captivité dans un écosystème vendor | 5 = très captif |
| Deal Size | Taille moyenne d'engagement | 5 = > $10K |
| Callibrate Fit | Le modèle "consultation call payante" correspond au cycle de vente | 5 = parfait |
| Ease of Conviction | Facilité à convaincre l'expert de rejoindre | 5 = très facile |

### Matrice Expert Pain

| | V1 | V2 | V3 | V4 | V5 | V6 | V7 | V8 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Lead Gen Pain | 4 | 4 | **5** | 3 | 3 | 2 | 2 | 4 |
| Race-to-Bottom | 4 | 3 | 3 | **5** | 3 | 2 | 3 | 2 |
| Education Burden | 3 | 1 | **5** | 1 | 2 | 1 | 2 | **5** |
| Incumbent Lock-in | 2 | **5** | 1 | 4 | 4 | 4 | 4 | 1 |
| Deal Size | 3 | 4 | 3 | 2 | 3 | **5** | **5** | **5** |
| Callibrate Fit | **5** | 2 | **5** | 2 | 3 | 2 | 1 | **5** |
| Ease of Conviction | **5** | 2 | **5** | 3 | 3 | 2 | 2 | 4 |
| **TOTAL /35** | **26** | 21 | **27** | 20 | 21 | 18 | 19 | **26** |

---

## 3. Gap compétitif (où est la place pour Callibrate ?)

| Vertical | Incumbent Strength | Gap Callibrate | Notes |
|----------|:---:|:---:|-------|
| V1 Workflow Auto | 2/5 | **5/5** | Vendor directories siloés (Zapier, Make, n8n séparés). Flowmondo seul concurrent direct (petit). |
| V2 CRM | **5/5** | 1/5 | HubSpot Solutions Directory + Salesforce AppExchange = écosystèmes matures. |
| V3 AI Chatbot | 1/5 | **5/5** | Aucune marketplace structurée. Voiceflow/Botpress = micro-directories. |
| V4 E-commerce | 4/5 | 2/5 | Storetasker domine Shopify. Shopify Partners Directory mature. |
| V5 Marketing Auto | 4/5 | 2/5 | Klaviyo Connect + MarketerHire couvrent le besoin. |
| V6 Data Pipeline | 4/5 | 2/5 | Snowflake/dbt partner networks + enterprise consulting. |
| V7 RPA | 4/5 | 2/5 | UiPath/AA/Microsoft = ecosystèmes enterprise matures. |
| V8 AI Integration | 1/5 | **5/5** | AUCUNE marketplace spécialisée. GLG/AlphaSights = $1K+/hr (investors, pas builders). |

### Concurrents directs identifiés

| Concurrent | Modèle | Vertical | Menace |
|-----------|--------|----------|--------|
| Flowmondo | Agence (pas marketplace) — n8n, Make, Zapier | V1 | Faible |
| Storetasker | Marketplace Shopify-specific, top 3%, $75+ min | V4 | Forte (dans Shopify) |
| MarketerHire | Talent marketplace pré-vetté, $5K-15K/mo | V5 | Forte |
| Clarity.fm | Per-minute expert calls, 15% cut, 30K experts — GENERALISTE | V8 | Modérée (pas spécialisé) |
| Codementor | 1:1 dev help, instant matching — DEV-FOCUSED | V8 | Faible (pas business-outcome) |
| GrowthMentor | $99/mo subscription, 500+ mentors — GROWTH-FOCUSED | — | Faible (pas AI/automation) |

---

## 4. Volumes de recherche prospect-side (données clés)

### V1 — Workflow Automation

| Keyword | Volume US | Volume FR | Intent | Pain Signal |
|---------|-----------|-----------|--------|-------------|
| hire n8n developer | 200-400/mo | <100 | Transactional | 5/5 |
| workflow automation consultant | 500-1K | 100-300 | Commercial | 4/5 |
| how to automate my business | 2K-5K | 500-1K | Informational | 2/5 |
| make.com vs zapier vs n8n | 1K-3K | 200-500 | Informational | 2/5 |

**Insight :** Faibles volumes transactionnels, forts volumes informationnels. Funnel content → expert booking.

### V3 — AI Chatbot

| Keyword | Volume US | Volume FR | Intent | Pain Signal |
|---------|-----------|-----------|--------|-------------|
| build ai chatbot for business | 1K-3K | 200-500 | Commercial | 4/5 |
| custom gpt for my company | 1K-3K | 200-500 | Commercial | 4/5 |
| ai chatbot for website | 3K-8K | 500-1.5K | Commercial | 3/5 |
| chatbot consultant | 300-700 | 100-300 | Commercial | 4/5 |

**Insight :** Volume + intent forts. "Custom GPT for [industry]" = long-tail goldmine. Marché FR en retard = blue ocean.

### V8 — AI Integration for SaaS

| Keyword | Volume US | Volume FR | Intent | Pain Signal |
|---------|-----------|-----------|--------|-------------|
| hire ai developer | 1K-3K | 200-500 | Transactional | 5/5 |
| openai api integration | 1K-3K | 200-500 | Informational | 3/5 |
| ai agent developer | 500-1.5K | 200-500 | Transactional | 5/5 |
| rag implementation expert | 100-300 | <100 | Transactional | 5/5 |

**Insight :** Vocabulaire encore émergent (RAG, embeddings, agents). +178% YoY sur Upwork. Blue ocean total.

### Marché français — Observations clés

- Quasi-aucune concurrence sur les termes transactionnels FR
- Prospects FR cherchent en français pour du conseil, en anglais pour les outils spécifiques
- IT freelance FR : 181.5M€ (2023) → 650M€ (2030)
- Keywords prioritaires FR : "consultant automatisation", "consultant IA", "chatbot IA entreprise"

---

## 5. Expert-side — Pain détaillé par vertical Tier 1

### V3 — AI Chatbot (Score 27/35)

- **18 347% surge** de demande "AI agent" sur Fiverr en 6 mois (Sep 2024 - Mai 2025)
- 55% des agencies : 1-6 semaines par conversion de lead
- 38% du temps non-facturable (principalement prospection)
- Le prospect ne sait pas quel outil il lui faut → matching tool-agnostic = killer feature
- Aucune marketplace structurée n'existe

**Pitch pain killer :**
> "Tu passes 40% de ton temps à éduquer des prospects qui ne savent pas s'ils ont besoin de Voiceflow ou d'un custom GPT. Callibrate pré-qualifie le besoin (use case, budget, timeline) avant que tu ne décroches le téléphone."

### V1 — Workflow Automation (Score 26/35)

- Freelancers n8n/Make construisent des automations de lead scraping Reddit pour trouver des clients
- Upwork : 10%+ fees + race to the bottom ($39/hr médian vs $100-150/hr en direct)
- Vendor directories siloés : être expert n8n ET Make = 2 listings séparés
- "50-100 cold emails pour décrocher un premier client"
- Caio Valadares (premier prospect expert identifié) = ce profil exactement

**Pitch pain killer :**
> "Tu paies 10% à Upwork pour des leads qui comparent ton tarif avec des freelancers à $15/hr. Sur Callibrate, les prospects arrivent avec un problème décrit, un budget validé, et le matching est basé sur tes compétences — pas sur qui bid le moins cher."

### V8 — AI Integration for SaaS (Score 26/35)

- +178% demande YoY sur Upwork mais AUCUNE marketplace spécialisée
- GLG/AlphaSights : $1 350/hr, ciblent investisseurs pas builders
- Clarity.fm : généraliste. Codementor : dev-help, pas strategic consulting
- Deal sizes $5K-$50K → justifient facilement le coût d'un lead
- 89-96% de pénurie mondiale de talent AI

**Pitch pain killer :**
> "Tes prospects cherchent 'add AI to my SaaS' et tombent sur des listicles d'agences à $500K. Toi tu factures $5K-$25K mais tu es invisible. Callibrate te met face à des CTOs qui ont un budget et un use case concret."

---

## 6. Trait commun des 3 verticals gagnantes

> **Le prospect ne sait pas quel outil il lui faut.**

- V3 : "J'ai besoin d'un chatbot" → Voiceflow ? Botpress ? Custom GPT ? RAG ?
- V1 : "J'ai besoin d'automatiser" → n8n ? Make ? Zapier ? Power Automate ?
- V8 : "J'ai besoin d'IA dans mon produit" → OpenAI ? Claude ? Fine-tuning ? RAG ? Agent ?

C'est précisément là que le matching engine Callibrate apporte le plus de valeur — en faisant le tri que ni les vendor directories (siloés par outil) ni Upwork (pas de matching intelligent) ne font.

**Overlap supply :** Un seul expert peut couvrir les 3 satellites (ex: Caio = n8n + Python + Claude + React → V1 + V3 + V8).

---

## 7. Priorité de lancement

| Rang | Vertical | Expert Pain | Gap Compétitif | Volume Prospect | Callibrate Fit | Verdict |
|:---:|----------|:---:|:---:|:---:|:---:|---------|
| **1** | V3 — AI Chatbot | 27/35 | 5/5 | Med-High | 5/5 | **Lancer en premier** |
| **2** | V1 — Workflow Auto | 26/35 | 5/5 | Med | 5/5 | **Lancer en parallèle** |
| **3** | V8 — AI Integration | 26/35 | 5/5 | Med (croissant) | 5/5 | **Lancer en parallèle** |
| 4 | V2 — CRM | 21/35 | 1/5 | Very High | 2/5 | Expansion post-traction |
| 5 | V5 — Marketing Auto | 21/35 | 2/5 | High | 3/5 | Expansion post-traction |
| 6 | V4 — E-commerce | 20/35 | 2/5 | Med-High | 2/5 | Skip |
| 7 | V7 — RPA | 19/35 | 2/5 | Med | 1/5 | Skip |
| 8 | V6 — Data Pipeline | 18/35 | 2/5 | High | 2/5 | Skip |

---

## 8. Décisions ouvertes (à valider)

- **D1 — Architecture URL :** Garder sous-domaines satellites pour profils experts + subdirectories callibrate.io/ pour contenu SEO ?
- **D2 — Phasage contenu P0 :** 5-7 pages SEO avant ou après le lancement marketplace ?
- **D3 — Cartes d'empathie prospect :** À construire pour V1/V3/V8 — intention de recherche, funnel satellite, structure de contenu menant au matching engine.

---

## 9. Sources (sélection)

- Fiverr Business Trends Index Spring 2025 — 18,347% surge AI agent demand
- Upwork In-Demand Skills 2026 — AI Integration +178% YoY
- Mordor Intelligence — Workflow Automation Market $23.77B (2025)
- Precedence Research — Chatbot Market $8.57B (2025), $72.47B by 2035
- Grand View Research — RPA Market $28.31B (2025)
- MarketsandMarkets — Marketing Automation Market $47.02B (2025)
- Nick Frates — Salesforce Consulting Industry Analysis (3,400+ partners, 170K+ certified)
- Callin.io — AI Automation Agency Reddit Analysis
- Stack.expert — AI Freelancing: Rates, Projects, Getting Clients
- French AI Market — EUR 6.2B by 2025, France 2030 : 2.2Mds€ investis
- IT Freelance France — EUR 181.5M (2023) → EUR 650M by 2030

---

## 10. Scope Strategy — Niche up vs Niche down vs AI-pure (DEC-85)

### Approches évaluées

| # | Approche | Exemple | Verdict |
|---|----------|---------|---------|
| **A** | Niche down — IA × Domaine | "AI Chatbot for Healthcare" | 3/10 lancement, 7/10 post-Gate 2 |
| **B** | AI-pure (statu quo) | "AI Chatbot Expert", "n8n Consultant" | **7/10 lancement**, 5/10 long-terme exclusif |
| **C** | Niche up — Domaines larges | "Healthcare IT Consultant" | 2/10 — perte de différenciation |
| **D** | Hors IA — Expertises domaine | "Salesforce Consultant" | 1/10 — incumbents imprenables |

### Scoring combinaisons

| Combo | Score | Rationale |
|-------|:-----:|-----------|
| B seul | 7/10 | Bon lancement mais vulnérable au hype cycle long-terme |
| **B → A** | **8/10** | Lancer large (V1/V3/V8), affiner par domaine quand data montre où ça convertit |
| B + C | 3/10 | Dilution immédiate, perte de positionnement |
| B + D | 2/10 | Incumbents invincibles, pire des deux mondes |
| A seul | 3/10 | Volume insuffisant, supply inexistante, 30 chicken-and-eggs |
| **B → A → C** | **9/10** | Trajectoire optimale SI Matching OS prouvé post-M3 |

### Test de cohérence — 6 dimensions

| Dimension | B (IA pure) | A (IA×Domaine) | C (Domaines larges) | D (Hors IA) |
|-----------|:---:|:---:|:---:|:---:|
| Matching OS valorisé (prospect ne sait pas quel outil) | OUI | OUI | NON | NON |
| Supply disponible (experts existent et souffrent) | OUI | Partielle | OUI mais saturée | OUI mais captive |
| Gap compétitif (pas d'incumbent dominant) | OUI | OUI | NON | NON |
| Cohérence positionnement | OUI | OUI | NON | NON |
| Scalabilité solo founder (Phase 2) | OUI (3 satellites) | NON (30 satellites) | NON | NON |
| Résilience hype cycle | PARTIELLE | PARTIELLE | OUI | OUI |
| **Score** | **5/6** | **4/6** | **1/6** | **1/6** |

### Décision validée

- **Phase 2 (lancement) :** Approche B — AI-pure. 3 satellites. Positionnement "marketplace experts IA/automation".
- **Phase 3 (post Gate 2) :** B → A — Niche-down data-driven. Le domaine prospect qui convertit le mieux dicte le premier satellite IA×Domaine.
- **Post M3 (vision) :** B → A → éventuellement C si le Matching OS est prouvé comme actif défensif.

### Exclusions explicites

- Pas de satellite Salesforce/CRM/Shopify — gap compétitif 0, matching engine non valorisé.
- Pas de 30 micro-satellites IA×Domaine au lancement — fragmentation prématurée.
- Pas de consulting IT large — aucune différenciation vs Upwork/Toptal/Clutch.
- Le niche-down est une conséquence de la data, pas une hypothèse a priori.

---

## 11. Niche-Down Candidates : IA × Domaine (DEC-88)

> Recherche pré-Gate 2 : identifier les candidats viables pour le niche-down data-driven.
> 13 domaines évalués × 3 expertises IA = 39 combinaisons. 8 viables, 5 éliminées d'emblée.

### Méthodologie de scoring (/30)

| Paramètre | Ce qu'il mesure |
|-----------|----------------|
| Volume de recherche (1-5) | Demand-side : volume mensuel US + FR pour les keywords IA×Domaine |
| Signal Reddit/communauté (1-5) | Pain signals réels : threads, deals documentés, use cases spécifiques |
| Taille marché (1-5) | TAM du segment IA dans ce domaine |
| SMB accessibility (1-5) | Le prospect est-il un SMB qui achète via marketplace ? (vs enterprise/RFP) |
| Expert supply niche (1-5) | Existe-t-il des freelancers spécialisés IA × ce domaine ? |
| Callibrate fit (1-5) | Le modèle "consultation call payante" fonctionne-t-il pour ce cycle d'achat ? |

### Classement

| Rang | Niche-Down | Score /30 | Forces clés | Faiblesses fatales |
|:---:|-----------|:---:|-------------|---------------------|
| **1** | **Real Estate × (Chatbot + Workflow)** | **26** | SMB natif, habitué à payer pour leads, ROI mesurable (+40% conversion), cycle court, 87% adoption, $25K/mo revenue documenté, 9+ templates n8n | Plateformes PropTech existantes (chatbot standard) |
| **2** | E-commerce × (Chatbot + Workflow) | 23 | Volume recherche max (15K+ US), SMB natif, 88% adoption | Self-serve tools dominent (Tidio $29/mo, Gorgias), Storetasker |
| **3** | Healthcare × (Chatbot + Workflow) | 21 | Volume fort (8K-14K US), deals $12K, moat HIPAA, $380K/an économies | SMB accessibility faible (81% hôpitaux non-adopteurs), supply expert rare, cycle long |
| **4** | Accounting × (Workflow + AI) | 21 | CAGR 44% (plus rapide), urgence facturation électronique FR 2026-2027, 76% cabinets FR utilisent IA | Supply expert nulle, SaaS (QuickBooks AI, Pennylane) absorbe la demande |
| **5** | Legal × (Workflow + AI) | 20 | Deal $35K documenté (r/n8n), moat confidentialité (LLM self-hosted), 315% YoY croissance usage | Adoption 20% petits cabinets, supply expert quasi-nulle |
| **6** | HR/Recrutement × (Workflow + Chatbot) | 18 | EU AI Act high-risk (conformité = demande consulting), $15K/placement ROI | Outils intégrés dominent (Workday, BambooHR), saisonnier |
| **7** | Insurance × (Chatbot + AI) | 18 | CPC $16 = intent max, 8%→34% adoption en 1 an, marché $4.5B chatbot | Enterprise-only, pas de freelancers spécialisés |
| **8** | Financial Services × (AI + Chatbot) | 16 | Marché $18-30B, high CPC | Enterprise, long sales cycle, pas de SMB |

### Domaines éliminés

| Domaine | Raison d'élimination |
|---------|---------------------|
| Education | Procurement institutionnel (ministère, rectorat), VC en contraction, 46% districts ont banni l'IA |
| Construction | 78% non-adopteurs, 1.5% multi-process AI, le plus digitalement en retard |
| Manufacturing | Enterprise + hardware/IoT, legacy systems, pas de marketplace fit |
| Logistics | Enterprise-heavy, faibles signaux SMB communautaires |
| Hospitality/Restaurant | Margins razor-thin, budgets $0-$500/mo max, adoption 26% |

### Cartes d'empathie — Top 3

#### Real Estate — Prospect (Agent immo / Directeur agence)

| Dimension | |
|-----------|---|
| **Pense** | "Je rate des leads le soir et le weekend parce que personne ne répond." |
| **Ressent** | Urgence (lead immo = périmable en heures), FOMO (87% des agences utilisent déjà l'IA) |
| **Cherche** | "chatbot immobilier", "real estate chatbot", "automatiser relance prospects immobilier" |
| **Pain** | 50% des appels = touristes, suivi relance manuel, réponse soir/weekend impossible |
| **Gain espéré** | +40% conversion leads, 0 lead perdu, qualification automatique 24/7 |
| **Budget** | $500-$2K/mois recurring (habitué à payer pour des leads) |

#### Real Estate — Expert (Consultant Automatisation Immo)

| Dimension | |
|-----------|---|
| **Pense** | "En immobilier on peut facilement facturer 4 chiffres par mois." |
| **Ressent** | Opportunisme (87% adoption = marché chaud), confiance (ROI évident et mesurable) |
| **Pain** | Agents immobiliers ne traînent pas sur Upwork → pas de canal d'acquisition |
| **Gain espéré** | Un flux régulier de prospects immobiliers prêts à payer |

#### Healthcare — Prospect (Directeur de clinique)

| Dimension | |
|-----------|---|
| **Pense** | "Mes secrétaires passent 3h/jour au téléphone pour des RDV et vérifications d'assurance." |
| **Ressent** | Frustration (patients le soir sans réponse), méfiance (HIPAA/RGPD santé = risque) |
| **Pain** | Interruptions staff, vérification assurance 12min→2min automatisable, patients perdus le soir |
| **Budget** | $99-$12K/projet (variable, dental chains au haut du range) |

#### Healthcare — Expert

| Dimension | |
|-----------|---|
| **Pain** | "Mon expertise HIPAA vaut 2× le tarif générique mais les plateformes ne différencient pas." |
| **Gain espéré** | Des prospects pré-qualifiés qui comprennent le besoin conformité |

#### Legal — Prospect (Associé cabinet 5-30 pers.)

| Dimension | |
|-----------|---|
| **Pense** | "Je ne peux PAS utiliser ChatGPT avec les dossiers de mes clients. Il me faut du self-hosted." |
| **Pain** | Revue documentaire = dizaines d'heures/semaine, intake client manuel, confidentialité |
| **Budget** | $7K-$35K/projet (payback attendu en 1 trimestre) |

#### Legal — Expert

| Dimension | |
|-----------|---|
| **Pain** | "Les cabinets ne savent même pas que ça existe. Le problème c'est l'éducation, pas la compétition." |
| **Gain espéré** | Un prospect qui a DÉJÀ compris qu'il a besoin d'un système IA privé |

### Pattern stratégique identifié

**Gros marché ≠ bon marché pour Callibrate.** Les niches avec les plus gros TAM (healthcare $39B, fintech $30B, insurance $18B) sont enterprise-driven → cycle d'achat 6 mois, comités, RFP. Un call de 30 min ne correspond pas.

**Callibrate fit optimal :** Prospect = SMB/indépendant + habitué à payer pour services + cycle de décision court + ROI mesurable et immédiat.

### Décision niche-down

- **Premier candidat post-Gate 2 :** Real Estate × (Chatbot + Workflow) — si les données de conversion confirment le signal
- **Sleepers à surveiller :** Accounting (vague facturation électronique FR 2026-2027), Legal (si supply expert se développe)
- **Ne pas activer :** Healthcare, Insurance, Financial Services — enterprise procurement incompatible avec le modèle
- **Trigger :** Le niche-down s'active quand les données Phase 2 montrent ≥30% des prospects V1/V3 provenant d'un même domaine
