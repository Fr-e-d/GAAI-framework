---
type: workflow
id: WORKFLOW-DELIVERY-LOOP-001
track: delivery
updated_at: 2026-02-23
---

# Delivery Loop Workflow

> **Branch model:** The delivery workflow targets the `staging` branch. AI never interacts with `production`. Promotion staging → production is a human action via GitHub PR.

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
- Specialists per `agents/specialists.registry.yaml` (Tier 3 only)

---

## Prerequisites

Before starting the loop:
- ✅ Stories are validated (`validate-artefacts` has PASSED)
- ✅ Acceptance criteria are present and testable
- ✅ Backlog item status is `refined`
- ✅ `agents/specialists.registry.yaml` is present

---

## Workflow Steps

### 0. Git Setup (before any execution)

**CRITICAL INVARIANT: The main working tree stays on `staging` at ALL times.** The daemon polls in the main working tree. Deliveries work in worktrees. All staging operations (pull, merge, push) are serialized via `flock .gaai/project/contexts/backlog/.delivery-locks/.staging.lock`.

### Staging Push Retry Pattern

With `--max-concurrent > 1`, concurrent `git push origin staging` can fail (non-fast-forward). All staging push operations use a retry-with-rebase pattern (DEC-146):

```bash
# Retry pattern: pull --rebase + push, 3 attempts, exponential backoff
for attempt in 1 2 3; do
  git pull --rebase origin staging && git push origin staging && break
  [ $attempt -lt 3 ] && sleep $((attempt * 2))  # backoff: 2s, 4s, 6s
done || { echo "ESCALATE: staging push failed after 3 attempts"; exit 1; }
```

- **3 attempts**, backoff 2s / 4s / 6s
- On exhaustion: **ESCALATE** (do not mark done, do not lose work)
- `flock` serialization still applies (prevents local contention on multi-worktree macOS setups)

For every Story, before any implementation begins:

```bash
# Step 0a: Sync with latest staging (under flock if concurrent)
flock .gaai/project/contexts/backlog/.delivery-locks/.staging.lock bash -c '
  git pull origin staging
'

# Step 0b: Mark in_progress + push with retry (cross-device coordination)
# If daemon-launched: already done by the daemon. Skip if status is already in_progress.
# If manual launch: the delivery agent does this itself.
flock .gaai/project/contexts/backlog/.delivery-locks/.staging.lock bash -c '
  .gaai/core/scripts/backlog-scheduler.sh --set-status {id} in_progress .gaai/project/contexts/backlog/active.backlog.yaml
  git add .gaai/project/contexts/backlog/active.backlog.yaml
  git commit -m "chore({id}): in_progress [delivery]"
  for attempt in 1 2 3; do
    git pull --rebase origin staging && git push origin staging && break
    [ $attempt -lt 3 ] && sleep $((attempt * 2))
  done || { echo "ESCALATE: staging push failed after 3 attempts"; exit 1; }
'

# Step 0c: Create branch WITHOUT switching (main stays on staging)
git branch story/{id} staging
git worktree add ../{id}-workspace story/{id}
```

All sub-agents operate exclusively inside `../{id}-workspace/`. The main working directory stays on `staging` and is never switched. If two Stories run in parallel, each has its own worktree — zero filesystem conflicts.

> Solo founder shortcut: for Tier 1 (MicroDelivery, low-risk, no schema changes), worktree is optional — branch only is acceptable.

### 1. Select Next Story

Read `.gaai/project/contexts/backlog/active.backlog.yaml`. Select the highest-priority ready Story (status: `refined`, no unresolved dependencies). Use `.gaai/core/scripts/backlog-scheduler.sh --next .gaai/project/contexts/backlog/active.backlog.yaml` for automated selection.

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

### 7b. Commit Delivery Artefacts to Story Branch

After QA PASS, commit all delivery artefacts (execution-plan, impl-report, qa-report, memory-delta) to the story branch in the worktree. This ensures artefacts flow to staging via the PR merge — never pushed directly to staging (DEC-146).

```bash
# Step 7b: Commit delivery artefacts to story branch (in worktree)
git -C ../{id}-workspace add .gaai/project/contexts/artefacts/
git -C ../{id}-workspace commit -m "docs({id}): delivery artefacts — plan, impl-report, qa-report, memory-delta"
```

