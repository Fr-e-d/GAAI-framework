---
type: memory
category: patterns
id: PATTERNS-001
tags:
  - patterns
  - conventions
  - procedural
created_at: 2026-02-19
updated_at: 2026-02-22
---

# Patterns & Conventions

> Procedural memory: how things are done in this project.
> Agent-maintained. Updated when durable patterns are confirmed.
> The Delivery Agent loads this before every implementation task.

---

## Git & Version Control

- **Repo:** `github.com/Fr-e-d/callibrate-core` (private, monorepo)
- **Main branch:** `production` — stable, never committed to directly during Delivery
- **Branch per Story:** `story/{id}` (e.g., `story/E06S01`) — created from `production` before any implementation
- **Worktree per Story:** `git worktree add ../{id}-workspace story/{id}` — agent works in isolated directory
  - Parallel Stories = parallel worktrees, zero filesystem conflict
  - Tier 1 shortcut: worktree optional, branch still required
- **Commit format:** conventional commits, AI-assisted work always includes Co-Author line
  ```
  feat(E06S01): bootstrap Supabase + CF Workers + Queues + KV [AC1–AC8]

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  ```
- **Commit types:** `feat` (new Story), `fix` (QA remediation), `chore` (config/tooling), `refactor`, `test`, `docs`
- **Commit timing:** implémentation atomique sur la branche → puis artefacts (impl-report, qa-report, memory-delta) → puis backlog done + mémoire — TOUT sur `story/{id}`, jamais sur `production` directement
- **Anti-pattern confirmé (E06S05) :** Ne pas committer les artefacts ou le backlog directement sur `production` après le squash merge. Tous les commits de gouvernance (artefacts, backlog, mémoire) doivent être sur la branche `story/{id}` avant le merge.
- **Merge strategy:** squash merge to `production` (one commit per Story — clean history)
  ```bash
  git merge --squash story/{id} && git commit -m "feat({id}): {title}"
  ```
- **PR required for:** Tier 3 Stories · schema migrations · auth/security changes (`gh pr create --base production --head story/{id}`)
- **PR optional for:** Tier 1/2 routine Stories (squash merge directly — solo founder MVP context)
- **Cleanup after merge:** `git worktree remove ../{id}-workspace && git branch -d story/{id} && git push origin --delete story/{id}`
- **Never:** force push · commit to `production` directly · leave stale worktrees or branches
- **Ignored files:** `.DS_Store`, `temp/`, `.env`, `node_modules/`, `.wrangler/` — `.gitignore` in root

---

## Code Patterns

