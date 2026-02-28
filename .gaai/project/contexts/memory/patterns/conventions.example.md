---
type: memory
category: patterns
id: PATTERNS-001
tags:
  - patterns
  - conventions
  - procedural
created_at: 2026-01-15
updated_at: 2026-02-10
---

# Patterns & Conventions

> Procedural memory: how things are done in this project.
> Agent-maintained. Updated when durable patterns are confirmed.
> The Delivery Agent loads this before every implementation task.

---

## Code Patterns

**Route handler shape** — Next.js App Router route handlers follow this exact structure:

```typescript
// app/api/time-entries/route.ts
import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { db } from "@/lib/db";
import { createTimeEntrySchema } from "@/lib/validation/time-entry";

export async function POST(req: Request) {
  const session = await getServerSession(authOptions);
  if (!session) return Response.json({ error: "Unauthorized" }, { status: 401 });

  const body = await req.json();
  const parsed = createTimeEntrySchema.safeParse(body);
  if (!parsed.success) return Response.json({ error: parsed.error }, { status: 400 });

  const entry = await db.timeEntry.create({ data: { ...parsed.data, userId: session.user.id } });
  return Response.json(entry, { status: 201 });
}
```

No business logic in route handlers. Validation via Zod schema in `lib/validation/`. Database access via Prisma client alias `db`.

**Error responses** — always `{ error: string }`. Never expose stack traces or Prisma internals. Use standard HTTP status codes.

---

## Test Patterns

**Integration tests over unit tests for API routes.** Use `supertest` + a test database (separate `DATABASE_TEST_URL`). Each test file resets the relevant tables in `beforeEach`.

**Pattern confirmed** in E01S02: unit-testing Prisma calls via mocking was brittle and gave false confidence. Integration tests against a real schema caught two migration errors that mocks missed.

**Test file naming:** `__tests__/api/time-entries.test.ts` — mirrors the route path.

---

## Architecture Patterns

**lib/ is framework-free.** Functions in `lib/` must not import from `next`, `next-auth`, or any server-only module. This makes them testable without a Next.js server context.

**Prisma client is a singleton.** Never instantiate `new PrismaClient()` outside `lib/db.ts`. Hot-reloading in dev would create connection pool exhaustion otherwise.

---

## Anti-Patterns (Avoid)

- **Raw SQL in route handlers** — caused a production outage in Jan 2026 (missing index). Use Prisma. If Prisma cannot express the query, create a Decision entry first.
- **Business logic in route handlers** — breaks testability and was the source of three bugs in E01. Move to `lib/`.
- **Mutating session state server-side** — NextAuth session data is read-only in route handlers; update the database directly and let the client re-fetch.
