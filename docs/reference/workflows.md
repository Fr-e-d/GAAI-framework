# Workflows Reference

Workflows describe how the pieces of GAAI connect. They are prose documents with decision gates — not code.

---

## All Workflows

| Workflow | Agent | When to use |
|---|---|---|
| `context-bootstrap.workflow.md` | Bootstrap | First session on an existing codebase |
| `delivery-loop.workflow.md` | Delivery | Executing refined Stories from the backlog |
| `discovery-to-delivery.workflow.md` | Discovery → Delivery | Handing off from Discovery to Delivery |
| `emergency-rollback.workflow.md` | Delivery | When Delivery goes wrong and you need to recover |

---

## Context Bootstrap Workflow

**File:** `.gaai/core/workflows/context-bootstrap.workflow.md`

**Purpose:** Initialize GAAI on an existing codebase. Run once.

**Agent:** Bootstrap Agent

**Phases:**
1. Codebase scan (`codebase-scan`)
2. Architecture extraction (`architecture-extract`)
3. Decision capture (`decision-extraction`)
4. Memory ingestion (`memory-ingest`)
5. Rules normalization (`rules-normalize`)
6. Consistency validation (`consistency-check`)

**Gate:** Completes with `✅ Bootstrap PASS` or `❌ Bootstrap FAIL` (specific gaps listed).

---

## Delivery Loop Workflow

**File:** `.gaai/core/workflows/delivery-loop.workflow.md`

**Purpose:** Execute governed Stories using the Orchestrator model — evaluate complexity, compose a sub-agent team, coordinate handoffs, and close the Story.

**Agent:** Delivery Orchestrator + sub-agents (Planning, Implementation, QA, MicroDelivery)

**Steps:**
1. Select next `refined` Story from `active.backlog.yaml`
2. `evaluate-story` → determine tier (1 / 2 / 3) and specialist triggers
3. `compose-team` → assemble context bundles per sub-agent
4. **Tier 1 — MicroDelivery:** spawn single MicroDelivery Sub-Agent (plan + implement + QA in one context)
5. **Tier 2/3 — Core Team:**
   - Spawn Planning Sub-Agent → produces `{id}.execution-plan.md`
   - Spawn Implementation Sub-Agent (+ Specialists if Tier 3) → produces `{id}.impl-report.md`
   - Spawn QA Sub-Agent → produces `{id}.qa-report.md` (contains internal remediation loop, max 3 attempts)
6. `coordinate-handoffs` validates each artefact: PROCEED / RE-SPAWN / ESCALATE / COMPLETE
7. On COMPLETE: mark Story done, archive artefacts, capture decisions in memory

**Flow:**

```
Backlog → Pick Story
  ↓
evaluate-story → tier 1 / 2 / 3
  ↓
compose-team → context bundles
  ↓
Tier 1:  [MicroDelivery] → micro-delivery-report → COMPLETE
Tier 2/3:[Planning] → execution-plan
         [Implementation (+Specialists)] → impl-report
         [QA] → qa-report (remediation loop inside, max 3x)
  ↓
coordinate-handoffs
  COMPLETE → mark done, archive, memory-ingest
  ESCALATE → human intervention
```

**Sub-agent lifecycle (invariant):** spawn → execute → handoff-artefact → die. No runtime communication between sub-agents. All coordination is via files.

---

## Discovery to Delivery Handoff

**File:** `.gaai/core/workflows/discovery-to-delivery.workflow.md`

**Purpose:** Formal handoff protocol between Discovery and Delivery tracks.

**Handoff gate conditions — all must be true:**

| Condition | Check |
|---|---|
| All target Stories have `status: refined` | `active.backlog.yaml` |
| `validate-artefacts` returned PASS for all Stories | Validation report present |
| Acceptance criteria are present and testable | Each Story has ≥2 criteria |
| No unresolved risks flagged as BLOCKER | Risk register reviewed |
| Memory captures current decisions | `memory/decisions/_log.md` updated |

If any condition fails: return to Discovery.

**Post-handoff:** Delivery begins autonomously. Human only re-engages if Delivery escalates.

---

## Emergency Rollback Workflow

**File:** `.gaai/core/workflows/emergency-rollback.workflow.md`

**Purpose:** Recover when Delivery produces incorrect or dangerous output.

**When to use:**
- QA is failing consistently after multiple remediation attempts
- Delivered code breaks existing functionality
- Agent made architectural decisions it should have escalated

**Steps:**
1. Stop Delivery Agent immediately
2. Identify last known good state (last `status: done` item)
3. Revert code changes (git)
4. Reset backlog item status to `refined` or `needs-refinement`
5. Diagnose root cause (see root cause table in workflow file)
6. Either: update acceptance criteria and retry, or return to Discovery

**Root cause categories:**

| Root cause | Action |
|---|---|
| Acceptance criteria were ambiguous | Return to Discovery; clarify Story |
| Rules were missing or conflicting | Update rules; re-run `rules-normalize` |
| Memory was outdated | Run `memory-refresh`; retry |
| Scope crept during implementation | Reset to Story spec; re-implement |

---

→ [Agents Reference](agents.md)
→ [Scripts Reference](scripts.md)
