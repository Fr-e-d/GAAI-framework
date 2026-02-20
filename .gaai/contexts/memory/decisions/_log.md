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

### DEC-2026-02-19-27 — Critères de Matching : Verticaux, Extensibles, Configurés par satellite_configs

**Context:** Les critères de matching (langue, localisation, remote/présentiel, disponibilité, budget, stade de projet, secteur, stack) ne sont pas universels — ils varient selon le vertical et selon chaque expert. Les encoder en colonnes fixes crée des migrations coûteuses à chaque nouveau vertical.
**Decision:** Tous les critères de matching sont verticalement configurés via `satellite_configs.quiz_schema` (côté prospect) et `expert.preferences` JSONB (côté expert). Les critères universels minimaux (langue, mode de travail, disponibilité, budget range, stade de projet accepté) sont toujours présents. Les critères verticaux spécifiques (stack, secteur, certifications, etc.) sont définis par le satellite_config du vertical. Ajouter un vertical = ajouter une config, pas modifier le schéma.
**Rationale:** Domain-agnostic par design (DEC-18/22). Un vertical formation a des critères différents d'un vertical AI consulting (QUALIOPI, format présentiel/distanciel, durée, taille de groupe, etc.). Encoder ces différences dans le JSONB + config est la seule approche scalable.
**Impact:** `satellite_configs.quiz_schema` définit les champs extraits par l'IA pour les prospects de ce vertical. `expert.preferences` JSONB contient les critères universels + les critères verticaux spécifiques. E06S05 matching engine lit les deux et score en conséquence.
**Date:** 2026-02-19

---

### DEC-2026-02-19-31 — GTM Reséquencé : Build + Learn → Launch Simultané

**Context:** Founder employé à un poste clé — ne peut pas publier sur LinkedIn sans risquer de créer de la panique dans son équipe et sa hiérarchie. LinkedIn était le canal primaire de Gate 0 (Hand Raiser). Cette contrainte bloque E01S02 et E01S03 tels que définis.
**Decision:** Séquence GTM révisée : (1) Build (E06) + Learn (E01S01 Reddit) en parallèle — maintenant. (2) LinkedIn activé comme levier de lancement simultané quand l'infrastructure tient et que le produit peut absorber le signal et s'adapter. X/Twitter possible comme canal de validation partielle sans risque professionnel. Gate 0 (Hand Raiser) redéfini : validation partielle via Reddit + X/Twitter maintenant, validation complète via LinkedIn au lancement. E01S02 et E01S03 passent à `deferred`.
**Rationale:** La contrainte professionnelle est réelle et non-négociable. L'architecture domain-agnostic et le modèle hypothesis-driven atténuent le risque de builder sans validation LinkedIn complète. LinkedIn au lancement avec un produit fonctionnel + manifeste + signal Reddit accumulé = position plus forte qu'un Hand Raiser à vide à J+3. "Organique" ne signifie pas "passif" — Reddit continue de générer du signal terrain utile.
**Impact:** E01S02, E01S03 → `deferred`. E06 démarre immédiatement (indépendant de la validation LinkedIn). GTM Phase 0 restructuré. Manifeste rédigé maintenant pour usage au lancement (MANIFESTO-001).
**Date:** 2026-02-19

---

### DEC-2026-02-19-30 — Billing Conditionnel + Anti-Gaming Auto-Régulé

