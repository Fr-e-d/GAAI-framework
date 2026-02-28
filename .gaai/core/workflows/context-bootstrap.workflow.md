---
type: workflow
id: WORKFLOW-CONTEXT-BOOTSTRAP-001
track: cross
updated_at: 2026-01-31
---

# Context Bootstrap Workflow

## Purpose

Initialize and converge a governed project context when adding GAAI to an **existing codebase**.

Builds: structured memory, explicit governance rules, extracted architecture decisions.

**Run once per project. Re-run after major architectural changes.**

---

## When to Use

- First time adding GAAI to an existing project
- After major refactoring or architectural shifts
- When memory is stale or gaps are significant

---

## Agent

**Bootstrap Agent** (`agents/bootstrap.agent.md`)

---

## Workflow Steps

### Phase 1 — Observe Project Reality

1. Activate Bootstrap Agent
2. Invoke `codebase-scan` → produces `codebase_tree` and `key_files_list`
3. Invoke `architecture-extract` → produces `architecture_insights`

### Phase 2 — Surface Durable Knowledge

4. Invoke `decision-extraction` on existing codebase and documentation → extracts implicit decisions into `contexts/memory/decisions/`

### Phase 3 — Persist Structured Memory

5. Invoke `memory-ingest` with architecture insights and extracted decisions → populates `contexts/memory/project/` and index

### Phase 4 — Normalize Governance

7. Invoke `rules-normalize` on detected conventions (linters, security configs, architecture docs) → populates `contexts/rules/`

### Phase 5 — Memory Hygiene

8. Invoke `memory-refresh` → ensures no session noise pollutes long-term memory

### Phase 6 — Convergence Validation

9. Bootstrap Agent performs context gap analysis:
   - Compare project reality vs structured memory
   - Identify missing architecture elements, uncaptured decisions, weak governance rules
10. If gaps remain → return to Phase 1 and refine

---

## Decision Gate

```
PASS      → context converged, bootstrap complete
ESCALATE  → human input required (ambiguous decisions, unknown constraints)
FAIL      → gaps remain, retry bounded (max 3 attempts)
```

---

## Completion Criteria (Bootstrap PASS)

- ✅ Core project memory exists (architecture, stack, conventions)
- ✅ Durable decisions are explicitly captured
- ✅ Governance rules are normalized and active
- ✅ Memory index is clean and accurate
- ✅ No raw session data pollutes long-term memory
- ✅ No significant gaps remain between reality and memory

---

## After Bootstrap

Switch to:
- **Discovery Track** → if intent needs clarification before building
- **Delivery Track** → if a validated backlog already exists

See `discovery-to-delivery.workflow.md` for the handoff protocol.

---

## Automation

Shell automation available at `scripts/context-bootstrap.sh`.

See `scripts/README.scripts.md` for usage.
