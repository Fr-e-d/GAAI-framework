---
type: rules
category: memory
id: RULES-MEMORY-ARCHITECTURE-001
tags:
  - memory
  - architecture
  - invariants
  - verify-before-update
  - governance
created_at: 2026-04-12
updated_at: 2026-04-12
---

# Memory Architecture File Rules

This document defines **what architecture memory files must contain** and **how they
must be verified** before being written or updated.

Scope: every file under `contexts/memory/architecture/`.

It complements:
- `memory.rules.md` — core memory governance
- `memory-freshness.rules.md` — `depends_on` schema and staleness tiers
- `memory-ingest.SKILL.md` — write-time procedure

---

## 1. Content Principle — Conceptual Invariants, Not Code Snapshots

Architecture memory files MUST capture **conceptual, cross-cutting invariants** —
principles, structural choices, integration rules, and cross-module constraints that
a future agent or human needs to understand to avoid breaking the system.

They MUST NOT store **code snapshots** — material that lives authoritatively in the
codebase and drifts every time the code evolves.

### What belongs in an architecture file

- The **reason** a structural choice exists ("why we use X over Y")
- **Invariants** that must hold across modules ("orgId must be derived from the workspace record, never from user input")
- **Cross-cutting rules** that span multiple components ("all audit writers skip governance.check to avoid recursion")
- **Trade-offs** accepted at design time and their consequences
- **Boundaries** between subsystems and the contracts between them

### What does NOT belong in an architecture file

- Counts that change per release ("N tools exposed", "M RPC methods available")
- Enumerations of functions, methods, fields, columns, endpoints
- Lists of schema fields, migration versions, or field types
- Copy-paste of code snippets that exist in the codebase
- Transient state from a specific story or spike
- "How we currently do X" — belongs in implementation docs, not memory

### Test (apply before writing)

> If the codebase is refactored tomorrow without changing the design intent, does this
> content still read correctly?
> - **Yes** → it's an invariant, write it
> - **No** → it's a code snapshot, do NOT write it

---

## 2. Verify-Before-Update Protocol

Before writing a new architecture file OR updating an existing one, the authoring
agent MUST:

1. **Load the target file's `depends_on.code_paths`** (or the intended list for a new file)
2. **Read each referenced path** in the current working tree
3. **For every claim the content makes**, verify:
   - The claim is consistent with what the code shows today
   - The claim has not been invalidated by a superseding decision (check DEC registry)
   - The claim describes an invariant, not a current implementation detail
4. **On divergence found:**
   - Update the content to match current reality, OR
   - If the divergence reveals a superseded concept, mark the file `status: stale`
     and escalate to the human (do NOT silently rewrite to a new model)
5. **Record attestation** — set `verified_against_commit_sha: <git sha>` and
   `verified_at: <ISO 8601 timestamp>` in the file frontmatter at write time

Skipping the verification is forbidden. Writing from a memory-delta without verifying
is forbidden (deltas are historical reports and may describe behaviour that has since
been refactored).

---

## 3. Frontmatter Schema Addition

In addition to the `depends_on` + `refresh_tier` schema defined in
`memory-freshness.rules.md`, architecture files MUST also declare:

```yaml
verified_against_commit_sha: "<40-char git SHA>"   # commit the content was verified against
verified_at: "<ISO 8601 timestamp>"                # when verification happened
```

These two fields are **mandatory** at every write or update of an architecture file.

---

## 4. Enforcement Split — Local vs Cloud

| Concern | Local (OSS) | Cloud (future, see §5) |
|---|---|---|
| Content principle (conceptual invariants) | Discovery Agent discipline | Not enforceable structurally — stays client-side |
| `depends_on.code_paths` present and non-empty | `memory-ingest` skill gate | Hard gate (schema validation) |
| `verified_against_commit_sha` + `verified_at` present | `memory-ingest` skill gate | Hard gate |
| Verification actually performed | Agent discipline | Cannot prove; attestation only |
| Staleness signal at read time | `memory-retrieve` skill (Tier 2) | Read-time staleness warning based on stored SHA vs current HEAD |

**Conceptual discipline stays client-side** (per DEC-equivalent governance-not-compute
principle). The server can enforce structural invariants and emit audit trails, but
cannot judge whether content is an invariant or a snapshot.

---

## 5. Cloud Enforcement (Future Spec)

This section is a **ready-to-use specification** for a future cloud-side story. It is
informational today — no implementation required for OSS compliance.

### 5.1 Write gate

On any write to a memory entry with `category: architecture`:

1. Reject if `depends_on.code_paths` is absent, empty, or not an array of strings
2. Reject if `verified_against_commit_sha` is absent or not a 40-char hex string
3. Reject if `verified_at` is absent or not a valid ISO 8601 timestamp
4. Record the attestation fields into the audit log alongside the write

### 5.2 Read signal

On any read of a memory entry with `category: architecture`:

1. Compute the current HEAD commit SHA for the declared `code_paths`
2. If it differs from `verified_against_commit_sha` → emit a `STALENESS_WARNING`
   alongside the content (advisory, not blocking)
3. The warning format mirrors the local freshness protocol:
   `"[STALENESS WARNING] architecture/{file} may be stale — code_paths changed since verified_at."`

### 5.3 What the cloud does NOT do

- Does not attempt to validate content semantics (no inference server-side)
- Does not detect code-snapshot anti-patterns
- Does not compare content claims against actual code behavior
- These remain Discovery Agent responsibilities, enforced via this rule file and the
  `memory-ingest` skill

### 5.4 Rationale for this split

Content discipline is semantic — it requires understanding what the code means. That
work stays with the agent (client-side intelligence). The server adds a belt on top
of the agent's braces: structural gate + audit trail + staleness signal. These
are cheap, deterministic, and cannot themselves drift.

---

## 6. Forbidden Patterns

- Writing an architecture file without running the verify-before-update protocol
- Copying content from a memory-delta into an architecture file without independent
  verification against the code
- Using architecture files to record transient state from a single story
- Omitting `verified_against_commit_sha` or `verified_at` at write time
- Updating an architecture file to match a new model without marking the old file
  `status: stale` first and surfacing the transition to the human
- Silently resolving a divergence between content and code without logging the
  reconciliation in the file's update history
