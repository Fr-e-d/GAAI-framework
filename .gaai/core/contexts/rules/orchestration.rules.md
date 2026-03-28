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

Discovery and Delivery must **never coexist in the same context window**. The Delivery Agent always runs as an isolated sub-agent with a clean context — only its own agent definition, the workflow, rules, and the story context bundle. This prevents cross-contamination between human-facing reasoning (Discovery) and pure execution (Delivery).

Sub-agents spawned by Delivery (Planning, Implementation, QA, Specialists) each run in their own isolated context with a targeted context bundle. See `agents/delivery.agent.md` for team composition and bundle definitions.

## 🗂️ Backlog Orchestration

→ Backlog state lifecycle, transition rules, and archiving rules are defined in `base.rules.md` (loaded at session startup, applies universally).

### Refined Status Gate (Mandatory)

A story may only be registered in the backlog as `status: refined` if BOTH of the following gates have passed in the current session:

1. **Format gate** — `validate-artefacts` (SKILL-VALIDATE-ARTEFACTS-001) returned PASS for the story
2. **Alignment gate** — `review-story-alignment` (SKILL-RSA-001) returned PASS for the story (when a Discovery Session Brief exists)

If either gate has not been executed, the story MUST be registered as `status: draft` — not `refined`. Only after both gates pass may the Discovery Agent update the status to `refined`.

**Evidence:** The commit message for stories registered as `refined` should include the gate verdicts (e.g., "validate-artefacts: PASS, review-story-alignment: PASS"). Absence of this evidence in a commit that sets `status: refined` is a detectable governance violation.

**Rationale (2026-03-28):** 14 Phase 3 stories were registered as `refined` without either gate executing. Root cause: gates were defined in `discovery.agent.md` but not enforced in the skill process or transition rules. This rule closes the enforcement gap at the rule level.

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
