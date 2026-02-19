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
- **Main branch:** `production` — all commits land here at MVP stage
- **Branch strategy (MVP):** direct commits to `production` acceptable for solo founder. Feature branches for anything requiring review.
- **Commit format:** imperative subject line + body if needed + `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` when AI-assisted
- **Never commit:** `.DS_Store`, `temp/`, `.env`, `node_modules/`, `.wrangler/` — covered by `.gitignore`
- **Push:** always `git push origin production` — no force push

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
