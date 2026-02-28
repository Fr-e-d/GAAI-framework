---
type: rules
category: skills
id: RULES-SKILLS-DESIGN-002
tags:
  - skills
  - design
  - hardcoding
  - modularity
  - registry
created_at: 2026-02-21
updated_at: 2026-02-21
---

# GAAI Skills Design Rules — Modularity & Dynamic Resolution

This document defines **mandatory design constraints for skill authoring**.
It is a companion to `skills.rules.md` (execution isolation) and applies at authoring time, not execution time.

A skill that violates these rules compiles and runs — but silently drifts as the project evolves.
That is worse than a skill that fails loudly.

---

## Why This Matters

Skills are **framework-level artefacts**. They outlive any single project state.

When a skill hardcodes a resource that belongs to the project (a file path, a category name, a technology name, a provider name), it makes an assumption about the project's current shape. That assumption is true today. It becomes false the moment the project evolves — and the skill won't tell you.

**The failure mode is silent.** An agent executing a skill with stale hardcoded paths does not error — it loads nothing, skips context it should have, or routes knowledge to a category that no longer exists. The system continues. The output is subtly wrong.

**Structural constants are different.** State machines, output format schemas, naming conventions, severity levels — these define the framework's grammar. They are correct to hardcode because changing them is a deliberate governance decision, not a project evolution.

The line is: **hardcode the framework, discover the project.**

---

## R8 — Never Hardcode Resource Paths That Belong to the Project

A skill MUST NOT hardcode specific file paths to project-owned resources.

**Forbidden examples:**
```yaml
# ❌ hardcoded memory file path
inputs:
  - contexts/memory/project/context.md
  - contexts/memory/decisions/_log.md
  - contexts/memory/patterns/conventions.md
```

**Correct pattern:**
```yaml
# ✅ registry-driven
inputs:
  - contexts/memory/index.md        (registry — read first to discover categories)
  - contexts/memory/**              (resolved at runtime from index.md)
```

**Why:** Memory categories, file names, and directory structure can change as the project evolves. A new category added to `index.md` is invisible to skills that hardcode the old list. Routing must go through the registry.

The only hardcoded memory path allowed in any skill is `contexts/memory/index.md` itself — it IS the registry.

---

## R9 — Never Hardcode Project-Specific Values in Framework Skills

A skill MUST NOT hardcode values that describe the current project's specific state: technology names, provider names, team size assumptions, stack details.

**Forbidden examples:**
```
# ❌ project-specific stack hardcoded in a framework skill
- Stack compatibility — does it work with CF Workers, Supabase, TypeScript, edge compute?

# ❌ project-specific team constraint hardcoded
- Operational fit — solo founder maintainability
```

**Correct pattern:**
```
# ✅ derived from the project context file
- Stack compatibility — does it work with the project's tech stack?
  (read from the `project` category file, resolved via index.md)
- Operational fit — does it match the operational constraints described in the project context?
```

**Why:** A framework skill instantiated in a different project carries the wrong project's assumptions silently. The right place for project-specific values is the project's memory — skills should read them there, not embed them.

---

## R10 — Reference Memory by Category, Not by File Path

When a skill needs to load memory, it MUST:
1. Read `contexts/memory/index.md` first
2. Identify the relevant category by name or tag
3. Load the file path registered for that category

A skill MUST NOT construct or assume a memory file path without consulting the index.

**Correct resolution pattern (in Process sections):**
```
Read contexts/memory/index.md.
Resolve the `project` category → load that file.
Resolve the `patterns` category → load that file.
If a category is absent from the index, omit it — do not fail, do not assume a default path.
```

**Why:** `index.md` is the single source of truth for what memory exists and where. Any skill that bypasses it creates a parallel, unsynchronized view of memory that will drift.

---

## R11 — Structural Constants Are the Exception, Not the Rule

The following categories of values ARE correct to hardcode in skills:

| Category | Examples | Rationale |
|---|---|---|
| State machines | Backlog states, QA verdicts, memory delta verdicts | Define the framework protocol — changing them is a governance event |
| Output schemas | QA report format, execution plan format, story format | Define the inter-agent contract — must be stable |
| Severity scales | `low / medium / high / critical` | Universal, not project-specific |
| Tier thresholds | Complexity ≤ 2 → Tier 1 | Operational heuristic, not a project value |
| Framework paths | `.gaai/`, `contexts/rules/`, `contexts/artefacts/` | Define the framework structure itself |

These are hardcoded because they **are** the framework. They do not describe the project — they define the system within which the project operates.

---

## R12 — Skill Inputs Must Reflect Actual Runtime Resolution

The `inputs` frontmatter of a skill is not just documentation — it is a contract that agents and reviewers use to understand what the skill consumes.

If a skill resolves its inputs dynamically (via index.md), its frontmatter MUST say so:

```yaml
# ✅ correct
inputs:
  - contexts/memory/index.md    (registry — read first)
  - contexts/memory/**          (resolved at runtime from index.md)

# ❌ misleading — implies fixed paths
inputs:
  - contexts/memory/project/context.md
  - contexts/memory/decisions/_log.md
```

Misleading frontmatter causes agents to pre-load wrong files or miss newly added categories.

---

## Audit Checklist (use when authoring or reviewing a skill)

Before marking a skill as `stable`:

- [ ] No specific memory file paths in `inputs` frontmatter (except `index.md`)
- [ ] No project-specific technology, provider, or team names in Process sections
- [ ] Memory is resolved via `index.md` lookup in the Process, not by assumed path
- [ ] Output paths use `{id}` patterns or category references, not hardcoded filenames
- [ ] All hardcoded values are structural constants (state machines, schemas, severity levels)
- [ ] `inputs` frontmatter accurately reflects runtime resolution behavior

---

> **Hardcode the framework. Discover the project.**
> A skill that encodes project state is a liability that compounds silently over time.
