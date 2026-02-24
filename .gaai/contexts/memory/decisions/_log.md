---
type: memory
category: decisions
id: DECISIONS-LOG
tags:
  - decisions
  - governance
created_at: 2026-02-19
updated_at: 2026-02-23
---

# Decision Log

> Append-only. Never delete or overwrite decisions.
> Only the Discovery Agent may add entries (or Bootstrap Agent during initialization).
> Format: one entry per decision, newest at top.
>
> **Compacted 2026-02-23:** DEC-01 to DEC-59 (59 entries) archived.
> Full text → `archive/decisions-01-59.archive.md` | Summary → `summaries/decisions-01-59.summary.md`

---

### DEC-2026-02-24-71 — Mandatory PR merge to staging at end of delivery cycle

**Context:** 19 PRs accumulated unmerged on staging over multiple delivery cycles. When batch-merged, cascading conflicts required 3 full rounds of resolution across all branches. Root causes: (1) delivery agent created PRs but never merged them, (2) story branches were stacked on previous stories instead of branching from staging, (3) hotspot files (`index.ts`, `wrangler.toml`, `env.ts`) modified by nearly every story guaranteed conflicts. Total remediation: ~60 conflict files resolved, 3 test fixes, 2+ hours of agent work.
**Decision:** PR merge to staging becomes a mandatory final step of the delivery cycle. The delivery agent must: create PR → pass QA → merge PR → confirm CI. PRs must not be left open. Story branches must be created from `staging`, never from other story branches. A dedicated "merge agent" is NOT needed — this is a process fix within the existing delivery track.
**Rationale:** The problem was not "who merges" but "when." Immediate merge after delivery keeps the conflict surface at exactly 1 PR (the current story) against a fresh staging. Accumulation is the enemy. A 4th sub-agent adds coordination overhead without addressing the root cause (branching strategy + merge timing).
**Impact:** conventions.md updated (5 new rules). Delivery agent flow should be updated to include merge-to-staging as final step. No new agent needed.
**Date:** 2026-02-24

---

### DEC-2026-02-24-70 — Artefact directory structure: one dedicated subdirectory per type

**Context:** Delivery artefacts (impl-report, qa-report, memory-delta) were scattered across wrong locations: root of `artefacts/`, inside `plans/`, and in a hybrid `reports/` catch-all folder. Root cause: all sub-agents (implementation, QA, micro-delivery), skills (coordinate-handoffs, memory-alignment-check), and README.artefacts.md hardcoded `reports/` as the single output directory. The filesystem had evolved to use dedicated subdirectories (`impl-reports/`, `qa-reports/`, `memory-deltas/`) but the agent instructions were never updated. The delivery.agent.md orchestration flow used abbreviated paths (no directory prefix), providing zero guidance.
**Decision:** Canonical artefact routing — one directory per artefact type, no exceptions:

| Artefact type | Directory |
|---|---|
| `{id}.execution-plan.md` | `plans/` |
| `{id}.plan-blocked.md` | `plans/` |
| `{id}.approach-evaluation.md` | `evaluations/` |
| `{id}.impl-report.md` | `impl-reports/` |
| `{id}.specialist-{domain}.md` | `impl-reports/` |
| `{id}.qa-report.md` | `qa-reports/` |
| `{id}.memory-delta.md` | `memory-deltas/` |
| `{id}.micro-delivery-report.md` | `delivery/` |

New rule R7 in `artefacts.rules.md`: no artefact may be written to the root of `contexts/artefacts/`. The hybrid `reports/` directory has been deleted — its contents redistributed to the dedicated subdirectories.
**Rationale:** Separation of concerns eliminates ambiguity. Each type has a single canonical location. Agents no longer have to guess. The routing table in `artefacts.rules.md` is the single source of truth.
**Impact:** 8 files updated (4 sub-agents, 2 skills, delivery.agent.md, README.artefacts.md, artefacts.rules.md). 80+ existing artefacts moved to correct locations. `reports/` deleted. All future deliveries will write to the correct directories.
**Date:** 2026-02-24

---

### DEC-2026-02-22-69 — KV eliminated from expert pool read path; E06S19 merged into E06S23

