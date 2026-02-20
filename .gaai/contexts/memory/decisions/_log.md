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

### DEC-2026-02-20-39 — Architecture domaines finale : callibrate.io + app.callibrate.io + satellites + api.callibrate.io

**Context:** callibrate.ai était prévu comme hub prospect central (DEC-07, DEC-08, DEC-22). Domaine coûteux. TLD `.ai` banalisé en 2026 — plus de signal différenciant. Les satellites couvrent déjà l'intégralité de l'acquisition prospect.
**Decision:** callibrate.ai supprimé du stack. Architecture finale : (1) `callibrate.io` = landing page expert (marketing, inscription) ; (2) `app.callibrate.io` = dashboard expert authentifié ; (3) Satellites (généraliste ou par vertical/domaine) = seul canal prospect (directory, funnel quiz, matching engine, embedded booking widget, data centralized in Layer 2 via api.callibrate.io) ; (4) `api.callibrate.io` = API publique, sert toutes les UI.
**Rationale:** Les satellites étaient déjà le canal prospect principal. callibrate.ai était un hub généraliste redondant avec les satellites. Supprimer callibrate.ai élimine un domaine coûteux sans perte fonctionnelle. `api.callibrate.io` remplace les endpoints `workers.dev` et clarifie la séparation UI/API. Convention `app.` = standard SaaS (Linear, Notion, Vercel).
**Impact:** DEC-07 et DEC-08 supersedés sur la partie callibrate.ai. `context.md` mis à jour. Track 3.2 (prospect) = satellites uniquement. Track 3.1 (expert) = callibrate.io + app.callibrate.io. Layer 2 API exposée via `api.callibrate.io`. Aucun développement sur callibrate.ai. CORS E06S07 : `*.callibrate.ai` retiré des origines autorisées.
**Date:** 2026-02-20

---

### DEC-2026-02-20-38 — callibrate.io acquis — domaine principal confirmé

