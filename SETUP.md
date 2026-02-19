# Callibrate Core — Setup Guide

This guide documents all manual steps required to provision Cloudflare infrastructure
after the initial `wrangler login`. Run these commands from the repo root.

---

## Naming Convention

**Rule:** every resource name encodes its project and its environment — `{project}-{resource}-{env}`.

This ensures resources from different Cloudflare projects are immediately distinguishable
in a shared workspace (dashboard, CLI output, billing).

**Dev exception:** `wrangler dev` (local) binds directly to staging remote resources.
No separate `-dev` resources are created or deployed anywhere.

---

### Workers

| Cloudflare worker name | Environment | Deployed via |
|---|---|---|
| `callibrate-core-staging` | staging | push to `main` |
| `callibrate-core-production` | production | push of a `v*` tag |
| `callibrate-core-dev` | local dev | `wrangler dev` — never deployed |

---

### Queues

| Queue name | DLQ name | Used by |
|---|---|---|
| `callibrate-core-email-notifications-staging` | `callibrate-core-email-notifications-staging-dlq` | staging + local dev |
| `callibrate-core-lead-billing-staging` | `callibrate-core-lead-billing-staging-dlq` | staging + local dev |
| `callibrate-core-matching-jobs-staging` | `callibrate-core-matching-jobs-staging-dlq` | staging + local dev |
| `callibrate-core-email-notifications-production` | `callibrate-core-email-notifications-production-dlq` | production |
| `callibrate-core-lead-billing-production` | `callibrate-core-lead-billing-production-dlq` | production |
| `callibrate-core-matching-jobs-production` | `callibrate-core-matching-jobs-production-dlq` | production |

---

### KV Namespaces

Wrangler auto-generates KV namespace names as `{worker-name}_{BINDING}`.
The worker name already carries the env suffix, so KV names follow the convention automatically.

| Cloudflare namespace name | Binding in code | Used by |
|---|---|---|
| `callibrate-core-staging_SESSIONS` | `SESSIONS` | staging + local dev |
| `callibrate-core-staging_RATE_LIMITING` | `RATE_LIMITING` | staging + local dev |
| `callibrate-core-staging_FEATURE_FLAGS` | `FEATURE_FLAGS` | staging + local dev |
| `callibrate-core-production_SESSIONS` | `SESSIONS` | production |
| `callibrate-core-production_RATE_LIMITING` | `RATE_LIMITING` | production |
| `callibrate-core-production_FEATURE_FLAGS` | `FEATURE_FLAGS` | production |

---

### Supabase

Only one Supabase project is available at this stage.
Production will be provisioned from the staging schema at launch.

| Supabase project | Used by |
|---|---|
| `callibrate-staging` | staging + local dev |
| `callibrate-production` | production — *(not yet created, deferred to launch)* |

---

### Future resources (R2, D1, Durable Objects…)

Apply the same rule — always prefix with the project name, no separate dev resource:

| Resource type | Staging name | Production name |
|---|---|---|
| R2 Bucket | `callibrate-core-{name}-staging` | `callibrate-core-{name}-production` |
| D1 Database | `callibrate-core-{name}-staging` | `callibrate-core-{name}-production` |
| Durable Object | `callibrate-core-{name}-staging` | `callibrate-core-{name}-production` |
| Queue | `callibrate-core-{name}-staging` | `callibrate-core-{name}-production` |

---

## Prerequisites

| Tool | Version |
|------|---------|
| `node` | 22.x or later |
| `npm` | 10.x or later |
| `wrangler` | 4.x (installed via `npm install` in this repo) |

---

## Step 1 — Authenticate Wrangler

```bash
npx wrangler login
```

Follow the browser prompt to authenticate with your Cloudflare account.
Confirm with: `npx wrangler whoami`

---

## Step 2 — Create Queues

Cloudflare Queues must be created via the Wrangler CLI (or dashboard). Each main queue
needs a corresponding Dead Letter Queue (DLQ).

> Dev local uses the staging queues directly — no separate dev queues to create.

### Staging queues *(also used by local dev)*

```bash
npx wrangler queues create callibrate-core-email-notifications-staging
npx wrangler queues create callibrate-core-email-notifications-staging-dlq
npx wrangler queues create callibrate-core-lead-billing-staging
npx wrangler queues create callibrate-core-lead-billing-staging-dlq
npx wrangler queues create callibrate-core-matching-jobs-staging
npx wrangler queues create callibrate-core-matching-jobs-staging-dlq
```

### Production queues

```bash
npx wrangler queues create callibrate-core-email-notifications-production
npx wrangler queues create callibrate-core-email-notifications-production-dlq
npx wrangler queues create callibrate-core-lead-billing-production
npx wrangler queues create callibrate-core-lead-billing-production-dlq
npx wrangler queues create callibrate-core-matching-jobs-production
npx wrangler queues create callibrate-core-matching-jobs-production-dlq
```

> DLQ routing is wired in `wrangler.toml` via `dead_letter_queue` on each consumer.
> The DLQ queues must still be created on Cloudflare (commands above).

