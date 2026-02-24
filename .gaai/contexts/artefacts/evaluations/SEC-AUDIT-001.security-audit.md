---
type: artefact
artefact_type: evaluation
id: SEC-AUDIT-001
track: discovery
created_at: 2026-02-24
updated_at: 2026-02-24
scope: Full codebase — 4 Cloudflare Workers (API, Matching Engine, PostHog Proxy, Satellite)
methodology: Manual code review (5 parallel audit agents) + source verification against Cloudflare docs & OWASP Top 10
---

# Security Audit — Callibrate Codebase

## Executive Summary

Audit exhaustif de la codebase Callibrate (4 Workers Cloudflare, Supabase RLS, OAuth, webhooks, crypto). 17 findings consolidés après déduplication et vérification source. 2 critiques, 5 high, 7 medium, 3 low.

**Verdict global :** La codebase applique de bonnes pratiques fondamentales (postgres.js paramétré, AES-256-GCM, HMAC-SHA256, RLS activé, CORS validé). Les failles identifiées sont concentrées sur **l'absence de protections secondaires** (CSRF OAuth, security headers, rate limiting granulaire, input validation) et non sur des erreurs d'architecture fondamentale.

---

## Findings — Par Sévérité

### CRITICAL

#### SEC-01: OAuth state parameter = plain expert ID (CSRF)
- **Fichiers :** `workers/backend/api/src/handlers/experts/gcal.ts:58,80`
- **Constat :** `state: expertId` — le paramètre OAuth `state` est l'ID expert brut, pas un token aléatoire lié à la session.
- **Risque :** Un attaquant peut forger une URL `accounts.google.com/o/oauth2/v2/auth?state=VICTIM_EXPERT_ID&...` pointant vers sa propre app. Si la victime complète le flow, les tokens Google de la victime sont liés au compte de l'attaquant. → Calendar hijack complet.
- **Ref :** RFC 6749 §10.12 (CSRF via OAuth), OWASP A07:2021
- **Remédiation :** Générer un state aléatoire (32 bytes, `crypto.getRandomValues`), le stocker en KV avec TTL 10 min et l'expert_id associé. Vérifier dans le callback que le state KV existe et correspond à l'expert.

#### SEC-02: `/api/bookings/hold` — aucune authentification, aucun rate limiting
- **Fichiers :** `workers/backend/api/src/handlers/bookings/hold.ts`, `workers/backend/api/src/index.ts:174`
- **Constat :** L'endpoint accepte `expert_id`, `prospect_id`, `start_at`, `end_at` avec une simple validation de type. Pas de JWT, pas de prospect token, pas de rate limit. CORS seul ne protège pas (curl, Postman, scripts).
- **Risque :** Un attaquant peut créer des milliers de holds, bloquant tous les slots de tous les experts pendant 10 min chacun → DoS applicatif. Renouvelable indéfiniment.
- **Ref :** OWASP A04:2021 (Insecure Design), CWE-770
- **Remédiation :** Exiger le prospect token JWT dans le body. Ajouter rate limiting : 5 holds/heure par IP et par prospect_id.

---

### HIGH

#### SEC-03: Missing PKCE dans le flow OAuth Google
- **Fichier :** `workers/backend/api/src/handlers/experts/gcal.ts:51-99`
- **Constat :** Authorization code flow sans code_challenge/code_verifier. Le code est échangé avec seulement client_id + client_secret.
- **Risque :** Si le code d'autorisation est intercepté (redirect leak, extension browser, logs proxy), il peut être échangé par un tiers.
- **Ref :** RFC 7636, Google OAuth recommande PKCE même pour confidential clients.
- **Remédiation :** Ajouter `code_challenge = BASE64URL(SHA256(code_verifier))` dans l'auth URL, envoyer `code_verifier` dans l'échange de token.

#### SEC-04: XSS via JSON-LD `structured_data` dans la landing page satellite
- **Fichier :** `workers/frontend/satellites/src/pages/landing.ts:38`
- **Constat :**
  ```typescript
  `<script type="application/ld+json">${JSON.stringify(config.structured_data)}</script>`
  ```
  `escapeHtml()` est correctement appliqué partout SAUF ici. `JSON.stringify()` n'échappe pas `</script>` — une valeur contenant `"</script><img onerror=alert(1)>"` breakout du tag script.
