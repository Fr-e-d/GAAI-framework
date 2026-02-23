# Callibrate Core — Setup Guide

This guide documents all manual steps required to provision Cloudflare infrastructure
after the initial `wrangler login`. Run these commands from the repo root.

---

## Naming Convention

```
{scope}-{entity}-{resource}-{env}
```

| Segment | Values | Notes |
|---|---|---|
| `{scope}` | `callibrate-core` · `callibrate-io` · `callibrate-ai` | Which application owns this resource |
| `{entity}` | `queue` · `kv` · `r2` · `d1` · `workflow` | Resource type — omitted for Workers (the worker IS the scope) |
| `{resource}` | slug describing what the resource does | e.g. `email-notifications`, `sessions` |
| `{env}` | `staging` · `prod` | No "dev" — local dev binds to staging resources directly |

**Dev exception:** `wrangler dev` binds to staging remote resources. No separate local resources are created.

**Scope ownership:** KV, Queues, R2, D1, and Workflows always belong to `callibrate-core`.
`callibrate-io` and `callibrate-ai` are UI workers — they call the API, never touch storage directly.

---

### Workers

| Name | Scope | Environment | Deployed via |
|---|---|---|---|
| `callibrate-core-staging` | core API + queue consumers | staging | push to `production` branch |
| `callibrate-core-prod` | core API + queue consumers | production | push of a `v*` tag |
| `callibrate-io-staging` | expert UI (Next.js) | staging | *(separate repo)* |
| `callibrate-io-prod` | expert UI (Next.js) | production | *(separate repo)* |
| `callibrate-ai-staging` | prospect UI (Next.js) | staging | *(separate repo)* |
| `callibrate-ai-prod` | prospect UI (Next.js) | production | *(separate repo)* |
| `callibrate-core-dev` | local dev | never deployed | `wrangler dev` |

---

### Queues

| Queue name | DLQ name | Used by |
|---|---|---|
| `callibrate-core-queue-email-notifications-staging` | `callibrate-core-queue-email-notifications-staging-dlq` | staging + local dev |
| `callibrate-core-queue-lead-billing-staging` | `callibrate-core-queue-lead-billing-staging-dlq` | staging + local dev |
| `callibrate-core-queue-email-notifications-prod` | `callibrate-core-queue-email-notifications-prod-dlq` | production |
| `callibrate-core-queue-lead-billing-prod` | `callibrate-core-queue-lead-billing-prod-dlq` | production |

---

### KV Namespaces

Created manually with explicit names (see Step 3). Binding names in code are uppercase.

| Cloudflare namespace name | Binding in code | Used by |
|---|---|---|
| `callibrate-core-kv-sessions-staging` | `SESSIONS` | staging + local dev |
| `callibrate-core-kv-rate-limiting-staging` | `RATE_LIMITING` | staging + local dev |
| `callibrate-core-kv-feature-flags-staging` | `FEATURE_FLAGS` | staging + local dev |
| `callibrate-core-kv-expert-pool-staging` | `EXPERT_POOL` | staging + local dev |
| `callibrate-core-kv-sessions-prod` | `SESSIONS` | production |
| `callibrate-core-kv-rate-limiting-prod` | `RATE_LIMITING` | production |
| `callibrate-core-kv-feature-flags-prod` | `FEATURE_FLAGS` | production |
| `callibrate-core-kv-expert-pool-prod` | `EXPERT_POOL` | production |

---

### Supabase

One Supabase project available at this stage. Production provisioned at launch.

| Supabase project | Used by |
|---|---|
| `callibrate-staging` | staging + local dev |
| `callibrate-prod` | production — *(not yet created, deferred to launch)* |

---

### Future resources (R2, D1, Workflows…)

Same rule — `callibrate-core-{entity}-{resource}-{env}`, no dev variant:

| Example | Staging | Production |
|---|---|---|
| R2 bucket for avatars | `callibrate-core-r2-avatars-staging` | `callibrate-core-r2-avatars-prod` |
| D1 main database | `callibrate-core-d1-main-staging` | `callibrate-core-d1-main-prod` |
| Workflow for matching | `callibrate-core-workflow-matching-staging` | `callibrate-core-workflow-matching-prod` |

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
npx wrangler queues create callibrate-core-queue-email-notifications-staging
npx wrangler queues create callibrate-core-queue-email-notifications-staging-dlq
npx wrangler queues create callibrate-core-queue-lead-billing-staging
npx wrangler queues create callibrate-core-queue-lead-billing-staging-dlq
```

### Production queues

```bash
npx wrangler queues create callibrate-core-queue-email-notifications-prod
npx wrangler queues create callibrate-core-queue-email-notifications-prod-dlq
npx wrangler queues create callibrate-core-queue-lead-billing-prod
npx wrangler queues create callibrate-core-queue-lead-billing-prod-dlq
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

KV namespaces are created with explicit names (not via `--env` auto-naming) to match the convention.
Copy the returned ID into `wrangler.toml` for both the root block and the env-specific block.

### Staging namespaces *(also used by local dev)*

