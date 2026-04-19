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

With `--max-concurrent > 1`, concurrent `git push origin staging` can fail (non-fast-forward). All staging push operations use a retry-with-rebase pattern:

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
# Step 0 — Prerequisites
# Verify remote exists (GAAI requires a configured remote for PR-based delivery)
git remote get-url origin 2>/dev/null || {
  echo "FATAL: no 'origin' remote configured. GAAI requires a remote repository for PR-based delivery."
  echo "Run: git remote add origin <url>"
  exit 1
}

# Resolve worktree path ONCE as absolute — all subsequent operations use $WORKTREE_PATH
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE_PATH="${GAAI_WORKTREE_BASE:-${REPO_ROOT}/..}/${id}-workspace"

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
git worktree add "$WORKTREE_PATH" story/{id}

# Step 0d: Validate worktree exists (mandatory gate — do NOT skip)
if [ ! -e "$WORKTREE_PATH/.git" ]; then
  echo "FATAL: worktree not found at $WORKTREE_PATH — cannot proceed with delivery"
  exit 1
fi
```

All sub-agents operate exclusively inside `$WORKTREE_PATH`. The main working directory stays on `staging` and is never switched. If two Stories run in parallel, each has its own worktree — zero filesystem conflicts. Worktree isolation is **unconditional** regardless of story tier.

Override the default worktree location by setting `GAAI_WORKTREE_BASE` (e.g., `export GAAI_WORKTREE_BASE=/tmp/gaai-worktrees` for cloud-synced repos).

### 1. Select Next Story

Read `.gaai/project/contexts/backlog/active.backlog.yaml`. Select the highest-priority ready Story (status: `refined`, no unresolved dependencies). Use `.gaai/core/scripts/backlog-scheduler.sh --next .gaai/project/contexts/backlog/active.backlog.yaml` for automated selection.

### 2. Evaluate Story

Invoke `evaluate-story` → returns tier (1/2/3), specialists_triggered, risk_analysis_required.

### 2b. Persist Tier Assignment

After evaluate-story completes and **before spawning any sub-agent**, persist the tier on the backlog entry:

```bash
.gaai/core/scripts/backlog-scheduler.sh --set-field {id} tier {1|2|3} \
  .gaai/project/contexts/backlog/active.backlog.yaml
```

The `tier` value is the integer (1, 2, or 3) returned by evaluate-story. This enables delivery telemetry segmentation (cost, duration, retry rate by tier) and future threshold calibration.

### 3. Compose Team

Invoke `compose-team` → assembles context bundles for each sub-agent in the selected tier.

If `risk_analysis_required: true` → invoke `risk-analysis` and add output to Planning Sub-Agent context bundle.

#### Per-story trace_id

Before spawning any sub-agent, generate a trace_id that will flow through Plan, Impl, and QA logging calls:

```bash
STORY_TRACE_ID="$(node -e 'import("node:crypto").then(m=>process.stdout.write(m.randomUUID()))')"
```

If the Implementation phase uses the secondary path, `STORY_TRACE_ID` is replaced by the wrapper's `trace_id` (see §6a). The same `STORY_TRACE_ID` is passed to all phase observability hooks (E94S06 defines the call; reserved here).

### 4. Execute — Tier 1 (MicroDelivery)

> **Scope note — `impl_model` is IGNORED for Tier 1 (V1 design):**
> MicroDelivery runs Plan+Impl+QA in a single sub-agent context. This is incompatible with isolated-Impl-phase routing to a secondary provider. For a true Tier 1 story (≤ 2 complexity, ≤ 3 ACs, minimal files), the overhead of splitting into Plan/Impl/QA sub-agents to enable secondary routing would COST MORE (3× context loading, 3× rules/memory retrieval) than the savings on a ≤10 LoC Impl phase.
>
> **Behavior:** if `impl_model: secondary` is set on a Tier 1 story, the tag is ignored with a log warning. Delivery proceeds as standard MicroDelivery on primary.
>
> **Log the ignored tag** at MicroDelivery entry:
> ```bash
> if [ "$impl_model" = "secondary" ]; then
>   echo "⚠ impl_model=secondary ignored for Tier 1 (MicroDelivery design). Running on primary."
>   node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
>     --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "impl" \
>     --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
>     --duration-ms 0 --fallback-reason "" --impl-model-tag "secondary_ignored_tier1" 2>/dev/null || true
> fi
> ```
>
> **Rationale:** Epic E94 D-0 non-regression and D-2 (Plan/QA primary) both hold; stories that want secondary routing should be Tier 2+ at discovery-time. If a Tier 1 story truly benefits from secondary, revisit its tiering at Discovery.

Spawn `micro-delivery.sub-agent.md` with minimal context bundle.

Collect `{id}.micro-delivery-report.md`.

Invoke `coordinate-handoffs`:
- PASS → proceed to step 8
- FAIL (recoverable: test failure, logic bug) → retry once; if second attempt fails → complexity-escalation to Tier 2
- FAIL (structural: AC ambiguous, context gap, rule conflict) → ESCALATE immediately, no retry
- ESCALATE → stop, surface to human + invoke `post-mortem-learning`
- complexity-escalation → re-evaluate as Tier 2, proceed to step 5

### 5. Execute — Tier 2/3: Planning Phase

> **Provider:** Task tool on primary (regardless of `impl_model`). *Plan phase authors the contract; reasoning stays on primary per Epic E94 D-2.*

Spawn `planning.sub-agent.md` with Planning context bundle.

Collect `{id}.execution-plan.md`.

Invoke `coordinate-handoffs` → validate artefact → PROCEED or RE-SPAWN or ESCALATE.

**After PROCEED — log Plan phase:**
```bash
node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
  --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "plan" \
  --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
  --duration-ms 0 --fallback-reason "" --impl-model-tag "${impl_model_tag:-absent}" 2>/dev/null || true
