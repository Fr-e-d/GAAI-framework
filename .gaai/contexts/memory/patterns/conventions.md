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

<!-- Recurring implementation patterns confirmed to work well -->

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

## Anti-Patterns (Avoid)

- Synchronous external API calls inside CF Worker request handlers (use Queues)
- Hardcoded matching criteria or domain-specific fields in Layer 2 code (use JSONB + satellite_configs)
- Email gate before match reveal (DEC-15 — kills conversion)
- Subscription billing at MVP (DEC-14 — pay-per-call only)
