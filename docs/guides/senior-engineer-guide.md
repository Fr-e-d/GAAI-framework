# Senior Engineer Guide

**For engineers who want full control over how GAAI governs their project.**

This guide covers: rules customization, memory architecture, CI integration, and governance enforcement.

---

## What You Control

GAAI's behavior is entirely driven by files in `.gaai/core/contexts/rules/`. Every constraint, every allowed action, every escalation condition — all in text. You read and modify them directly.

The framework enforces what you write. Nothing more.

---

## Rules Architecture

```
.gaai/core/contexts/rules/
├── README.rules.md           ← loading priority and index
├── orchestration.rules.md    ← agent authority and forbidden patterns
├── skills.rules.md           ← skill activation rules
├── artefacts.rules.md        ← artefact lifecycle and ownership
├── backlog.rules.md          ← backlog state transitions
├── memory.rules.md           ← memory loading and storage rules
└── context-discovery.rules.md ← when Discovery must run
```

**Load order matters.** `orchestration.rules.md` is always loaded first. It defines the authority hierarchy. Other rules are loaded by agents selectively based on the task.

**Editing rules is safe.** Agents read rules at runtime. No rebuild, no restart. Change a rule file → next agent activation picks it up.

---

## Customizing for Your Project

### 1. Add project-specific conventions

Edit `contexts/memory/patterns/conventions.md`. This is where you capture conventions that should influence agent behavior:

```markdown
## Code Style
- Use async/await — no raw Promise chains
- Error types: always typed (never `any`)
- Functions: max 40 lines

## Testing
- Unit tests required for all business logic
- Integration tests required for all API endpoints
- No mocking of database layer

## PR conventions
- One Story per PR
- PR title = Story title
```

The Delivery Agent loads `memory/patterns/conventions.md` when it builds execution context. Your conventions become implicit constraints on every implementation.

### 2. Add domain-specific rules

If your project has domain constraints (regulatory, security, architecture), add a custom rules file:

```
.gaai/core/contexts/rules/your-domain.rules.md
```

Reference it in `README.rules.md` so agents know to load it.

Example for a fintech project:

```markdown
---
type: rules
id: RULES-FINTECH-001
scope: delivery
---
# Fintech Rules

## Payment Flows
- All payment state changes must be idempotent
- Every transaction must log: amount, currency, user_id, timestamp, result
- No payment logic in controllers — service layer only

## PII
- Mask card numbers in all logs (show last 4 only)
- User PII never in query parameters
```

### 3. Tighten the Discovery gate

`context-discovery.rules.md` defines when Discovery is mandatory before Delivery can proceed. By default it's advisory. To make it enforced:

```markdown
## Enforcement
Discovery is MANDATORY before Delivery when:
- New user-facing feature
- API contract change
- Data schema change
- Cross-service dependency change

The Delivery Agent must refuse to proceed without a validated Story artefact for these categories.
```

---

## Memory Architecture

GAAI uses three memory files by default. You can extend this.

```
.gaai/project/contexts/memory/
├── memory/project/context.md     ← always loaded (project fundamentals)
├── memory/decisions/_log.md   ← append-only decision log
├── memory/patterns/conventions.md    ← conventions and preferences
└── memory/_template.md   ← template for new entries
```

**memory/project/context.md** — loaded by every agent on every session. Keep it short and stable. It answers: what is this project, what constraints exist, what are the non-negotiables.

**memory/decisions/_log.md** — accumulates. Agents append decisions after extracting them. Review it periodically and archive old entries that are no longer relevant.

**memory/patterns/conventions.md** — your living style guide. Update it when conventions evolve. The `rules-normalize` skill can help normalize and deduplicate entries.

### Adding domain-specific memory

For large projects, split memory by domain:

```
memory/
├── memory/project/context.md
├── memory/decisions/_log.md
├── memory/patterns/conventions.md
├── auth.memory.md        ← authentication decisions
├── api.memory.md         ← API design decisions
└── infra.memory.md       ← infrastructure constraints
```

