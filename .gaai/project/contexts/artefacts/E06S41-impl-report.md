# E06S41 — Implementation Report
# Multi-project support: prospect ≠ project data model

Date: 2026-02-28
PR: https://github.com/Fr-e-d/callibrate-core/pull/65 (merged)
Branch: story/E06S41 → staging

## Files Changed (8)

| File | Change |
|------|--------|
| `supabase/migrations/20260228000008_e06s41_prospect_projects.sql` | NEW — schema + data migration |
| `workers/backend/api/src/types/db.ts` | Add ProspectProjectRow, update MatchRow.project_id |
| `workers/backend/api/src/lib/jwt.ts` | Add verifyProspectTokenGetClaims |
| `workers/backend/api/src/routes/matches.ts` | project_id in body + scoped DELETE/INSERT |
| `workers/backend/api/src/routes/prospects.ts` | Major refactor: fast-track, anti-abuse, new endpoints |
| `workers/backend/api/src/index.ts` | Route + import for handleProspectProjects |
| `workers/backend/api/src/routes/prospects.test.ts` | 8 new tests |
| `.gaai/contexts/artefacts/E06S41-execution-plan.md` | Execution plan artefact |

## AC Coverage

| AC | Status | Notes |
|----|--------|-------|
| AC1 — prospect_projects table | ✅ | Migration 20260228000008 |
| AC2 — matches.project_id FK | ✅ | Migration, backwards compat (prospect_id kept) |
| AC3 — Data migration | ✅ | One project per existing prospect, all matches backfilled |
| AC4 — POST /api/extract no change | ✅ | No change needed |
| AC5 — POST /api/prospects/submit with project_id | ✅ | Fast-track + anonymous path both create project |
| AC6 — POST /api/prospects/:id/identify no change | ✅ | No change needed |
| AC7 — GET /api/prospects/:id/matches project_id param | ✅ | Resolves to most recent project if omitted |
| AC8 — NEW GET /api/prospects/:id/projects | ✅ | handleProspectProjects with match_count + top_score |
| AC9 — Identified prospect fast-track | ✅ | verifyProspectTokenGetClaims routing + handleIdentifiedProjectSubmit |
| AC10 — Max 5 active projects | ✅ | KV + DB check, 429 max_projects_exceeded |
| AC11 — 3 new/24h rate limit | ✅ | KV counter rate:new_project:{prospectId} TTL 86400 |
| AC12 — Duplicate detection Jaccard >85% | ✅ | tokenizeText + jaccardSimilarity helpers |
| AC13 — "Autre projet?" CTA on results page | ⚠️ | Frontend-only — satellite site, not in this worker |
| AC14 — Tests + tsc clean | ✅ | 8 new tests, 581 total PASS, tsc 0 errors |

## Notes

- MATCHING_SERVICE path: after service returns, UPDATE matches SET project_id = X WHERE prospect_id = Y AND project_id IS NULL
- Fallback path: project_id included directly in INSERT
- matches.prospect_id kept as denormalized column (DEC-124, backwards compat)
- AC13 requires satellite frontend change: add CTA that calls POST /api/prospects/submit with existing JWT in Authorization header
