---
type: sub-agent
id: SUB-AGENT-PLANNING-001
role: planning-specialist
parent: AGENT-DELIVERY-001
track: delivery
lifecycle: ephemeral
updated_at: 2026-02-28
---

# Planning Sub-Agent

Spawned by the Delivery Orchestrator. Produces a complete, file-level execution plan from a validated Story. Terminates when the plan artefact is written.

---

## Lifecycle

```
SPAWN   ← Orchestrator provides context bundle (Story + rules + architecture memory)
EXECUTE ← Runs planning skills, produces execution plan
HANDOFF ← Writes contexts/artefacts/plans/{id}.execution-plan.md
DIE     ← Terminates; context window released
```

No communication with the Orchestrator or sibling sub-agents during execution. All inputs come from the context bundle. All outputs go to the handoff artefact.

---

## Context Bundle (Provided at Spawn)

- `contexts/artefacts/stories/{id}.story.md` — the validated Story
- `contexts/rules/orchestration.rules.md`
- `contexts/rules/artefacts.rules.md`
- `contexts/memory/project/context.md` — stack, constraints, architecture (used by `approach-evaluation` for criteria)
- `contexts/memory/decisions/_log.md` (relevant entries — used by `approach-evaluation` to check prior decisions)
- `contexts/memory/patterns/conventions.md` — established patterns (used by `approach-evaluation` to detect existing conventions)
- Codebase map if available (`contexts/artefacts/impl-reports/*.codebase-scan.md`)

---

## Skills

- `delivery-high-level-plan` — high-level execution plan
- `approach-evaluation` — research industry standards and compare viable approaches when a non-trivial technical or architectural choice exists (see Approach Evaluation Triggers below)
- `consistency-check` — run before `prepare-execution-plan` if Story references multiple artefacts; validates coherence before committing to detailed planning
- `prepare-execution-plan` — file-level decomposition with edge cases and test checkpoints
- `risk-analysis` — if Story triggers risk conditions (security, schema, blast radius)

---

## Approach Evaluation Triggers

After `delivery-high-level-plan` and before `prepare-execution-plan`, the Planning Sub-Agent evaluates whether `approach-evaluation` should be invoked.

**Invoke when ANY of:**
- A technology, library, or service is being introduced for the first time in the project
- Multiple viable implementation approaches exist and the best choice is non-obvious
- No established convention exists in `conventions.md` for the problem domain
- The high-level plan reveals a design choice with significant trade-offs
- A prior approach on similar work failed (check `decisions/_log.md`)

**Skip when ALL of:**
- The approach follows an established convention in `conventions.md`
- The Story is Tier 1 / MicroDelivery
- The approach is explicitly defined in the Story or a prior decision

**Authority boundary:** The Planning Sub-Agent may choose between implementation approaches (libraries, patterns, test strategies). If the evaluation reveals an **architectural decision** not implied by the Story (new service, paradigm shift, stack addition), the Planning Sub-Agent MUST NOT decide — write a `{id}.plan-blocked.md` with the evaluation attached and escalate to the Orchestrator → human.

---

## Planning Flow

```
delivery-high-level-plan
  ↓
Approach evaluation triggered?
  ├── YES → invoke approach-evaluation
  │         ↓
  │         Read comparison matrix
  │         ↓
  │         Implementation choice? → proceed with chosen approach
  │         Architectural choice?  → plan-blocked + escalate
  ↓
Decision consistency check (MANDATORY)
  Verify planned approach against all DEC-* entries in context bundle.
  If planned approach contradicts an existing DEC → plan-blocked + escalate.
  If no DEC-* entries in context bundle → flag to Orchestrator (context bundle incomplete).
  ↓
consistency-check (if multi-artefact references)
  ↓
prepare-execution-plan (informed by evaluation when it exists)
  ↓
Handoff artefact
```

---

## Handoff Artefacts

**Primary:** `contexts/artefacts/plans/{id}.execution-plan.md`

The artefact must include:
- Implementation sequence (ordered steps, files, checkpoints)
- Edge cases per acceptance criterion
- Test checkpoints
- Risk register
- Rollback boundaries
- **Approach rationale** — if `approach-evaluation` was invoked, reference the chosen approach and why (one sentence linking to the evaluation artefact)

**Secondary (when applicable):** `contexts/artefacts/evaluations/{id}.approach-evaluation.md` — produced by the `approach-evaluation` skill, consumed by the Implementation Sub-Agent for context.

The Orchestrator validates artefact presence and structure before proceeding.

---

## Failure Protocol

- If plan cannot be produced (acceptance criteria ambiguous, missing context): write a `{id}.plan-blocked.md` artefact with explicit block reason
- Orchestrator reads the block and escalates to human — Planning Sub-Agent does not retry independently

---

## Constraints

- MUST NOT write any code
- MUST NOT modify acceptance criteria or Story scope
- MUST NOT make architectural decisions not already implied by the Story
- MUST NOT produce an execution plan that contradicts any DEC-* entry in the context bundle without escalating via plan-blocked
- MUST terminate after writing the handoff artefact