```

### 6. Execute — Tier 2/3: Implementation Phase

#### 6a. Implementation Phase Routing

> **Plan phase:** Always uses the Task tool on primary regardless of `impl_model`.
> *Plan phase authors the contract; reasoning stays on primary per Epic E94 D-2.*

> **QA phase:** Always uses the Task tool on primary regardless of `impl_model`.
> *QA validates against the Plan's contract; consistency stays on primary per Epic E94 D-2.*

The routing decision is evaluated **exactly once** at Implementation phase entry. Mid-phase changes to env vars or the backlog entry do NOT re-trigger evaluation.

> **🔒 Mode invariance (NON-NEGOTIABLE — applies to ALL Implementation Agents):**
> The decision to invoke `nested-claude-spawn.js` is based EXCLUSIVELY on the two conditions in the decision matrix below:
> (a) `impl_model == "secondary"` in the backlog entry, AND
> (b) all three `GAAI_IMPL_*` environment variables are present and non-empty.
>
> **No other factor influences this decision.** In particular:
> - Whether the delivery was launched by the daemon, by `/gaai-deliver` manually, or in any other context is **IRRELEVANT**. `nested-claude-spawn.js` is a standalone Node.js module callable from ANY bash context — it does not require, detect, or care about "daemon mode".
> - Whether the current session feels "interactive" or "non-interactive" is **IRRELEVANT**. The wrapper spawns a `claude -p` subprocess regardless.
> - The agent's subjective judgment about whether the story "really needs" secondary routing is **IRRELEVANT**. If the two conditions are met, the wrapper MUST be invoked. There is no "prefer primary because simpler" escape hatch.
>
> **If you (the agent) find yourself reasoning "I'll use primary because X":** STOP. X is invalid unless X is literally one of the two matrix conditions. Route to nested wrapper per the matrix.
>
> **Rationale:** Epic E94 D-0 (non-regression) is preserved by the `impl_model` tag itself — stories without the tag use primary. Agents second-guessing the matrix defeat the entire Epic's purpose (quota savings) and produce misleading `runtime-routing.jsonl` logs (e.g., `secondary_but_env_missing` logged when env was actually present).

**Decision matrix:**

```
read impl_model from backlog entry    # canonical runtime source per E94S02 AC6

# Non-behaviors (V1 — explicit):
#   - No "try with half-quota first" or tiered fallback
#   - No exponential backoff on endpoint errors
#   - No retry on the nested subprocess
#   - No circuit-breaker auto-disable of secondary
# Fallback is atomic binary: secondary failed → primary runs (or escalates). T-2.

