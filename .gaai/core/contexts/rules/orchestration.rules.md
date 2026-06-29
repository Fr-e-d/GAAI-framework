---
type: rules
category: orchestration
id: RULES-ORCHESTRATION-001
tags:
  - orchestration
  - agents
  - memory
  - backlog
  - governance
created_at: 2026-02-09
updated_at: 2026-03-22
---

# 🧭 GAAI Orchestration Rules

This document defines **who triggers what, when, and under which conditions**
inside the GAAI agent system.

It is the **single source of truth** for orchestration behavior.

## 🎯 Purpose

The orchestration rules ensure that:
- agents have **clear and non-overlapping responsibilities**
- no action is implicit or magical
- long-term behavior remains predictable
- memory, backlog, and delivery stay governed

## 🧠 Core Principle

**Agents decide.**
**Skills execute.**
**Cron enforces hygiene.**

## 👥 Agent Responsibilities

### Discovery Agent

Discovery is the **only human-facing agent**.

Discovery is responsible for:
- interpreting human intent
- determining task complexity (quick fix vs new story)
- creating and validating backlog entries
- deciding what knowledge becomes long-term memory

Discovery **may trigger**:
- backlog creation / update
- `memory-ingest.skill.md`
- `memory-retrieve.skill.md`

Discovery **must NOT**:
- implement code
- execute tests
- directly modify artefacts
- auto-load memory without selection

### Delivery Agent

Delivery is a **pure execution agent**.

Delivery is responsible for:
- consuming ready backlog items
- analyzing technical feasibility
- implementing code
- generating and running tests
- iterating until acceptance criteria PASS

Delivery **may trigger**:
- code changes
- test execution
- artefact generation
- status updates in backlog

Delivery **must NOT**:
- interact directly with humans
- create or modify long-term memory
- ingest decisions into memory
- bypass backlog rules

### Context Isolation (Non-Negotiable)

Discovery and Delivery must **never coexist in the same context window**. The Delivery Agent always runs as an isolated `claude -p` process launched by the daemon (via tmux or Terminal.app) — a completely separate OS process with its own context containing only its agent definition, the workflow, rules, and the story context bundle. This prevents cross-contamination between human-facing reasoning (Discovery) and pure execution (Delivery).

**Runtime dependency, not a tool restriction:** `claude -p` is the execution runtime for autonomous delivery (Tier 3 of the 3-tier compatibility model). The user's choice of AI coding tool for Discovery — Claude Code, Cursor, Windsurf, or any MCP client — is independent. The daemon requires the Claude Code CLI (`claude` binary in PATH, local) as a hard dependency. Discovery and Delivery interactive (tiers 1–2) work with any tool. This requirement applies to both GAAI OSS and GAAI Cloud.

Sub-agents spawned by Delivery (Planning, Implementation, QA, Specialists) each run in their own isolated context with a targeted context bundle. See `agents/delivery.agent.md` for team composition and bundle definitions.

## 🗂️ Backlog Orchestration

→ Backlog state lifecycle, transition rules, and archiving rules are defined in `base.rules.md` (loaded at session startup, applies universally).

### Backlog & Staging Write Coordination — Discovery ↔ Daemon (Claim Protocol)

**Principle:** an interactive Discovery session and the Delivery Daemon both write the backlog and the `staging` branch. The daemon continuously `git reset --hard origin/staging` on its working tree, so **`origin/staging` is the only durable state** — any local edit that is not committed *and pushed* can be clobbered by a concurrent daemon reset/commit. Discovery MUST therefore claim writes under the **same staging lock the daemon uses**, never edit the live shared tree opportunistically.

**The claim protocol (Discovery — every backlog/staging mutation):**

