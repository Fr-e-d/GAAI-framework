---
type: memory
category: patterns
id: PATTERNS-001
tags:
  - patterns
  - conventions
  - procedural
created_at: 2026-02-19
updated_at: 2026-02-23
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
- **PR merge timing (DEC-2026-02-24-71):** PRs MUST be merged to staging as the final step of delivery — never left open to accumulate. 19 unmerged PRs caused cascading conflicts that required 3 rounds of resolution (2026-02-24 incident). Each merge changed staging, invalidating all other pending branches.
- **Branch base rule:** Story branches MUST be created from `staging` (or `production` for hotfixes) — NEVER from another story branch. Stacking branches (E06S22 on E06S21 on E06S18) creates an implicit dependency chain that cascades conflicts.
- **Conflict-minimizing merge order:** When multiple PRs must be merged, process sequentially in dependency order (oldest/leaf first). For each PR: (1) merge staging into branch, (2) push immediately, (3) merge PR immediately. Do NOT batch-resolve then batch-merge — each merge changes staging and invalidates subsequent resolutions.
- **Shared hotspot files:** `src/index.ts`, `wrangler.toml`, `src/types/env.ts` are modified by nearly every story and are guaranteed conflict zones when PRs accumulate. This reinforces the merge-immediately rule.
- **Worktree cleanup:** Always `git worktree remove` after use. Stale worktrees under `.claude/worktrees/` are picked up by vitest test discovery, causing phantom test failures.
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
- **OpenAI function calling pattern (E06S12, DEC-2026-02-23-01):** OpenAI Chat Completions with `tools` + `tool_choice: { type: "function", function: { name: "..." } }` is the canonical pattern for structured AI extraction. Response parsed from `choices[0].message.tool_calls[0].function.arguments` (JSON string). Direct `fetch` to `https://api.openai.com/v1/chat/completions` — no CF AI Gateway for OpenAI calls at this stage. Error surface: `'OpenAI API error'` (non-200), `'Invalid response from OpenAI API'` (JSON parse fail), `'AI service unreachable'` (network failure). Supersedes Anthropic tool_use + CF AI Gateway patterns (E06S08 — removed by E06S12).
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
- **GCal freebusy + slot computation pattern (E06S11):** `computeFreeSlots(params)` in `src/lib/availability.ts` — pure function, no side effects, fully testable. Combines GCal freebusy intervals with DB held/confirmed bookings into a single `allBusy` array. Slot spacing = `SLOT_DURATION_MS + BUFFER_MS` (buffer applied as spacing between consecutive slots AND as padding around busy intervals). Working day determined by `rules.working_hours[dayKey]` presence — missing key = non-working day. Min notice: `earliestStart = now + MIN_NOTICE_MS`. Output: UTC ISO strings.
- **Hold-then-confirm booking flow pattern (E06S11):** Two-phase lifecycle: (1) `POST /api/bookings/hold` → DB conflict check → insert `status=held`, `held_until=now+10min`, `prep_token=crypto.randomUUID()`. (2) `POST /api/bookings/:id/confirm` → fetch booking + assert held + assert not expired → freebusy re-check (race guard) → if taken: DELETE row → 409 `{error:'slot_taken'}` → else: `gcalInsertEvent(conferenceDataVersion=1)` → update to `status=confirmed` → push both queues. Hold cleanup: cron `*/5 * * * *`.
- **GCal API retry/error wrapper pattern (E06S11):** `withGcalRetry<T>(fn, onTokenRefresh, context, attempt=0)` in `src/lib/gcalClient.ts`. 429→delays `[1000,4000,16000][attempt]` ms (max 3 retries). 401→`refreshGcalToken`+retry (attempt===0 guard). 404 on delete→normalized to success inside `gcalDeleteEvent` before wrapper sees it. Other non-2xx→throw `GcalApiError`→callers return 502. `onTokenRefresh` is a closure mutating `currentToken` in outer scope.
- **CF Worker cron trigger pattern (E06S11):** Worker exports `scheduled(controller, env)` alongside `fetch` and `queue`. `handleScheduled` dispatches by `controller.cron` string match. Crons declared in `wrangler.toml` at top-level `[triggers].crons`, `[env.staging.triggers].crons`, AND `[env.production.triggers].crons` — all three required. Unknown cron values → `console.warn` (non-fatal).
- **Prep endpoint token-expiry pattern (E06S11):** Public route registered BEFORE the CORS-gated block. Token = UUID in `bookings.prep_token` (generated at hold time). Expiry computed at read time: `start_at + 2h`. Returns 404 `{error:'prep_token_expired'}` on expiry — same status as not-found (prevents enumeration via status code). Contains full bi-directional prep payload.
- **Route placement rule extension (E06S11):** Any no-auth route that shares a URL prefix with a JWT-gated block MUST be registered before that block in `index.ts`. Example: `GET /api/experts/:id/availability` (satellite-facing, CORS-only) registered before `/api/experts/` JWT block. Extends E06S10 OAuth callback rule. Violation symptom: silent 401 for all callers.

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
| `{scope}` | `callibrate-core` · `callibrate-satellite` · `callibrate-io` · `callibrate-ai` |
| `{entity}` | `queue` · `kv` · `r2` · `d1` · `workflow` — **omitted for Workers** |
| `{resource}` | functional slug (e.g. `email-notifications`, `sessions`) |
| `{env}` | `staging` · `prod` — never `production`, never `dev` |