- **Workers entrypoint:** `src/index.ts` exports `default { fetch(request, env) }` using `satisfies ExportedHandler<Env>`
- **Env interface:** `src/types/env.ts` — single `Env` interface, all bindings typed: secrets = `string`, KV = `KVNamespace`, Queue producers = `Queue`
- **Queue consumers:** declared in `wrangler.toml` `[[queues.consumers]]` but handler (`queue` export) added in the story that implements the consumer logic — not in bootstrap
- **Queue consumer dispatcher pattern (E06S06):** `queue` export in `src/index.ts` dispatches by `batch.queue.includes('{name}')` to `src/queues/{name}.ts` consumer modules. The `includes()` match handles env suffixes (`-staging`, `-prod`) without branching. Each consumer module exports a single `consume{Name}(batch, env)` function.
- **Queue consumer idempotency pattern (E06S06):** `isAlreadyProcessed(env.SESSIONS, queueName, message.id)` at the top of each message loop iteration (before any side effect). `markProcessed(env.SESSIONS, queueName, message.id)` only after ALL side effects succeed and before `message.ack()`. Key format: `idem:{queue}:{message_id}`, TTL: 86400s. Never mark on failure — ensures safe retry on any partial failure. Utility in `src/lib/idempotency.ts`.
- **Queue retry + DLQ pattern (E06S06):** `handleMessageFailure(message, err, queueName)` in `src/lib/retryQueue.ts`. Exponential backoff: `4^(attempts-1)` seconds → 1s/4s/16s. On `attempts >= 3`: `console.error(JSON.stringify({ queue, message_id, type, payload, error, failed_at }))` before `message.retry({ delaySeconds })`. CF Queue runtime routes to DLQ after max retries. All consumers call this shared util from their catch block — no per-consumer retry duplication.
- **Health endpoint:** `GET /api/health` → `{ status: "ok", supabase: "connected"|"error", queues: [...] }` — returns 503 when Supabase unreachable (not 200-always)
- **Supabase ping in Workers:** `fetch(${SUPABASE_URL}/rest/v1/, { headers: { apikey: SUPABASE_ANON_KEY, Authorization: Bearer ... } })` — uses anon key, not service key
- **Auth middleware pattern (E06S03):** `authenticate(request, env)` returns discriminated union `AuthResult` — caller checks `if (authResult.response)` to short-circuit with 401. Never throws. See `src/middleware/auth.ts`.
- **Zod validation pattern (E06S03):** Always use `safeParse()` (never `.parse()` — throws). On failure: 422 + `{ error: "Validation failed", details: parsed.error.flatten().fieldErrors }`. Use `z.record(z.string(), z.unknown())` for flexible JSONB object fields (Zod v3 — two-argument form required; single-arg is Zod v4+ only).
- **Rate limiter pattern (E06S03):** `src/lib/rateLimit.ts` — KV key `rate_limit:{action}:{ip}` where ip = `CF-Connecting-IP` (fallback `'unknown'` in dev). Sliding window via `expirationTtl`. Enforced after auth, before DB operations.
- **Ownership guard pattern (E06S03):** `user.id !== resourceId` check at handler entry — returns 403 before any DB query. `resourceId` extracted from URL in the router, passed as handler arg.
- **Anthropic tool_use pattern (E06S08):** Use `tool_choice: { type: 'tool', name }` to force structured JSON output from Claude without prompt engineering. Tool schema enforces field types + required fields. Raw `fetch` only — no Anthropic SDK.
- **CF AI Gateway routing (E06S08):** `const apiUrl = \`${env.CLOUDFLARE_AI_GATEWAY_URL}/v1/messages\`` where `CLOUDFLARE_AI_GATEWAY_URL = https://gateway.ai.cloudflare.com/v1/{account}/{gateway}/anthropic`. Header: `x-api-key: env.ANTHROPIC_API_KEY` (NOT `Authorization: Bearer`). `anthropic-version: 2023-06-01`.
- **Non-blocking optional enrichment pattern (E06S08):** Wrap optional DB reads in `try/catch`, use null-check after. Core logic proceeds regardless. Example: `satellite_configs.vertical` lookup for extraction context.
- **JWT pattern — Web Crypto API (E06S07):** `signProspectToken()` / `verifyProspectToken()` in `src/lib/jwt.ts`. No external library — CF Workers provides `crypto.subtle` natively. HMAC-SHA256, base64url encoding, claims `{ prospect_id, exp }`.
- **KV cache-aside pattern (E06S07):** `src/lib/expertPool.ts` — `get(key, { type: 'json' })` → DB fallback on null → `put(key, json, { expirationTtl: 300 })` write-back. Non-blocking write failure (try/catch). Expert pool TTL: 300s.
- **CORS middleware pattern (E06S07):** `handleCors(request, env)` returns `{ allowed, origin, preflight }`. Caller checks `preflight` first (OPTIONS → 204), then `allowed`, then wraps response with `addCorsHeaders(response, origin)`. Blocked origins get 403 WITH `Access-Control-Allow-Origin` header (browser can read error body). No Origin header → allow (server-to-server). Satellite domain whitelist from `satellite_configs.domain` (bare hostname, not full URL).
- **Quiz schema validation pattern (E06S07):** `extractRequiredKeys(quizSchema)` handles two formats — Format A (`{ questions: [{ key, required }] }`) and Format B (`{ fieldKey: { required: true } }`). Returns `[]` for unrecognized formats (liberal — no 422 on unknown schema).
- **AES-256-GCM token encryption pattern (E06S10):** `src/lib/gcalCrypto.ts` — `encryptToken(plaintext, rawKey)` / `decryptToken(stored, rawKey)`. Key: base64-encoded 32-byte raw key (`GCAL_TOKEN_ENCRYPTION_KEY` Worker secret). Storage format: `base64(IV[12 bytes] || ciphertext)`. Uses `crypto.subtle` natively — no library. Error: `GcalDecryptionError` on decrypt failure. Canonical pattern for any sensitive token/secret stored in DB.
- **OAuth2 callback route placement rule (E06S10):** Unauthenticated external callbacks (OAuth, webhooks) MUST be registered BEFORE the authenticated `/api/experts/` block in `index.ts`. Google OAuth redirects without a Bearer token — placing callback inside the auth block causes silent 401 for all users.
- **OAuth2 refresh token preservation pattern (E06S10):** When updating stored tokens, build the update object conditionally — only include `gcal_refresh_token` key when a new refresh token is present. Omit the key entirely (do NOT set to null). Prevents overwriting a valid refresh token when Google only returns a new access token (standard on re-auth without `prompt=consent`).
- **OAuth connected status derivation (E06S10):** `connected: data.gcal_refresh_token != null` — derive from actual token column presence, not from a stored `gcal_connected` boolean. The boolean can drift; the token presence is ground truth.
- **Google OAuth token response field (E06S10 post-delivery fix):** Google's `/oauth2/googleapis.com/token` returns `expires_in` (integer, seconds from now), NOT `expiry_date` (absolute ms timestamp used by google-auth-library). Calculate expiry as `new Date(Date.now() + expires_in * 1000).toISOString()`.
- **Google OAuth email scope (E06S10 post-delivery fix):** Calendar scopes alone (`calendar.events`, `calendar.readonly`) do NOT grant access to user email. Include `openid email` in the scope string to allow the userinfo endpoint to return `email`. Full scope string: `openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly`.
- **Two-step join pattern for indirect FK tables (E06S09):** `call_experience_surveys` and `project_satisfaction_surveys` join to `experts` through `bookings → matches`. Fetch `matchIds` (via `matches.expert_id`) then `bookingIds` (via `bookings.match_id IN matchIds`) once in the parent function, then pass ID arrays to component functions. Avoids unreliable 2-level PostgREST nested filter. Pattern: `from('matches').select('id').eq('expert_id', expertId)` → `from('bookings').select('id').in('match_id', matchIds)`.
- **Parallel component computation pattern (E06S09):** When multiple DB-touching functions share pre-fetched ID arrays, run them concurrently via `Promise.all([...])`. Fetch shared data once at the parent level, pass arrays as arguments. Result: 7 DB queries/invocation (vs. up to 15 with individual nested fetches).
- **Profile JSONB canonical keys for trust_score (E06S09):** `experts.profile` uses these keys for trust_score computation (5 × 20pt each): `portfolio_items: unknown[]` (>0 items), `linkedin_url: string` (present), `years_experience: number` (≥2), `certifications: unknown[]` (>0 items), `bio` or `description: string` (present). Future profile handlers MUST use these same keys.

