---
type: workflow
id: WORKFLOW-DELIVERY-LOOP-001
track: delivery
updated_at: 2026-04-29
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
REPO_NAME="$(basename "$REPO_ROOT")"
WORKTREE_PATH="${GAAI_WORKTREE_BASE:-${REPO_ROOT}/../.gaai-worktrees/${REPO_NAME}}/${id}-workspace"
mkdir -p "$(dirname "$WORKTREE_PATH")"

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

Default worktree location is `<parent-of-repo>/.gaai-worktrees/<repo-name>/<story-id>-workspace` — this groups all GAAI worktrees under a single dedicated folder at the parent level, avoiding pollution of the parent directory when multiple projects share it. The `.gaai-worktrees/` name avoids collision with the in-project `.gaai/` folder. Override by setting `GAAI_WORKTREE_BASE` (e.g., `export GAAI_WORKTREE_BASE=/tmp/gaai-worktrees` for cloud-synced repos).

### 1. Select Next Story

**Do NOT `Read` the full backlog file** — it routinely exceeds Claude's 25k-token single-Read limit and will error out mid-delivery. Use the scheduler script to pick the next ready story:

```bash
STORY_ID=$(.gaai/core/scripts/backlog-scheduler.sh --next .gaai/project/contexts/backlog/active.backlog.yaml)
```

The scheduler returns the highest-priority Story with `status: refined` and all dependencies satisfied. If a specific Story was requested by the user (e.g. `/gaai-deliver E19S01`), use `--ready-ids` to verify it's schedulable, or inspect a single entry with `grep -A 20 "^- id: $STORY_ID$" .gaai/project/contexts/backlog/active.backlog.yaml` — never load the whole file.

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

After the Implementation phase call returns, `STORY_TRACE_ID` **must** be overwritten with `result.trace_id` (see §6a). `runImpl()` always returns a `trace_id` — whether the delivery ran on primary or secondary. The same `STORY_TRACE_ID` is then passed to the QA phase observability hook (E94S06 defines the call; reserved here).

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

The routing decision is evaluated inside `runImpl()` — a deterministic pure function (`resolveMode()`) within `nested-claude-spawn.js`. The workflow invokes the module via its CLI; **no routing logic lives here**.

> **Rationale and deeper context:** see `contexts/memory/architecture/impl-phase-spawn-pattern.md` for the operational summary (why always-subprocess, the mode resolution table, the forbidden anti-pattern). For the formal decision record, see DEC-86 (amends DEC-72).

> **🔒 MANDATORY — NON-NEGOTIABLE :** the Implementation phase MUST be executed by invoking the CLI block below. Do **NOT** spawn `implementation.sub-agent.md` via the Task tool. Do **NOT** perform implementation work inline in the orchestrator session via Read/Edit/Write/Bash. The CLI is the **only** path. Skipping it produces a delivery that bypasses routing, audit logging, and the universal fallback — exactly the failure mode E131 was created to eliminate.
>
> The CLI invocation is **mandatory regardless of impl_model tag value** : even when the resolved mode is primary, the spawn happens through this CLI (the module routes primary internally for architectural consistency).

**Invoke the module (this is the only impl spawn — no Task tool sub-agent for impl) :**

> **Secondary-routing context discipline preamble :** when `impl_model_tag == secondary`, prepend the context-discipline preamble below to `IMPL_PROMPT`. Mitigates Claude Code `rapid_refill_breaker` (autocompact thrashing) observed empirically at 43% fail rate on secondary providers (e.g., GLM 5.1). Skip when routing primary — Sonnet already follows these implicitly.

