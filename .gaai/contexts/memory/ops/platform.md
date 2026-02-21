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
updated_at: 2026-02-21
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
| **n8n** | Automatisation business (surveys, onboarding sequences) | ops@callibrate.io |
| **OpenAI** | Extraction freetext prospect via GPT-4o-mini (`/api/extract`) | ops@callibrate.io |

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