if impl_model == "secondary":
    # Pre-flight env check (never attempt secondary if env missing)
    missing = []
    if not GAAI_IMPL_BASE_URL  (non-empty): missing += ["GAAI_IMPL_BASE_URL"]
    if not GAAI_IMPL_AUTH_TOKEN(non-empty): missing += ["GAAI_IMPL_AUTH_TOKEN"]
    if not GAAI_IMPL_MODEL     (non-empty): missing += ["GAAI_IMPL_MODEL"]

    if missing:
        warn("IMPL_ROUTING_ENV_MISSING: expected GAAI_IMPL_BASE_URL|AUTH_TOKEN|MODEL, got: " + join(missing, ", "))
        echo "⚠ impl_model=secondary but GAAI_IMPL_* env vars missing; using primary."
        node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
          --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "impl" \
          --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
          --duration-ms 0 --fallback-reason "" --impl-model-tag "secondary_but_env_missing" 2>/dev/null || true
        route → Task tool on primary

    else:
        # EXPLICIT BASH INVOCATION (mandatory — do NOT attempt the Task tool here).
        # The nested-claude-spawn.js module now exposes a CLI (since commit 252f60b7+).
        # Write the impl prompt to a tempfile and invoke the wrapper via Bash tool:
        #
        #   IMPL_PROMPT_FILE="$(mktemp -t gaai-impl-prompt.XXXXXX)"
        #   printf '%s' "$IMPL_PROMPT" > "$IMPL_PROMPT_FILE"
        #   result_json=$(node .gaai/core/adapters/claude-code/nested-claude-spawn.js \
        #     --prompt-file "$IMPL_PROMPT_FILE" \
        #     --report-path "$IMPL_REPORT_PATH")
        #   rm -f "$IMPL_PROMPT_FILE"
        #   result_trace_id=$(echo "$result_json" | jq -r '.trace_id')
        #   result_success=$(echo "$result_json" | jq -r '.success')
        #   result_model_actual=$(echo "$result_json" | jq -r '.model_actual')
        #   result_error_reason=$(echo "$result_json" | jq -r '.error_reason // empty')
        #   result_duration=$(echo "$result_json" | jq -r '.duration_ms')
        #
        # The CLI exits 0 regardless of business-logic success (distinguish via result_success).
        # IMPL_PROMPT is the same impl prompt you would pass to an Implementation Sub-Agent
        # via Task tool — just redirected to the wrapper via CLI.
        #
        # After this call, STORY_TRACE_ID is replaced with result_trace_id.
        STORY_TRACE_ID="$result_trace_id"
        # Pass result.error_reason as fallback_reason: non-null on failure, null on success.
        # On success the logger prints "... done"; on failure "... ⚠ Falling back to primary (reason: <CLASS>)".
        node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
          --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "impl" \
          --provider "secondary" --model "${result.model_actual:-$GAAI_IMPL_MODEL}" \
          --duration-ms "${result.duration_ms}" --fallback-reason "${result.error_reason:-}" \
          --impl-model-tag "secondary" 2>/dev/null || true
        if result.success:
            proceed to QA (§7)
        else:
            # Universal fallback — any error class triggers primary re-invocation (E94S05)
            fallback_reason = result.error_reason   # exact error class name; passed to E94S06 log
            # trace_id is already captured from result.trace_id above (shared across both attempts)
            primary_result = invoke Implementation Sub-Agent via Task tool on primary
                             with identical implPrompt, implReportPath, story context
            # Log primary fallback attempt (stdout: "▸ Phase Impl (primary / <model>) ... done|failed")
            node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
              --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "impl" \
              --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
              --duration-ms 0 --fallback-reason "" --impl-model-tag "secondary" 2>/dev/null || true
            if primary_result.success:
                proceed to QA (§7)
            else:
                # Primary also failed — existing escalation path runs unchanged (AC6)
                ESCALATE via existing daemon behavior (backlog status update + notes)
                # Note: no retry, no tier-based strategy, no circuit-breaker (AC3, AC18, AC19)

elif impl_model == "primary" OR impl_model is absent:
    # Task tool on primary — byte-for-byte identical to pre-Epic delivery
    node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
      --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "impl" \
      --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
      --duration-ms 0 --fallback-reason "" --impl-model-tag "${impl_model_tag:-absent}" 2>/dev/null || true
    route → Task tool on primary