- **Dev exception:** `wrangler dev` binds to staging resources. No `-dev` resources exist.
- **Scope ownership:** KV · Queue · R2 · D1 · Workflow → always `callibrate-core` (except: `callibrate-satellite` owns its own KV for config caching). UI workers (`callibrate-io`, `callibrate-ai`) never own storage.
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

### Active Cloudflare resources (callibrate-satellite)

| Resource | Staging | Production |
|---|---|---|
| Worker | `callibrate-satellite-staging` | `callibrate-satellite-prod` |
| KV — config cache | `callibrate-satellite-kv-config-staging` | `callibrate-satellite-kv-config-prod` |

### Active Cloudflare resources (callibrate-posthog-proxy)

| Resource | Staging | Production |
|---|---|---|
| Worker | `callibrate-posthog-proxy-staging` | `callibrate-posthog-proxy-prod` |
| Route | `ph.staging.callibrate.io/*` | `ph.callibrate.io/*` |

---

## Multi-Worker Project Structure (E06S14)

- **Secondary Workers** live in `workers/{name}/` subdirectory (e.g. `workers/satellite/`)
- Each has its own `package.json`, `wrangler.toml`, `tsconfig.json`
- GitHub Actions deploy all Workers in parallel (separate jobs in same workflow)
- **Satellite Worker uses Hono** for routing (first use in the project). Core Worker remains regex-based. Both patterns are valid.
- **Satellite config resolution pattern:** `resolveConfig(hostname, env)` — KV cache-aside (key: `satellite:config:${hostname}`, TTL: 3600s) with Supabase REST fallback (anon key). Non-blocking KV write on miss. Returns null on DB miss or Supabase unreachable → caller handles 302 redirect.
- **Cache purge endpoint:** `POST /admin/cache/purge` with `x-admin-secret` header validation. Deletes KV key. Returns `{ purged: true, domain }`.
- **Regle operationnelle (non-negotiable) :** Tout INSERT, UPDATE ou DELETE sur `satellite_configs` en DB DOIT etre suivi d'un purge du cache KV config pour le domaine concerne. Sans purge, l'ancienne config reste servie jusqu'a expiration du TTL (1h). Purge : `curl -X POST https://[domain]/admin/cache/purge -H "x-admin-secret: ..." -H "Content-Type: application/json" -d '{"domain":"[domain]"}'`. Le deploiement de code n'invalide PAS le cache KV (seulement le cache edge CDN). Pas de skill GAAI — action manuelle du founder.

## CF Workflows (first use: E06S16)

- **Class exports required:** Workflow classes MUST be named exports from `src/index.ts` — the CF runtime discovers them by class name matching `[[workflows]]` entries
- **`[[workflows]]` top-level only** — `[[env.staging.workflows]]` does not exist in wrangler.toml. Isolation staging/prod is via separate Worker scripts (`callibrate-core-staging` vs `callibrate-core-prod`)
- **`this.env` accessible** in `WorkflowEntrypoint` (same pattern as DurableObject)
- **`step.sleep(label, duration)`** — `label` is a string step name; `duration` is `string | number`. String: `'7 days'`; number: milliseconds
- **Sleep acceleration pattern** (staging-only): `parseInt(this.env.DELAY_MS ?? String(realMs))` — always produces a number. Set `DELAY_MS` as a staging secret for smoke tests (absent in prod → real duration)
- **Workflow → Queue dispatch loop:** Workflows dispatch new message types back to EMAIL_NOTIFICATIONS queue rather than calling Resend directly. This preserves retry/idempotency of the queue consumer. New types: `booking.confirmed.enriched`, `survey.call_experience`, `survey.project_satisfaction`

---

## PostHog Analytics Patterns (E07S01–E07S02)