```bash
# When secondary-routed, prepend context discipline preamble (rapid_refill_breaker mitigation).
# Source : observed 5/6 GLM 5.1 fails ($1.97-6.11 each) terminated with rapid_refill_breaker
# in nested-fail-debug.jsonl 2026-04-30 ; 3 behaviors lacking : (1) re-Read post-compact,
# (2) no self-summarization, (3) full-file Read defaults instead of offset/limit.
if [ "$impl_model_tag" = "secondary" ]; then
  IMPL_PROMPT="$(cat <<PREAMBLE
=== CONTEXT DISCIPLINE (MANDATORY for this delivery) ===

You operate in a long-running agentic session with a 200K context window
and aggressive autocompaction. Failure to follow these rules causes session
termination via rapid_refill_breaker (Claude Code internal safety) — observed
empirically at 43% fail rate on this routing path.

These rules are derived from Anthropic's "Effective Context Engineering for
AI Agents" guidance. They apply throughout this session.

## R1 — Persistent NOTES.md (MOST IMPORTANT)

Maintain a file at \${WORKTREE_PATH}/.gaai/project/contexts/artefacts/notes/{id}.notes.md
as your durable working memory. This file survives autocompaction (it lives on
disk, outside the context window). After any compact, your **first action MUST
be to Read that file** to recover state.

The file is committed alongside other delivery artefacts at QA PASS — do NOT
delete it at end of session.

### NOTES.md template — MANDATORY first-write structure

When you create the file at the start of the session, write EXACTLY this template
including the rules header (it bootstraps your discipline on every re-read post-compact):

\`\`\`markdown
# Working memory — {id}

## ⚠ Context discipline rules (re-read every time you open this file)
1. Files in "Files read" below are CANONICAL. NEVER re-read them.
   Reference the summary; if you need more detail, Read with offset/limit
   targeting only the new range you need.
2. After every Read / Bash / Glob / Grep result, append a 1-line entry below
   in the appropriate section.
3. Read files in chunks ≤200 lines (offset/limit). Use Glob/Grep before Read.
4. Bash with verbose output: pipe through head/tail (e.g., \\\`pnpm test 2>&1 | tail -100\\\`).
5. If your context feels gappy or unfamiliar, you were just compacted —
   Read this file + the execution-plan.md FIRST before any new action.
6. Update "Current step" continuously. Update AC status as you progress.
7. Append-only for "Files read" and "Decisions made" — never delete prior entries.

## Current step
<one sentence — what you are doing right now>

## Files read (canonical — DO NOT re-read)
<append entries: path : 1-line summary of content + line ranges examined>

## Decisions made
<append: decision + brief rationale>

## Acceptance criteria status
- AC1: <pending|in_progress|done|blocked>
- AC2: ...

## Open questions / blockers
<append if any; clear when resolved>

## Tool-call audit
<optional: short trail of recent tool calls to detect drift loops>
\`\`\`

Update the file after every meaningful tool result. Write durable structured
facts, not narration.

## R2 — Never re-read

Never re-read a file already in your NOTES.md "Files read" section. NOTES.md
is the source of truth for what you've seen. If you suspect autocompaction
just occurred (gap in context), Read NOTES.md and execution-plan.md FIRST
before any other action.

## R3 — Self-summarize after every tool result

After each Read / Bash / Glob / Grep, write ONE structured sentence
summarizing the key fact learned, then continue. Example:
"auth.ts exports validateSession(token), uses HMAC-SHA256 over headers
(lines 23-67). Now editing membership.ts to add workspace_id field."

## R4 — Just-in-time chunked retrieval (don't load upfront)

- Read files in chunks ≤200 lines using offset/limit. Use Glob/Grep
  first to locate exact line ranges. Never Read a file >300 lines
  without offset/limit.
- For Bash with verbose output (tests, builds, logs), always pipe
  through head/tail: \`pnpm test 2>&1 | tail -100\`
- Prefer file paths and grep patterns over loading full content.

## R5 — Single-feature focus

Per Anthropic's harness guidance: work on one acceptance criterion at a
time, commit when complete, then advance. Do not parallelize ACs across
multiple files in flight — context bloat is fatal here.

## Few-shot example — one good cycle

User: "Implement AC2: validateSession() in middleware"

You (turn 1):
\`\`\`
[Glob "**/auth*.ts"]
\`\`\`
Result: \`workers/api/src/auth.ts, workers/api/src/auth.test.ts\`

You (turn 2): "Glob found 2 auth files. Reading auth.ts targeted to find validateSession."
\`\`\`
[Read workers/api/src/auth.ts offset=1 limit=80]
\`\`\`

You (turn 3): "auth.ts exports validateSession(token) at L23-67, HMAC-SHA256 over headers.
Updating NOTES.md."
\`\`\`
[Edit \${WORKTREE_PATH}/.gaai/project/contexts/artefacts/notes/{id}.notes.md
 — append to "Files read": "auth.ts: validateSession(token) L23-67, HMAC-SHA256 over headers"
 — set "Current step": "Wiring validateSession into membership middleware"
 — set "AC2": "in_progress"]
\`\`\`

You (turn 4): proceed with the actual edit on membership.ts. Do NOT re-Read auth.ts.

=== END CONTEXT DISCIPLINE ===

PREAMBLE
)\$IMPL_PROMPT"
fi

IMPL_PROMPT_FILE="$(mktemp -t gaai-impl-prompt.XXXXXX)"
printf '%s' "$IMPL_PROMPT" > "$IMPL_PROMPT_FILE"
result_json=$(node .gaai/core/adapters/claude-code/nested-claude-spawn.js \
  --prompt-file "$IMPL_PROMPT_FILE" \
  --report-path "$IMPL_REPORT_PATH" \
  --story-id "{id}" \
  [--impl-model-tag primary|secondary|absent] \
  [--log-file "$GAAI_DELIVERY_LOG_FILE"])
rm -f "$IMPL_PROMPT_FILE"
```

