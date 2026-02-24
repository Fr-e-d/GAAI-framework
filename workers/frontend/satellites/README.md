# callibrate-satellite

Worker Cloudflare multi-tenant qui sert toutes les landing pages satellite depuis un seul déploiement. Chaque domaine satellite est configuré via une ligne dans la table `satellite_configs` de Supabase.

## Architecture

```
Requête entrante (https://n8n-experts.io/)
    ↓
hostname = n8n-experts.io
    ↓
KV cache lookup (satellite:config:n8n-experts.io)
    ├── HIT → config chargé (TTL 3600s)
    └── MISS → Supabase REST query (satellite_configs WHERE domain AND active)
                 ├── trouvé → stocké en KV, config chargé
                 └── pas trouvé → 302 redirect vers callibrate.io
    ↓
Rendu HTML avec design tokens injectés en CSS custom properties
    ↓
CF edge cache (max-age=300, stale-while-revalidate=3600)
```

## Routes

| Route | Méthode | Auth | Description |
|-------|---------|------|-------------|
| `/` | GET | - | Landing page brandée (HTML complet) |
| `/robots.txt` | GET | - | Robots.txt dynamique (bots AI bloqués) |
| `/sitemap.xml` | GET | - | Sitemap XML (/, /match, /experts) |
| `/health` | GET | - | Health check (`{ ok, domain, satellite_id }`) |
| `/admin/cache/purge` | POST | `x-admin-secret` | Purge du cache KV pour un domaine |

## Dev local

```bash
cd workers/frontend/satellites
npm install
npx wrangler dev
# -> http://localhost:8787
```

Creer un fichier `.dev.vars` (gitignored) :

```
SUPABASE_URL=https://xiilmuuafyapkhflupqx.supabase.co
SUPABASE_ANON_KEY=<anon-key-depuis-supabase-dashboard>
ADMIN_SECRET=local-dev-secret
```

## Secrets (par environnement)

Toutes les commandes doivent etre lancees depuis `workers/frontend/satellites/` :

```bash
cd workers/frontend/satellites

# Staging
npx wrangler secret put SUPABASE_URL --env staging
npx wrangler secret put SUPABASE_ANON_KEY --env staging
npx wrangler secret put ADMIN_SECRET --env staging

# Production
npx wrangler secret put SUPABASE_URL --env production
npx wrangler secret put SUPABASE_ANON_KEY --env production
npx wrangler secret put ADMIN_SECRET --env production
```

`ADMIN_SECRET` est une chaine aleatoire que tu generes toi-meme :

```bash
openssl rand -base64 32
```

## KV Namespaces

Deja provisionnes :

| Namespace | ID | Env |
|-----------|-----|-----|
| `callibrate-satellite-kv-config-staging` | `f6319960eb4348d8a3a8a375f5e42d9c` | staging + dev |
| `callibrate-satellite-kv-config-prod` | `3efd7935547146149495a9da3c2e8067` | production |

## Deploiement

Le deploiement est automatique via GitHub Actions (en parallele avec `callibrate-core`) :

- **Staging :** push sur la branche `production` → deploie `callibrate-satellite-staging`
- **Production :** push d'un tag `v*` → deploie `callibrate-satellite-prod`

Deploiement manuel :

```bash
cd workers/frontend/satellites
npx wrangler deploy --env staging
npx wrangler deploy --env production
```

## Ajouter un nouveau satellite

1. **Inserer une ligne** dans `satellite_configs` avec `active: false` :

```sql
INSERT INTO satellite_configs (id, domain, label, vertical, active, theme, brand, content, structured_data, quiz_schema, matching_weights)
VALUES (
  'n8n-experts',
  'n8n-experts.io',
  'n8n Experts',
  'n8n',
  false,
  '{"primary":"#EA4B71","accent":"#FF8C69","font":"Inter, sans-serif","radius":"0.5rem","logo_url":null}',
  '{"name":"n8n Experts","tagline":"L''expert n8n qu''un pair de confiance t''aurait recommande."}',
  '{"meta_title":"Trouvez un expert n8n | n8n Experts","meta_description":"Decrivez votre projet n8n. Matchs en 2 minutes.","hero_headline":"L''expert n8n qu''un pair de confiance t''aurait recommande.","hero_sub":"Decris ton besoin. On te trouve l''expert qui correspond.","value_props":["Pre-qualifies sur tes criteres reels","Call booke dans son agenda","Resultats en moins de 2 minutes"]}',
  '{"@context":"https://schema.org","@type":"ProfessionalService","name":"n8n Experts","url":"https://n8n-experts.io"}',
  '{}',
  '{}'
);
```

2. **Configurer le DNS** : le domaine satellite doit pointer vers Cloudflare (NS ou CNAME)

3. **Ajouter le Custom Domain** dans Cloudflare Dashboard :
   Workers & Pages → `callibrate-satellite-staging` (ou `-prod`) → Settings → Domains & Routes → Add Custom Domain

4. **Smoke test** (encore inactif, doit retourner 302) :
   ```bash
   curl -v https://n8n-experts.io/health
   ```

5. **Activer** :
   ```sql
   UPDATE satellite_configs SET active = true WHERE id = 'n8n-experts';
   ```

6. **Verifier** :
   ```bash
   curl https://n8n-experts.io/health
   # -> { "ok": true, "domain": "n8n-experts.io", "satellite_id": "n8n-experts" }

   curl https://n8n-experts.io/
   # -> HTML avec <h1>n8n Experts</h1>, CSS custom properties, etc.
   ```

7. **Bloquer les bots AI training** dans Cloudflare Dashboard :
   [zone du domaine satellite] → Security → Bots → AI Training Bots → Block on all pages

## Purge du cache

Apres modification d'une config satellite en DB, pour appliquer immediatement (sans attendre le TTL KV de 1h) :

```bash
curl -X POST https://n8n-experts.io/admin/cache/purge \
  -H "x-admin-secret: TON_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"domain":"n8n-experts.io"}'
# -> { "purged": true, "domain": "n8n-experts.io" }
```

## Stack

- **Runtime :** Cloudflare Workers
- **Routing :** [Hono](https://hono.dev/) v4
- **Cache :** KV (config, TTL 3600s) + CF edge cache (HTML 300s, robots/sitemap 86400s)
- **DB :** Supabase REST API (anon key, read-only sur `satellite_configs`)
- **TypeScript :** strict mode