- **Risque :** Stored XSS si un acteur avec accès DB écrit une payload dans `satellite_configs.structured_data`. Impact : vol de session PostHog, injection de contenu, redirection.
- **Ref :** CWE-79, OWASP A03:2021
- **Remédiation :** Échapper `</` dans la sortie JSON : `.replace(/</g, '\\u003c')` sur le résultat de `JSON.stringify()`.

#### SEC-05: Absence totale de security headers HTTP
- **Fichiers :** TOUS les workers (`index.ts` des 4 workers)
- **Constat :** Aucun header de sécurité sur les réponses :
  - ❌ `Content-Security-Policy`
  - ❌ `X-Content-Type-Options: nosniff`
  - ❌ `X-Frame-Options: DENY`
  - ❌ `Strict-Transport-Security`
  - ❌ `Referrer-Policy`
- **Risque :** MIME sniffing, clickjacking, absence de HSTS (downgrade attacks), fuite de referrer.
- **Ref :** OWASP A05:2021, [Cloudflare Workers Security Headers](https://developers.cloudflare.com/workers/examples/security-headers/)
- **Remédiation :** Middleware global ajoutant les headers à chaque réponse.

#### SEC-06: Admin vectorize reindex — comparaison non constant-time + réutilisation du service key
- **Fichier :** `workers/backend/api/src/handlers/admin/vectorize.ts:15`
- **Constat :**
  ```typescript
  if (authHeader !== `Bearer ${env.SUPABASE_SERVICE_KEY}`) {
  ```
  1. Comparaison string standard (`!==`) → timing attack théorique (atténué en pratique par le réseau).
  2. Le `SUPABASE_SERVICE_KEY` (accès DB complet) est réutilisé comme token d'API admin → si compromis, donne accès à toute la base.
- **Risque :** Confusion de responsabilité. Un seul secret pour deux fonctions (DB admin + API auth).
- **Ref :** CWE-208, principe du moindre privilège
- **Remédiation :** Créer un `ADMIN_API_KEY` dédié. Utiliser `crypto.subtle.timingSafeEqual()` (via encode to ArrayBuffer).

#### SEC-07: Input validation manquante sur `/api/bookings/confirm` et `/api/bookings/reschedule`
- **Fichiers :** `workers/backend/api/src/handlers/bookings/confirm.ts:40-43`, `reschedule.ts:34-40`
- **Constat :**
  - `prospect_email` : pas de validation format email, cast direct `as string` puis envoyé à GCal comme attendee.
  - `prospect_name` : pas de validation longueur.
  - `new_start_at`, `new_end_at` (reschedule) : pas de validation ISO-8601, pas de check `start < end`.
- **Risque :** Données invalides stockées en DB et propagées à GCal. `prospect_email: "<script>..."` persiste dans les bookings.
- **Ref :** CWE-20, OWASP A03:2021
- **Remédiation :** Zod schema avec `z.string().email()`, `z.string().max(255)`, `z.string().datetime()` + check `start < end`.

---

### MEDIUM

#### SEC-08: TURNSTILE_SECRET_KEY en clair dans `[env.staging.vars]`
- **Fichier :** `workers/backend/api/wrangler.toml:131`
- **Constat :** `TURNSTILE_SECRET_KEY = "1x0000000000000000000000000000000AA"` — c'est le token de test CF "always pass". Intentionnel pour staging, mais le pattern est dangereux : si quelqu'un copie-colle pour production, la clé réelle sera committée dans git.
- **Risque :** Pattern anti-sécurité. Les secrets doivent toujours être dans `wrangler secret put`.
- **Ref :** [Cloudflare Secrets docs](https://developers.cloudflare.com/workers/configuration/secrets/)
- **Remédiation :** Supprimer de `[vars]`, utiliser `wrangler secret put` même en staging.

#### SEC-09: `localConnectionString` avec credentials Supabase dans wrangler.toml
- **Fichiers :** `workers/backend/api/wrangler.toml:15`, `workers/backend/matching-engine/wrangler.toml:14`
- **Constat :** `localConnectionString = "postgresql://postgres:postgres@db.xiilmuuafyapkhflupqx.supabase.co:5432/postgres"` — expose le project ID Supabase et des credentials (même par défaut).
- **Risque :** Information disclosure. Le Supabase project ID est public dans git.
- **Remédiation :** Déplacer dans `.dev.vars` (gitignored).

#### SEC-10: JWT prospect/survey — pas de claims `aud`/`iss`/`jti`
- **Fichier :** `workers/backend/api/src/lib/jwt.ts`
- **Constat :** Les tokens prospect et survey contiennent uniquement `prospect_id`/`booking_id` + `exp`. Pas de :
  - `iss` (issuer) → pas de binding à l'application
  - `aud` (audience) → un prospect token signé pour `/matches` est réutilisable sur `/identify`
  - `jti` → impossible de révoquer un token spécifique
- **Risque :** Cross-endpoint token reuse. Si un token fuite, il fonctionne sur tous les endpoints prospect jusqu'à expiration (24h).
- **Ref :** RFC 7519 §4.1, OWASP A07:2021
- **Remédiation :** Ajouter `aud` par endpoint (`matches`, `identify`). Ajouter `iss: "callibrate"`. Optionnel : `jti` pour revocation.

#### SEC-11: Survey JWT TTL = 30 jours
- **Fichier :** `workers/backend/api/src/lib/jwt.ts:123`
- **Constat :** `30 * 86400` — fenêtre de 30 jours pendant laquelle un lien de survey est valide.
- **Risque :** Si un email est compromis ou forwarded, le token reste valide un mois.
- **Remédiation :** Réduire à 7 jours. Implémenter one-time use via KV.

#### SEC-12: CORS validation utilise `SUPABASE_SERVICE_KEY` sur chaque requête
- **Fichier :** `workers/backend/api/src/lib/cors.ts:51`
- **Constat :** `createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY)` est instancié à chaque validation CORS pour vérifier si le domaine est dans `satellite_configs`.
- **Risque :** Le service key (accès DB complet, bypass RLS) est utilisé pour une opération de lookup. Si Supabase JS loggue les headers, le key apparaît dans les logs. Violation du principe du moindre privilège.
- **Remédiation :** Utiliser `SUPABASE_ANON_KEY` + RLS policy sur `satellite_configs` (SELECT public). Ou cacher les domaines validés en KV (TTL 1h).

#### SEC-13: `/api/extract` — prompt injection via `verticalContext`
- **Fichier :** `workers/backend/api/src/routes/extract.ts:182-184`
- **Constat :** `verticalContext` (depuis `satellite_configs.vertical` en DB) est interpolé directement dans le system prompt LLM :
  ```typescript
  `...for the "${verticalContext}" industry vertical...`
  ```
- **Risque :** Si un acteur avec accès DB modifie `satellite_configs.vertical` avec des instructions LLM, le modèle peut être manipulé pour extraire des données différentes.
- **Impact réel :** Faible (requiert accès DB write), mais la pratique est anti-pattern.
- **Remédiation :** Valider `verticalContext` contre une allowlist de verticals connus.

#### SEC-14: Webhook LemonSqueezy — idempotency KV avec TTL limité
- **Fichier :** `workers/backend/api/src/handlers/webhooks/lemonsqueezy.ts`
- **Constat :** L'idempotency key est stockée en KV avec un TTL (probablement 24h). Après expiration, un webhook rejoué sera traité à nouveau (e.g., double welcome credit).
- **Risque :** Replay attack après expiration du TTL.
- **Remédiation :** Idempotency persistante (table DB `webhook_events` avec UNIQUE constraint sur event_id).

---

### LOW

#### SEC-15: Prospect token dans les URL query params
- **Fichier :** `workers/backend/api/src/index.ts:133` — `GET /api/prospects/:id/matches?token=xxx`
- **Constat :** Le token est dans l'URL → visible dans logs serveur, historique browser, header Referer.
- **Risque :** Fuite de token via logs ou browser history.
- **Remédiation :** Migrer vers `Authorization: Bearer` header (breaking change) ou ajouter `Cache-Control: no-store` + `Referrer-Policy: no-referrer`.

#### SEC-16: SECURITY DEFINER fonctions RPC sans validation d'ownership
- **Fichier :** `supabase/migrations/20260223100001_lead_credit_rpc.sql`
- **Constat :** `debit_lead_credit` et `restore_lead_credit` sont `SECURITY DEFINER` (bypass RLS) mais ne vérifient pas que `p_expert_id` correspond à l'utilisateur authentifié.
- **Risque :** Si appelées directement via PostgREST avec un expert_id forgé, elles opèreraient sur le mauvais compte. Mitigé par le fait que l'application valide l'ownership avant l'appel.
- **Remédiation :** Ajouter `ASSERT auth.uid() = p_expert_id` dans les fonctions (defense-in-depth).

#### SEC-17: Pas de validation `Content-Type: application/json` sur les POST
- **Fichier :** Tous les handlers POST
- **Constat :** Les endpoints acceptent n'importe quel Content-Type tant que le body parse en JSON. Pas de rejet explicite de `multipart/form-data`.
- **Risque :** Potentiel CSRF via form submission (mitigé par CORS + absence de cookies).
- **Remédiation :** Rejeter si `Content-Type !== 'application/json'`.

---

## Positive Findings — Ce Qui Est Bien Fait

| Pratique | Status | Détail |
|---|---|---|
| SQL injection | ✅ SAFE | postgres.js tagged templates partout. Aucune concaténation SQL détectée. |
| AES-256-GCM tokens | ✅ SAFE | IV 12 bytes aléatoires, tag authentification intégré. `crypto.getRandomValues()`. |
| HMAC-SHA256 webhooks | ✅ SAFE | `crypto.subtle.verify()` (constant-time natif) pour LemonSqueezy. |
| RLS Supabase | ✅ SAFE | Activé sur toutes les tables sensibles. Default deny. |
| Supabase Auth JWT | ✅ SAFE | Middleware `authenticate()` via `supabase.auth.getUser()` sur tous les endpoints expert/lead. |
| Turnstile bot protection | ✅ SAFE | Vérifié côté serveur sur prospect submit. |
| Secret management | ✅ SAFE | Tous les secrets réels via `wrangler secret put`. `.dev.vars` gitignored. CI/CD via GitHub Secrets. |
| HTML escaping | ✅ SAFE | `escapeHtml()` appliqué sur tout le contenu dynamique dans le satellite (sauf JSON-LD — SEC-04). |
| CF-Connecting-IP | ✅ SAFE | Utilisé pour rate limiting. Header injecté par Cloudflare Edge, non spoofable par le client. |
| Token encryption | ✅ SAFE | GCal refresh tokens chiffrés AES-256-GCM avant stockage DB. |
| Idempotency queues | ✅ SAFE | KV-backed idempotency sur email et billing consumers. |
| Smart Placement | ✅ SAFE | Activé — réduit la latence DB en plaçant le Worker proche de la DB. |

---

## Résumé

| Sévérité | Count | IDs |
|---|---|---|
| CRITICAL | 2 | SEC-01, SEC-02 |
| HIGH | 5 | SEC-03, SEC-04, SEC-05, SEC-06, SEC-07 |
| MEDIUM | 7 | SEC-08 → SEC-14 |
| LOW | 3 | SEC-15, SEC-16, SEC-17 |
| **Total** | **17** | |

---

## Sources

- [RFC 6749 §10.12 — OAuth CSRF](https://datatracker.ietf.org/doc/html/rfc6749#section-10.12)
- [RFC 7636 — PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [OWASP Top 10 (2021)](https://owasp.org/Top10/)
- [Cloudflare Workers Security Headers](https://developers.cloudflare.com/workers/examples/security-headers/)
- [Cloudflare Secrets Management](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
- [Google OAuth PKCE Best Practice](https://developers.google.com/identity/protocols/oauth2/native-app#pkce)
