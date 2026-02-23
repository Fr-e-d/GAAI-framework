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
| `callibrate-satellite-staging` | satellite landing pages (multi-tenant) | staging | push to `production` branch |
| `callibrate-satellite-prod` | satellite landing pages (multi-tenant) | production | push of a `v*` tag |
| `callibrate-io-staging` | expert UI (Next.js) | staging | *(separate repo)* |
| `callibrate-io-prod` | expert UI (Next.js) | production | *(separate repo)* |
| `callibrate-ai-staging` | prospect UI (Next.js) | staging | *(separate repo)* |
| `callibrate-ai-prod` | prospect UI (Next.js) | production | *(separate repo)* |
| `callibrate-core-dev` | local dev | never deployed | `wrangler dev` |
| `callibrate-satellite-dev` | satellite local dev | never deployed | `cd workers/satellite && wrangler dev` |

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
| `callibrate-satellite-kv-config-staging` | `CONFIG_CACHE` | satellite staging + local dev |
| `callibrate-satellite-kv-config-prod` | `CONFIG_CACHE` | satellite production |

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

---

## Satellite Worker — `callibrate-satellite` (E06S14)

The satellite Worker serves all satellite landing pages from a single deployed codebase.
Each satellite domain is configured via a row in the `satellite_configs` Supabase table.

### Satellite KV Namespaces

Create one KV namespace per environment for satellite config caching.
Copy the returned ID into `workers/satellite/wrangler.toml` replacing `PLACEHOLDER_*` strings.

```bash
npx wrangler kv namespace create "callibrate-satellite-kv-config-staging"
# -> id into: [[kv_namespaces]] id= AND [[env.staging.kv_namespaces]] binding="CONFIG_CACHE" id=

npx wrangler kv namespace create "callibrate-satellite-kv-config-prod"
# -> id into: [[env.production.kv_namespaces]] binding="CONFIG_CACHE" id=
```

### Satellite Secrets

```bash
# Staging (run from workers/satellite/)
cd workers/satellite
npx wrangler secret put SUPABASE_URL --env staging
# Paste: https://xiilmuuafyapkhflupqx.supabase.co

npx wrangler secret put SUPABASE_ANON_KEY --env staging
# Paste: (anon/public key from Supabase dashboard)

npx wrangler secret put ADMIN_SECRET --env staging
# Paste: (generate a strong random secret)
# openssl rand -base64 32
```

### Custom Domain Setup (per satellite)

For each new satellite domain:

1. **Cloudflare Dashboard** > Workers & Pages > `callibrate-satellite-staging` (or `-prod`)
   > Settings > Domains & Routes > Add Custom Domain > enter the satellite domain
2. Cloudflare will automatically provision SSL and configure DNS

### Satellite Onboarding Checklist

For each new satellite:

- [ ] INSERT row in `satellite_configs` with `active: false` (set all JSONB fields: theme, brand, content, structured_data)
- [ ] Configure DNS: satellite domain points to Cloudflare (NS or CNAME)
- [ ] Add Custom Domain in Cloudflare Dashboard for the satellite Worker
- [ ] Smoke test: `curl https://[satellite_domain]/health` (should 302 to callibrate.io while inactive)
- [ ] Flip `active: true` in `satellite_configs`
- [ ] Smoke test: `curl https://[satellite_domain]/health` (should return `200 { ok: true, ... }`)
- [ ] Verify: `curl https://[satellite_domain]/` returns branded landing page
- [ ] Cloudflare Dashboard > [satellite domain zone] > Security > Bots > AI Training Bots: select "Block on all pages"

### Cache Purge

Force-refresh a satellite's config (without waiting for KV TTL expiry):

```bash
curl -X POST https://[satellite_domain]/admin/cache/purge \
  -H "x-admin-secret: YOUR_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"domain":"[satellite_domain]"}'
```

### Satellite Local Dev

```bash
cd workers/satellite
npm install
npx wrangler dev
# -> http://localhost:8787
```

Create `workers/satellite/.dev.vars` for local development:
```
SUPABASE_URL=https://xiilmuuafyapkhflupqx.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
ADMIN_SECRET=local-dev-secret
```

---

