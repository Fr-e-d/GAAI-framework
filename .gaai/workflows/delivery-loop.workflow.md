---
type: workflow
id: WORKFLOW-DELIVERY-LOOP-001
track: delivery
updated_at: 2026-02-18
---

# Delivery Loop Workflow

## Purpose

Transform validated Stories into working, tested, governed software through coordinated sub-agent execution.

The Delivery Agent acts as orchestrator. It spawns specialized sub-agents, collects their handoff artefacts, and coordinates phase transitions until every Story either PASSes QA or ESCALATEs to the human.

---

## When to Use

- When Stories are validated and acceptance criteria are complete
- As the primary execution loop for all delivery work
- Invoked per Story or per batch from the active backlog

---

## Agent

**Delivery Agent / Orchestrator** (`agents/delivery.agent.md`)

Sub-agents spawned during execution:
- `agents/sub-agents/micro-delivery.sub-agent.md` (Tier 1)
- `agents/sub-agents/planning.sub-agent.md` (Tier 2/3)
- `agents/sub-agents/implementation.sub-agent.md` (Tier 2/3)
- `agents/sub-agents/qa.sub-agent.md` (Tier 2/3)
- Specialists per `contexts/specialists.registry.yaml` (Tier 3 only)

---

## Prerequisites

Before starting the loop:
- ✅ Stories are validated (`validate-artefacts` has PASSED)
- ✅ Acceptance criteria are present and testable
- ✅ Backlog item status is `refined`
- ✅ `contexts/specialists.registry.yaml` is present

---

## Workflow Steps

### 0. Git Setup (before any execution)

For every Story, before any implementation begins:

```bash
# Create isolated branch from production
git checkout production
git pull origin production
git checkout -b story/{id}

# Create worktree — agent works in isolated directory, never in the main repo
git worktree add ../{id}-workspace story/{id}
```

All sub-agents operate exclusively inside `../{id}-workspace/`. The main working directory is never touched during delivery. If two Stories run in parallel, each has its own worktree — zero filesystem conflicts.

> Solo founder shortcut: for Tier 1 (MicroDelivery, low-risk, no schema changes), worktree is optional — branch only is acceptable.

### 1. Select Next Story

Read `contexts/backlog/active.backlog.yaml`. Select the highest-priority ready Story (status: `refined`, no unresolved dependencies). Use `scripts/backlog-scheduler.sh --next` for automated selection.

### 2. Evaluate Story

Invoke `evaluate-story` → returns tier (1/2/3), specialists_triggered, risk_analysis_required.

### 3. Compose Team

Invoke `compose-team` → assembles context bundles for each sub-agent in the selected tier.

If `risk_analysis_required: true` → invoke `risk-analysis` and add output to Planning Sub-Agent context bundle.

### 4. Execute — Tier 1 (MicroDelivery)

Spawn `micro-delivery.sub-agent.md` with minimal context bundle.

Collect `{id}.micro-delivery-report.md`.

Invoke `coordinate-handoffs`:
- PASS → proceed to step 8
- FAIL (recoverable: test failure, logic bug) → retry once; if second attempt fails → complexity-escalation to Tier 2
- FAIL (structural: AC ambiguous, context gap, rule conflict) → ESCALATE immediately, no retry
- ESCALATE → stop, surface to human + invoke `post-mortem-learning`
- complexity-escalation → re-evaluate as Tier 2, proceed to step 5

### 5. Execute — Tier 2/3: Planning Phase

Spawn `planning.sub-agent.md` with Planning context bundle.

Collect `{id}.execution-plan.md`.

Invoke `coordinate-handoffs` → validate artefact → PROCEED or RE-SPAWN or ESCALATE.

### 6. Execute — Tier 2/3: Implementation Phase

Spawn `implementation.sub-agent.md` with Implementation context bundle.

For Tier 3: Implementation Sub-Agent spawns Specialists per registry triggers.

Collect `{id}.impl-report.md`.

Invoke `coordinate-handoffs` → validate artefact → PROCEED or RE-SPAWN or ESCALATE.

