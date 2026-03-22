---
type: rules
category: memory
id: RULES-MEMORY-OVERRIDE-EXAMPLE
example_for: memory.rules.md
override_scenario: Allow full memory index loading for small projects
tags:
  - memory
  - governance
  - solo-dev
  - retrieval
created_at: 2026-03-22
updated_at: 2026-03-22
---

# Example Override: Permissive Memory Loading for Small Projects

> **This is an example file.** It does not override any core rule.
> To activate this override, copy this file to `project/contexts/rules/memory.rules.md`
> (removing the `.example` suffix). The `memory.rules.md` filename triggers the override.

---

## What This Overrides

Core rules from `core/contexts/rules/memory.rules.md`:

- **R2 — Selective Retrieval Only:** Agents must start from the memory index and retrieve the minimal necessary set. They must NOT load entire memory folders.
- **R3 — Explicit Invocation Required:** Memory retrieval must occur only via `memory-retrieve` or `memory-search` skills — never auto-loaded.

---

## Scenario

Your project has a **small, stable memory corpus** — fewer than 40 entries, total size well under 20k tokens. In this case, the selective retrieval discipline (index → tag filter → minimal load) adds process overhead without preventing context bloat, because the full memory fits comfortably in context anyway. You want Discovery to load the full memory index at session startup rather than querying it selectively.

---

## The Override

```markdown
### R2 — Memory Loading (Relaxed for Small Projects)

**Condition:** If `contexts/memory/index.md` contains ≤40 entries AND the total estimated
token size of all memory files is ≤15,000 tokens (verify by scanning file sizes at session start):

- Discovery MAY load the full memory index at session startup without selective filtering
- Discovery MAY load all `decisions/` and `patterns/` files without a prior `memory-search` call
- Selective retrieval (R2 core) is still RECOMMENDED but not required

**If either threshold is exceeded,** selective retrieval (R2 core) applies in full — this
override deactivates automatically. Agents must check both thresholds at session start.

### R3 — Explicit Invocation (Unchanged)

Memory retrieval still requires `memory-retrieve` skill invocation. This override relaxes
the *scope* of retrieval, not the *mechanism*.
```

---

## Tradeoff

**What you gain:** Simpler, faster Discovery. No need to run `memory-search` before every planning step. Agents have the full project context available immediately without a retrieval round-trip.

**What you lose:** The context discipline that selective retrieval enforces. As the project grows, auto-loading full memory will degrade instruction-following quality — more context is not always better. The override has built-in thresholds (40 entries / 15k tokens) specifically to prevent this from becoming a permanent habit.

**When this is appropriate:** Projects in early stages with a small, well-curated memory corpus. A good signal: if `memory-search` consistently returns all entries because nothing is irrelevant, selective retrieval is providing no filtering benefit.

**When this is NOT appropriate:** Projects with >40 memory entries, fast-moving projects where memory grows quickly, or any project where instruction-following quality is already degrading.