**Context:** The expert pool cache architecture planned 3 layers: Cache API (L1) → KV (L2) → Hyperdrive (L3). Analysis revealed KV adds no value over D1: KV has a 25 Mo per-value limit (~5,000 experts max), no SQL filtering, ~50ms latency. D1 provides SQL WHERE filtering, sub-5ms edge reads, 10 Go limit, and $0.001/M rows. R2 was also evaluated and rejected — `list()` does not support metadata filtering, making it unsuitable for queryable structured data.
**Decision:** KV removed from expert pool read path. E06S19 (Cache API L1 for KV) cancelled and absorbed into E06S23. New read chain: Cache API (L1, 60s, per-datacenter) → D1 (L2, SQL queryable, edge) → Hyperdrive (L3, source of truth). `EXPERT_POOL` KV namespace retained only if used by other features.
**Rationale:** Simpler architecture (2 cache layers instead of 3), no 25 Mo limit, SQL filtering enables satellite-specific pools without client-side filtering, lower cost ($0.001/M vs $0.50/M). One fewer story to implement.
**Impact:** E06S19 cancelled. E06S23 updated (absorbs Cache API L1 scope, dependency on E06S19 removed). Backlog, epic E06, and memory index updated.
**Date:** 2026-02-22

---

### DEC-2026-02-22-68 — Billing Model — LS Usage-Based Subscription + Internal Credit Accounting

**Context:** Le billing per-lead checkout (un checkout LS par lead) crée de la friction (expert doit cliquer à chaque lead) et des coûts de refund (LS garde ses fees sur les remboursements). Le projet a besoin d'un modèle qui supporte : (1) carte on file avec auto-charge, (2) flag/restore instantané sans frais LS, (3) LS comme MoR pour la gestion fiscale, (4) anti-gaming transparent. Analyse des modèles industrie : Thumbtack et Bark utilisent des crédits prépayés ; Angi (post-pay auto-charge) est le plus controversé (amende FTC $7.2M). LS supporte les usage-based subscriptions ($0/mois, carte on file, charge en fin de cycle basée sur l'usage reporté).
**Decision:** Modèle hybride — LS usage-based subscription pour le billing + credit accounting interne pour le flag/restore temps réel.

**Flux complet :**
1. Expert active son pipeline → souscription LS $0/mois "Lead Pipeline" (entre sa carte une fois)
2. Lead créé → crédits déduits en interne instantanément, prix et breakdown affichés dans le dashboard
3. Expert peut flag "non qualifié" dans les 7 jours → crédits restaurés en interne (zéro transaction LS)
4. Silence ou confirmation explicite après 7 jours → lead confirmé → usage reporté à LS
5. Fin de cycle billing LS → LS charge automatiquement le total usage confirmé → carte on file
6. Carte échoue → LS dunning automatique (retry) → si échec final : leads pausés

**Usage reporting différé de 7 jours :** L'usage n'est reporté à LS qu'après expiration du flag window. Leads flaggés ne sont jamais reportés → jamais chargés → pas de refund nécessaire. Élimine le misalignment flag/billing cycle.

**Crédit d'accueil :** 100€ offerts à l'activation (internal credit, pas de charge LS). Permet à l'expert de tester 1-2 leads sans engagement financier.

**Expert controls :**
- `max_lead_price` — plafond par lead (deal-breaker au matching, DEC-67)
- `spending_limit` — plafond mensuel de dépense. Quand atteint → leads pausés → notification.
- Dashboard affiche : solde crédits temps réel, progression spending limit, nombre de leads manqués (cause : solde insuffisant OU max_lead_price dépassé)

**Anti-gaming — règles transparentes dès l'onboarding (mise à jour DEC-30) :**
- `qualification_rate = leads_confirmed / total_leads` reste composant du composite_score
- Règles communiquées explicitement à l'onboarding : "Les experts qui confirment leurs leads reçoivent de meilleurs leads. Un taux de flag élevé réduit naturellement ta visibilité dans le matching."
- Framing positif uniquement (jamais "si tu triches → sanctions"). Conforme aux principes de communication expert (context.md).
- Dashboard affiche la qualification_rate de l'expert + explication de son impact

