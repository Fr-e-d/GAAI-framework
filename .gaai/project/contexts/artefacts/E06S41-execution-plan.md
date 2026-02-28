# E06S41 — Execution Plan
# Multi-project support: prospect ≠ project data model

Generated: 2026-02-28
Status: implemented

## Overview

Breaking data model change: add `prospect_projects` table so one prospect can have
multiple projects without re-doing OTP. Matches now reference a project (not a prospect).

## Implementation Steps

### Step 1: Migration (supabase/migrations/20260228000008_e06s41_prospect_projects.sql)
- Create `prospect_projects` table (id, prospect_id FK, satellite_id, freetext, requirements, status, timestamps)
- Add `project_id` nullable FK to `matches` (prospect_id kept for backwards compat)
- Data migration: one prospect_projects row per existing prospect, backfill matches.project_id

### Step 2: TypeScript types (workers/backend/api/src/types/db.ts)
- Add `project_id: string | null` to MatchRow
- Add ProspectProjectRow interface

### Step 3: JWT helper (workers/backend/api/src/lib/jwt.ts)
- Add `verifyProspectTokenGetClaims(token, secret, aud)` → returns { prospect_id } or null
- Used by identified fast-track to detect prospect:submit JWT in Authorization header

### Step 4: Match compute (workers/backend/api/src/routes/matches.ts)
- Accept `project_id` in body
- Scope DELETE by project_id (or prospect_id for backwards compat)
- Include project_id in match INSERT

### Step 5: Prospect routes (workers/backend/api/src/routes/prospects.ts)
- Add anti-abuse helpers: tokenizeText, jaccardSimilarity
- Add handleIdentifiedProjectSubmit (private): handles project 2+ fast-track
- Refactor handleProspectSubmit: detect prospect:submit JWT → fast-track; else → existing flow
- Anonymous path: create prospect_projects row, link matches after MATCHING_SERVICE
- handleProspectMatches: add project_id query param resolution with IDOR check
- handleProspectRequirements: scope match expiry + compute by project_id
- New handleProspectProjects: GET list of projects with match_count/top_score

### Step 6: Router (workers/backend/api/src/index.ts)
- Import handleProspectProjects
- Add GET /api/prospects/:id/projects route

### Step 7: Tests (workers/backend/api/src/routes/prospects.test.ts)
- Fast-track routing test (proves JWT → identified path)
- handleProspectProjects: 403 without token, 403 invalid token, 200 empty list
- Anti-abuse max projects (AC10): 429 max_projects_exceeded

## ACs Not Fully Covered in Backend

- AC13 (CTA on results page): Frontend-only change in satellite site. API supports it via
  handleIdentifiedProjectSubmit (called when valid JWT present in Authorization header).
  The satellite frontend needs to add the CTA and call POST /api/prospects/submit with
  the existing JWT in the Authorization header.

## Breaking Changes

- `POST /api/prospects/submit` response now includes `project_id` field
- `GET /api/prospects/:id/matches` defaults to most recent project (backwards compatible)
- `matches.project_id` is nullable — existing rows get project_id set by migration