- **PostHog reverse proxy:** `ph.callibrate.io` (CF Worker, E07S01) — all SDK calls routed through first-party domain. SDK `api_host: "https://ph.callibrate.io"`, `ui_host: "https://eu.posthog.com"` (EU region). Never use PostHog direct endpoints.
- **PostHog injection pattern (satellite Worker — E07S02):** Inline stub in `<head>` via template string (no `defer`/`src` on outer tag — stub creates async script element internally with `p.async=!0`). `capture_pageview: false` prevents blocking network call at init. Manual `page_view` fired in separate `<body>` script with `{ satellite_id, referrer, utm_source, utm_campaign, utm_medium }`. CTA click fires `satellite.cta_clicked` with `{ satellite_id, cta_text }`. Config: `persistence:"memory"` (cookieless, GDPR), `autocapture:true`, `disable_session_recording:false`.
- **PostHog API key:** `POSTHOG_API_KEY` Cloudflare secret (per-worker). Public write-only key — safe to embed in HTML. Interpolated via `JSON.stringify(posthogApiKey)` in inline scripts (XSS-safe). Both head+body snippets guarded by `posthogApiKey` truthiness.
- **Per-satellite tracking toggle:** `satellite_configs.tracking_enabled BOOLEAN NOT NULL DEFAULT true`. Guard in renderer: `config.tracking_enabled !== false && posthogApiKey` — strict false check (not falsy) to handle `undefined` from stale KV cache during column migration transitions.
- **Satellite analytics event schema:**
  | Event | Properties | Trigger |
  |---|---|---|
  | `page_view` | `satellite_id`, `referrer`, `utm_source`, `utm_campaign`, `utm_medium` | On page load (body script) |
  | `satellite.cta_clicked` | `satellite_id`, `cta_text` | On `.cta` element click |
  UTM params → `null` (not `undefined`) when absent. `referrer`: `document.referrer || null`.

---

## Standalone Setup Scripts (E07S04)

- **Location:** `scripts/` at repo root — sibling to `src/`
- **Runtime:** `npx tsx scripts/{name}.ts` — no compilation output, no wrangler bindings
- **Env vars:** `process.env["VAR_NAME"]` (bracket notation, `noUncheckedIndexedAccess`-compatible). Fail fast with `process.exit(1)` + descriptive message if required vars missing.
- **TypeScript config:** `scripts/tsconfig.json` — independent from root `tsconfig.json` (which only includes `src/**/*`). Same strict flags, no `@cloudflare/workers-types`, `moduleResolution: "bundler"`.
- **Type check:** `npx tsc --project scripts/tsconfig.json --noEmit` (NOT root tsconfig)
- **Error handling:** `main().catch((err: unknown) => { ...; process.exit(1) })`
- **Use for:** One-time operator setup (PostHog dashboards, Resend domain, data seeds not in Supabase migrations)

---

## PostHog Dashboard + Insights API (E07S04)

- **Base URL (EU):** `https://eu.posthog.com`
- **Auth:** `Authorization: Bearer {POSTHOG_PERSONAL_API_KEY}` — Personal API Key required for write operations (not Project API Key)
- **Create dashboard:** `POST /api/projects/{projectId}/dashboards/` → `{ name, description }`
- **List dashboards:** `GET /api/projects/{projectId}/dashboards/?limit=100` → `{ results: [{ id, name }], next }`
- **Create insight:** `POST /api/projects/{projectId}/insights/` → `{ name, filters: {...}, dashboards: [dashboardId] }`
- **FUNNELS filter shape:** `{ insight: "FUNNELS", events: [{ id, name, order, type: "events" }], breakdown?, breakdown_type?: "event", date_from, funnel_window_interval?, funnel_window_interval_unit? }`
- **TRENDS filter shape:** `{ insight: "TRENDS", events: [{ id, name, order, type: "events", math?: "total" }], date_from, interval: "day", formula?, display? }`
- **Idempotency:** Check existing by exact name match before creating; operate at dashboard level for one-time setup scripts
- **Dashboard URL:** `https://eu.posthog.com/project/{projectId}/dashboard/{dashboardId}`

---

## Anti-Patterns (Avoid)

- **Invalid backlog status values:** The only valid statuses are `draft → refined → in_progress → done | failed` (plus `deferred` / `superseded` for exceptional cases). Never use `ready` — the correct term is `refined`. Fixed 2026-02-23: 5 stories (E06S27–S30, E07S06) were created with `status: ready` instead of `refined`, invisible to the Delivery Daemon which polls `refined` only.
- Synchronous external API calls inside CF Worker request handlers (use Queues)
- Hardcoded matching criteria or domain-specific fields in Layer 2 code (use JSONB + satellite_configs)
- Email gate before match reveal (DEC-15 — kills conversion)
- Subscription billing at MVP (DEC-14 — pay-per-call only)
- Applying inferred preferences automatically to `expert.preferences` — system observes and suggests only, expert approves explicitly (DEC-29)
- Any config change without explicit expert approval — Suggest + Approve model, never auto-apply (DEC-29)
- Artificial top-N limit on match results — ranked list complet, top 3 highlighted visuellement (DEC-24)
- Async batch re-matching of anonymous prospects — matching is synchronous at search time, no persistent prospect profile to re-match (DEC-33)
- **`gh pr merge --auto` requires branch protection rules** — without required status checks configured on the target branch, `--auto` silently does nothing (no error, no merge). This was the technical root cause of the 19-PR incident (DEC-71): the delivery agent ran `--auto --squash` which appeared to succeed but never merged. Fix: use `gh pr merge --squash` (immediate) instead. Branch protection is not configured on this repo (solo founder MVP).
- Cloudflare resource names without `{scope}-{entity}-{resource}-{env}` pattern (DEC-32)
- Using `production` or `dev` as env suffix — use `staging` and `prod` only (DEC-32)
