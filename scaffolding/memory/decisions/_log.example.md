---
type: memory
category: decisions
id: DECISIONS-LOG
tags:
  - decisions
  - governance
created_at: 2026-01-10
updated_at: 2026-02-12
---

# Decision Log

> Append-only. Never delete or overwrite decisions.
> Only the Discovery Agent may add entries (or Bootstrap Agent during initialization).
> Format: one entry per decision, newest at top.

---

### DEC-2026-02-12-03 — Use Prisma for all database access

**Context:** E02S01 required a new `time_entry` table. The engineer asked whether to use raw SQL or an ORM.

**Decision:** Prisma ORM for all database access. No raw SQL anywhere in the application.

**Rationale:** Prisma migrations are version-controlled and reviewable. Raw SQL in route handlers caused a production incident in January (missing index on a hand-written query). Team agreed: consistency over flexibility.

**Impact:** All future Stories touching the database must use Prisma schema + migrations. Any Story proposing raw SQL must be escalated to the team lead before proceeding.

**Date:** 2026-02-12

---

### DEC-2026-02-03-02 — No time entry editing after 7-day window

**Context:** E01S03 (time entry editing) raised the question of how far back engineers should be able to edit.

**Decision:** Time entries are editable for 7 calendar days after creation. After that they are read-only.

**Rationale:** Accounting team requires entries to be stable within the same week for reporting. Unlimited editing window would complicate the weekly report snapshots.

**Impact:** UI must show "locked" state on entries older than 7 days. API must reject edits on locked entries with HTTP 409.

**Date:** 2026-02-03

---

### DEC-2026-01-15-01 — Google OAuth only; no password accounts

**Context:** Bootstrap session. Authentication approach for the tool.

**Decision:** Google OAuth via company SSO. No username/password login. No third-party auth providers.

**Rationale:** All team members have Google Workspace accounts. Password management adds compliance burden (GDPR, password reset flows). SSO gives the team lead automatic offboarding.

**Impact:** All auth code uses NextAuth.js with the Google provider. No `password` or `passwordHash` columns in the schema. Engineers outside the Google Workspace cannot access the tool.

**Date:** 2026-01-15

---

<!-- Add decisions above this line, newest first -->