---

## Supabase Patterns

- **Migration files:** `supabase/migrations/{timestamp}_{name}.sql` — tracked in repo, applied via `mcp__supabase__apply_migration` (DDL)
- **Seed data:** applied via `mcp__supabase__execute_sql` (DML — not tracked as a migration)
- **Migration version:** auto-assigned at apply time (not the filename timestamp) — `list_migrations` returns actual apply timestamp
- **TypeScript types:** generated via `mcp__supabase__generate_typescript_types` → written to `src/types/database.ts` — committed alongside every schema migration, never manually edited
- **Types usage:** `createClient<Database>(url, publishableKey)` — use publishable key with SDK, anon key only for raw REST calls (DEC-37)
- **Verify after migration:** `mcp__supabase__list_tables` — returns `rls_enabled`, columns with `check` field, FKs directly. Preferred over `information_schema` JOIN for CHECK constraint verification.
- **RLS pattern — service-role-only tables:** Enable RLS, add no user-facing policies. Service role bypasses automatically. Supabase advisor reports `rls_enabled_no_policy` INFO notice — expected and correct for internal tables (not a security gap).
- **RLS pattern — user-facing tables:** Enable RLS + add explicit policies per role. Example: `experts` SELECT/UPDATE own row via `auth.uid() = id`.
- **RPC JSONB merge pattern (E06S03):** Postgres function with `SECURITY DEFINER`, `COALESCE` for scalar fields, `||` operator for JSONB fields. Declare signature manually in `database.ts` `Functions:` block — type generator does not capture function signatures reliably. RPC returns `data[]` — check `data.length === 0` for not-found.
- **Partial-failure retry recovery pattern (E06S06):** In multi-step queue consumers that INSERT then call external APIs, catch INSERT error code `23505` (unique violation), fetch the existing row by business key, and continue with the existing row ID. Requires a unique constraint on the business key column. Complements KV idempotency: KV prevents re-processing fully completed messages; unique constraint recovery handles partial completion (step 1 succeeded, step 2+ failed).
- **PostgREST error codes:** `PGRST116` = no rows from `.single()` → 404. `23505` = unique violation → 409. Other errors → generic 500 with `error.message` in details.
- **Service key scope (E06S03, DEC-37):** `createServiceClient(env)` (service key) is used for ALL Worker DB operations and auth token validation (`supabase.auth.getUser(token)`). Anon key retained only for raw REST health check fetch.

