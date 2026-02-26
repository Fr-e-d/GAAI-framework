---
name: delivery-readiness-audit
description: Spot-check AC internal consistency and scan for pending revisions on delivery-ready stories. Activated by `/gaai-status --audit` as Section 5. Complements the standard status checks with depth checks that standard status skips for speed.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-019
  updated_at: 2026-02-23
  tags: [governance, delivery-gate, coherence]
  status: stable
inputs:
  - delivery-ready stories (from /gaai-status Section 1)
  - contexts/artefacts/stories/*.story.md (for each ready story)
  - contexts/backlog/active.backlog.yaml (notes field)
outputs:
  - ac_consistency_issues (structured list)
  - pending_revisions (structured list)
  - delivery_verdict (READY FOR DELIVERY | ISSUES TO RESOLVE FIRST)
---

# Delivery Readiness Audit

## Purpose / When to Activate

Activate via `/gaai-status --audit`. This skill runs **after** the standard status sections (1–4) have already identified delivery-ready stories, memory staleness, and framework health.

This skill adds two depth checks that standard status skips for speed:
- **AC internal consistency** — catches missing columns, undeclared endpoints, broken cross-references within a story
- **Pending revisions** — catches deferred work flagged in backlog notes but not yet captured as stories

---

## Process

### 1. AC internal consistency — spot-check READY stories

For each story identified as "ready to deliver" by Section 1:

1. Open the story artefact file
2. Build an inventory of all resources **declared** by schema/setup ACs: columns, tables, endpoints, queues, secrets, cron triggers
3. Scan all other ACs for resources **referenced** but not in the inventory
4. Flag any reference to a column, endpoint, queue, table, or resource that is not declared elsewhere in the same story

**Example of what this catches:**
- AC12 uses `bookings.reminder_j1_sent_at` for idempotency, but AC11 (schema migration) doesn't list that column
- AC13 references `bookings.prep_token` but it's missing from the migration

Severity: CRITICAL if it would cause the Delivery Agent to produce incomplete code.

### 2. Pending revisions scan

Scan all backlog item `notes` fields for patterns indicating unresolved work:

**Patterns to match:**
- "sera révisé", "à réviser", "sera revu"
- "story à générer", "story E0x à générer", "à créer"
- "TODO", "à remplacer", "à migrer"
- "will be revised", "to be created", "to migrate", "to replace", "needs update"
- `DEC-` references followed by a pending action description

For each match:
- State the backlog item ID, the DEC reference (if any), and the pending action
- Check whether a corresponding story already exists in the backlog
- Flag as IMPORTANT if no story exists yet

### 3. Delivery verdict

Produce a summary:
- Count of stories truly ready (all deps met + ACs internally consistent)
- Count of issues by severity (CRITICAL / IMPORTANT / MINOR)
- Verdict: **READY FOR DELIVERY** (0 critical issues) or **ISSUES TO RESOLVE FIRST** (list critical issues)

For issues safe to correct (missing AC metadata, column alignment), list them as "auto-fixable" in the report. Discovery or the human decides whether to apply fixes — this skill reports only.

---

## Output Format

```
### Section 5 — Delivery Readiness

**5a. AC Consistency (READY stories)**

| Story | Issue | Severity |
|---|---|---|
| E06S11 | AC12 uses `bookings.reminder_j1_sent_at` — missing from AC11 migration | CRITICAL |

Verdict: PASS | N issues found

**5b. Pending Revisions**

| Backlog Item | DEC | Pending Action | Story Exists? |
|---|---|---|---|
| E06S06 | DEC-68 | lead-billing consumer revision to credit model | No |

**5c. Delivery Verdict**

N stories ready. M critical, K important issues.
READY FOR DELIVERY | ISSUES TO RESOLVE FIRST
```

---

## Quality Checks

- Every finding references a specific story ID, AC number, and resource name
- No vague findings ("something might be wrong" is invalid)
- Severity is explicit: CRITICAL (blocks Delivery), IMPORTANT (should fix), MINOR (cosmetic)
- No false positives — only flag cross-references that are genuinely missing
- The report is additive to standard status — never repeats Sections 1–4

---

## Non-Goals

This skill must NOT:
- Repeat checks already done by `/gaai-status` Sections 1–4 (staleness, dependency graph, backlog counts)
- Fix issues (report only — Discovery or human decides)
- Rewrite artefacts or memory
- Make prioritization decisions about delivery order

**If an AC can't survive a cross-reference check, Delivery will produce broken code. Catch it here.**
