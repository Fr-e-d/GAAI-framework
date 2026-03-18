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
updated_at: 2026-02-26
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

### Backlog States

Backlog items MUST follow this lifecycle:

```
draft → refined → in_progress → done | failed
```

Auxiliary states: `blocked`, `cancelled`, `superseded` — see `backlog.rules.md` §Backlog Lifecycle for definitions and transition rules.

- `draft` — Story created but not yet validated or acceptance-criteria complete
- `refined` — Story is validated, acceptance criteria are present and unambiguous, ready for Delivery to consume
- `in_progress` — Delivery is actively executing the Story
- `done` — Story passed QA; moved to `done/` archive
- `failed` — Story failed and cannot be retried without human intervention

### Rules

- Only Discovery may move items from `draft` to `refined`
- Delivery may only consume items in `refined`
- Delivery must update status to `in_progress` when execution begins, then `done` on PASS
- Failed executions must be marked `failed` with artefact notes

## 🌿 Branch Rules

All AI-driven execution targets the **`staging`** branch. The `production` branch is human-only.

**INVARIANT: The main working tree stays on `staging` at ALL times.** Deliveries operate in isolated worktrees (`git worktree add`). The main working tree is never checked out to another branch — the daemon and other processes depend on it remaining on staging.

- AI agents MUST NOT push to, merge to, or interact with `production`
- Delivery creates story branches from staging: `git branch story/{id} staging` (no checkout — main stays on staging)
- All implementation happens in worktrees: `git worktree add ../{id}-workspace story/{id}`
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

### Memory Retrieval

- Memory is NEVER auto-loaded
- Agents MUST explicitly call `memory-retrieve.skill`
- Retrieval MUST start from `contexts/memory/index.md`
- Retrieval MUST be selective (by category / tags)

### Memory Ingestion

- Only Discovery may trigger `memory-ingest.skill`
- Only validated knowledge may be ingested
- Raw chat transcripts are forbidden

**Governed exception — `decision-extraction`:** Delivery may invoke `decision-extraction` after QA PASS to scan for durable architectural or governance decisions. This is the sole Delivery-permitted memory write, governed by the skill's deduplication gate and consistency checks. All other memory ingestion (project knowledge, patterns, domain memory) remains Discovery-only.

### Memory Maintenance

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

The following are explicitly forbidden:
- agents auto-loading full memory
- skills accessing memory implicitly
- Delivery ingesting memory (exception: `decision-extraction` post-QA-PASS — see §Memory Ingestion)
- Cron creating knowledge
- bypassing backlog states
- direct human → Delivery interaction

## 🧠 Final Rule

**If a behavior is not explicitly allowed here, it is forbidden.**

This document governs **all agent orchestration decisions** in the GAAI system.