**Balance check au matching :** `expert.credit_balance >= lead_price` est un prérequis pour le match. Si insuffisant → expert exclu du match pour ce lead + notification "Ton solde est insuffisant pour recevoir ce lead. Recharge pour réactiver."

**Évolution post-M3 :** Si l'auto-charge instantané (vs fin de cycle) devient critique, migration payment layer vers Stripe (PaymentIntents + saved PaymentMethod). LS reste MoR tant que le volume ne justifie pas Stripe Tax + service de filing fiscal.

**Rationale:** Le modèle usage-based LS préserve le MoR (taxes gérées par LS) tout en offrant carte on file + auto-billing. Le credit accounting interne permet le flag/restore instantané sans LS fees. Le report d'usage différé de 7 jours résout le misalignment flag/cycle. L'anti-gaming communiqué en positif est conforme aux valeurs Transparence et Agentivité.
**Impact:** Mise à jour DEC-30 (flux billing révisé). Nouveau produit LS : "Lead Pipeline" usage-based subscription. Nouvelles structures DB : `experts.credit_balance` INTEGER (centimes), `credit_transactions` table. CF Workflow ou Cron Trigger pour report usage LS après 7j. E05S01/S02 : révisés pour modèle crédits. E06S06 lead-billing consumer : révisé pour debit/restore pattern.
**Date:** 2026-02-22

---

### DEC-2026-02-22-67 — Dynamic Lead Pricing — Budget Tier × Qualification Modifier

**Context:** Le prix du lead était fixé à "100–200€" (context.md, PRD-001) sans grille ni formule. Un prix unique crée une friction : un prospect à 3 000€ de budget et un prospect à 100 000€ ne représentent pas la même valeur pour l'expert. Le pricing doit refléter la valeur potentielle du lead pour l'expert tout en restant transparent et prédictible (calcul ROI).

Benchmarks secteur : appointment setting B2B cold 200–500€/meeting, lead qualifié agence B2B 150–400€/lead, Upwork 20% du premier projet, LinkedIn Sales Navigator ~120€/mois (pas par lead). Un lead Callibrate est chaud, pré-qualifié, auto-initié → vaut structurellement plus qu'un lead froid.

**Decision:** Tarification dynamique basée sur 2 facteurs publiés :

**Facteur 1 — Budget prospect déclaré (primaire).** `budget_range.max` détermine le tier :

| Budget prospect (max déclaré) | Prix base | Ratio coût/valeur attendue (conv. 30%) |
|---|---|---|
| Non déclaré ou < 5 000€ | 49€ | ~3% |
| 5 000 – 20 000€ | 89€ | ~1.5% |
| 20 000 – 50 000€ | 149€ | ~1% |
| 50 000€+ | 229€ | ~0.5% |

**Facteur 2 — Niveau de qualification (modificateur) :**
- Standard (confidence 0.6–0.8) : prix base × 1.0
- Premium (confidence > 0.8 sur tous les champs, budget explicite, timeline précise) : prix base × 1.15

**Grille résultante publiée :**

| Budget prospect | Standard | Premium (+15%) |
|---|---|---|
| Non déclaré / < 5k€ | 49€ | 56€ |
| 5k – 20k€ | 89€ | 102€ |
| 20k – 50k€ | 149€ | 171€ |
| 50k€+ | 229€ | 263€ |

**Match score = filtre + ranking, PAS facteur de prix.** Le même lead coûte le même prix à tous les experts qui le reçoivent. Raisons : (1) le match score varie par expert pour le même prospect → prix différents pour le même lead = confus et injuste, (2) match élevé = prix plus élevé → incentive perverse (expert pénalisé pour être un bon match), (3) aucune plateforme B2B leader n'utilise le match score comme variable de prix.

**Expert `max_lead_price` :** L'expert peut fixer un plafond par lead via `preferences.max_lead_price`. Agit comme deal-breaker au matching : si `final_price > max_lead_price` → expert exclu du match pour ce lead. Pas de limite par défaut (tous les tiers éligibles). Dashboard affiche : nombre de leads manqués à cause du max + estimation du % du pool accessible avec le max actuel. Information factuelle au moment du réglage, jamais manipulatoire.