1. **Hold the daemon's staging lock for the whole write-burst.** Wrap the burst in `scripts/gaai-claim.sh -- <command…>`, which acquires the identical lock primitive as the daemon's `with_staging_lock` (flock on Linux, atomic `mkdir` on macOS). While held, the daemon waits — no clobber, no push race.
2. **Backlog mutations go through `scripts/backlog-scheduler.sh` only** (`--set-status` / `--set-field` / `--set-phase-status`). These are atomic, daemon-format-compatible, and **field-scoped** so a concurrent daemon status-write on a different field/entry rebases cleanly. **Raw whole-file rewrites of `active.backlog.yaml` (python/sed/`yaml.dump`/manual) are forbidden** — they cause clobbers and merge conflicts.
3. **The burst commits AND pushes to `staging` inside the lock.** Once on `origin/staging` the daemon's reset preserves it. A commit that is not pushed is not durable.
4. **Run on the primary working tree** (its installed dependencies let the pre-push hooks pass) — a throwaway worktree is the fallback only when the primary tree is unavailable, and it must still push to `origin/staging`.

**Never trust the local working tree as state** — it is ephemeral under the daemon. To read true state, read `origin/staging` (`git show origin/staging:<path>`), not the working copy.

**Why:** prior sessions edited the live shared tree with raw file/git operations while the daemon ran; the daemon's reset/`add -A`/clean cycles wiped untracked artefacts and reverted backlog promotions, producing repeated rework. The claim protocol makes Discovery a coordinated writer on the daemon's existing lock instead of an uncoordinated one.

### Independent Review Gate (Mandatory)

**Principle:** Discovery must never be the sole evaluator of its own outputs. Every Discovery output must be independently reviewed by the Review Sub-Agent (SUB-AGENT-REVIEW-001) before reaching the human (for proposals/recommendations) or the backlog (for stories/epics).

**Why:** Generator/evaluator separation is a foundational LLM quality pattern. The generating agent has confirmation bias — it wrote the output believing it was correct. An independent agent with fresh context and an adversarial prompt is more likely to detect contradictions, drift, weak reasoning, and governance violations. Self-assessment is preparation, not verification.

#### Tier Selection

The Review Sub-Agent operates in two tiers. Discovery selects the tier based on the output's content:

| Tier | Trigger | Checks |
|---|---|---|
| **Tier 1 — Sanity** | Every output without exception | DEC constraints, DoR coverage, skill attestation, scope creep |
| **Tier 2 — Adversarial** | Output contains D- (decisions), T- (trade-offs), scope changes, approach evaluations, or batch story generation (2+) | All Tier 1 checks + Brief quality + substance challenge + story alignment |

**Trigger rule:** If Discovery made a choice between alternatives, Tier 2 applies. The presence of consequential decisions — not complexity score — is the trigger.

#### Refined Status Gate

A story may only be registered in the backlog as `status: refined` if ALL of the following gates have passed in the current session:

1. **Format gate** — `validate-artefacts` (SKILL-VALIDATE-ARTEFACTS-001) returned PASS for the story
2. **Independent Review gate** — Review Sub-Agent (SUB-AGENT-REVIEW-001) returned PASS at the applicable tier

If either gate has not been executed, the story MUST be registered as `status: draft` — not `refined`. Only after both gates pass may the Discovery Agent update the status to `refined`.

**Evidence:** The commit message for stories registered as `refined` must include the gate verdicts (e.g., "validate-artefacts: PASS, review[tier-2]: PASS"). Absence of this evidence in a commit that sets `status: refined` is a detectable governance violation.

#### Proposal & Recommendation Gate (Pre-Artefact AND Artefact Phases)

Discovery recommendations must pass the Review Sub-Agent at the applicable tier BEFORE being presented to the human. **This applies at every phase of Discovery — including conversational recommendations made before any artefact exists.**

**Why pre-artefact recommendations matter most:** The most impactful decisions happen early — "use Stripe", "target solo devs", "architecture = event-driven". These shape everything downstream. If a pre-artefact recommendation is biased, all artefacts built on it inherit the bias — and no artefact-level gate can catch a flawed premise. The earlier the review, the higher the leverage.

**Scope — what triggers this gate:**
- Any recommendation that implies a **choice between viable alternatives** (architecture, library, pattern, target audience, pricing model, service provider)
- Any recommendation that **constrains future decisions** (technology lock-in, scope boundary, priority ordering)
- Any output containing **D-** (decisions) or **T-** (trade-offs) — whether in a Session Brief, an artefact, or a conversational recommendation