---

## Test Patterns

- **Test framework:** `vitest` — added in E06S05. Pure functions (no CF Worker bindings) test cleanly with vitest. Run: `npm run test`.
- **Mocking global fetch in vitest (E06S08):** `vi.stubGlobal('fetch', vi.fn())` in `beforeEach`, `vi.unstubAllGlobals()` in `afterEach`. Then `vi.mocked(fetch).mockResolvedValueOnce(new Response(...))` to mock API calls.
- **scoreMatch timeline behavior:** When a prospect specifies a timeline but the expert has no `accepted_timelines`, the engine returns 0 (no confirmed match). Full points only when: (a) prospect has no timeline requirement, OR (b) expert's `accepted_timelines` explicitly includes the prospect's timeline. Prevents false positives; incentivizes experts to declare preferences.

---

## CF Workflows Patterns (DEC-59, validés contre doc officielle 2026-02-21)

- **wrangler.toml déclaration :** `[[workflows]]` top-level uniquement — `[[env.staging.workflows]]` n'existe pas. L'isolation staging/prod est naturelle : les Worker scripts séparés (`callibrate-core-staging` vs `callibrate-core-prod`) scope leurs instances Workflow indépendamment.
- **Env access :** `this.env` accessible dans `WorkflowEntrypoint` (même pattern que DurableObject). Tous les secrets et bindings KV/Queue disponibles.
- **step.sleep :** `await step.sleep('label', duration)` — duration : string humain-lisible (`"7 days"`, `"1 hour"`, `"20 seconds"`) ou number (millisecondes). `step.sleep` ne compte pas dans la limite des 1024 steps.
- **Sleep acceleration pour smoke tests staging :** Secrets env-specific optionnels `SURVEY_DELAY_7D_MS` / `SURVEY_DELAY_38D_MS`. Absents en prod → valeur par défaut (7j réels). Définis en staging → valeur courte (ex. `7000` = 7 secondes). Pattern : `parseInt(this.env.SURVEY_DELAY_7D_MS ?? String(7 * 24 * 60 * 60 * 1000))`.
- **Tests :** vitest recommandé officiellement par CF (release avril 2025). Mocker `step.sleep` et `step.do`. `wrangler dev` supporte les Workflows localement (wrangler ≥ 3.89.0). `wrangler dev --remote` NE supporte PAS les Workflows.
- **CLI instance management :** `wrangler workflows instances list|describe|terminate|restart|pause|resume [WORKFLOW_NAME] [INSTANCE_ID]`. `INSTANCE_ID` peut être `latest`.
- **Trigger depuis Worker :** `await env.MY_WORKFLOW.create({ params: { ... } })` — le binding est déclaré dans `wrangler.toml` sous `[[workflows]]` avec `binding = "MY_WORKFLOW"`.