```

The routing helper is implemented in `.gaai/core/adapters/claude-code/impl-routing.js` (`resolveImplRouting(implModelTag)`) — testable without invoking a real subprocess.

**Compliance:** no specific provider names appear in this workflow file. Only generic terms: "secondary provider", "nested subprocess", "user-configured endpoint" (AC13).

Spawn `implementation.sub-agent.md` with Implementation context bundle.

For Tier 3: Implementation Sub-Agent spawns Specialists per registry triggers.

Collect `{id}.impl-report.md`.

Invoke `coordinate-handoffs` → validate artefact → PROCEED or RE-SPAWN or ESCALATE.

**After PROCEED — atomic commit:**
```bash
git -C "$WORKTREE_PATH" add .
git -C "$WORKTREE_PATH" commit -m "feat({id}): {Story title summary}

Implements: {AC list e.g. AC1–AC9}
Story: contexts/artefacts/stories/{id}.story.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### 7. Execute — Tier 2/3: QA Phase

> **Provider:** Task tool on primary (regardless of `impl_model`). *QA validates against the Plan's contract; consistency stays on primary per Epic E94 D-2.*

Spawn `qa.sub-agent.md` with QA context bundle.

Collect `{id}.qa-report.md`.

Invoke `coordinate-handoffs`:
- PASS → proceed to step 8
- FAIL → re-spawn Implementation Sub-Agent with qa-report, then re-spawn QA Sub-Agent (max 3 cycles — see `qa.sub-agent.md`)
- ESCALATE → stop, surface to human

**After PASS — log QA phase and print consistency-check summary:**
```bash
node .gaai/core/adapters/claude-code/runtime-routing-logger.js \
  --trace-id "$STORY_TRACE_ID" --story-id "{id}" --phase "qa" \
  --provider "primary" --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
  --duration-ms 0 --fallback-reason "" --impl-model-tag "${impl_model_tag:-absent}" 2>/dev/null || true
echo "✓ Plan adherence check: passed"
```

### 7b. Commit Delivery Artefacts to Story Branch

After QA PASS, commit all delivery artefacts (execution-plan, impl-report, qa-report, memory-delta) to the story branch in the worktree. This ensures artefacts flow to staging via the PR merge — never pushed directly to staging.

```bash
# Step 7b: Commit delivery artefacts to story branch (in worktree)
git -C "$WORKTREE_PATH" add .gaai/project/contexts/artefacts/
git -C "$WORKTREE_PATH" commit -m "docs({id}): delivery artefacts — plan, impl-report, qa-report, memory-delta"
```

### 7c. Diff-Scope Sanity Check (MANDATORY)

**Before pushing, verify the diff is consistent with the Story scope.** This is a safety heuristic to catch corrupted trees, accidental `git add .` on wrong directories, or GIT_DIR contamination from hooks. It is NOT a hard limit on story size.

```bash
# Count files changed vs staging baseline
DIFF_STAT=$(git -C "$WORKTREE_PATH" diff --stat staging..HEAD)
CHANGED_FILES=$(git -C "$WORKTREE_PATH" diff --name-only staging..HEAD)
CHANGED_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
DELETED_COUNT=$(git -C "$WORKTREE_PATH" diff --diff-filter=D --name-only staging..HEAD | wc -l)

echo "Diff-scope check: $CHANGED_COUNT files changed, $DELETED_COUNT deleted"

NON_GAAI_DELETIONS=$(git -C "$WORKTREE_PATH" diff --diff-filter=D --name-only staging..HEAD \
  | grep -vcE '^\.gaai/' || true)
```

#### Hard escalation triggers (always STOP — no reviewer)

These are mechanical signals of tree corruption. No judgment needed.

```bash
# Non-.gaai file deletions → possible tree corruption
if [ "$NON_GAAI_DELETIONS" -gt 0 ]; then
  echo "ESCALATE: $NON_GAAI_DELETIONS non-.gaai deletions — possible tree corruption"
  echo "$DIFF_STAT"
  # Push story branch to preserve work before stopping
  git -C "$WORKTREE_PATH" push origin "story/{id}" 2>/dev/null || true
  exit 1  # Do NOT merge. ESCALATE to human.
fi
```

#### Soft threshold (> 30 files) — sub-agent reviewer decides