**After PROCEED — atomic commit:**
```bash
git -C ../{id}-workspace add .
git -C ../{id}-workspace commit -m "feat({id}): {Story title summary}

Implements: {AC list e.g. AC1–AC9}
Story: contexts/artefacts/stories/{id}.story.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### 7. Execute — Tier 2/3: QA Phase

Spawn `qa.sub-agent.md` with QA context bundle.

Collect `{id}.qa-report.md`.

Invoke `coordinate-handoffs`:
- PASS → proceed to step 8
- FAIL → re-spawn Implementation Sub-Agent with qa-report, then re-spawn QA Sub-Agent (max 3 cycles — see `qa.sub-agent.md`)
- ESCALATE → stop, surface to human

### 8. Merge & Complete Story

**After QA PASS — push, merge, cleanup:**

```bash
# Push branch
git -C ../{id}-workspace push origin story/{id}

# Squash merge to production (single clean commit per Story)
git checkout production
git merge --squash story/{id}
git commit -m "feat({id}): {Story title}

$(cat contexts/artefacts/reports/{id}.impl-report.md | head -20)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push origin production

# Cleanup
git worktree remove ../{id}-workspace
git branch -d story/{id}
git push origin --delete story/{id}
```

> **PR instead of direct merge** — required for: Tier 3 Stories, database schema changes, auth/security changes. Optional for Tier 1/2 routine Stories (solo founder context). When required: `gh pr create --base production --head story/{id}` before merge.

**Backlog & memory:**

Update Story status to `done` in `contexts/backlog/active.backlog.yaml`.

Move completed Story to `contexts/backlog/done/{YYYY-MM}.done.yaml`.

Invoke `decision-extraction` if notable architectural or governance decisions emerged.

Invoke `memory-retrieve` + `memory-ingest` if new patterns worth persisting were identified.

**If the Story required human intervention or reached 3 QA cycles:** invoke `post-mortem-learning`. Record the friction signal (domain, root cause hypothesis, AC gap if applicable) as a `[FRICTION]` entry in `contexts/memory/decisions.memory.md`. This informs future Discovery refinement.

Proceed to next Story.

---

## Flow Diagram

```
active.backlog.yaml
       ↓
Pick next ready Story
       ↓
git checkout -b story/{id} + worktree add ../{id}-workspace
       ↓
evaluate-story
       ↓
Tier 1? ──→ spawn MicroDelivery Sub-Agent
             ↓
             coordinate-handoffs
             ↓
             PASS→done
             FAIL(recoverable)→retry once→FAIL again→Tier2
             FAIL(structural)→ESCALATE+post-mortem immediately
             ESCALATE→human+post-mortem  COMPLEX→Tier2
       ↓
Tier 2/3? ──→ compose-team (+ risk-analysis if needed)
             ↓
             spawn Planning Sub-Agent ──→ {id}.execution-plan.md
             ↓
             spawn Implementation Sub-Agent ──→ {id}.impl-report.md
             │    (+ Specialists if Tier 3)
             ↓ atomic commit in worktree
             spawn QA Sub-Agent ──→ {id}.qa-report.md
             ↓
             PASS → push story/{id} → squash merge → production → cleanup worktree → done
             FAIL → re-spawn Impl + re-spawn QA (max 3 cycles)
             ESCALATE → human intervention required
             ↓ (on ESCALATE or 3 QA cycles)
             post-mortem-learning → [FRICTION] entry in decisions.memory.md
```

---

## Sub-Agent Lifecycle (Invariant)

Every sub-agent, without exception:

```
SPAWN   ← Orchestrator provides explicit context bundle
EXECUTE ← Runs autonomously, no runtime communication
HANDOFF ← Writes structured artefact to known file path
DIE     ← Terminates, context window released
```

The Orchestrator only acts after a sub-agent has terminated and its artefact has been collected.

---

## Stop Conditions

**Recoverable failures** — retry is authorized (up to the cycle limits above):
- Test failure with a clear root cause
- Logic bug with a deterministic fix
- Missing file or dependency that can be created within Story scope

**Structural failures** — ESCALATE immediately, no retry:
- Acceptance criteria are ambiguous or contradictory
- A fix would require changing product scope or intent
- A rule violation has no compliant resolution path
- Missing context that cannot be inferred from the Story or memory
- The same failure pattern recurs across retry cycles (loop detected)

The Delivery Orchestrator MUST escalate on any structural failure regardless of remaining retry budget.

---

## Automation

Shell automation available at `scripts/backlog-scheduler.sh` (selects next Story).

See `scripts/README.scripts.md` for usage.