## PostHog MCP Server — AI Analytics Access (E07S05)

Enables Claude Code to query PostHog funnels, dashboards, and experiments directly via the GAAI `analytics-query` skill.

### Prerequisites

- PostHog EU Cloud account with a project created (Settings → Organizations & projects)
- A Personal API Key with **MCP Server preset** (Settings → Personal API Keys → New key → Preset: MCP Server)

### Step 1 — Set environment variable

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export POSTHOG_PERSONAL_API_KEY="Bearer phx_YOURPERSONALAPIKEY"
```

> **Important:** Include the `Bearer ` prefix. The value must be the full Authorization header content.

Reload your shell:

```bash
source ~/.zshrc
```

### Step 2 — Verify MCP server is available

Restart Claude Code. The PostHog MCP server (`posthog`) should appear in your MCP tools list. You can verify with:

```
/mcp
```

### Step 3 — Confirm EU connectivity

The MCP server connects to `https://mcp-eu.posthog.com/mcp` (EU region). Verify your PostHog project is on EU Cloud (Settings → Organization → Region should show "EU").

### Available MCP Tools

Once connected, the following PostHog tools are available to Claude Code:

| Tool | Description |
|------|-------------|
| Query insights | Run HogQL queries and structured insight queries |
| Read dashboards | Retrieve dashboard definitions and data |
| Manage feature flags | Read and update feature flags |
| Read experiments | View A/B test configurations and results |

### Rate Limits

- HogQL queries: 120/hour
- Structured queries: 2400/hour

Plan query frequency accordingly when using the `analytics-query` skill for long analysis sessions.

### Local Dev

The MCP server runs via `npx mcp-remote@latest` — no local installation required. The `npx` call fetches and caches the package on first use.

---

## D1 — Expert Pool Edge Cache (E06S23)

`expert-pool-edge` is a D1 database that caches the expert pool at the edge for <5ms reads.
It is synced from Supabase every 5 minutes via the `*/5 * * * *` cron trigger.

### Create and provision (run from repo root)

```bash
# 1. Create the D1 database (staging)
npx wrangler d1 create expert-pool-edge --env staging
# Copy the returned database_id into wrangler.toml [[env.staging.d1_databases]] database_id=

# 2. Apply the schema (staging)
npx wrangler d1 execute expert-pool-edge --file=d1/expert-pool-edge.schema.sql --env staging

# 3. Create the D1 database (production)
npx wrangler d1 create expert-pool-edge --env production
# Copy the returned database_id into wrangler.toml [[env.production.d1_databases]] database_id=
# Also update top-level [[d1_databases]] database_id= for wrangler dev

# 4. Apply the schema (production)
npx wrangler d1 execute expert-pool-edge --file=d1/expert-pool-edge.schema.sql --env production
```

After updating the database IDs in `wrangler.toml`, deploy to staging:
```bash
npx wrangler deploy --env staging
```

The first cron run (`*/5 * * * *`) will trigger a full load of the expert pool into D1.

### Cache API note

Cache API L1 (60s TTL) requires a **custom domain** — it is silently a no-op on `*.workers.dev`.
- Staging: needs a custom domain or route configured in the Cloudflare Dashboard
- Production: `api.callibrate.io` — Cache API is active

On a miss, D1 serves the request in <5ms. Cache API misses are expected on first hit per datacenter.

## PostHog Proxy Worker — `callibrate-posthog-proxy` (E07S01)

The PostHog proxy routes analytics events through a first-party subdomain (`ph.callibrate.io`),
bypassing ad blockers that block direct calls to `eu.i.posthog.com`. The Worker is a
transparent pass-through — no PostHog API keys are stored in the Worker.

### Workers Table Update

| Name | Scope | Environment | Deployed via |
|---|---|---|---|
| `callibrate-posthog-proxy-staging` | PostHog reverse proxy | staging | push to `staging` branch |
| `callibrate-posthog-proxy-prod` | PostHog reverse proxy | production | push of a `v*` tag |

### DNS Setup

Configure two DNS records in Cloudflare (or your DNS provider) pointing the subdomains to the
Worker. Since the Worker uses Cloudflare zone routes, a proxied (orange-cloud) DNS record is
sufficient.

