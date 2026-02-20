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

## Mission

> **Callibrate rend chaque bonne collaboration possible — indépendamment de qui tu connais.**

---

## Valeurs

**Alignement**
On ne gagne que quand les deux parties gagnent. Le call booké est l'unité de valeur — pas le clic, pas l'impression, pas la commission. Les revenus de la plateforme dépendent directement de la qualité du match.

**Transparence**
Ce que le système fait est toujours explicable. Pas de boîtes noires. Les experts comprennent leur profil de matching, leur score, leur billing. Les prospects comprennent comment leurs matches sont calculés. La transparence porte sur les bénéfices et les principes — pas sur les seuils et algorithmes internes.

**Précision**
Pas de volume. Pas de spray-and-pray. Un bon match vaut plus que dix approximations. Chaque critère, chaque score, chaque suggestion existe pour affiner — pas pour remplir un pipeline.

**Agentivité**
L'utilisateur contrôle toujours son expérience. Le système apprend, propose, suggère. L'utilisateur décide. Toujours. Ni l'expert ni le prospect ne sont gouvernés par une logique qu'ils ne comprennent pas et ne peuvent pas influencer.

**Ce que ces valeurs excluent explicitement :**
- Dark patterns (email gate avant la valeur, urgence artificielle, upsell agressif)
- Métriques de vanité (nombre de profils, impressions, clics)
- Croissance au détriment de la qualité

---

## Principes de communication expert (billing + évaluation)

- Transparence totale sur **ce qu'ils paient** et **quand** — dès l'onboarding
- Transparence sur le fait que leurs évaluations **améliorent leurs futurs matchs** — framing bénéfice, jamais surveillance
- Éducation **contextuelle et progressive** — jamais en une seule fois (onboarding dense = ignoré)
- Ne jamais formuler l'anti-gaming en négatif ("si tu triches...") — toujours en positif ("les experts qui évaluent honnêtement reçoivent de meilleurs leads")
- Ne jamais publier les seuils de scoring ni les détails algorithmiques — expliquer les principes, pas les paramètres

---

## Project Overview

**Name:** Callibrate (callibrate.io + app.callibrate.io + satellites)

**Purpose:** Matching OS — moteur de qualification et matching bi-directionnel configurable par domaine. MVP focalisé sur les experts AI. Architecture domain-agnostic : peut accueillir tout type de prestataire de service qualifié. Le call booké est l'unité monétisable. Pas de commission sur les deals.

**Taglines validés (DEC-49) :**
- Expert-facing (callibrate.io) : *"Pre-qualified leads, booked to your calendar."*
- Prospect-facing (satellites) : *"The expert a trusted friend would recommend."*
- Brand-level (social bios, meta, decks) : *"Qualified matches. Booked calls."*
- Secondary (mode dual) : *"Browse like a directory. Match like magic."*

**Positionnement dual :**
- Mode directory : exploration, profils, trust scores, SEO-friendly
- Mode engine : freetext + AI extraction → matching bi-directionnel → résultats rankés

**Positionnement profond (issu du signal terrain E01S01) :**
Le vrai concurrent n'est pas Upwork — c'est le réseau humain de confiance (bouche-à-oreille, recommandation par un tiers). Ce réseau produit les meilleurs leads des deux côtés mais exclut structurellement ceux qui n'y sont pas.
Callibrate = **l'intermédiaire de confiance scalable** — celui qui pré-qualifie et fait le pont pour ceux qui ne sont pas dans le réseau.
- Pour l'expert : recevoir des leads comme si un pair de confiance les avait pré-filtrés pour lui
- Pour le prospect : trouver l'expert qu'un pair de confiance t'aurait recommandé — même sans ce réseau