When the diff exceeds 30 files, the Delivery Agent MUST NOT decide alone whether to proceed. Instead, **spawn a sub-agent reviewer** to evaluate whether the diff is consistent with the Story scope. The Delivery Agent is the generator — it cannot be the sole evaluator of its own output (base.rules.md Rule 5).

```
Reviewer input:
  - Story title + Acceptance Criteria (from the story artefact)
  - CHANGED_FILES list (full paths, one per line)
  - CHANGED_COUNT

Reviewer task:
  "This delivery changed {CHANGED_COUNT} files (exceeds the 30-file soft threshold).
   Determine whether ALL changed files are traceable to the Story's scope.

   Story: {title}
   ACs: {acceptance criteria}

   Changed files:
   {CHANGED_FILES}

   Answer with a structured verdict:
   - PROCEED: every file is within the Story's domain — the count is high but
     explainable (e.g., test-rewrite story touching many test files).
   - ESCALATE: one or more files are outside the Story's expected scope, OR the
     changes span unrelated modules, OR you cannot confidently trace all files
     to the ACs.

   Be conservative: when in doubt, ESCALATE."
```

**Decision flow:**

```
CHANGED_COUNT > 30
  → spawn sub-agent reviewer (isolated context, no conversation history)
    → reviewer says PROCEED → continue to Step 8 (push + PR + merge)
    → reviewer says ESCALATE → push story branch to preserve work, then exit 1
```

**Important:** The reviewer runs in an **isolated context window** — it receives only the Story ACs and the file list, NOT the Delivery Agent's self-assessment or conversation history. This prevents confirmation bias (base.rules.md Rule 5).

If the reviewer is unavailable (sub-agent spawn fails), treat as ESCALATE — fail safe.

### 8. Create PR & Complete Story

**8a. Push story branch and create PR to staging:**

```bash
# Push story branch to origin
git -C "$WORKTREE_PATH" push origin story/{id}

# Create PR targeting staging
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

# CI Watch — invoke ci-watch-and-fix skill
# Returns: CI PASS | CI PASS (advisory) | CI FAIL
# CI PASS (advisory) = CI failed but no branch protection → merge anyway
# CI FAIL = branch protection active AND CI cannot pass → ESCALATE
ci_result = invoke ci-watch-and-fix(pr_number, story_id, story_branch, repo, worktree_path, log_dir)

if ci_result == CI FAIL:
    # Branch protection prevents merge — escalate to human
    exit 1  # on_exit trap marks story failed

# CI PASS or CI PASS (advisory) — proceed to merge
gh pr merge --squash --delete-branch
```

> **CI advisory mode:** When no branch protection exists on the target branch, CI failures caused by infrastructure issues (billing, quotas) do not block merge. The `ci-watch-and-fix` skill checks branch protection status before deciding whether to block or proceed. See `ci-watch-and-fix/SKILL.md` Step 0.
>
> **Staging self-merge: PERMITTED** after diff-sanity check passes (zero non-.gaai deletions; if > 30 files, sub-agent reviewer must verdict PROCEED — see §7c). If the check fails → ESCALATE, do NOT merge.
>
> **Production/main merge: FORBIDDEN.** The AI MUST NEVER run `gh pr merge` targeting `main` or `production`. The human reviews and merges to production. This is a non-negotiable safety boundary.

**8b. Delivery artefacts:** Delivery artefacts are committed to the story branch before PR creation (step 7b) and merge to staging via the PR. No separate staging push needed.

**8c. Mark Story done + cleanup worktree:**

```bash
# Remove worktree (but keep story branch — needed for the PR)
git worktree remove "$WORKTREE_PATH"

# Update backlog (push with retry-rebase pattern)
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

Flag any new patterns worth persisting as a memory-delta artefact (`memory-deltas/{id}.memory-delta.md`) for Discovery to review and ingest in the next session. Delivery does not invoke `memory-ingest` directly — see `orchestration.rules.md` §Memory Ingestion.

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

## Sub-Agent Lifecycle (Invariant)

Every sub-agent follows: `SPAWN (with context bundle) → EXECUTE (autonomous) → HANDOFF (artefact to known path) → DIE (context released)`. The Orchestrator only acts after a sub-agent has terminated and its artefact has been collected.

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