The CLI exits 0 in all business-logic outcomes (success, fallback, env-missing). Distinguish via `result.success`.

**After the call — mandatory STORY_TRACE_ID overwrite:**

```bash
result_trace_id=$(echo "$result_json" | jq -r '.trace_id')
STORY_TRACE_ID="$result_trace_id"
```

`runImpl()` always returns a `trace_id`. Overwriting `STORY_TRACE_ID` here is **unconditional** — it applies whether the delivery ran on primary or secondary.

**Observability:** `runImpl()` emits exactly one `phase: impl` record to `runtime-routing.jsonl` on success; two records when secondary fails and primary fallback is invoked (one per attempt, shared `trace_id`). The operator will see one `phase: impl` entry per resolved delivery attempt in `runtime-routing.jsonl`.

**Non-null `result.error_reason` field:** When the module returns a successful result but with a non-null `error_reason` field (e.g., `secondary_but_env_missing`), the agent emits a one-line warning to stdout before proceeding:

```bash
result_error_reason=$(echo "$result_json" | jq -r '.error_reason // empty')
if [ -n "$result_error_reason" ]; then
  echo "⚠ impl routing: $result_error_reason"
fi
```

This matches the `warn() + echo` behaviour of the previous in-workflow matrix.

**When `result.success` is false:** the module has already exhausted its internal fallback chain (per E131S02 AC3 — no in-workflow fallback chain exists here). Escalate via the existing daemon behaviour:

```bash
result_success=$(echo "$result_json" | jq -r '.success')
if [ "$result_success" != "true" ]; then
  # Escalate: update backlog status + notes; do not mark done
  ESCALATE via existing daemon behaviour
fi
```

**Compliance:** no specific provider names appear in this workflow file. Only generic terms: "secondary provider", "nested subprocess", "user-configured endpoint".

**Implementation context bundle :** the `IMPL_PROMPT` written to `IMPL_PROMPT_FILE` is the bundle. It contains the same content the legacy `implementation.sub-agent.md` Task spawn used to receive — story context, AC list, plan output, codebase pointers. The CLI passes the file content as the spawned `claude -p` prompt ; the spawned subprocess reads it and performs the implementation work end-to-end inside its own session.

**Tier 3 specialists :** the spawned subprocess invokes Specialists via Task tool from inside its own session per `agents/specialists.registry.yaml`. The orchestrator does **not** spawn Specialists directly ; specialist coordination lives inside the impl subprocess so it shares the impl model + isolated context.

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

#### Diff-consistency check — sub-agent reviewer decides

Two diff signals trigger the consistency check:
- `NON_GAAI_DELETIONS > 0` — any non-`.gaai/` file deleted (possible tree corruption OR legitimate story-scoped removal).
- `CHANGED_COUNT > 30` — diff exceeds the soft threshold (possible scope drift OR legitimate wide-touch story like test rewrites).

In both cases, the Delivery Agent MUST NOT decide alone whether to proceed. **Spawn a sub-agent reviewer** to evaluate whether the diff is consistent with the Story scope. The Delivery Agent is the generator — it cannot be the sole evaluator of its own output (base.rules.md Rule 5).

```
Reviewer input:
  - Story title + Acceptance Criteria (from the story artefact)
  - CHANGED_FILES list (full paths, one per line)
  - DELETED_FILES list (non-.gaai deletions specifically, if any)
  - CHANGED_COUNT, NON_GAAI_DELETIONS

Reviewer task:
  "This delivery triggered a diff-consistency check ({CHANGED_COUNT} files changed,
   {NON_GAAI_DELETIONS} non-.gaai deletions). Determine whether ALL changed and
   deleted files are traceable to the Story's scope.

   Story: {title}
   ACs: {acceptance criteria}

   Changed files:
   {CHANGED_FILES}

   Non-.gaai deletions (if any):
   {DELETED_FILES}

   Answer with a structured verdict:
   - PROCEED: every file is within the Story's domain — the count is high or
     the deletion is explainable (e.g., test-rewrite story, refactor removing
     a generated/dead file declared in an AC).
   - ESCALATE: one or more files are outside the Story's expected scope, OR
     the changes span unrelated modules, OR a deletion has no trace to any AC,
     OR you cannot confidently trace all files to the ACs.

   Be conservative: when in doubt, ESCALATE."
```

**Decision flow:**

```
NON_GAAI_DELETIONS > 0  OR  CHANGED_COUNT > 30
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
> **Staging self-merge: PERMITTED** after diff-sanity check passes (if any non-.gaai deletion OR > 30 files, sub-agent reviewer must verdict PROCEED — see §7c). If the check fails → ESCALATE, do NOT merge.
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