**Budget non déclaré :** Tier par défaut (49€). Le prospect ne sait pas que son budget influence le prix du lead — pas d'incentive à sous-déclarer. Le prospect déclare son budget pour le matching (être connecté au bon expert), pas pour le pricing. Sous-déclarer dégrade la qualité de son propre match (guard-rail naturel). La déclaration de budget peut être configurée comme obligatoire ou optionnelle par satellite/vertical via `satellite_configs.quiz_schema`.

**Rationale:** Le budget prospect est le seul facteur directement corrélé à la valeur du deal, transparent, prédictible, et conforme aux standards industrie (Thumbtack : prix par valeur du job, Bark : crédits variables par valeur estimée). La qualification en 2 niveaux ajoute une nuance de valeur sans complexifier le calcul ROI. Tous les ratios coût/valeur sont très favorables à l'expert (<3%) → le pricing est un no-brainer à tous les tiers.
**Impact:** Remplacement du range "100–200€" dans context.md et PRD-001. Formule de calcul implémentée dans `processLeadBilling`. `leads.amount` renseigné à la création du lead. Grille publiée dans l'onboarding expert et le dashboard.
**Date:** 2026-02-22

---

### DEC-2026-02-22-66 — Hyperdrive + postgres.js replaces Supabase JS for DB queries

**Context:** All 48 database queries use `@supabase/supabase-js` (PostgREST/HTTP). Each Worker invocation opens a new HTTP connection — no pooling, no caching. The score-computation consumer (7 sequential queries) pays ~210ms in HTTP overhead. Supabase Micro plan has 60 connection limit.
**Decision:** Hyperdrive (free on Workers Paid) for TCP connection pooling + query caching. `postgres` v3.4.4+ (tagged template SQL, zero sub-dependencies, serverless-native) replaces Supabase JS for all DB queries. No ORM (Drizzle) — SQL direct with existing types via `sql<T[]>`. Supabase JS retained ONLY for `supabase.auth.getUser()` in auth middleware. Connection string: Supabase Direct (port 5432, bypasses Supavisor). Config: `prepare: true` for Hyperdrive query cache compatibility.
**Rationale:** 6× latency improvement on multi-query paths. Connection pooling protects against Supabase connection exhaustion. postgres.js tagged templates are injection-safe, zero-config, type-safe with existing interfaces. No RLS dependency (service key bypass). Migration is mechanical (48 queries, 11 files).
**Impact:** E06S18 (foundation story). All subsequent stories (E06S19–E06S26) build on this.
**Date:** 2026-02-22

---

### DEC-2026-02-22-65 — Analytics Engine for matching observability

**Context:** No observability into matching pipeline performance (latency, cache hits, scoring quality).
**Decision:** Analytics Engine dataset `matching-metrics`. Fire-and-forget `writeDataPoint()` (not awaited, try/catch). Tracks: latency_ms, cache_layer, pool_size, vectorize_candidates, top_score, mean_score. No-op if binding missing.
**Rationale:** Free (100K events/day on Workers Paid), zero-latency (fire-and-forget), queryable via CF Dashboard/GraphQL.
**Impact:** E06S26. Binding: `MATCHING_ANALYTICS: AnalyticsEngineDataset`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-64 — CF Rate Limiting binding replaces manual KV rate limiter

**Context:** Current rate limiting uses manual KV-based implementation (10 req/60s per IP). Wastes KV reads/writes on every request.
**Decision:** CF Rate Limiting binding (free on Workers Paid) replaces `src/lib/rateLimit.ts`. 30 req/min per IP on public endpoints. Native binding API — zero storage overhead.
**Rationale:** Native, free, no KV waste, cleaner code. `RATE_LIMITING` KV namespace removable after migration.
**Impact:** E06S20. Removes KV dependency for rate limiting.
**Date:** 2026-02-22

---

### DEC-2026-02-22-63 — Turnstile on public prospect endpoints

**Context:** `POST /api/prospects/submit` is unauthenticated and publicly accessible. No bot protection.
**Decision:** Turnstile invisible CAPTCHA on `POST /api/prospects/submit`. Server-side verification via `challenges.cloudflare.com/turnstile/v0/siteverify`. Test mode in staging/dev (test keys always pass). Missing/invalid token → 422.
**Rationale:** Free, invisible, zero friction for real users. Protects the most critical public endpoint.
**Impact:** E06S20. Requires `TURNSTILE_SECRET_KEY` secret + site key from CF Dashboard.
**Date:** 2026-02-22