| Subdomain | Type | Value | Env |
|---|---|---|---|
| `ph.callibrate.io` | CNAME | `callibrate-posthog-proxy-prod.{account}.workers.dev` | Production |
| `ph.staging.callibrate.io` | CNAME | `callibrate-posthog-proxy-staging.{account}.workers.dev` | Staging |

> **Tip:** Once the Worker route `ph.callibrate.io/*` is configured in wrangler.toml, Cloudflare
> intercepts all matching requests at the edge — you can also use a proxied A record pointing to
> `192.0.2.1` (a dummy IP) if a CNAME conflicts with an existing record.

### Cloudflare API Token Scope

Extend the `CLOUDFLARE_API_TOKEN` GitHub secret to include `callibrate-posthog-proxy*` Worker names:

1. Cloudflare Dashboard > Profile > API Tokens > Edit existing token (or create a new one)
2. Ensure the token has **Workers Scripts:Edit** permission scoped to include `callibrate-posthog-proxy*`
3. Update the GitHub secret if the token was changed

### Deploy

No pre-provisioning required (no KV, no Queues, no secrets). Install and deploy:

```bash
cd workers/posthog-proxy
npm install
npx wrangler deploy --env staging    # staging
npx wrangler deploy --env production  # production
```

### Local Dev

```bash
cd workers/posthog-proxy
npm install
npx wrangler dev
# -> http://localhost:8787
```

Test proxy routing locally:
```bash
# Should proxy to eu.i.posthog.com/ingest/batch
curl -X POST http://localhost:8787/ingest/batch \
  -H "Content-Type: application/json" \
  -d '{"batch":[]}'

# Should return PostHog JS SDK
curl http://localhost:8787/static/array.js | head -5
```

### PostHog Account Setup (founder action)

1. Create a PostHog EU Cloud account at [posthog.com](https://posthog.com)
2. Create a new project — select **EU region**
3. Note the **Project API Key** (format: `phc_...`) — needed for E07S02/E07S03
4. In PostHog project settings, set the **API host** to `https://ph.callibrate.io`
   (or `https://ph.staging.callibrate.io` for staging testing)

### Smoke Test (post-deploy)

After deploying to staging and configuring DNS:

```bash
# Should return 200 from PostHog EU assets
curl -I https://ph.staging.callibrate.io/static/array.js

# Should return PostHog's response (1 for accepted)
curl -X POST https://ph.staging.callibrate.io/ingest/batch \
  -H "Content-Type: application/json" \
  -d '{"api_key":"phc_test","batch":[]}'
```

---

## PostHog Dashboards Setup (E07S04)

Creates 3 pre-configured dashboards in PostHog EU Cloud:
- **Prospect Conversion Funnel** — 5-step funnel with `satellite_id` breakdown, last 30 days
- **Expert Activation Funnel** — 4-step funnel from registration to first booking, last 30 days
- **Business Overview** — daily trends (form submissions, bookings, registrations) + conversion rate

### Prerequisites

1. PostHog EU Cloud account with a project created (E07S01 prerequisite)
2. **Personal API Key** — NOT the Project API Key (the Dashboard API requires a Personal API Key)
   - Generate at: `https://eu.posthog.com/settings/user-api-keys`
   - Required scopes: Dashboard read + write, Insight read + write
3. **Project ID** — the numeric ID visible in your PostHog project URL:
   `https://eu.posthog.com/project/{PROJECT_ID}/...`

### Run the script

```bash
POSTHOG_PERSONAL_API_KEY=phx_xxx POSTHOG_PROJECT_ID=12345 npx tsx scripts/posthog-setup-dashboards.ts
```

The script is **idempotent** — running it multiple times is safe. If a dashboard with the same name already exists, it is skipped. Dashboard URLs are printed on success.

### What the script creates

| Dashboard | Insight type | Key config |
|-----------|-------------|------------|
| Prospect Conversion Funnel | FUNNELS | 5 steps, breakdown: `satellite_id`, 14-day window, 30d range |
| Expert Activation Funnel | FUNNELS | 4 steps, 30-day window, 30d range |
| Business Overview | TRENDS (×4) | Daily counts + formula-based conversion rate |
