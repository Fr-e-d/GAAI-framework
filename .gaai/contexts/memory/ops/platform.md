---
type: memory
category: ops
id: OPS-001
tags:
  - ops
  - infrastructure
  - dns
  - email
  - providers
created_at: 2026-02-21
updated_at: 2026-02-27
---

# Platform Operations

> Ce fichier documente les décisions opérationnelles de la plateforme Callibrate.
> Il est destiné à toute personne — technique ou non — qui gère ou contribue à l'infrastructure de la plateforme.
> En cas de doute sur une procédure, consulter ce fichier en premier.

---

## Domaines

| Domaine | Usage | Statut |
|---|---|---|
| `callibrate.io` | Landing page expert (marketing, inscription) | Actif |
| `app.callibrate.io` | Dashboard expert authentifié | Actif |
| `api.callibrate.io` | API publique (toutes les UIs consomment ce point d'entrée) | Actif |
| Satellites (TBD) | Sites prospects — directory + funnel matching | À créer |

**Registrar (détenteur des domaines) :** OVHcloud
→ OVHcloud sert uniquement à renouveler les domaines et à payer. On ne touche pas à la configuration DNS depuis OVHcloud.

---

## DNS

**Qui gère le DNS ?** Cloudflare exclusivement.

Les nameservers des domaines Callibrate pointent vers Cloudflare (`xxx.ns.cloudflare.com`). Cela signifie :
- Toute modification DNS se fait dans le **Cloudflare dashboard** → zone du domaine → DNS.
- OVHcloud ne peut plus modifier les enregistrements DNS (c'est voulu).
- Cloudflare est autorité sur le DNS = proxy CDN, WAF, bot management, Workers custom domains sont tous actifs.

**Pourquoi Cloudflare et pas OVHcloud DNS ?**
L'intégralité du stack technique (Workers, Queues, KV, CDN, bot blocking) requiert que Cloudflare soit l'autorité DNS. Sans ça, aucune de ces fonctionnalités n'est opérationnelle.

---

## Email

### Architecture

Cloudflare Email Routing est activé sur `callibrate.io`.
Toutes les adresses `@callibrate.io` sont des **alias de redirection** — elles n'ont pas de boîte propre. Chaque email reçu est automatiquement redirigé vers l'adresse personnelle du founder.

### Adresses et leurs usages

| Adresse | Usage | Redirigée vers |
|---|---|---|
| `ops@callibrate.io` | Comptes providers (Resend, Lemon Squeezy, Google Cloud, OVH, Cloudflare...) | Adresse pro founder |
| `hello@callibrate.io` | Contact public — prospects et experts qui écrivent depuis le site | Adresse pro founder |
| `support@callibrate.io` | Reply-to des emails transactionnels + support futur | Adresse pro founder |

**Règle :** Pour créer un nouveau compte chez un provider, utiliser `ops@callibrate.io` avec subaddressing tant que la plateforme l'accepte — ex: `ops+resend@callibrate.io`, `ops+lemonsqueezy@callibrate.io`. Si le formulaire rejette le `+`, utiliser `ops@callibrate.io` sans tag. Documenter l'adresse exacte utilisée dans le tableau Providers ci-dessous pour faciliter la récupération de compte.

### Email transactionnel (envoi depuis la plateforme)

Les emails envoyés par la plateforme (confirmations de booking, notifications experts, etc.) sont gérés par **Resend** et expédiés depuis le sous-domaine **`send.callibrate.io`** (DEC-55).

| Paramètre | Valeur |
|---|---|
| Sous-domaine d'envoi | `send.callibrate.io` |
| Adresse from | `notifications@send.callibrate.io` |
| Reply-to | `support@callibrate.io` |
| DKIM | Vérifié (Resend) |
| SPF | Vérifié (Resend) |
| DMARC | `p=none` sur `_dmarc.callibrate.io` (hérité par `send.`) → passer à `p=reject` après 72h de monitoring |
| Click tracking | OFF |
| Open tracking | OFF |
| TLS | Opportunistic |
| Receiving | OFF (pas besoin — le reply-to pointe vers le domaine racine) |

**Architecture dual-stream (DEC-55) :**
- `send.callibrate.io` = transactionnel (Resend, actif)
- Futur marketing = sous-domaine séparé (`news.callibrate.io` ou équivalent, ESP séparé ou domaine Resend séparé) — **jamais** sur `send.callibrate.io`
- La séparation dès J0 est impérative : migrer un sous-domaine d'envoi = reset de réputation

Ceci est distinct du Email Routing (qui gère l'entrant). Resend utilise ses propres enregistrements DNS (DKIM, SPF) ajoutés dans Cloudflare DNS lors de la vérification du domaine.

---

## Sécurité — Bots et Crawlers

**Cloudflare Bot Management (zone-level) :** activé sur chaque domaine satellite.
- Réglage : **"Block AI training bots → Block on all pages"**
- À activer dans : Cloudflare dashboard → zone → Security → Bots → AI Training Bots

**Qui est bloqué et pourquoi :**

| Type de bot | Exemples | Règle | Raison |
|---|---|---|---|
| SEO bots | Googlebot, Bingbot | Autorisés partout | Indexation search traditionnelle |
| AI training bots | GPTBot, CCBot, anthropic-ai | Bloqués partout | Empêche les profils experts d'être intégrés dans les LLMs |
| AI answer bots | PerplexityBot, OAI-SearchBot | Autorisés sur pages plateforme, bloqués sur profils individuels | GEO OK, bypass funnel interdit |

Le détail technique (robots.txt, sitemap) est implémenté dans chaque satellite site — voir Story E03S05.

---

## Providers — Comptes et Stack

| Provider | Usage | Compte créé avec |
|---|---|---|
| **Cloudflare** | DNS, CDN, Workers, Queues, KV, bot management, email routing | ops@callibrate.io |
| **OVHcloud** | Registrar (renouvellement domaines uniquement) | ops@callibrate.io |
| **Supabase** | Base de données PostgreSQL + Auth + Storage | ops@callibrate.io |
| **Resend** | Email transactionnel (confirmations booking, notifications) | ops@callibrate.io |
| **Lemon Squeezy** | Paiements (Merchant of Record — gestion TVA internationale) | ops@callibrate.io |
| **Google Cloud** | OAuth2 Google Calendar (booking layer) | ops@callibrate.io |
| ~~**n8n**~~ | SUPPRIMÉ (DEC-59) — remplacé par Cloudflare Workflows | — |
| **OpenAI** | Extraction freetext prospect via GPT-4o-mini (`/api/extract`) | ops@callibrate.io |
| **PostHog EU** | Product analytics — funnels, events, session replay (`eu.posthog.com`) | ops@callibrate.io |
| **Anthropic** | Claude Code (Delivery Agent via Claude Sonnet) — développement assisté par .gaai | Compte perso founder |

---

## Coûts de développement

### Claude API — Delivery (24 stories mesurées + 1 estimée, 24/02/2026)

**Source :** `.gaai/.delivery-logs/*.log` (JSONL) — champ `result.total_cost_usd` par story.
**Outil :** `.gaai/skills/cross/cost-analysis/references/extract-costs.sh` (SKILL-CRS-022).

| Métrique | Valeur |
|---|---|
| Stories mesurées | 24 (+ E07S03 estimée ~$5.50, session interrompue) |
| **Coût total Delivery** | **$149.90** |
| Coût moyen / story | $6.02 |
| Story la moins chère | E07S06 — $1.29 (32 turns, 3.8 min) |
| Story la plus chère | E06S24 — $14.08 (214 turns, 37.7 min) |
| Durée totale | 8h45 (524.9 min) |
| API turns totaux | 1,943 |

**Répartition par modèle :**

| Modèle | Coût | % |
|---|---|---|
| Claude Sonnet 4.6 | $142.96 | 99.0% |
| Claude Haiku 4.5 | $1.43 | 1.0% |

**Structure du coût Sonnet 4.6 :**
- Cache read (173M tokens) : ~$52 (36%)
- Thinking tokens (non séparés dans usage) : ~$57 (40%)
- Output (1.27M tokens) : ~$19 (13%)
- Cache write (3.9M tokens) : ~$15 (10%)
- Input non-caché (<10K tokens) : ~$0.03 (<1%)

**Estimation coût total projet :**

| Phase | Mesuré | Estimé | Total |
|---|---|---|---|
| Delivery (25 stories trackées) | $149.90 | — | $149.90 |
| Delivery (15 stories non trackées, E06S01-S15) | — | ~$105 | ~$105 |
| Discovery (toutes sessions) | — | ~$40 | ~$40 |
| Annexe (debugging, merges, admin) | — | ~$30 | ~$30 |
| **Total** | **$149.90** | **~$175** | **~$325** |

**Lacunes :** E06S01-E06S15 (pas de delivery logs), Discovery sessions (non capturées), sessions annexes.
**Note :** coût théorique API pay-per-use. Avec Claude Max ($100-200/mois), le coût est le forfait mensuel.

### Accès Reddit API

Pattern validé : `curl -s -A "Mozilla/5.0..." "https://www.reddit.com/user/{username}/submitted.json"` fonctionne pour l'extraction de posts et commentaires. WebFetch bloqué sur reddit.com. Pas besoin de credentials pour le contenu public.

---

## CI/CD & Preview Deployments

### Architecture de déploiement

```
story/{id}  →  PR → staging  →  PR → production
     ↓              ↓                   ↓
  preview        deploy staging      deploy prod (tag v*)
```

| Trigger | Workflow | Action |
|---|---|---|
| Push sur `story/*` | `preview-deploy.yml` | tsc + vitest + `wrangler versions upload --preview-alias` → commente preview URL sur la PR |
| Push sur `staging` | `deploy-staging.yml` | `wrangler deploy --env staging` (core + satellite) |
| Tag `v*` | `deploy-production.yml` | `wrangler deploy --env production` (core + satellite) |

### Workers Preview URLs

**Mécanisme :** `wrangler versions upload --preview-alias <slug>` (PAS `--branch` qui est un concept Pages).

Upload une nouvelle version du Worker avec un alias de preview, **sans affecter le trafic staging**. Le Worker staging continue de servir sa version actuelle.

**Format URL :** `https://<slug>.callibrate-core-staging.frederic-geens-consulting.workers.dev`
- Exemple : `https://story-e06s15.callibrate-core-staging.frederic-geens-consulting.workers.dev`

**Slug :** nom de branche transformé (`story/E06S15` → `story-e06s15` : `/` → `-`, lowercase).

**Pré-requis :**
- Wrangler v4.21.0+ (l'action `cloudflare/wrangler-action@v3` installe la dernière version)
- `preview_urls = true` dans `wrangler.toml` section `[env.staging]`
- Secret `CLOUDFLARE_API_TOKEN` dans les secrets GitHub du repo

**Limitations (beta) :**
- Uniquement sur le sous-domaine `workers.dev` (pas de custom domains)
- Non supporté pour les Workers avec Durable Objects
- Non supporté pour Workers for Platforms

**Bindings :** la preview partage les mêmes bindings que staging (KV, Queues, Supabase). Pas d'isolation des données — c'est un aperçu du code, pas un environnement séparé.

### Comment accéder à la preview URL

**Depuis la PR GitHub :**
1. Le delivery agent crée la PR `story/{id}` → staging
2. Le push déclenche `preview-deploy.yml`
3. Un commentaire automatique apparaît sur la PR avec l'URL de preview
4. Cliquer sur l'URL → teste directement le Worker de la story

**Depuis le Cloudflare Dashboard :**
1. Dashboard → Workers & Pages → `callibrate-core-staging`
2. Onglet "Deployments" → voir les versions uploadées avec leur preview alias
3. Cliquer sur le lien preview de la version souhaitée

**Manuellement (si on connaît le slug) :**
```
https://story-e06s15.callibrate-core-staging.frederic-geens-consulting.workers.dev
```
Le slug = nom de branche avec `/` → `-` et en lowercase.

**Tester un endpoint spécifique :**
```bash
curl https://story-e06s15.callibrate-core-staging.frederic-geens-consulting.workers.dev/api/health
```

Les previews utilisent les mêmes secrets que staging (configurés via `wrangler secret put --env staging`). Pas besoin de configurer des secrets séparés.

---

### Deux niveaux de preview

1. **Preview story** (branche `story/*`) — teste une story isolée avant de la merger sur staging
2. **Staging** (branche `staging`) — teste l'ensemble des stories mergées avant de promouvoir en production

L'IA ne merge jamais. Elle crée des PRs. Le humain review et merge sur GitHub.

### Pipeline preview-deploy.yml (détail)

1. `npm ci` — install dependencies
2. `tsc --noEmit` — type check
3. `vitest run` — unit tests
4. `wrangler versions upload --env staging --preview-alias $SLUG` — upload preview
5. `actions/github-script` — commente (ou met à jour) la preview URL sur la PR associée

Le commentaire contient un marker HTML `<!-- preview-deploy -->` pour identifier et mettre à jour le commentaire sur les pushes suivants (pas de doublons).

---

## Procédures courantes

### Ajouter un enregistrement DNS
1. Cloudflare dashboard → sélectionner la zone du domaine → DNS → Records
2. Ajouter le record (type A, CNAME, TXT selon besoin)
3. Activer le proxy Cloudflare (nuage orange) sauf si c'est un record API/DKIM (nuage gris)
4. Propagation immédiate via Cloudflare

### Ajouter une adresse email alias
1. Cloudflare dashboard → zone `callibrate.io` → Email → Email Routing
2. Custom addresses → Add address
3. Entrer la nouvelle adresse `xxx@callibrate.io` → Forward to → adresse de destination
4. Confirmer via l'email de vérification envoyé à la destination

### Créer un compte chez un nouveau provider
1. Utiliser `ops@callibrate.io` comme adresse d'inscription
2. Documenter le provider dans ce fichier (tableau Providers ci-dessus)
3. Stocker les credentials dans le gestionnaire de mots de passe de l'équipe (à configurer)

---

## PostHog EU — Analytics Stack (E07)

| Paramètre | Valeur |
|---|---|
| Instance | EU Cloud (`eu.posthog.com`) |
| Projet | Callibrate (ID: `131035`) |
| Project API Key | `phc_9MGVc1dDaNAugnSHJ692t5YuWFNy2WQ4kIHNvlEsXkr` (secret Workers: `POSTHOG_API_KEY`) |
| Personal API Key | `phx_yEouGY3S...` (shell env: `POSTHOG_PERSONAL_API_KEY`, `.dev.vars`) |
| Reverse proxy | `ph.callibrate.io` → `callibrate-posthog-proxy` Worker (E07S01) |
| MCP server | `.mcp.json` → `mcp-eu.posthog.com` (auth via `POSTHOG_PERSONAL_API_KEY`) |
| GAAI skill | `analytics-query` (SKILL-CRS-020) |

**Dashboards (créés 2026-02-26) :**
- [Prospect Conversion Funnel](https://eu.posthog.com/project/131035/dashboard/543054) — 5-step funnel + satellite breakdown
- [Expert Activation Funnel](https://eu.posthog.com/project/131035/dashboard/543055) — 4-step funnel
- [Business Overview](https://eu.posthog.com/project/131035/dashboard/543056) — daily trends + conversion rate

**Architecture (E07S01→E07S05) :**
- Client-side : PostHog JS stub dans satellite HTML (cookieless, `persistence:memory`)
- Server-side : `posthog-node` dans Core API (15 events, `ctx.waitUntil()`)
- Proxy : CF Worker `ph.callibrate.io` → `eu.i.posthog.com` (no API keys stored)

---

## À configurer (en attente)

- [ ] Gestionnaire de mots de passe partagé équipe (1Password Teams ou Bitwarden Business) — à mettre en place avant tout recrutement
- [x] `support@callibrate.io` — configuré (Cloudflare Email Routing → founder)
- [ ] Satellites : activer "Block AI training bots" dans Cloudflare pour chaque nouvelle zone satellite ajoutée

---

## Principes

- **Un seul gestionnaire DNS :** Cloudflare. Jamais OVHcloud pour le DNS.
- **Une seule adresse ops :** `ops@callibrate.io` pour tous les comptes providers.
- **Aucun compte plateforme avec une adresse personnelle externe** — tout passe par les alias `@callibrate.io`.
- **Toute décision opérationnelle significative** est loggée dans `decisions/_log.md` avec son numéro DEC.