---

### DEC-2026-02-22-62 — Vectorize + Workers AI for semantic matching

**Context:** Current matching relies on 30 manual SKILL_ALIASES and 8 INDUSTRY_PROXIMITY pairs. Fails on long tail: "data science" ≠ "machine learning", "medtech" ≠ "biotech".
**Decision:** `@cf/baai/bge-base-en-v1.5` (768 dims) for embeddings. Vectorize cosine similarity for semantic pre-filtering (top-K candidates). `scoreMatch()` deterministic for final ranking. Blended scoring: 0.7 × exact + 0.3 × vector. Graceful fallback if Vectorize unavailable → deterministic-only path.
**Rationale:** Semantic matching captures relationships that alias maps cannot. Vectorize pre-filtering reduces scoring from O(N) to O(K). Workers AI free tier (10K neurons/day) sufficient for registration-time embeddings.
**Impact:** E06S21 (infrastructure) + E06S22 (scoring integration). Bindings: `AI: Ai`, `EXPERT_INDEX: VectorizeIndex`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-61 — D1 as edge serving layer (hybrid Supabase + D1)

**Context:** Expert pool reads are the hottest read path. KV is fast but not queryable. Need edge SQL for filtered reads.
**Decision:** Supabase = source of truth. D1 = edge read cache (denormalized expert_pool table). Cron sync every 5 min via Hyperdrive. Fallback chain: Cache API → D1 → Hyperdrive. D1 is read-only in this architecture.
**Rationale:** D1 provides sub-5ms edge SQL reads. Combined with Cache API L1 (~0ms), origin DB hit rate drops to near-zero for reads. Cron sync keeps D1 fresh within 5 minutes.
**Impact:** E06S23 (D1 + sync) + E06S19 (Cache API L1). Binding: `EXPERT_DB: D1Database`.
**Date:** 2026-02-22

---

### DEC-2026-02-22-60 (REVISED) — Scalable Matching Engine: implement now

**Supersedes:** DEC-2026-02-22-60 (documentation only)
**Context:** Matching engine works but has 5 structural weaknesses: B1 (O(N) match inserts), B2 (KV bypass), B3 (30 manual skill aliases), B4 (8 manual industry pairs), B5 (no scale infrastructure). Analysis confirms: matching IS the core value, Hyperdrive is free, migration is mechanical, risk of connection exhaustion is real.
**Decision:** Implement in 4 phases. Phase 1: Hyperdrive + postgres.js + Smart Placement + bug fixes (E06S18). Phase 2 (parallel): Cache API L1 (E06S19) + Rate Limiting + Turnstile (E06S20) + Vectorize infra (E06S21) + Analytics (E06S26). Phase 3: Semantic scoring (E06S22) + D1 edge (E06S23). Phase 4: Service Bindings (E06S24) + Durable Objects (E06S25). Total additional CF cost: ~$7-8/month.
**Rationale:** The matching engine is the platform's core value proposition. Broken matches = broken trust = lost users. Hyperdrive + postgres.js foundation is $0 and makes every subsequent story faster. Connection pooling is a safety net against Supabase Micro's 60-connection limit.
**Impact:** 9 new stories (E06S18–E06S26) added to backlog. Critical path: E06S18 → E06S21 → E06S22 → E06S24.
**Date:** 2026-02-22

---

### DEC-2026-02-22-60 — Scoring/Matching Scalability Path (documentation only)

**Context:** E06S09 delivered with in-memory scoring for MVP scale (10-50 experts). Need to document the scaling path before it becomes urgent, without implementing anything now.
**Decision:** Scaling path documented in 4 phases:

| Phase | Seuil | Mécanisme | Impact |
|-------|-------|-----------|--------|
| Phase 1 (MVP) | 10-50 experts | In-memory scoring, KV cache pool, pure function | Actuel — sous 100ms |
| Phase 2 | 100-500 experts | SQL pre-filtering via GIN indexes (`profile->'industries' ?| ARRAY[...]`) avant chargement mémoire. KV pool splitté par satellite_id | Réduit le pool scoré de 60-80% |
| Phase 3 | 500-2000 | Durable Object avec expert pool warm en mémoire. Cursor-based KV pagination | Latence stable |
| Phase 4 | 2000+ | pgvector embeddings pour matching sémantique skills. ML re-ranking | Qualité matching + scale |

