# Callibrate Core — Setup Guide

This guide documents all manual steps required to provision Cloudflare infrastructure
after the initial `wrangler login`. Run these commands from the repo root.

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

### Production / dev queues (shared name)

```bash
npx wrangler queues create email-notifications
npx wrangler queues create email-notifications-dlq
npx wrangler queues create lead-billing
npx wrangler queues create lead-billing-dlq
npx wrangler queues create matching-jobs
npx wrangler queues create matching-jobs-dlq
```

### Staging queues

```bash
npx wrangler queues create email-notifications-staging
npx wrangler queues create email-notifications-staging-dlq
npx wrangler queues create lead-billing-staging
npx wrangler queues create lead-billing-staging-dlq
npx wrangler queues create matching-jobs-staging
npx wrangler queues create matching-jobs-staging-dlq
```

> Note: DLQ routing is not yet wired in `wrangler.toml`. After creating the DLQ queues,
> add `dead_letter_queue` properties to each `[[queues.consumers]]` block pointing to
> the corresponding `-dlq` queue name.

---

## Step 3 — Create KV Namespaces

Create one KV namespace per binding per environment. After running each command,
Wrangler prints the namespace ID — copy it into `wrangler.toml` replacing the
corresponding `PLACEHOLDER_*` string.

### Dev namespaces (used by `wrangler dev` via `preview_id`)

```bash
npx wrangler kv namespace create SESSIONS
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="SESSIONS" id=
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="SESSIONS" preview_id=

npx wrangler kv namespace create RATE_LIMITING
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="RATE_LIMITING" id=
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="RATE_LIMITING" preview_id=

npx wrangler kv namespace create FEATURE_FLAGS
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="FEATURE_FLAGS" id=
# -> Copy returned id   into wrangler.toml: [[kv_namespaces]] binding="FEATURE_FLAGS" preview_id=
```

> For `preview_id` you can create a separate preview namespace or reuse the same ID.
> Wrangler recommends a separate one for local dev isolation:
> `npx wrangler kv namespace create SESSIONS --preview`

### Staging namespaces

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

```bash
npx wrangler secret put SUPABASE_URL --env production
# Paste: (production Supabase project URL — may differ from staging)

npx wrangler secret put SUPABASE_ANON_KEY --env production
# Paste: (anon/public key from production Supabase project)

npx wrangler secret put SUPABASE_SERVICE_KEY --env production
# Paste: (service_role key from production Supabase project — keep this private)
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
available in your local environment. For local dev you can set them via a `.dev.vars`
file (gitignored):

```
# .dev.vars  (never commit this file)
SUPABASE_URL=https://xiilmuuafyapkhflupqx.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_SERVICE_KEY=<your-service-key>
```

Wrangler automatically loads `.dev.vars` during `wrangler dev`.
