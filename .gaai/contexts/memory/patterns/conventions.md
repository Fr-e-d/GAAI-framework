---
type: memory
category: patterns
id: PATTERNS-001
tags:
  - patterns
  - conventions
  - procedural
created_at: 2026-02-19
updated_at: 2026-02-19
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
- **Commit timing:** once, atomically, after all ACs are implemented — before handoff artefact is written
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
- **Health endpoint:** `GET /api/health` → `{ status: "ok", supabase: "connected"|"error", queues: [...] }` — returns 503 when Supabase unreachable (not 200-always)
- **Supabase ping in Workers:** `fetch(${SUPABASE_URL}/rest/v1/, { headers: { apikey: SUPABASE_ANON_KEY, Authorization: Bearer ... } })` — uses anon key, not service key

---

## Test Patterns

<!-- Testing conventions and preferences -->

---

## Architecture Patterns

- **Layer rule:** Layer 3 (E02–E05) consumes Layer 2 API only — never touches Layer 1 (Supabase) directly
- **Layer 2 additions:** any new API endpoint or worker needed by E02–E05 must be a new E06Sxx story, not implemented inside the UI epic
- **TypeScript:** strict mode, all Workers + Next.js. Types generated from Supabase schema (`src/types/database.ts`)
- **CF Workers:** no Cloudflare Pages — Workers only (DEC-04)
- **Async:** never call Resend / Lemon Squeezy / Cal.com synchronously from a Worker request — always via Cloudflare Queue

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

Score computation queue (`callibrate-core-queue-score-computation-staging/prod`) added in E06S09.

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