**Pas d'implémentation maintenant.** Le seuil Phase 2 (100 experts) est un bon signal pour déclencher la prochaine optimisation. Story dédiée à créer quand ce seuil approche.
**Rationale:** Documenter le chemin avant qu'il soit urgent permet de prendre des décisions architecturales informées (ex: GIN indexes déjà en place via E06S02). Chaque phase est un palier autonome — pas de big bang.
**Impact:** Documentation only. No code changes. Informs future story creation when thresholds approach.
**Date:** 2026-02-22

---

### DEC-2026-02-23-02 — PR-based delivery + preview deployments + model selection

**Context:** Le delivery agent mergeait directement sur staging via `git merge --squash`. Aucune revue de code avant staging. L'humain devait tout vérifier en un seul bloc lors du PR staging→production. Tous les outils majeurs d'agentic coding (Copilot, Codex, Devin) imposent un flux PR — l'IA ne merge jamais directement.
**Decision:** 3 changements architecturaux :

1. **PR-based delivery :** Le delivery agent crée une PR `story/{id}` → staging via `gh pr create`. Il ne merge jamais. L'humain review et merge sur GitHub. Le backlog passe à `done` = "PR créée, travail agent terminé".

2. **Preview deployments :** GitHub Action `preview-deploy.yml` sur chaque push `story/*`. Pipeline : tsc + vitest + `wrangler versions upload --env staging --preview-alias <slug>`. Preview URL commentée sur la PR. Format : `https://story-e06s15.callibrate-core-staging.frederic-geens-consulting.workers.dev`. La preview partage les bindings staging (KV, Queues, Supabase) — aperçu code, pas environnement isolé.

3. **Model selection :** `GAAI_CLAUDE_MODEL` env var (default: `sonnet`). Le daemon passe `--model $CLAUDE_MODEL` à Claude Code. Sonnet pour les deliveries (coût-efficace), Opus réservé à Discovery/décisions complexes.

**Rationale:** Industry standard unanime — l'IA crée des PRs, pas des merges. Deux niveaux de preview (story isolée + staging complet) permettent une validation progressive. Sonnet réduit le coût des sessions de delivery (~5× moins cher qu'Opus) sans impact qualité sur l'implémentation.
**Impact:** `delivery-loop.workflow.md` Step 8 réécrit (PR au lieu de merge). `delivery.agent.md` git workflow mis à jour. `delivery-daemon.sh` : `--model` flag ajouté. `deploy-staging.yml` : trigger corrigé (staging au lieu de production). `wrangler.toml` : `preview_urls = true`. Nouveau workflow : `.github/workflows/preview-deploy.yml`.
**Date:** 2026-02-23

---

### DEC-2026-02-23-01 — OpenAI integration pattern: function calling for structured extraction (E06S12 impl)

**Context:** E06S12 completed the Anthropic→OpenAI migration for `POST /api/extract`. DEC-48 (archived) decided the provider swap. This entry captures the implementation pattern established.
**Decision:** OpenAI Chat Completions with `tools` + `tool_choice: { type: "function", function: { name: "..." } }` is the canonical pattern for structured AI extraction in this codebase. Response parsed from `choices[0].message.tool_calls[0].function.arguments` (JSON string). Direct `fetch` to `https://api.openai.com/v1/chat/completions` — no CF AI Gateway for OpenAI calls at this stage.
**Error surface:** `'OpenAI API error'` (non-200), `'Invalid response from OpenAI API'` (JSON parse fail), `'AI service unreachable'` (network failure).
**Rationale:** Forced function calling guarantees structured output. The named `tool_choice` form ensures `tool_calls` is always populated. Direct fetch avoids CF AI Gateway complexity for a single endpoint.
**Impact:** Pattern to follow for any future AI extraction or structured-output endpoint using OpenAI. CF AI Gateway re-addition is a separate story if observability is needed.
**Date:** 2026-02-23

---

<!-- Add decisions above this line, newest first -->
