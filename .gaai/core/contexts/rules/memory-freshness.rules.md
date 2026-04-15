---
type: rules
category: memory
id: RULES-MEMORY-FRESHNESS-001
tags:
  - memory
  - freshness
  - depends_on
  - staleness
  - governance
  - memory-ingest
created_at: 2026-04-05
updated_at: 2026-04-05
---

# Memory Freshness Rules

This document defines the **`depends_on` schema** for memory file freshness metadata
and the **governance rules** that apply when memory files are ingested.

It extends the core memory governance in `memory.rules.md` with staleness-tracking
declarations. All rules here are compatible with Tier 4 graceful degradation (see below).

---

## 1. The `depends_on` Schema

Every memory file under `architecture/`, `patterns/conventions.md`, or
`project/context.md` (Tier 1–2 files) MUST declare the following YAML frontmatter
fields at the time of ingest:

```yaml
depends_on:
  code_paths: ["workers/gaai-cloud/api/src/services/"]  # git-trackable paths
  decisions: [DEC-11, DEC-20]                            # DEC IDs referenced in content
  epics: [E33, E34]                                      # epics whose completion may invalidate content
refresh_tier: 1  # 1=post-epic-hook, 2=read-time-check, 3=cadence, 4=stable
```

### 1.1 `depends_on.code_paths`

- Accepts relative paths from the project root
- Supports directories (trailing `/`) and individual files
- **Glob patterns are NOT supported** — too fragile across renames; use explicit paths only
- An empty list (`[]`) is a valid declaration — it means "no code dependency identified"
- Examples:
  - `"workers/gaai-cloud/api/src/services/"` — directory watch
  - `"workers/gaai-cloud/api/src/services/backlog.service.ts"` — file watch
  - `[]` — no code dependency (or not yet identified)

### 1.2 `depends_on.decisions`

- Accepts DEC-N format strings (e.g., `DEC-11`, `DEC-20`)
- Referenced DECs are validated during `memory-reconcile` — **not** at ingest time
  (DECs may not yet exist when a memory file is first written)
- An empty list (`[]`) is valid

### 1.3 `depends_on.epics`

- Accepts E{N} format strings (e.g., `E33`, `E34`)
- Used for **human-readable context only** — not machine-checked
  (epics are transient and typically closed after delivery)
- An empty list (`[]`) is valid

### 1.4 `refresh_tier`

Integer 1–4. Governs which freshness mechanism applies (see Section 2).

---

## 2. Refresh Tiers

| Tier | Name | Mechanism | Automation |
|------|------|-----------|------------|
| 1 | Post-epic hook | Proactive refresh triggered by the delivery daemon's post-epic hook when a dependent epic is marked `done` | Automated — daemon triggers |
| 2 | Read-time check | Staleness warning emitted by `memory-retrieve` at read time, based on `depends_on.code_paths` having changed since last `updated_at` | Automated — checked on read |
| 3 | Cadence review | Human or event-triggered review on a defined cadence | No automation — human responsibility |
| 4 | Stable | No freshness check — content is considered durable | No check (default when `depends_on` is absent) |

### Tier 1 — Post-Epic Hook (Proactive)

Trigger: the delivery daemon completes an epic whose ID appears in a memory file's
`depends_on.epics` list.  
Action: the daemon emits a staleness signal for all memory files that declare
that epic.  
Scope: all files with `refresh_tier: 1`.

### Tier 2 — Read-Time Check (Reactive)

Trigger: `memory-retrieve` reads a file with `refresh_tier: 2`.  
Action: if any path in `depends_on.code_paths` has been modified since
the file's `updated_at`, emit a staleness warning in the session output.  
The warning does NOT block the retrieval — it is advisory.  
Format: `"[FRESHNESS WARNING] {file_path} may be stale. depends_on.code_paths changed since {updated_at}."`

### Tier 3 — Cadence Review (Human)

No automation. The file carries a `refresh_tier: 3` declaration as a human-readable
signal that periodic review is expected.  
Discovery Agent or human operator schedules reviews.

### Tier 4 — Stable (No Check)