**What does NOT trigger this gate:**
- Factual answers to diagnostic questions ("what does this function do?")
- Status reports with no recommendation
- Obvious choices with no viable alternative (governed by `base.rules.md` § Recommendation Validation proportionality clause)

**Pre-artefact context bundle:** When no Session Brief or artefact exists yet, the Review Sub-Agent receives:
- The recommendation itself (Discovery's proposed direction)
- Referenced DECs (if any)
- Relevant memory entries (if Discovery loaded any via `memory-retrieve`)
- The human's stated intent or question (paraphrased by Discovery — NOT the raw conversation)

Discovery's Critical Self-Assessment remains as a preparatory step (it helps Discovery catch obvious issues before invoking the reviewer), but the Review Sub-Agent verdict is the authoritative evaluation.

- Review Sub-Agent PASS → Discovery may present to human
- Review Sub-Agent FAIL → Discovery must refine, then re-submit to reviewer
- Review Sub-Agent ESCALATE → Discovery surfaces the escalation to the human alongside the proposal

**Refinement loop limit (applies to all Discovery review gates):** Maximum **2 review cycles** per output. If the output still FAILs after 2 rounds of refinement, ALL remaining findings are escalated to the human — regardless of whether Discovery believes it can self-fix. This limit is absolute and applies to proposals, recommendations, Session Briefs, and stories equally. See `review.sub-agent.md` § Refinement Loop for the detailed flow.

**Rationale:** Infinite refinement loops waste tokens and indicate a deeper problem (ambiguous constraints, conflicting DECs, or genuine knowledge gap). Two rounds is enough for honest errors; anything beyond signals a structural issue that requires human judgment. Aligned with Constitutional AI research: quality peaks at 2-3 critique-revision rounds then yields diminishing returns (Anthropic, 2022).

#### Session Brief Gate

The Discovery Session Brief must pass Review Sub-Agent Tier 2 BEFORE being presented to the human for validation. Discovery's Brief Self-Assessment remains as draft preparation, but the independent review is the quality gate. Same 2-cycle refinement limit applies.

**Why the Brief matters most:** The Brief is the root of the quality chain. If the Brief is weak, stories will be weak — even if they pass format and alignment checks. An independent reviewer catching Brief issues BEFORE human validation saves the human from reviewing a flawed Brief and prevents downstream waste.

**Rationale (2026-03-30):** Prior to this rule, Discovery self-evaluated all outputs except story alignment. The Critical Self-Assessment Protocol and Brief Self-Assessment were executed by the same agent instance that produced the output — the textbook confirmation bias anti-pattern. `review-story-alignment` proved the isolated reviewer model works (it has caught real issues). This rule extends that model to all Discovery outputs.

**Supersedes (2026-03-28):** The previous Refined Status Gate rule required `review-story-alignment` (SKILL-RSA-001) as a standalone gate. That skill's 3-pass process is now executed by the Review Sub-Agent during Tier 2 review. The enforcement is stronger (all outputs reviewed, not just stories) and the architecture is cleaner (one reviewer, tiered depth).

## 🌿 Branch Rules

All AI-driven execution targets the **`staging`** branch. The `production` branch is human-only.

**INVARIANT: The main working tree stays on `staging` at ALL times.** Deliveries operate in isolated worktrees (`git worktree add`). The main working tree is never checked out to another branch — the daemon and other processes depend on it remaining on staging.

- AI agents MUST NOT push to, merge to, or interact with `production`
- Delivery creates story branches from staging: `git branch story/{id} staging` (no checkout — main stays on staging)
- All implementation happens in worktrees: `git worktree add "$WORKTREE_PATH" story/{id}` (absolute path resolved once at Step 0 — see `delivery-loop.workflow.md`)
- Sub-agents work exclusively inside their worktree — never in the main repo directory
- Squash merges back to staging are serialized via `flock`
- Promotion staging → production is a human action via GitHub PR
- Before creating a story branch, verify that the **previous story's PR is merged** into staging.
  If a prior story's PR is open (not yet merged), the Delivery Agent must wait before starting the next story.
  This prevents chained branch conflicts and ensures each story builds on a clean staging base.

> **Concurrent mode note:** This sequential constraint applies in `--max-concurrent 1` mode (default). In concurrent delivery (`--max-concurrent > 1`), each session manages its own branch independently from staging HEAD; conflicts are resolved at PR merge time via the retry-with-rebase pattern (see delivery-loop.workflow.md §Staging Push Retry Pattern).
- After creating a PR, immediately enable GitHub auto-merge: `gh pr merge --auto --squash story/{id}`.
  This ensures PRs merge automatically when CI passes, without human intervention.

A pre-push hook (`.githooks/pre-push`) enforces this rule at the git level.

### Worktree lifecycle & cleanup

Scope: **worktree-isolated delivery of code/content** — daemon-spawned story delivery and any manual session making an isolated change in a worktree. The merge path here is the same one the `production`-prohibition and auto-merge clauses above already govern; this subsection does not re-assert them, it adds the lifecycle clauses those clauses omit. The mechanism (idempotent creation, throttled reaping, retries, locks) lives in the daemon scripts; the procedure lives in `delivery-loop.workflow.md §Commit Phase`. This section is the normative authority both implement.

- **Governed merge path.** Worktree-originated code/content reaches `staging` only via `gh pr create --base staging --head story/{id}` then squash merge (auto-merge per the clause above). **Exempt:** Discovery's backlog/governance mutations push directly to `origin/staging` under the daemon staging lock per §Claim Protocol — that path has no story PR and is unaffected by this clause.
- **Post-merge cleanup.** After a story's PR merges, its remote branch (`gh pr merge --delete-branch`) and its worktree are removed; the daemon also drops the local branch ref. No worktree may persist past its story's terminal state.
- **Orphan reaping is eventually-consistent.** A worktree whose story PR is MERGED/CLOSED, or whose HEAD is an ancestor of `origin/staging`, is an orphan and MUST be reaped. Reaping is periodic/convergent, **not** synchronous — "no orphan subsists" is a convergence guarantee, not an instantaneous one. Do not assert or rely on synchronous orphan removal.
- **Data-safety refusal (INVARIANT).** A dirty or still-active worktree is NEVER force-removed. The reaper refuses removal and defers it (skip-and-retry next cycle); committed work is never lost because removal frees only the working dir, never a branch ref. Data safety dominates cleanup.

---

## 🎯 Capability Readiness

Before execution begins, the system must verify that agents have both the **skills** and **knowledge** required for the mission. Readiness is split across two agents, matching their existing responsibilities.

### Knowledge Readiness (Discovery — before `refined`)

Before marking a Story as `refined` in a domain where no relevant knowledge exists in memory, Discovery must:

1. Invoke `memory-retrieve` for the target domain
2. Assess whether returned entries cover current best practices and industry standards for the domain
3. If no entries exist, or existing entries are stale (last updated >30 days ago for fast-moving domains, >90 days for stable domains):
   - For **narrow decision points** (2-3 competing approaches): run `approach-evaluation`
   - For **broad domain knowledge gaps**: research best practices and persist findings via `memory-ingest`
   - Run `memory-ingest` to persist validated findings
4. Only after knowledge gaps are remediated may the Story be marked `refined`

This rule applies to **domains not yet covered** in `contexts/memory/`. For well-covered domains with recent memory entries, Discovery may proceed directly — no overhead on routine work.

### Recommendation Validation (All Agents)

→ Defined in `base.rules.md` (loaded at session startup). Applies in both structured flows and conversational mode.

**Discovery does NOT need to verify skill coverage** — it defines *what* to build, not *how* to build it. Skill coverage is Delivery's responsibility.

### Skill Coverage (Delivery — during `evaluate-story`)

During `evaluate-story`, the Delivery Orchestrator must verify that all skills required for the identified domains exist in `skills-index.yaml`.

If a required skill is absent:
- The Story is marked `blocked` with an explicit gap report (which skill is missing, for which domain)
- The gap is escalated to Discovery, which creates a Story for the missing skill via `create-skill`
- The original Story resumes only when the dependency is delivered and the skill exists in the index

If required knowledge is absent (detected during evaluation, not caught by Discovery):
- Same escalation pattern: `blocked` + gap report → Discovery remediates

---

## ⏰ Cron / Automation Responsibilities

Cron jobs and the **Delivery Daemon** are **allowed and encouraged**, but limited to governance tasks.

### Delivery Daemon (`scripts/delivery-daemon.sh`)

The daemon automates backlog polling and AI agent session launch:
- Polls staging for `refined` stories at a configurable interval
- Marks stories `in_progress` on staging before launch (cross-device coordination)
- Launches the AI coding agent in isolated worktrees
- Monitors session health (heartbeat, `--max-turns` limit)
- Marks stories `failed` on non-zero exit (human must review and reset to `refined`)

The daemon is a **governance automation** — it does not reason, implement, or make decisions.

### Other Cron Jobs

Cron MAY trigger:
- backlog polling (check for `refined` items)
- `memory-refresh.skill`
- `memory-compact.skill`

Cron MUST NOT:
- create new stories
- ingest new project knowledge
- modify decisions
- inject memory into agents

## 🧠 Memory Orchestration Rules

→ Memory retrieval discipline and ingestion authority are defined in `base.rules.md` Core Governance Rule #3 (loaded at session startup, applies universally).

### Memory Maintenance (flow-specific)

- `memory-refresh.skill` is maintenance-only
- `memory-compact.skill` is compression-only
- Both may be triggered by cron or Discovery
- Neither may create new project knowledge

### Memory Ingestion and Delta Triage

**Authority split (draft vs validate):**

a. `memory-ingest` remains Discovery-only. No agent other than Discovery (human-initiated
   or autonomous) may invoke `memory-ingest`. This rule is not modified by E62.

b. `memory-delta-triage` in `draft` mode writes no memory. It produces a Triage Verdict
   block and stops. The draft mode verdict is for Discovery's review — it does not
   authorize or trigger any memory write.

c. `memory-delta-triage` in `validate` mode instructs Discovery to invoke `memory-ingest`
   for ACCEPTED candidates. The skill issues an explicit instruction per candidate;
   Discovery (the human-facing agent) executes the `memory-ingest` invocations.
   Validate mode requires human-initiated Discovery — never autonomous.

d. The only skill permitted in autonomous Discovery draft mode is `memory-delta-triage`.
   Autonomous Discovery may not invoke `memory-ingest`, `memory-refresh`, `memory-compact`,
   or any skill outside the scope whitelist `[memory-delta-triage]`.

**Daemon-spawn-Discovery pattern:**

The Delivery Daemon is authorized to spawn an isolated Discovery agent process in
`memory-delta-triage` draft mode after a successful QA PASS delivery. This is the sole
authorized cross-agent-identity spawn pattern — the only case in which the Delivery
Daemon may launch a Discovery agent. All other Discovery activation is human-initiated.
(Delivery daemon may spawn one autonomous subprocess per QA PASS for memory-delta-triage in draft mode.)

The spawned Discovery context is bounded: it contains only the `memory-delta-triage`
skill file, the target delta file, and the base governance rules. No other context
is provided and no other skill may be invoked within this spawn.

**Forbidden (in addition to base.rules.md and flow-specific forbidden patterns above):**
- Autonomous Discovery invoking `memory-ingest` (permitted only in human-initiated validate mode)
- Autonomous Discovery loading skills outside `[memory-delta-triage]`
- The Delivery Daemon spawning Discovery for any purpose other than `memory-delta-triage` draft mode

## 🔁 Canonical Execution Flows

→ See `workflows/delivery-loop.workflow.md` (delivery) and `workflows/discovery-to-delivery.workflow.md` (end-to-end).

## ⚠️ Conflict & Escalation Protocol

→ Base protocol defined in `base.rules.md` (loaded at session startup).

**Flow-specific addition:** When ambiguity is in a backlog item or acceptance criteria, Delivery must escalate to Discovery. Delivery must not begin on ambiguous criteria.

## 🚫 Forbidden Patterns

→ Universal forbidden patterns and default deny are defined in `base.rules.md` (loaded at session startup).

**Flow-specific additions** (on top of base forbidden patterns):
- Delivery ingesting memory (exception: `decision-extraction` post-QA-PASS)
- Cron creating knowledge or modifying decisions
- Direct human → Delivery interaction (Delivery is never human-facing)