**Context:** DEC-07 mentionnait "both domains available and secured" mais sans confirmation d'achat réel. callibrate.io est désormais officiellement acquis.
**Decision:** callibrate.io est le domaine principal de la plateforme. callibrate.ai reste le domaine prospect-facing (statut d'acquisition à confirmer séparément).
**Rationale:** Confirmation de possession réelle — plus une vérification de disponibilité.
**Impact:** Tous les artefacts, DNS, déploiements Cloudflare Workers doivent pointer vers callibrate.io pour l'interface expert. Aucun changement architectural — cohérent avec DEC-07 et DEC-22.
**Date:** 2026-02-20

---

### DEC-2026-02-20-40 — E06S07 : matching synchrone au submit prospect (suppression du push matching-jobs)

**Context:** E06S07 AC3 référençait un push vers la queue `matching-jobs` (supprimée en DEC-33). Le flux nominal du satellite funnel doit être cohérent avec DEC-33 : aucune queue async pour le matching, tout est synchrone à la demande.
**Decision:** `POST /api/prospects/submit` appelle `scoreMatch()` de façon synchrone pour chaque expert actif et INSERT les résultats dans la table `matches` avant de répondre. La réponse reste `{ prospect_id, token, token_expires_at }` — inchangée. AC6 (202 + `status: "computing"`) est conservé comme garde défensive : il se déclenche uniquement si la table `matches` est vide pour ce `prospect_id` après insert (cas d'erreur ou expert pool vide), jamais dans le flux nominal. Le binding `EXPERT_POOL: KVNamespace` est ajouté comme dépendance de E06S07 pour cacher le pool d'experts actifs (évite N requêtes DB par soumission).
**Rationale:** DEC-33 a supprimé `matching-jobs` pour over-engineering. E06S07 référençait encore cette queue dans AC3 — incohérence à corriger avant la Delivery. Le matching synchrone est sub-100ms sur un pool MVP (dizaines à centaines d'experts). EXPERT_POOL KV évite une requête DB full-scan à chaque soumission prospect — pattern déjà prévu dans l'architecture (binding déclaré dans env.ts et wrangler.toml par la Delivery de E06S07).
**Impact:** E06S07 AC3 révisé : synchronous scoreMatch() + INSERT matches, plus de queue push. E06S07 AC6 : note "garde défensive — hors flux nominal" ajoutée. E06S07 dependencies : `EXPERT_POOL: KVNamespace` ajouté (nouveau binding à créer dans env.ts + wrangler.toml). E06S05 `scoreMatch()` : réutilisée telle quelle — aucun changement.
**Date:** 2026-02-20

---

### DEC-2026-02-20-46 — Fiche de préparation : matching bi-directionnel + scoring visible par les deux parties

**Context:** L'événement Google Calendar contient un lien vers une fiche de préparation. La question s'est posée de ce que cette fiche doit contenir au-delà du contexte prospect.
**Decision:** La fiche prep (`/prep/[booking_token]`) affiche le matching bi-directionnel complet avec scoring, accessible en un clic depuis l'événement Google Calendar, sans authentification. Contenu : (1) détails du call (date, heure, lien Meet) ; (2) contexte prospect — résumé des requirements soumis (besoin, budget, stade, secteur) ; (3) profil expert — prénom, spécialités, bio courte, composite_score tier (rising/established/top — pas le score brut) ; (4) score global du match + breakdown par critère avec label lisible (ex: "Budget aligné — 90/100", "Secteur maîtrisé — 85/100") ; (5) direction bi-directionnelle explicite : "Pourquoi ce prospect vous correspond" (côté expert) + "Pourquoi cet expert vous correspond" (côté prospect). La page est identique pour les deux parties — chacun voit le match de son point de vue. Les données sont lues depuis `bookings` + `prospects.requirements` + `experts.profile/preferences` + `matches.score_breakdown`.
**Rationale:** Concrétisation directe de la valeur Transparence (context.md). Le call commence avec un contexte partagé et un niveau de confiance établi — les deux parties comprennent le "pourquoi" avant même de se parler. Le `score_breakdown` JSONB est déjà produit par E06S05 (`scoreMatch()`) et stocké dans `matches` — la fiche le rend lisible en langage clair. Différenciateur visible : aucune plateforme existante n'expose ce niveau de transparence sur le matching au prospect et à l'expert simultanément.
**Impact:** E06S11 AC13 révisé : endpoint `/api/bookings/:token/prep` retourne `{ booking, expert, prospect, match }` avec `match.score`, `match.breakdown[]` (label + score par critère), `match.direction_expert` (pourquoi ce prospect correspond à l'expert), `match.direction_prospect` (pourquoi cet expert correspond au prospect). Requête : JOIN `bookings` → `prospects` + `experts` + `matches` WHERE `expert_id + prospect_id`. Satellite : page `/prep/[token]` lit cet endpoint et l'affiche — UI à définir en E03 (satellite funnel UX).
**Date:** 2026-02-20

---

### DEC-2026-02-20-45 — Google OAuth app verification : soumettre dès E06S10 staging, pas au lancement produit

**Context:** En Testing mode, Google affiche à chaque expert un écran "This app hasn't been verified" avec un bouton "Back to safety" — friction rédhibitoire pour des experts qui découvrent la plateforme. La confiance est le produit.
**Decision:** La vérification Google OAuth (sensitive scope `calendar.events`) doit être soumise dès que E06S10 est fonctionnel en staging (pas au lancement produit). Mitigation pour les premiers beta experts : les ajouter manuellement comme "test users" dans Google Cloud Console (until 100 users max) — ils voient toujours un avertissement mais peuvent procéder. Ce canal est acceptable pour 5–10 beta experts contactés directement. La vérification doit être complète avant la campagne LinkedIn de lancement et avant ~80 experts inscrits.
**Rationale:** Le process de vérification Google prend 2 à 6 semaines pour les sensitive scopes. Attendre le lancement produit = bloquer le lancement ou aller en production avec l'écran d'avertissement = perte de confiance expert = churn onboarding. Soumettre tôt (dès staging) permet à la vérification de se terminer en parallèle du build restant.
**Impact:** Action founder : (1) créer Google Cloud project + activer Calendar API + credentials OAuth2 (prérequis dev E06S10) ; (2) vérifier `callibrate.io` dans Google Search Console maintenant ; (3) publier privacy policy sur `callibrate.io` (prérequis vérification + RGPD) ; (4) soumettre la vérification dès E06S10 fonctionnel en staging.
**Date:** 2026-02-20

---

### DEC-2026-02-20-44 — Booking reminders : Prospect obligatoire (J-1 + H-1), Expert optionnel (dashboard)

**Context:** Un booking confirmé nécessite des rappels pour réduire les no-shows. Expert et prospect ont des besoins différents : le prospect a besoin d'un rappel systématique ; l'expert peut vouloir gérer ses notifications lui-même.
**Decision:** Prospect : reminders J-1 (24h) + H-1 (1h) obligatoires, non désactivables, email via Resend. Expert : reminders J-1 + H-1 optionnels, activés par défaut à l'inscription, désactivables depuis le dashboard `app.callibrate.io` (`experts.reminder_settings` JSONB). Email J-1 expert inclut le contexte prospect (nom, besoin, budget) pour préparation active. Implémentation : Cloudflare Workers Cron Trigger (toutes les 15 min) → requête `bookings WHERE status='confirmed'` dans les fenêtres J-1 et H-1 → push `email-notifications` queue → Resend. Pas de n8n pour les reminders (stateless + prévisibles).
**Rationale:** Les reminders prospects sont non-négociables (réduction no-shows = protection du revenu expert et de la qualité du matching). Le contrôle expert respecte l'agentivité (DEC-29 — l'utilisateur contrôle toujours son expérience). Le Cron Trigger est plus simple et moins coûteux que n8n pour un pattern prévisible à fenêtre fixe.
**Impact:** E06S11 : Cron Trigger toutes les 15 min + 2 nouveaux message types dans `email-notifications` queue (`booking.reminder_prospect`, `booking.reminder_expert`). E06S06 : consumer gère ces 2 nouveaux types. Schema : `experts.reminder_settings jsonb DEFAULT '{"enabled": true}'`. Dashboard expert (E02) : toggle reminders on/off.
**Date:** 2026-02-20

---

### DEC-2026-02-20-43 — Google Calendar event description : résumé inline + lien fiche prep

**Context:** L'expert et le prospect doivent être sur la même longueur d'onde au début du call. L'expert a déjà pris connaissance du contexte via le lead pipeline ; le prospect doit se rappeler ce qu'il a soumis et réfléchir à ce qu'il veut préciser.
**Decision:** L'événement Google Calendar créé à la confirmation du booking contient : (1) un résumé structuré inline (besoin, budget, stade, secteur — extrait de `prospect.requirements` JSONB) ; (2) un lien vers une fiche de préparation complète (`/prep/[booking_token]`) accessible sans compte, token à durée limitée (expire après le call). La fiche prep affiche le contexte complet formaté + invite le prospect à réfléchir à ce qu'il veut clarifier ("Avant votre appel, pensez à...").
**Rationale:** Le résumé inline est visible sans cliquer depuis n'importe quel client calendrier (offline-friendly). Le lien fiche permet un affichage complet et formaté sans surcharger la description. Les deux ensemble maximisent la préparation des deux parties avec un effort d'implémentation minimal.
**Impact:** E06S11 AC4 : `events.insert` description field = résumé structuré + lien `/prep/[booking_token]`. Nouvel endpoint léger requis : `GET /api/bookings/:token/prep` (lecture `prospects.requirements` + `bookings` sans auth, token-gated, CORS satellite). Endpoint peut être ajouté en E06S11 ou story dédiée si scope trop large.
**Date:** 2026-02-20

---

### DEC-2026-02-20-42 — OAuth Google Calendar : expert uniquement — prospect reçoit invitation nativement

**Context:** Question soulevée sur la nécessité d'un OAuth côté prospect pour recevoir la confirmation de booking dans son calendrier.
**Decision:** OAuth uniquement côté expert (E06S10). Le prospect fournit uniquement son email lors de la confirmation du booking. Google Calendar API crée l'événement avec le prospect en tant qu'`attendee` (`attendees: [{ email: prospect@email.com }]`) → Google envoie nativement l'invitation calendrier par email au prospect, incluant le lien Google Meet et la possibilité d'accepter/refuser l'événement. Aucun OAuth, aucun compte Google requis côté prospect.
**Rationale:** Le flow prospect doit rester frictionless — pas de compte, pas de login, pas d'OAuth. Google Calendar gère nativement l'envoi d'invitation aux attendees lors de la création d'un événement via `events.insert`. C'est le comportement standard utilisé par tous les outils de scheduling (Calendly, etc.). Zéro code additionnel requis pour ce mécanisme.
**Impact:** E06S10 : inchangé (OAuth expert uniquement). E06S11 AC4 : `events.insert` avec `attendees: [{ email: expert_google_email }, { email: prospect_email }]` — Google envoie l'invite au prospect automatiquement. Prospect reçoit : email d'invitation Google Calendar + événement dans son agenda (s'il accepte) + lien Google Meet.
**Date:** 2026-02-20

---

### DEC-2026-02-20-41 — Booking Layer : Cal.com superseded → Google Calendar API directe

**Context:** Cal.com Platform (Managed Users API) a fermé ses inscriptions aux nouveaux clients le 15/12/2025. E06S04 (livré) était construit sur cette API. Un deep research comparatif (20 solutions évaluées : Nylas, Cronofy, Cal.com self-hosted, Acuity, YouCanBookMe, OnceHub, SavvyCal, Harmonizely, Google Calendar API directe, Microsoft Graph) a été conduit avec la grille de contraintes Callibrate.
**Decision:** E06S04 superseded. Architecture booking headless construite en interne sur **Google Calendar API directe** (OAuth2, token storage chiffré Supabase, freebusy + events.insert + conferenceDataVersion=1). Deux nouvelles stories : **E06S10** (Google Calendar OAuth layer) et **E06S11** (Booking engine — availability, create, cancel, reschedule). Les colonnes `cal_*` existantes en DB sont conservées sans nettoyage jusqu'au post-MVP.
**Rationale:** Toutes les alternatives SaaS échouent sur au moins un critère rédhibitoire : Nylas ($1/compte/mois → coût des inactifs incompatible avec un ratio actifs/inscrits de 1–10% en early stage) ; Cronofy ($819/mois plancher → incompatible 0-revenue) ; Cal.com self-hosted (EE commercial requis pour Managed Users + infrastructure Node.js hors stack) ; tous les booking SaaS (pricing per-seat, pas de managed users marketplace). Google Calendar API est gratuite à l'usage, mature, directement appelable depuis un Cloudflare Worker via `fetch`, et ne génère aucun coût marginal par expert inactif.
**Impact:** E06S04 → `superseded` dans le backlog. E06S06 dependency sur E06S04 → remplacée par E06S10 (OAuth layer requis avant billing). E06S10 est la nouvelle dépendance de E06S11. **Point critique pre-go-live :** Google OAuth scope `calendar.events` est un "sensitive scope" → vérification formelle de l'app Google requise pour accès production aux comptes externes (process peut prendre plusieurs semaines — à initier immédiatement). Anti double-booking nécessite : table `bookings` avec colonne `held_until` + re-check freebusy à la confirmation.
**Date:** 2026-02-20

---

### DEC-2026-02-20-48 — LLM provider pour /api/extract : GPT-4o-mini remplace Anthropic Haiku

**Context:** E06S08 utilisait `claude-haiku-4-5` via Cloudflare AI Gateway (path Anthropic). Évaluation comparative conduite en session : Gemini 2.0 Flash ($0.10/$0.40/1M), GPT-4o-mini ($0.15/$0.60/1M), Haiku ($0.80/$4.00/1M), Cloudflare Workers AI Llama 3.x. La tâche d'extraction est de la classification structurée — pas de raisonnement complexe.
**Decision:** Migration vers **GPT-4o-mini** comme provider unique. Pas de fallback au stade MVP. Direct API call (`https://api.openai.com/v1/chat/completions`), pas de CF AI Gateway dans un premier temps (ajout ultérieur si observabilité requise). `ANTHROPIC_API_KEY` et `CLOUDFLARE_AI_GATEWAY_URL` supprimés de la stack. `OPENAI_API_KEY` ajouté.
**Rationale:** GPT-4o-mini = meilleur JSON Structured Outputs du marché (le plus documenté, le plus testé en production pour cette tâche). Coût ~5x inférieur à Haiku pour une qualité équivalente ou supérieure sur l'extraction. Le fallback Gemini→GPT-4o-mini via CF AI Gateway Dynamic Routing (Beta) est la bonne architecture long terme — mais ajoute de la complexité injustifiée à volume zéro. Décision réversible : CF Gateway peut être réintroduit en 1 story.
**Impact:** E06S12 story créée (migration code + secrets). Supprimer `ANTHROPIC_API_KEY` et `CLOUDFLARE_AI_GATEWAY_URL` de wrangler secrets staging/prod après livraison de E06S12. Provisionner `OPENAI_API_KEY --env staging` avant delivery.
**Date:** 2026-02-20

---

### DEC-2026-02-20-47 — Staging-first deployment flow + convention de tag production

**Context:** Le GAAI delivery loop squashait directement vers la branche `production` sans jamais déployer sur le worker Cloudflare staging. Les GitHub Actions existantes ciblaient `main` (branche inexistante) — aucun code n'avait jamais été déployé sur les workers CF. L'utilisateur souhaitait valider chaque story sur le staging réel (données Supabase staging) avant de promouvoir en production.
**Decision:** Flow staging-first en 3 phases : (1) QA PASS → squash merge → push `production` branch → GitHub Actions auto-déploie `callibrate-core-staging`. (2) Delivery Agent exécute smoke tests contre staging URL. (3) Smoke PASS → Delivery Agent s'arrête et reporte à l'humain la commande de tag pour déclencher le deploy production. Gate production = **human gate** (l'humain crée le tag). Convention de tag : `v0.{EPIC_NUMBER}.{STORY_NUMBER}` (ex. `v0.6.7` pour E06S07) avec annotation `{id}: {Story title}`. GitHub Actions `deploy-production.yml` déclenche sur `v*` tags → `wrangler deploy --env production`.
**Rationale:** Human gate = cohérent avec la philosophie GAAI (contrôle + gouvernance). Smoke tests = signal de confiance runtime (bindings KV, secrets, Supabase), pas exhaustif. Facile d'automatiser plus tard. Tag format `v0.EPIC.STORY` offre traçabilité directe story → tag sans sacrifier la compatibilité semver. Le trigger GitHub Actions staging était cassé (ciblait `main` inexistant) → corrigé vers `production`.
**Impact:** `.github/workflows/deploy-staging.yml` : trigger `main` → `production`. `.gaai/workflows/delivery-loop.workflow.md` : Step 8 enrichi (8a–8e). `SETUP.md` : références `main` → `production` + ANTHROPIC_API_KEY + CLOUDFLARE_AI_GATEWAY_URL ajoutés aux secrets staging. Secrets staging manquants à provisionner avant la prochaine delivery : `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`, `ANTHROPIC_API_KEY`, `CLOUDFLARE_AI_GATEWAY_URL`. Premier tag production : `v0.6.7` (E06S07 déjà livré en staging après ce fix).
**Date:** 2026-02-20

---

### DEC-2026-02-20-49 — Naming confirmé "Callibrate" + taglines dual validés

**Context:** Question de savoir si "Callibrate" évoque suffisamment le concept de lead qualification. Analyse structurée des alternatives (4 axes : qualification/filtrage, matching/précision, confiance/réseau, hybride) vs conservation du nom existant avec travail de tagline.
**Decision:** Nom "Callibrate" confirmé définitivement. Taglines dual adoptés : (1) Expert-facing : "Pre-qualified leads, booked to your calendar." (2) Prospect-facing : "The expert a trusted friend would recommend." (3) Brand-level : "Qualified matches. Booked calls." Les taglines compensent ce que le nom seul ne porte pas (qualification explicite) tout en respectant le positionnement profond (réseau de confiance scalable).
**Rationale:** Aucune alternative ne bat Callibrate sur l'ensemble des critères : domain-agnostic (pas de "AI" ou "lead" dans le nom — cohérent DEC-18/19), domaine sécurisé (callibrate.io + app.callibrate.io déjà dans le code/CORS), double lecture sémantique (calibrate + call), mémorable et prononçable FR/EN. Le gap "qualification pas explicite dans le nom" est résolvable par le tagline — le gap des alternatives (vertical lock, connotation erronée, domaine indisponible) ne l'est pas. Alternatives évaluées et rejetées : QualifyAI (vertical lock), LeadSift (sonne outil interne), Vetted (saturé), PreQual (connotation immo), MatchOS (trop technique), TrueMatch (dating), FitScore (fitness), Vouchd (SEO fragile), Screenr (connotation RH).
**Impact:** context.md mis à jour avec les taglines validés. Positionnement "Browse like a directory. Match like magic." conservé comme secondary tagline (mode dual directory/engine). Les taglines sont applicables immédiatement : callibrate.io (expert-facing), satellites (prospect-facing), meta descriptions et social bios (brand-level). Supersede partiel de DEC-07 : le "why" du nom est désormais documenté avec les taglines associés.
**Date:** 2026-02-20

---

### DEC-2026-02-20-52 — Flow Hybride Prospect : Expression libre → Extraction AI → Confirmation ciblée

**Context:** Le quiz form pur crée de la friction et manque le contexte nuancé. Le prospect comprend son problème en langage naturel, pas en vocabulaire technique structuré.
**Decision:** Flow prospect en 3 phases : (1) Expression libre (freetext description) → (2) Extraction AI via `/api/extract` existant (E06S08) → (3) Confirmation ciblée des champs low-confidence uniquement. Remplace le quiz form pur comme canal principal. Le quiz form reste disponible comme fallback.
**Rationale:** Réduit la friction funnel, exploite l'infrastructure d'extraction AI déjà livrée (E06S08), et produit des données de meilleure qualité que le forced-choice. Cohérent avec DEC-17 (AI Freetext Extraction).
**Impact:** Story séparée à créer pour l'implémentation UI. Aucun changement backend — `/api/extract` est déjà opérationnel. Décision loggée uniquement, pas d'implémentation dans ce scope.
**Date:** 2026-02-20

---

### DEC-2026-02-20-51 — Reliability Modifier Anti-Gaming : composite_score comme scoring modifier

**Context:** Le composite_score était utilisé uniquement comme tiebreaker dans le ranking (sort secondaire). Un expert avec un composite_score faible (gaming, flags systématiques) pouvait toujours être #1 s'il avait des skills uniques matchant le prospect. Le tiebreaker ne pénalise que les ex-aequo.
**Decision:** composite_score passe de tiebreaker à scoring modifier via `applyReliabilityModifier()`. Cold start protection : < 5 leads OU composite null/0 → pas de pénalité (aucun expert pénalisé avant données réelles). Composite >= 50 → modifier 1.0 (pas de pénalité). Composite < 50 → multiplier progressif (0.5 à 1.0). Le modifier est enregistré dans `breakdown.reliability_modifier` pour transparence. E06S09 dependency pour activation réelle (composite_score = 0 pour tous actuellement → cold start → aucune pénalité appliquée).
**Rationale:** Aligne les incentives : experts honnêtes avec bon composite_score conservent leur ranking. Experts gaming voient leur score match réduit progressivement. La cold start protection garantit zéro impact avant données suffisantes. Réf: DEC-19, DEC-30.
**Impact:** `applyReliabilityModifier()` exporté depuis `src/matching/score.ts`. Wired dans `src/routes/prospects.ts` et `src/routes/matches.ts`. `reliability_modifier` ajouté à `ScoreBreakdown`. Activation réelle dépend de E06S09 (composite score worker) + accumulation de 5+ leads par expert.
**Date:** 2026-02-20

---

### DEC-2026-02-20-50 — Scoring Engine Phase 1 : normalisation skills, proximité industries/timelines, budget configurable, fix case-sensitivity

**Context:** L'analyse objective du scoring engine a révélé 7 faiblesses structurelles : (1) deal-breaker case-sensitive (seul check non-normalisé), (2) skills matching par string equality sans alias, (3) industry match binaire, (4) budget proxy ×20 hardcodé, (5) timeline matching par string equality, (6) anti-gaming composite en tiebreaker uniquement, (7) données collectées mais inutilisées.
**Decision:** Phase 1 corrige les 6 premières faiblesses. Fix : deal-breaker case-insensitive. Skills : `normalizeSkill()` avec alias map (react.js→react, nodejs, etc.). Industries : `getIndustryProximity()` graduée (banking↔fintech 0.8, e-commerce↔retail 0.9, etc.). Timelines : `parseTimelineDays()` avec ratio-based proximity scoring. Budget : `budget_conversion_factor` configurable dans `MatchingWeights` (default 20, backward-compatible). Tous les utilitaires dans `src/matching/normalize.ts`. Réf: DEC-18, DEC-27.
**Impact:** `src/matching/normalize.ts` créé (3 fonctions exportées). `src/matching/score.ts` mis à jour (4 scorers + deal-breaker fix). `src/types/matching.ts` étendu (`budget_conversion_factor`, `reliability_modifier`). 11 nouveaux tests, 5 existants inchangés (non-régression vérifiée). Phase 2 (embeddings pgvector) et Phase 3 (ML re-ranking) hors scope.
**Date:** 2026-02-20

---

<!-- Add decisions above this line, newest first -->
