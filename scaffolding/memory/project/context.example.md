---
type: memory
category: project
id: PROJECT-001
tags:
  - product
  - vision
  - scope
created_at: 2026-01-10
updated_at: 2026-02-14
---

# Project Memory

> This file is loaded at the start of every session. Keep it concise and high-signal.

---

## Project Overview

**Name:** Trackr

**Purpose:** Internal time-tracking tool for a 12-person engineering team. Replaces a spreadsheet workflow. Engineers log hours per Story; team leads view weekly summaries and flag overruns.

**Target Users:** Engineers logging time; team leads reviewing reports.

---

## Core Problems Being Solved

- Manual spreadsheet logging is error-prone and time-consuming (avg 5 min/day per engineer)
- No automatic linkage between logged hours and backlog Stories
- Team leads have no visibility until weekly sync; no early warning on overruns

---

## Success Metrics

- Engineers can log time in under 30 seconds per entry
- Team lead dashboard shows live story-level burn vs estimate
- Zero manual data exports required for weekly review

---

## Tech Stack & Conventions

- **Language(s):** TypeScript (backend + frontend)
- **Frameworks:** Next.js (App Router), Prisma ORM, PostgreSQL
- **Key conventions:** All public API routes must have integration tests; no raw SQL (Prisma only); snake_case columns, camelCase variables

---

## Architectural Boundaries

- `app/api/` — Next.js route handlers only; no business logic here
- `lib/` — all business logic; pure functions, no framework imports
- `prisma/` — schema and migrations; never modified during Story execution without a migration Story

---

## Known Constraints

- No external AI APIs in production (cost and privacy policy)
- Must run on existing Heroku free tier; no new paid services without explicit approval
- Auth via company SSO (Google OAuth) only — no username/password accounts

---

## Out of Scope (Permanent)

- Invoicing or billing integration
- Mobile app
- Time approval workflows (team leads observe, do not approve)