```bash
npx wrangler kv namespace create "callibrate-core-kv-sessions-staging"
# -> id into: [[kv_namespaces]] id= AND [[env.staging.kv_namespaces]] binding="SESSIONS" id=

npx wrangler kv namespace create "callibrate-core-kv-rate-limiting-staging"
# -> id into: [[kv_namespaces]] id= AND [[env.staging.kv_namespaces]] binding="RATE_LIMITING" id=

npx wrangler kv namespace create "callibrate-core-kv-feature-flags-staging"
# -> id into: [[kv_namespaces]] id= AND [[env.staging.kv_namespaces]] binding="FEATURE_FLAGS" id=

npx wrangler kv namespace create "callibrate-core-kv-expert-pool-staging"
# -> id into: [[kv_namespaces]] binding="EXPERT_POOL" id= AND preview_id=
#             [[env.staging.kv_namespaces]] binding="EXPERT_POOL" id=
```

### Production namespaces

```bash
npx wrangler kv namespace create "callibrate-core-kv-sessions-prod"
# -> id into: [[env.production.kv_namespaces]] binding="SESSIONS" id=

npx wrangler kv namespace create "callibrate-core-kv-rate-limiting-prod"
# -> id into: [[env.production.kv_namespaces]] binding="RATE_LIMITING" id=

npx wrangler kv namespace create "callibrate-core-kv-feature-flags-prod"
# -> id into: [[env.production.kv_namespaces]] binding="FEATURE_FLAGS" id=

npx wrangler kv namespace create "callibrate-core-kv-expert-pool-prod"
# -> id into: [[env.production.kv_namespaces]] binding="EXPERT_POOL" id=
```

After updating all IDs in `wrangler.toml`, no `PLACEHOLDER_*` strings should remain.

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

npx wrangler secret put OPENAI_API_KEY --env staging
# Paste: (API key from https://platform.openai.com/api-keys)




npx wrangler secret put PROSPECT_TOKEN_SECRET --env staging
# Already set — skip if already done
# openssl rand -base64 32 | npx wrangler secret put PROSPECT_TOKEN_SECRET --env staging
```

### Production secrets

> Production secrets will be configured at launch when the production Supabase
> project is created from the staging schema. Skip this step for now.
> `PROSPECT_TOKEN_SECRET` for production is already set.

```bash
# npx wrangler secret put SUPABASE_URL --env production            # (deferred to launch)
# npx wrangler secret put SUPABASE_ANON_KEY --env production       # (deferred to launch)
# npx wrangler secret put SUPABASE_SERVICE_KEY --env production    # (deferred to launch)
# npx wrangler secret put OPENAI_API_KEY --env production              # (deferred to launch)

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

Once set, pushing to the `production` branch auto-deploys to staging, and pushing a `v*` tag deploys to production.

**Production tag convention:** `v0.{EPIC_NUMBER}.{STORY_NUMBER}` — e.g. `v0.6.7` for E06S07.
```bash
git tag v0.6.7 -m "E06S07: Satellite Funnel API" && git push origin v0.6.7
```

---

## Google Calendar OAuth Secrets (E06S10)

wrangler secret put GOOGLE_CLIENT_ID
# Paste: OAuth 2.0 Client ID from Google Cloud Console (Credentials page)

wrangler secret put GOOGLE_CLIENT_SECRET
# Paste: OAuth 2.0 Client Secret from Google Cloud Console

wrangler secret put GCAL_TOKEN_ENCRYPTION_KEY
# Paste: base64-encoded 32-byte AES-256 key
# Generate: openssl rand -base64 32


**Required redirect URIs in Google Cloud Console (Authorized redirect URIs):**
- Staging:    https://callibrate-core-staging.{account}.workers.dev/api/gcal/callback
- Production: https://api.callibrate.io/api/gcal/callback

---

## Email Deliverability — Sending Domain & DMARC (E06S15)

### Sending domain: `send.callibrate.io`

Transactional emails are sent from `notifications@send.callibrate.io` via Resend.
The subdomain isolates ESP reputation from the root domain, allowing a future
marketing email subdomain without cross-contamination.

**Resend dashboard setup:**
1. Add domain `send.callibrate.io` in Resend > Domains
2. Add the 3 DNS records Resend provides (DKIM x2 + SPF)
3. Verify the domain in Resend
4. Disable click tracking and open tracking (transactional emails only)

### DMARC record

Add a TXT record on `_dmarc.callibrate.io`:

```
v=DMARC1; p=none; rua=mailto:<report-address>@dmarc-reports.cloudflare.net
```

Start with `p=none` (monitoring). Upgrade to `p=reject` after 72h of clean reports.
Reports are managed via Cloudflare DMARC Management.

### Environment variables (non-secret)

| Variable | Purpose | Default value |
|---|---|---|
| `EMAIL_FROM_DOMAIN` | Sending subdomain for Resend | `send.callibrate.io` |
| `EMAIL_REPLY_TO` | Reply-to address on all transactional emails | `support@callibrate.io` |

These are set as `[vars]` in `wrangler.toml` (staging + production) and in `.dev.vars` for local development.

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
- Queues: EMAIL_NOTIFICATIONS, LEAD_BILLING
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
  "queues": ["email-notifications", "lead-billing"]
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