**Context:** Facturer l'expert à la confirmation de booking (Cal.com webhook) crée un risque de churn si le lead est de mauvaise qualité (no-show, hors-scope). Un système de dispute manuel est incompatible avec le modèle solo founder. Il faut une mécanique qui protège l'expert honnête et pénalise naturellement le fraudeur.
**Decision:** L'expert n'est facturé que sur un lead confirmé qualifié. Flux : (1) Call confirmé → lead en statut `pending` → `billing_deadline_at = now() + 7 days`. (2) Expert peut flag "non qualifié" dans les 7 jours → pas de billing, flag enregistré. (3) Silence ou confirmation explicite au bout de 7 jours → Lemon Squeezy checkout déclenché automatiquement. Anti-gaming : `qualification_rate = leads_confirmed / total_leads` est un composant du composite_score. Expert qui flag systématiquement → `qualification_rate` chute → composite_score baisse → moins visible dans le matching → moins de leads. Pas de sanction explicite — le système se régule naturellement.
**Rationale:** Aligne parfaitement les incentives : experts honnêtes paient leurs bons leads et montent dans le ranking. Fraudeurs descendent et reçoivent moins de leads. Zéro overhead de support ou de dispute. La conséquence est graduelle et proportionnelle. Silence = satisfait = facturé (un expert insatisfait prend la peine de flag — l'inaction est un signal positif).
**Impact:** `leads.qualification_status` (pending / confirmed / flagged) + `leads.billing_deadline_at`. E06S06 : billing queue consumer vérifie billing_deadline_at — déclenche checkout si deadline atteinte sans flag. Composite score (DEC-19) : `qualification_rate` ajouté comme composant — remplace ou complète `hire_rate`. E05S01/S02 : flux revu — expert peut flag dans les 7j, sinon checkout auto. DEC-14 : billing trigger = confirmation expert ou silence 7j (pas Cal.com webhook direct).
**Date:** 2026-02-19

---

### DEC-2026-02-19-29 — Préférences Expert : Toujours Visibles, Éditables et Réinitialisables

**Context:** Un système qui apprend les préférences en silence crée des boîtes noires. Un expert dont les critères se sont progressivement restreints sans qu'il le sache peut se retrouver sans leads et sans comprendre pourquoi — scénario de churn silencieux.
**Decision:** Le système observe le comportement de l'expert (leads acceptés/déclinés, scores J+48, taux de conversion) et génère des **suggestions de mise à jour de profil** — jamais des modifications automatiques. La config de l'expert ne change que sur son accord explicite ("Appliquer" dans le dashboard). Pas de flags `source: inferred/manual`, pas de différenciation UI complexe. Observer → Suggérer → Expert approuve. C'est tout. L'expert peut modifier ses critères à tout moment depuis le dashboard, indépendamment de toute suggestion.
**Rationale:** Appliquer silencieusement des préférences déduites — même si visibles et éditables — introduit de la complexité d'implémentation (flags JSONB, UI différenciée) et un risque résiduel d'impact non voulu. Le modèle Suggest + Approve est plus simple, plus sûr, et plus respectueux de l'agentivité de l'expert. Les humains changent : leurs critères aussi. Rien ne doit figer sans leur accord.
**Impact:** E02S04 (dashboard expert) : section "Ton profil de matching" — affiche les critères actifs en langage clair + bouton d'édition libre. Notification suggérée après N leads : "Basé sur ton activité récente, on suggère d'ajuster ton profil → [Voir la suggestion]". Expert approuve ou ignore. E06S09 : écrit les suggestions dans `expert.preference_suggestions` JSONB — ne touche jamais à `expert.preferences` directement.
**Date:** 2026-02-19

---

### DEC-2026-02-19-28 — Critères Expert : 3 Couches (Hard Constraints / Soft Preferences / Learned)

**Context:** Les experts n'ont pas tous les mêmes attentes. Capturer toute cette diversité à l'onboarding crée de la friction et de la complexité d'implémentation. Ne rien capturer produit un matching grossier. La solution est une architecture à 3 couches progressive.
**Decision:** Les critères expert sont organisés en 3 couches : (1) **Hard constraints** — filtres binaires non-négociables capturés à l'onboarding (budget min, langues, mode remote/présentiel/hybrid, zone géographique) — 5 questions max, pas de match si non respectés. (2) **Soft preferences** — facteurs de scoring capturés à l'onboarding et éditables depuis le dashboard (secteurs préférés, stade de projet, type de relation client one-shot/récurrent, complexité technique) — influencent le score sans éliminer. (3) **Learned preferences** — émergent du comportement dans le temps (leads acceptés/déclinés, scores J+48, taux de conversion) — le matching engine affine les poids automatiquement par expert sans saisie. Les 3 couches sont stockées dans `expert.preferences` JSONB.
**Rationale:** La diversité des experts (junior cherchant volume, senior high-ticket only, expert cherchant récurrence, expert testant un nouveau secteur) ne peut pas être entièrement capturée upfront sans friction excessive. Les contraintes dures filtrent les mismatches évidents. Les préférences souples donnent la subtilité dès J0. Le feedback loop apprend le reste. Complexité d'implémentation minimale — JSONB absorbe les 3 couches sans migration.
**Impact:** E02S02 : onboarding = 5 questions hard constraints + profiling light soft preferences. Dashboard expert : édition des soft preferences post-onboarding. E06S09 : observe le comportement et génère des suggestions de config — ne modifie jamais `expert.preferences` directement (voir DEC-29).
**Date:** 2026-02-19

---

### DEC-2026-02-19-26 — Expert Onboarding : Profiling de Positionnement Marché (pas formulaire de critères bruts)

**Context:** Demander à un expert de remplir des critères de matching abstraits ("budget minimum", "stade de projet accepté") est une mauvaise UX et produit des données de mauvaise qualité. Les experts ne pensent pas en critères — ils pensent en positionnement marché.
**Decision:** L'onboarding expert est un profiling de positionnement marché structuré, pas un formulaire de critères. Le profiling couvre : (1) stade de carrière / ambition (junior cherche expérience et volume → critères larges / medior sélectionne / senior high-ticket only → critères stricts) ; (2) mode de travail (remote only / présentiel possible / hybrid) ; (3) disponibilité (freelance full-time / side projects / X jours/semaine) ; (4) secteurs maîtrisés ; (5) budget confortable ; (6) stade de projet accepté (exploration / scope défini / exécution urgente) ; (7) langues de travail ; (8) zone géographique si présentiel. Le profiling génère automatiquement `expert.preferences` JSONB — l'expert décrit son positionnement, le système traduit en critères de matching.
**Rationale:** UX plus naturelle = données plus précises = meilleur matching. La segmentation junior/medior/senior est un critère de matching à part entière : un prospect avec €500 et projet early-stage matche mieux avec un junior cherchant de l'expérience qu'avec un senior high-ticket. Les deux y gagnent — c'est de la précision, pas une dégradation.
**Impact:** E02S02 révisé : UI de profiling de positionnement (pas formulaire de critères). Génère `expert.preferences` JSONB incluant `career_stage`, `work_mode`, `availability`, `budget_min`, `project_stage_accepted[]`, `languages[]`, `geo_zone`, `industries[]`. E06S05 matching engine utilise ces champs pour scorer.
**Date:** 2026-02-19

---

### DEC-2026-02-19-25 — Qualification des Prospects : Critères par Expert, Pas de Standard Universel

**Context:** La promise expert "budget confirmé, décisionnaire identifié, projet défini" suggérait un standard universel de qualification. Cela crée un problème structurel : si tous les experts filtrent au même seuil élevé, les prospects moins qualifiés n'ont aucun match et sont abandonnés.
**Decision:** Il n'existe pas de prospect "non qualifié" globalement. La qualification est relative aux critères de chaque expert. Chaque expert configure ses propres seuils dans son profil (budget min, stade de projet accepté, décisionnaire requis, secteurs). Le matching engine score chaque prospect contre les critères de chaque expert individuellement. Un prospect "froid" obtient un faible score chez un expert senior, mais un score correct chez un expert qui accepte les projets early-stage. Aucun prospect n'est abandonné — il existe toujours un expert configuré pour l'accueillir, reflété dans son ranking.
**Rationale:** Le bi-directionnel matching est l'actif fondamental. Le "rejet" d'un prospect par l'Expert A = match potentiel avec Expert B ou C (DEC-23). Un standard universel de qualification détruirait ce mécanisme. La seule exception : si la confidence AI est trop faible sur tous les champs critiques → E03S02 invite le prospect à préciser avant matching (pas un abandon, une invitation à clarifier).
**Impact:** `expert.preferences` JSONB contient les critères individuels de chaque expert. E02S02 : UI de configuration de ces critères. E06S05 : matching engine score contre `expert.preferences` de chaque expert, pas contre un seuil global. Promise expert révisée : "Reçois des prospects qui matchent tes critères — budget, secteur, stade de projet — directement dans ton agenda, sans filtrage de ta part."
**Date:** 2026-02-19

---

### DEC-2026-02-19-24 — Match Results : Ranked List Complet (pas de limite top 3)

**Context:** DEC-15 mentionnait "top-3 anonymized" pour la logique de gate email. Cette formulation a été interprétée à tort comme une limite de résultats. L'UX correcte est un ranked list complet.
**Decision:** Le reveal de matching affiche tous les experts matchés, rankés par composite_score + per-criterion breakdown visible. Les premiers sont les plus pertinents (score global le plus élevé). Le prospect scrolle librement. Pas de limite artificielle à 3 résultats.
**Rationale:** Limiter à 3 crée une perte de valeur prospect (le bon expert peut être #4 ou #5), réduit l'exposition des experts moins bien scorés mais pertinents sur des critères spécifiques, et réduit le volume de bookings potentiels. Le modèle correct est Google : tous les résultats, les meilleurs en premier. La décision DEC-15 portait uniquement sur la gate email (montrer de la valeur avant de demander un email), pas sur le nombre de résultats affichés.
**Impact:** E06S07 : endpoint retourne tous les matches rankés, pas top-3 uniquement. E03S03 : UI affiche ranked list complet avec score global + breakdown par critère. DEC-15 : "top-3" remplacé par "ranked list" dans l'interprétation. Meilleur pour le data flywheel — plus de bookings possibles sur toute la liste.
**Date:** 2026-02-19

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
**Decision:** `composite_score = call_experience_avg × 0.30 + trust_score × 0.20 + client_satisfaction_avg × 0.20 + qualification_rate × 0.15 + recency_score × 0.15`. Used as tiebreaker in match ranking. Starts at 0 — no score inflation before real data. `qualification_rate` (DEC-30) remplace `hire_rate` comme signal d'honnêteté et d'alignement — expert qui confirme ses leads qualifiés vs expert qui flag systématiquement.
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
**Impact:** E06S07: `GET /api/prospects/:id/matches` returns full anonymized ranked list without email — no top-3 limit (voir DEC-24). Email captured at booking via Cal.com webhook → `prospects.email` updated on booking.
**Date:** 2026-02-19

---

### DEC-2026-02-19-14 — Pay-Per-Call Only (No Subscription)

**Context:** Monthly subscription plans (900€/5 leads, 1500€/10 leads) were initially considered. They create a committed monthly burden with uncertain ROI at MVP stage.
**Decision:** Revenue model is pure pay-per-call. Expert pays 100–200€ per booked call, only when a prospect books. No monthly subscription, no upfront commitment.
**Rationale:** Lower adoption barrier for early experts — no sunk cost before seeing lead quality. Aligns platform incentives with expert success. Easier to explain and justify. Subscriptions can be introduced post-M3 once lead quality is proven and experts demand volume.
**Impact:** E05 rewritten for pay-per-call only. Subscription bundles removed. Lemon Squeezy configured for one-time checkout per call, not recurring subscription. *(Billing trigger précisé par DEC-30 : checkout déclenché sur confirmation expert ou silence 7j post-call — pas sur Cal.com webhook direct.)*
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

### DEC-2026-02-20-35 — Supabase : une seule DB en staging, partagée entre dev et staging

**Context:** Une seule DB Supabase est disponible à ce stade. La DB de production sera créée à partir du schéma staging au moment du lancement.
**Decision:** `callibrate-staging` = DB unique pour dev local ET staging. Production différée. Dev local (`wrangler dev`) pointe sur staging Supabase via `.dev.vars`. Aucune DB séparée pour dev.
**Rationale:** Contrainte budgétaire réelle. Pas de risque — dev et staging partagent la même base de données de test, aucun impact production.
**Impact:** `.dev.vars` = mêmes credentials que staging. Secrets staging = `SUPABASE_URL` + `SUPABASE_ANON_KEY` + `SUPABASE_SERVICE_KEY` → pointent vers `callibrate-staging`. Secrets production configurés au lancement.
**Date:** 2026-02-20

---

### DEC-2026-02-20-34 — `cal.setup` : sort de matching-jobs, home à définir en E06S04

**Context:** `matching-jobs` queue est supprimée (DEC-33). Elle portait deux types de messages : `compute.matches` (over-engineering) et `cal.setup` (création du managed user Cal.com lors de l'inscription expert). Le `cal.setup` est légitime mais n'a plus de queue pour le transporter.
**Decision:** `cal.setup` est traité de manière synchrone lors de l'inscription expert (POST /api/experts/register → appel Cal.com API directement). Si la latence Cal.com est trop élevée, une queue dédiée `callibrate-core-queue-onboarding-staging/prod` sera créée en E06S04. Décision finale à prendre dans E06S04.
**Rationale:** À l'inscription, l'expert attend déjà une confirmation — une latence de 1–2s pour le Cal.com setup est acceptable. Si Cal.com répond > 3s en médiane, on bascule en async. MVP first.
**Impact:** E06S04 : implémenter cal.setup synchrone dans POST /api/experts/register. Si besoin async → créer `callibrate-core-queue-onboarding-staging` + `callibrate-core-queue-onboarding-prod` en suivant la convention de nommage (DEC-32).
**Date:** 2026-02-20

---

### DEC-2026-02-20-33 — Suppression de la queue `matching-jobs` (over-engineering MVP)

**Context:** `matching-jobs` queue était destinée au batch re-matching : re-scorer des prospects existants quand un nouvel expert s'inscrit. La question s'est posée lors de la révision de l'architecture async vs sync.
**Decision:** La queue `matching-jobs` est supprimée définitivement. Le matching est synchrone au moment de la recherche prospect. Aucun batch re-matching.
**Rationale:** Le prospect est anonyme — il n'a pas de profil persistant à re-matcher. La recherche se fait à la demande et retourne un résultat immédiat. Conserver des "prospects en attente" à re-scorer n'a pas de sens dans ce modèle. Sur une base de quelques dizaines à centaines d'experts (MVP), le matching synchrone est sub-100ms.
**Impact:** `wrangler.toml` : queue `matching-jobs` supprimée (root, staging, production). `src/index.ts` : QUEUES constant mise à jour. E06S06 : 2 queue consumers (email + billing), pas 3. E06S09 AC9 : dispatch vers matching-jobs supprimé — le re-ranking post score update est best-effort inline ou supprimé du scope MVP.
**Date:** 2026-02-20

---

### DEC-2026-02-20-32 — Convention de nommage Cloudflare : `{scope}-{entity}-{resource}-{env}`

**Context:** Le workspace Cloudflare héberge plusieurs projets. Sans préfixe projet, les ressources (queues, KV, workers) sont indiscernables dans le dashboard, la CLI et la facturation.
**Decision:** Convention universelle pour toutes les ressources Cloudflare : `{scope}-{entity}-{resource}-{env}`.
- `{scope}` : `callibrate-core` | `callibrate-io` | `callibrate-ai`
- `{entity}` : `queue` | `kv` | `r2` | `d1` | `workflow` — **omis pour les Workers** (le Worker IS le scope)
- `{resource}` : slug décrivant la fonction (ex: `email-notifications`, `sessions`)
- `{env}` : `staging` | `prod` — pas `production`, pas `dev`
- **Exception dev** : dev local (`wrangler dev`) pointe sur les ressources staging directement. Aucune ressource `-dev` créée.
- **Scope ownership** : KV, Queue, R2, D1, Workflow → toujours `callibrate-core`. `callibrate-io` et `callibrate-ai` = UI workers uniquement, ils consomment l'API, jamais le storage directement.
**Rationale:** Multi-projet Cloudflare → les noms doivent être auto-explicatifs depuis n'importe quelle vue (dashboard, billing, logs). Le type de ressource dans le nom évite les confusions entre une KV `sessions` et une queue `sessions`.
**Impact:** `wrangler.toml` mis à jour. `SETUP.md` mis à jour. Queues renommées avec préfixe `queue-`. KV namespaces créés avec noms explicites (pas via `--env` auto-naming). Aucune ressource ne doit être créée sans respecter cette convention.
**Date:** 2026-02-20

---

### DEC-2026-02-20-36 — Parallel `/gaai-deliver` : autorisé quand le backlog le permet (RÉVISÉ)

**Context:** DEC-36 initial interdisait tout parallélisme. Révisé après constat que le backlog gère déjà les dépendances — deux stories `refined` avec des dépendances toutes `done` et des fichiers disjoints sont safe à livrer en parallèle.
**Decision:** Deux `/gaai-deliver` peuvent tourner simultanément **si et seulement si** : (1) chaque session cible une **story différente** (argument story ID explicite obligatoire) ; (2) les deux stories ont des dépendances indépendantes (toutes `done`) dans le backlog ; (3) les fichiers touchés ne se chevauchent pas. Le human orchestre : c'est lui qui décide de lancer deux sessions et choisit les stories cibles. Le parallélisme non-supervisé (deux agents choisissant librement) reste interdit faute de locking.
**Rationale:** Le backlog + système de dépendances est le mécanisme de coordination. Il n'est pas nécessaire de sérialiser toutes les livraisons quand les stories sont structurellement indépendantes. Gain de temps réel sur les Epics avec de nombreuses stories parallélisables (ex: E06S07 + E06S08).
**Impact:** `/gaai-deliver` mis à jour : argument story ID supporté, logique de sélection strictement backlog-first. `delivery.agent.md` mis à jour : story selection non-negotiable = backlog only, jamais inférée depuis git/artefacts. Règle : chaque session doit passer l'ID story en argument si parallèle.
**Date:** 2026-02-20

---

### DEC-2026-02-20-37 — Supabase : Publishable Key vs Anon Key selon le contexte d'appel

**Context:** La publishable key (`sb_publishable_*`) ne fonctionne pas pour les appels REST directs à PostgREST — celui-ci exige un JWT dans le header `Authorization: Bearer`. Les publishable keys sont conçues pour le SDK `supabase-js`, qui gère l'échange d'auth sous le capot différemment.
**Decision:** Deux contextes, deux clés : (1) Appels REST directs (Workers health check, appels PostgREST bruts) → utiliser la **legacy anon key** (JWT). (2) Client `@supabase/supabase-js` (E06S02 et au-delà) → instancier avec la **publishable key** (`sb_publishable_*`). Aucun changement de code immédiat — la migration vers publishable key se fait au moment de l'intégration supabase-js en E06S02.
**Rationale:** La publishable key est le standard recommandé pour les nouvelles applications, mais elle suppose l'usage du SDK. Les Workers qui appellent PostgREST directement via fetch doivent continuer à utiliser l'anon key JWT jusqu'à adoption complète du SDK.
**Impact:** E06S01 (health check Worker) : conserve l'anon key. E06S02 : instancier `createClient()` avec la publishable key. Documenter dans les secrets staging/prod : `SUPABASE_ANON_KEY` (legacy, REST direct) + `SUPABASE_PUBLISHABLE_KEY` (SDK).
**Date:** 2026-02-20

---

### DEC-2026-02-20-38 — callibrate.io acquis — domaine principal confirmé

**Context:** DEC-07 mentionnait "both domains available and secured" mais sans confirmation d'achat réel. callibrate.io est désormais officiellement acquis.
**Decision:** callibrate.io est le domaine principal de la plateforme. callibrate.ai reste le domaine prospect-facing (statut d'acquisition à confirmer séparément).
**Rationale:** Confirmation de possession réelle — plus une vérification de disponibilité.
**Impact:** Tous les artefacts, DNS, déploiements Cloudflare Workers doivent pointer vers callibrate.io pour l'interface expert. Aucun changement architectural — cohérent avec DEC-07 et DEC-22.
**Date:** 2026-02-20

---

<!-- Add decisions above this line, newest first -->