---

## Architecture Patterns

- **Layer rule:** Layer 3 (E02–E05) consumes Layer 2 API only — never touches Layer 1 (Supabase) directly
- **Layer 2 additions:** any new API endpoint or worker needed by E02–E05 must be a new E06Sxx story, not implemented inside the UI epic
- **TypeScript:** strict mode, all Workers + Next.js. Types generated from Supabase schema (`src/types/database.ts`)
- **CF Workers:** no Cloudflare Pages — Workers only (DEC-04)
- **Async:** never call Resend / Lemon Squeezy / Cal.com synchronously from a Worker request — always via Cloudflare Queue
- **Async temps-différé (J+7, J+45, séquences) :** CF Workflows avec `step.sleep()` — jamais n8n (DEC-59)

---

## Cloudflare Resource Naming

Convention: `{scope}-{entity}-{resource}-{env}` (DEC-32)

| Segment | Values |
|---|---|
| `{scope}` | `callibrate-core` · `callibrate-io` · `callibrate-ai` |
| `{entity}` | `queue` · `kv` · `r2` · `d1` · `workflow` — **omitted for Workers** |
| `{resource}` | functional slug (e.g. `email-notifications`, `sessions`) |
| `{env}` | `staging` · `prod` — never `production`, never `dev` |

- **Dev exception:** `wrangler dev` binds to staging resources. No `-dev` resources exist.
- **Scope ownership:** KV · Queue · R2 · D1 · Workflow → always `callibrate-core`. UI workers (`callibrate-io`, `callibrate-ai`) never own storage.
- **Workers:** named as `{scope}-{env}` (no entity segment) — e.g. `callibrate-core-staging`
- **KV namespaces:** created with explicit names via `wrangler kv namespace create "callibrate-core-kv-sessions-staging"` — never rely on `--env` auto-naming
- **DLQs:** `{queue-full-name}-dlq` — e.g. `callibrate-core-queue-email-notifications-staging-dlq`

### Active Cloudflare resources (callibrate-core)

| Resource | Staging | Production |
|---|---|---|
| Worker | `callibrate-core-staging` | `callibrate-core-prod` |
| Queue — email | `callibrate-core-queue-email-notifications-staging` | `callibrate-core-queue-email-notifications-prod` |
| Queue — billing | `callibrate-core-queue-lead-billing-staging` | `callibrate-core-queue-lead-billing-prod` |
| KV — sessions | `callibrate-core-kv-sessions-staging` | `callibrate-core-kv-sessions-prod` |
| KV — rate limiting | `callibrate-core-kv-rate-limiting-staging` | `callibrate-core-kv-rate-limiting-prod` |
| KV — feature flags | `callibrate-core-kv-feature-flags-staging` | `callibrate-core-kv-feature-flags-prod` |
| KV — expert pool | `callibrate-core-kv-expert-pool-staging` | `callibrate-core-kv-expert-pool-prod` |
| Queue — score computation | `callibrate-core-queue-score-computation-staging` | `callibrate-core-queue-score-computation-prod` |

---

## Anti-Patterns (Avoid)

- Synchronous external API calls inside CF Worker request handlers (use Queues)
- Hardcoded matching criteria or domain-specific fields in Layer 2 code (use JSONB + satellite_configs)
- Email gate before match reveal (DEC-15 — kills conversion)
- Subscription billing at MVP (DEC-14 — pay-per-call only)
- Applying inferred preferences automatically to `expert.preferences` — system observes and suggests only, expert approves explicitly (DEC-29)
- Any config change without explicit expert approval — Suggest + Approve model, never auto-apply (DEC-29)
- Artificial top-N limit on match results — ranked list complet, top 3 highlighted visuellement (DEC-24)
- Async batch re-matching of anonymous prospects — matching is synchronous at search time, no persistent prospect profile to re-match (DEC-33)
- Cloudflare resource names without `{scope}-{entity}-{resource}-{env}` pattern (DEC-32)
- Using `production` or `dev` as env suffix — use `staging` and `prod` only (DEC-32)