---

## Step 3 — Create KV Namespaces

Create one KV namespace per binding per environment. After running each command,
Wrangler prints the namespace ID — copy it into `wrangler.toml` replacing the
corresponding `PLACEHOLDER_*` string.

> Dev local reuses the staging KV namespace IDs — no separate dev namespaces to create.
> After creating the staging namespaces below, copy their IDs into **both** the root
> `[[kv_namespaces]]` block and the `[[env.staging.kv_namespaces]]` block in `wrangler.toml`.

### Staging namespaces *(also used by local dev)*

```bash
npx wrangler kv namespace create SESSIONS --env staging
# -> Copy returned id into wrangler.toml: [[env.staging.kv_namespaces]] binding="SESSIONS" id=

npx wrangler kv namespace create RATE_LIMITING --env staging
# -> Copy returned id into wrangler.toml: [[env.staging.kv_namespaces]] binding="RATE_LIMITING" id=

npx wrangler kv namespace create FEATURE_FLAGS --env staging
# -> Copy returned id into wrangler.toml: [[env.staging.kv_namespaces]] binding="FEATURE_FLAGS" id=
```

### Production namespaces

```bash
npx wrangler kv namespace create SESSIONS --env production
# -> Copy returned id into wrangler.toml: [[env.production.kv_namespaces]] binding="SESSIONS" id=

npx wrangler kv namespace create RATE_LIMITING --env production
# -> Copy returned id into wrangler.toml: [[env.production.kv_namespaces]] binding="RATE_LIMITING" id=

npx wrangler kv namespace create FEATURE_FLAGS --env production
# -> Copy returned id into wrangler.toml: [[env.production.kv_namespaces]] binding="FEATURE_FLAGS" id=
```

After updating all 9 IDs in `wrangler.toml`, no `PLACEHOLDER_*` strings should remain.

---

## Step 4 — Set Secrets

Secrets are never hardcoded. Bind them per environment using `wrangler secret put`.
You will be prompted to paste the value interactively (nothing is echoed to the terminal).

Find the values in the Supabase dashboard at:
`https://supabase.com/dashboard/project/xiilmuuafyapkhflupqx/settings/api`

### Staging secrets

```bash
npx wrangler secret put SUPABASE_URL --env staging
# Paste: https://xiilmuuafyapkhflupqx.supabase.co

npx wrangler secret put SUPABASE_ANON_KEY --env staging
# Paste: (anon/public key from Supabase dashboard)

npx wrangler secret put SUPABASE_SERVICE_KEY --env staging
# Paste: (service_role key from Supabase dashboard — keep this private)
```

### Production secrets

> Production secrets will be configured at launch when the production Supabase
> project is created from the staging schema. Skip this step for now.

```bash
# npx wrangler secret put SUPABASE_URL --env production        # (deferred to launch)
# npx wrangler secret put SUPABASE_ANON_KEY --env production   # (deferred to launch)
# npx wrangler secret put SUPABASE_SERVICE_KEY --env production # (deferred to launch)
```

---

## Step 5 — GitHub Actions Secrets

The CI/CD workflows authenticate to Cloudflare via an API token stored as a GitHub secret.

1. Create a Cloudflare API token at:
   `https://dash.cloudflare.com/profile/api-tokens`
   - Use the "Edit Cloudflare Workers" template
   - Scope it to your account and the `callibrate-core*` Worker names

2. Add the token as a GitHub repository secret:
   `https://github.com/Fr-e-d/callibrate-core/settings/secrets/actions`
   - Secret name: `CLOUDFLARE_API_TOKEN`
   - Value: (paste the token created above)

Once set, pushing to `main` auto-deploys to staging, and pushing a `v*` tag deploys to production.

---

## Step 6 — Verify Local Dev

Install dependencies (one-time):

```bash
npm install
```

Start local dev server:

```bash
npx wrangler dev
```

Expected output:
```
Your worker has access to the following bindings:
- KV Namespaces: SESSIONS, RATE_LIMITING, FEATURE_FLAGS
- Queues: EMAIL_NOTIFICATIONS, LEAD_BILLING, MATCHING_JOBS
⎔ Starting local server...
[wrangler:inf] Ready on http://localhost:8787
```

Test the health endpoint:

```bash
curl http://localhost:8787/api/health
```

Expected response (HTTP 200):

```json
{
  "status": "ok",
  "supabase": "connected",
  "queues": ["email-notifications", "lead-billing", "matching-jobs"]
}
```

If `supabase` shows `"error"`, verify that `SUPABASE_URL` and `SUPABASE_ANON_KEY` are
available in your local environment. For local dev set them via a `.dev.vars` file (gitignored):

```
# .dev.vars  (never commit this file)
# Points to the staging Supabase project (shared with the staging environment)
SUPABASE_URL=https://xiilmuuafyapkhflupqx.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_SERVICE_KEY=<your-service-key>
```

Wrangler automatically loads `.dev.vars` during `wrangler dev`.

