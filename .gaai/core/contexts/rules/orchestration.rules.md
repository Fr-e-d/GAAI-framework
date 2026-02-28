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
updated_at: 2026-02-28
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

## 🗂️ Backlog Orchestration

### Backlog States

Backlog items MUST follow this lifecycle:

```
draft → refined → in_progress → done | failed
```

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

- AI agents MUST NOT push to, merge to, or interact with `production`
- Delivery creates story branches from staging: `git branch story/{id} staging` (no checkout)
- All implementation happens in worktrees (`git worktree add`)
- Squash merges back to staging are serialized via `flock`
- Promotion staging → production is a human action via GitHub PR
- Before creating a story branch, verify that the **previous story's PR is merged** into staging.
  If a prior story's PR is open (not yet merged), the Delivery Agent must wait before starting the next story.
  This prevents chained branch conflicts and ensures each story builds on a clean staging base.
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
   - For **broad domain knowledge gaps** (best practices, standards, patterns across a domain): run `domain-knowledge-research`
   - Run `memory-ingest` to persist validated findings from either skill's report
4. Only after knowledge gaps are remediated may the Story be marked `refined`

This rule applies to **domains not yet covered** in `contexts/memory/`. For well-covered domains with recent memory entries, Discovery may proceed directly — no overhead on routine work.

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

The daemon automates backlog polling and Claude Code session launch:
- Polls staging for `refined` stories at a configurable interval
- Marks stories `in_progress` on staging before launch (cross-device coordination)
- Launches Claude Code in isolated worktrees (tmux on VPS, Terminal.app on macOS)
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

### Memory Maintenance

- `memory-refresh.skill` is maintenance-only
- `memory-compact.skill` is compression-only
- Both may be triggered by cron or Discovery
- Neither may create new project knowledge

## 🔁 Canonical Execution Flows

### Human → Feature Flow

```
Human
→ Discovery
→ memory-retrieve (selective)
→ story creation → validation → backlog.refined
→ Delivery → implement → test → PASS → done
```

### Human → Quick Fix Flow

```
Human
→ Discovery → classify as quick fix
→ minimal backlog entry
→ Delivery → implement → test → PASS → done
```

### Memory Hygiene Flow

```
Cron / Discovery
→ memory-refresh
→ memory-compact (if thresholds exceeded)
→ index update
```

## ⚠️ Conflict & Escalation Protocol

When an agent encounters a conflict between a human instruction and an existing rule:
- Stop immediately. Do not attempt to resolve it silently.
- Surface the conflict explicitly: name the instruction, name the rule, state what they contradict.
- Wait for human resolution. Do not proceed until the conflict is resolved.

When an agent encounters ambiguity in a backlog item or acceptance criteria:
- Stop. Do not interpret intent.
- Escalate to Discovery for clarification.
- Delivery must not begin on ambiguous criteria.

**If in doubt: stop and ask. Always.**

## 🔒 Decision Consistency Gate (Mandatory)

Before recording ANY new decision (DEC-*), the authoring agent MUST:

1. **Retrieve:** Invoke `memory-retrieve` for all existing decisions touching the same domain/topic (search by keywords, tags, and related DEC references)
2. **List:** Explicitly enumerate which existing decisions are relevant and what they state
3. **Verify:** Confirm that the new decision does not contradict any existing decision
4. **Supersede or stop:**
   - If no contradiction → proceed with recording
   - If contradiction detected AND the new decision should replace the old → the new DEC MUST explicitly state "Supersedes DEC-XX" with rationale for the change
   - If contradiction detected AND the agent cannot determine which is correct → stop and ask the human
5. **Never record silently:** A decision recorded without this verification is **invalid by governance**

This gate applies to:
- Discovery Agent (primary decision-maker)
- Delivery Agent (via `decision-extraction` after story completion)
- Bootstrap Agent (during decision formalization from codebase analysis)

---

## 🚫 Forbidden Patterns

The following are explicitly forbidden:
- agents auto-loading full memory
- skills accessing memory implicitly
- Delivery ingesting memory
- Cron creating knowledge
- bypassing backlog states
- direct human → Delivery interaction

## 🧠 Final Rule

**If a behavior is not explicitly allowed here, it is forbidden.**

This document governs **all agent orchestration decisions** in the GAAI system.