### 8. Create PR & Complete Story

**8a. Push story branch and create PR to staging:**

```bash
# Push story branch to origin
git -C ../{id}-workspace push origin story/{id}

# Create PR targeting staging (human will review and merge)
gh pr create --base staging --head story/{id} \
  --title "feat({id}): {Story title}" \
  --body "$(cat <<'EOF'
## Summary
{1-3 bullet points from impl-report}

## Test Results
- Tests: {X}/{X} pass
- TSC: clean
- QA Verdict: PASS

## Changes Delivered
| File | Purpose |
|------|---------|
{table from impl-report}

## Story
- ID: {id}
- Artefact: .gaai/project/contexts/artefacts/stories/{id}.story.md

🤖 Generated with [GAAI Delivery Agent](https://github.com/Fr-e-d/GAAI-framework)
EOF
)"
```

> The AI never merges to staging. It creates a PR for human review. The human merges when satisfied.

**8b. Delivery artefacts:** Delivery artefacts are committed to the story branch before PR creation (step 7b) and merge to staging via the PR (DEC-146). No separate staging push needed.

**8c. Mark Story done + cleanup worktree:**

```bash
# Remove worktree (but keep story branch — needed for the PR)
git worktree remove ../{id}-workspace

# Update backlog (push with retry — DEC-146)
flock .gaai/project/contexts/backlog/.delivery-locks/.staging.lock bash -c '
  git pull origin staging
  .gaai/core/scripts/backlog-scheduler.sh --set-status {id} done .gaai/project/contexts/backlog/active.backlog.yaml
  git add .gaai/project/contexts/backlog/active.backlog.yaml
  git commit -m "chore({id}): done [delivery]"
  for attempt in 1 2 3; do
    git pull --rebase origin staging && git push origin staging && break
    [ $attempt -lt 3 ] && sleep $((attempt * 2))
  done || { echo "ESCALATE: staging push failed after 3 attempts"; exit 1; }
'
```

> **Note:** The story branch is NOT deleted. It stays on origin for the PR. GitHub can auto-delete branches after PR merge (configure in repo Settings → General → "Automatically delete head branches").

Move completed Story to `contexts/backlog/done/{YYYY-MM}.done.yaml`.

Invoke `decision-extraction` if notable architectural or governance decisions emerged.

Invoke `memory-retrieve` + `memory-ingest` if new patterns worth persisting were identified.

**If the Story required human intervention or reached 3 QA cycles:** invoke `post-mortem-learning`. Record the friction signal (domain, root cause hypothesis, AC gap if applicable) as a `[FRICTION]` entry in `contexts/memory/decisions.memory.md`. This informs future Discovery refinement.

**STOP — report to human:**

```
✅ PR created for review: {PR_URL}

Story: {id} — {Story title}
QA: PASS ({X}/{X} tests, tsc clean)

Next: review and merge the PR on GitHub.
```

**8d. On PR creation failure:**

If `gh pr create` fails (e.g., branch conflict, auth issue):
- Log the error
- Do NOT update backlog to done
- ESCALATE to human with the error details

---

## Flow Diagram

```
active.backlog.yaml (read via git show origin/staging:...)
       ↓
Pick next ready Story
       ↓
flock: git pull staging → mark in_progress → commit → push staging (with retry)
       ↓
git branch story/{id} staging (NO checkout) + worktree add ../{id}-workspace
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
             PASS → commit artefacts to story branch (step 7b)
                      → push story/{id} → gh pr create --base staging
                      → flock: mark done → push staging (with retry)
                      → cleanup worktree (keep branch for PR)
                      → STOP + report PR URL (human reviews + merges on GitHub)
             FAIL → re-spawn Impl + re-spawn QA (max 3 cycles)
             ESCALATE → human intervention required
             ↓ (on ESCALATE or 3 QA cycles)
             post-mortem-learning → [FRICTION] entry in decisions.memory.md
             ↓ (human merges PR staging→production)
             CI/CD auto-deploys production
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

Shell automation available at `.gaai/core/scripts/backlog-scheduler.sh` (selects next Story).

See `scripts/README.scripts.md` for usage.