**Target Users:**
- **Experts** (paying customers): AI integration consultants et freelancers — paient uniquement par call booké (pay-per-call, pas d'abonnement)
- **Prospects** (product delivered): Entreprises avec un besoin réel — gratuit, accès via satellite sites niches

**Founder profile:** Solo founder, AI-assisted development, minimal manual support target.
**Contrainte founder :** Employé à un poste clé — LinkedIn bloqué jusqu'au lancement produit (risque de panique équipe/hiérarchie). GTM reséquencé en conséquence (DEC-31). LinkedIn activé comme levier de lancement simultané avec substance (manifeste + infra + signal Reddit accumulé).

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
- **Async / Background jobs:** Cloudflare Queues + Workflows (technical pipelines) — naming convention: `callibrate-core-queue-{resource}-{env}` (DEC-32)
- **Business automation:** n8n (integrations tierces, notifications, onboarding sequences)
- **Cache / Session:** Cloudflare KV
- **Email transactionnel:** Resend (via Cloudflare Queues)
- **Calendar / Booking:** Google Calendar API directe (OAuth2 — DEC-41). Cal.com supprimé (Platform fermée aux nouveaux signups 15/12/2025). Token storage : chiffrement AES-256-GCM via Workers Web Crypto (`GCAL_TOKEN_ENCRYPTION_KEY`). Visio : Google Meet auto-généré par booking (`conferenceDataVersion=1`). Teams/Outlook : post-MVP.
- **Payment / MoR:** Lemon Squeezy (Merchant of Record — gestion taxes internationales)
- **Frontend platform:** Next.js 15 (App Router) — callibrate.io + app.callibrate.io (expert dashboard) + satellites
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
- Cloudflare Queues: async workers (email, billing, score) — matching is synchronous (DEC-33)
- n8n: time-based workflows (survey triggers, onboarding sequences)
- This layer is domain-agnostic — no UI concerns, no platform-specific assumptions

**Layer 3 — Interfaces**
Two tracks. Each track can host as many platforms as needed. All platforms in Layer 3 consume Layer 2 exclusively.

*Track 3.1 — Expert dedicated UIs*
- **callibrate.io**: landing page expert (marketing, inscription)
- **app.callibrate.io**: dashboard expert authentifié (profil, lead pipeline, analytics, billing)

*Track 3.2 — Prospect dedicated UIs*
- **Satellite sites** (N domains, généraliste ou par vertical/domaine): seul canal prospect — directory, funnel quiz, matching engine, embedded booking widget, content — data centralized in Layer 2 via api.callibrate.io
- ~~callibrate.ai supprimé~~ (DEC-39)

## Architectural Boundaries

- **AI extraction:** Freetext description → Claude (haiku-4-5) → ProspectRequirements JSONB (CF Worker, stateless — `POST /api/extract`)
- **Qualification engine:** Quiz funnel (satellite) → requirements JSONB → Supabase (CF Worker)
- **Matching engine:** Expert profile JSONB vs prospect requirements JSONB → scored matches + composite_score tiebreaker (CF Worker)
- **Booking layer:** Google Calendar API directe — OAuth2 par expert (E06S10) → freebusy availability + hold slot + events.insert (Meet link) + cancel/reschedule (E06S11). Headless, consommé par satellite funnel widget. Anti double-booking : held status + freebusy re-check à la confirmation.
- **Lead billing trigger:** booking confirmed → Lemon Squeezy one-time checkout → lead billed (pay-per-call)
- **Score computation:** Feedback events (call_experience + satisfaction + lead_eval) → composite_score (CF Queue consumer)
- **Feedback loop:** n8n triggers J+7 and J+45 survey emails → submissions → score worker → match re-ranking
- **Expert dashboard:** Profile, criteria, lead pipeline, analytics, composite_score tier — servi par `app.callibrate.io`
- **Notification layer:** Cloudflare Queues → Resend (email) / n8n (complex workflows, time-based triggers)

---

## Founding Philosophy — Hypothèses et Agilité

**Principe fondateur :** Le marché des experts AI est la première hypothèse, pas la vérité. Comme toute hypothèse, elle peut être confirmée, infirmée, ou partiellement correcte. La grande majorité des businesses pivotent. L'enjeu n'est pas d'avoir raison au départ — c'est de construire un système capable de lire le marché et de s'adapter.

**Ce qui est testé :** Le vertical AI consulting (experts + prospects PME). Ce qui n'est pas testé : tout le reste.

**Ce qui est l'actif durable :** Le Matching OS bi-directionnel — pas le vertical. Si le marché AI ne génère pas le signal attendu, l'engine reste valide sur d'autres domaines.

**Règle de décision :** Pivoter sur un pattern répété dans la data — jamais sur un commentaire isolé, une opinion, ou une intuition non testée. La data prime sur les idées auxquelles on s'accroche.

**Discipline anti-flottement :** L'agilité ne signifie pas changer de direction à chaque friction. Elle signifie tester une hypothèse à fond, lire les résultats honnêtement, puis décider. Un pivot prématuré est aussi dangereux qu'une rigidité aveugle.

**Pourquoi le domain-agnostic était non-négociable dès le départ (DEC-19) :** Pas un choix esthétique — une résilience architecturale anticipée. Si le vertical change, l'engine ne se réécrit pas.

**Méthode :** E01S01 → data marché → décision. Pas l'inverse.

---

## Known Constraints

- Solo founder — UX must be simple, support must be minimal
- No commission on deals — revenue only from lead access fees
- GAAI governance active: all execution via backlog
- Cloudflare Workers (not Pages) for all deployment
- AI augments the product — does not replace it
- **⚠️ Google OAuth sensitive scope review (pre-go-live blocker):** Le scope `calendar.events` requiert une vérification formelle de l'app Google pour les utilisateurs externes (domain verification, privacy policy, security assessment). Process peut prendre plusieurs semaines. À initier immédiatement — bloque le go-live de E06S10/E06S11.

---

## Competitive Moat

**Moat primaire — Data flywheel**
Chaque transaction (quiz, match score, booking, feedback) améliore les weights du matching engine. Plus de volume → meilleure calibration → meilleurs matchs → plus de volume. Impossible à répliquer pour un acteur solo ou un système mono-expert.

**Différenciateur clé — Valeur au prospect "rejeté"**
Un système mono-expert (Typeform ROI, filtre Upwork) : le prospect qui ne matche pas disparaît sans valeur.
Callibrate : le prospect qui ne matche pas Expert A est matché avec Expert B ou C. Les "rejets" d'un expert deviennent des revenus pour un autre. **Aucune plateforme existante ne fait ça.**

**Barrière technique — Matching bi-directionnel**
Upwork / Malt / LinkedIn = unidirectionnel ou textuel. Callibrate évalue simultanément `expert.preferences` vs `prospect.requirements` dans les deux sens. Le composite score (data de vrais calls) est un actif défensif qui se renforce dans le temps.

**Matching OS vs moteur de recherche :**
Un moteur de recherche qualifie le prestataire *sur base des besoins du prospect* → unidirectionnel.
Callibrate évalue simultanément `expert.preferences` vs `prospect.requirements` dans les deux sens → bi-directionnel.
C'est structurellement plus puissant : le match tient compte de ce que les deux parties veulent réellement.

**L'unité de charge est verticale, pas fondamentale :**
MVP : call booké = unité monétisable (adapté au consulting AI).
Post-M3 : d'autres verticals peuvent avoir d'autres unités (ex : session de formation validée, mise en relation formalisée, contrat signé via webhook).
Le Matching OS est agnostique de l'unité — c'est la couche de billing qui s'adapte au vertical, pas l'engine.

**La vraie promesse :** "Ne rate pas le bon match parce que tu as atterri sur le mauvais expert en premier."
- Expert : reçoit des prospects qui matchent **ses** critères (budget, secteur, stade de projet) — sans filtrage manuel, sans construire son propre système de qualification
- Prospect : n'est jamais perdu — il existe toujours un expert configuré pour l'accueillir, quelque soit son stade de qualification

**Promise terrain validée (E01S01) :**
- Expert : "Reçois des prospects qui matchent tes critères — budget, secteur, stade de projet — directement dans ton agenda, sans filtrage de ta part."
- Prospect : "3 mois pour trouver le bon expert en cherchant seul. Quelques minutes en décrivant ton besoin ici."

**UX match results :** ranked list complet. Top 3 visuellement mis en avant (#1 le plus prominent — badge Best Match). Aucun prospect abandonné — qualification relative aux critères de chaque expert, pas à un standard universel (DEC-25).

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

### Option B — Formation professionnelle (vertical expansion)

**Idée :** Déployer Callibrate comme moteur de matching sur le marché de la formation professionnelle — entreprises cherchant un formateur qualifié pour un besoin précis (sujet, secteur, niveau d'audience, format, budget).

**Opportunité :**
- Marché fragmenté avec trop d'acteurs et trop de choix → même problème que les consultants AI
- Dominé par la cooptation → les bons formateurs hors réseau sont invisibles
- Matching bi-directionnel applicable : `trainer.profile` (sujets, pédagogie, secteur, format) vs `company.needs` (sujet, niveau, taille, budget, format)
- Architecture domain-agnostic : nouveau vertical = nouvelle `satellite_config`, pas une réécriture

**Risques :**
- **QUALIOPI (France)** : certification obligatoire pour les formations financées via OPCO ou CPF. Sans vérification et affichage du statut QUALIOPI, la plateforme est inutilisable pour 80% des cas B2B. Intégration non triviale.
- **OPCO / CPF** : les budgets de formation passent souvent par ces organismes — cycles d'achat longs, comités de validation, dossiers administratifs. Incompatible avec le modèle pay-per-call instantané tel quel.
- **Vendor lists entreprise** : les grandes entreprises ont des listes de fournisseurs agréés. Un outsider n'entre pas par une plateforme — il entre par un RFP ou un commercial.
- **Économie différente** : prix par tête, par session, développement de contenu custom, durée de relation longue. L'unité monétisable n'est pas un call de 30 min.
- **Signal source biaisé** : cette option a émergé d'un commentaire sceptique (HotNeon, r/ArtificialNtelligence) suggérant un pivot — pas d'une validation de marché indépendante.

**Trade-offs :**
- Matching domain-agnostic = force architecturale → mais complexité réglementaire française = overhead non technique significatif
- Cooptation comme barrière = opportunité réelle → mais réseau de confiance difficile à court-circuiter sans volume initial
- Potentiel de GMV élevé (formations multi-sessions) → mais cycle de vente plus long que consulting

**Prérequis avant d'envisager :**
- Gate 3 PASS (≥10 calls payés, ≥3 experts re-payants sur le vertical AI)
- Validation indépendante du problème côté formateurs (pas seulement signal HotNeon)
- Analyse réglementaire QUALIOPI + OPCO avant tout développement

---

## Out of Scope (MVP)

- Mobile native app
- Multi-language (FR first, EN later)
- Custom CRM integration (beyond Airtable/HubSpot webhook)
- White-label version