Files with `refresh_tier: 4` or **no `depends_on` at all** are treated as stable.
No freshness check is emitted. This is the safe default for incremental rollout
(see Section 4 — Graceful Degradation).

---

## 3. Which Files Must Declare `depends_on`

Tier 1–2 files are those under these paths (relative to project root):

- `contexts/memory/architecture/` — all files
- `contexts/memory/patterns/conventions.md`
- `contexts/memory/project/context.md`

All other memory files MAY declare `depends_on` but are not required to.

### 3.1 Documentation and README Files

Documentation files (`**/docs/**/*.md`) and README files (`**/README.md`) are
**in-scope for freshness tracking** alongside memory files. They describe the
project to external consumers and drift silently when the codebase evolves.

Documentation files SHOULD declare `depends_on` frontmatter when they describe
code, APIs, architecture, or capabilities that change with the implementation.
The schema is identical to memory files:

```yaml
---
depends_on:
  code_paths: ["src/"]      # directories or files this doc describes
  decisions: [DEC-11]        # decisions referenced in the content
  epics: []
refresh_tier: 2
---
```

**Rules for documentation freshness:**

- Documentation files default to **Tier 3** (cadence review) when `depends_on`
  is absent. This differs from memory files (which default to Tier 4) because
  documentation is externally visible and staleness has higher cost.
- Documentation files with `depends_on` declared follow the same tier logic as
  memory files (Tier 1–4 based on `refresh_tier` value).
- `memory-reconcile` discovers documentation files via glob patterns
  (`**/docs/**/*.md`, `**/README.md`) — they do NOT need to be registered in
  `contexts/memory/index.md`. The memory index is for memory only.
- Discovery and reconciliation patterns use project-agnostic globs — no
  hardcoded project-specific paths.

When the author cannot determine the correct `code_paths`, use this safe fallback:

```yaml
depends_on:
  code_paths: []
  decisions: []
  epics: []
refresh_tier: 2
```

Rationale: `refresh_tier: 2` (read-time check) is the conservative default for
unknown dependencies — it triggers a warning rather than silently skipping freshness
enforcement. Do NOT default to `refresh_tier: 4` when dependencies are unknown.

---

## 4. Graceful Degradation

**If `depends_on` is absent on a memory file, the file is treated as Tier 4 (stable).**

- No error is raised
- No staleness check is performed
- The system continues normally

This rule enables incremental rollout: existing files without `depends_on` are safe.
New files must declare it at ingest time (governed by the `memory-ingest` skill).

---

## 5. Cloud Forward-Compatibility

The `depends_on` schema is designed to map to GAAI Cloud knowledge graph edges:

| Local field | Cloud graph concept |
|-------------|---------------------|
| `depends_on.code_paths` | Source edges — links a memory node to code-path nodes in the graph |
| `depends_on.decisions` | DEC dependency edges — links a memory node to decision nodes |
| `depends_on.epics` | Epic context edges — human-readable, informational in graph |

This mapping is informational for the OSS layer. Cloud enforcement is an
out-of-scope concern for this story (E41S01). Downstream stories (E41S04+) wire
the local staleness check; Cloud graph enforcement is a separate track.

---

## 6. Validation Responsibilities

| Field | Validated by | Timing |
|-------|-------------|--------|
| `depends_on` presence | `memory-ingest` skill | At write time (AC6 governance step) |
| `depends_on.code_paths` format | Human review / `memory-reconcile` | Post-ingest |
| `depends_on.decisions` DEC references | `memory-reconcile` | Post-ingest (DECs may be created later) |
| `depends_on.epics` format | Not machine-validated | Human-readable only |
| `refresh_tier` value (1–4) | `memory-ingest` skill | At write time |

---

## Forbidden Patterns

- Setting `refresh_tier: 4` as a default when `depends_on` is unknown (use Tier 2 instead)
- Omitting `depends_on` on a new Tier 1–2 file during ingest
- Using glob patterns in `depends_on.code_paths`
- Blocking memory retrieval on a staleness warning (Tier 2 is advisory, never blocking)