Agents won't auto-load domain memory. They use `memory-retrieve` to load only what's relevant to the current task. Reference new files in `README.memory.md` so agents know they exist.

---

## CI Integration

GAAI ships a validation script. Use it as a CI gate.

### GitHub Actions

```yaml
# .github/workflows/validate-structure.yml
name: GAAI Structure Validation
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate .gaai/ integrity
        run: bash .gaai/core/scripts/health-check.sh
```

The health check validates:
- All SKILL.md files have required `name` and `description`
- All rule files are present
- VERSION file exists and is valid
- Backlog YAML is parseable
- Cross-references between artefacts and backlog are consistent

Exit 0 = pass. Exit 1 = fail with report.

### Pre-commit hook

```bash
# .git/hooks/pre-commit
#!/bin/bash
bash .gaai/core/scripts/health-check.sh
```

Blocks commits that break framework integrity.

---

## Backlog Governance

The backlog in `contexts/backlog/active.backlog.yaml` is the sole authorization mechanism. Govern it.

### Backlog item validation

The `backlog.rules.md` file defines what a valid backlog item looks like. Review and extend it for your project:

```markdown
## Required Fields
All backlog items must have:
- id (format: BL-NNN)
- title
- status
- priority
- track (discovery|delivery)
- complexity (fibonacci)
- acceptance_criteria (min 2 criteria)

## Forbidden States
- No item may transition from `refined` to `in-progress` without artefact path set
- No item may be marked `done` without QA report
```

### Backlog scheduler — governance views

The `backlog-scheduler.sh` script provides governance-focused views of the backlog beyond just "what's next":

```bash
# Priority conflicts: high-priority items blocked by lower-priority dependencies
.gaai/core/scripts/backlog-scheduler.sh --conflicts active.backlog.yaml
```

Example output:

```
Priority conflicts (2):

  ⚠️  BL-005 (high) is blocked by BL-002 (low)
      → Consider raising priority of BL-002 or lowering BL-005

  ⚠️  BL-007 (high) depends on BL-003 — dependency not found in backlog
      → BL-003 is listed as a dependency but not found in backlog
```

Run `--conflicts` during sprint planning or priority reviews to catch misalignments before they delay high-value work.

```bash
# Full dependency graph — which items are blocked and by what
.gaai/core/scripts/backlog-scheduler.sh --graph active.backlog.yaml
```

Add `--conflicts` to CI alongside `health-check.sh` if your team wants automated priority governance:

```yaml
# .github/workflows/validate-structure.yml
- run: |
    bash .gaai/core/scripts/health-check.sh
    bash .gaai/core/scripts/backlog-scheduler.sh --conflicts \
      .gaai/project/contexts/backlog/active.backlog.yaml || true
```

### Artefact traceability

Run `artefact-sync.sh` to validate that every backlog item with an artefact reference points to a real file:

```bash
bash .gaai/core/scripts/artefact-sync.sh
```

Use this in CI if traceability is required.

---

## Memory Hygiene

Memory grows. Keep it useful.

**Compact on context pressure:** When an agent reports token pressure, run `memory-compact` — it distills entries into summaries, replacing raw notes with actionable knowledge.

**Review quarterly:**
- `memory/decisions/_log.md` — archive decisions that are no longer relevant
- `memory/patterns/conventions.md` — remove patterns that have changed
- `memory/project/context.md` — update project fundamentals as the project evolves

**Snapshot before risky work:**

```bash
bash .gaai/core/scripts/memory-snapshot.sh
```

Creates a timestamped archive of the current memory state. Roll back to it if needed.

---

## Team Setup

For team usage, see [Team Setup Guide](team-setup-guide.md).

Key topics:
- Shared memory in git
- Branching and backlog conventions
- Rule ownership and review process
- Parallel Discovery sessions

---

→ [Team Setup Guide](team-setup-guide.md)
→ [Design Decisions](../architecture/design-decisions.md) — why the framework is structured this way
→ [Rules Reference](../reference/contexts.md)
