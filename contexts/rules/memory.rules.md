---
type: rules
category: memory
id: RULES-MEMORY-001
tags:
  - memory
  - governance
  - long_term_context
  - determinism
  - agent_control
created_at: 2026-02-09
updated_at: 2026-03-01
---

# 🧠 GAAI Memory Rules

This document defines the **mandatory rules governing memory**
inside the GAAI (Governed Agentic AI Infrastructure) system.

Memory provides **long-term, distilled knowledge**.
It is **never a log, never a transcript, and never implicit**.

Any behavior violating these rules is **invalid by design**.

## 🧠 Core Principles

**Memory is distilled knowledge — not history.**
**Memory is agent-selected — never auto-loaded.**

## 👥 Memory Authority Model

### R1 — Agents Own Memory

Only **agents** may:
- retrieve memory
- ingest memory
- decide what becomes memory
- decide what is summarized or archived

Skills MUST NEVER:
- load memory
- ingest memory
- modify memory
- infer memory relevance

## 🔍 Memory Retrieval Rules

### R2 — Selective Retrieval Only

Agents MUST:
- start from `contexts/memory/index.md`
- retrieve memory by category and/or tags
- retrieve the minimal necessary set

Agents MUST NOT:
- load entire memory folders
- retrieve memory opportunistically
- bypass the memory index

### R3 — Explicit Invocation Required

Memory retrieval MUST occur only via `memory-retrieve` or `memory-search` skills.
- `memory-search` — locates relevant memory files (returns paths, IDs, excerpts)
- `memory-retrieve` — loads the actual file content into context

Memory MUST NEVER:
- be auto-loaded
- be implicitly injected
- leak into skill context

## 🧾 Memory Ingestion Rules

### R4 — Validated Knowledge Only

Only **validated, high-signal knowledge** may be ingested.

Memory ingestion MUST NOT include:
- raw chat transcripts
- speculative ideas
- intermediate reasoning
- execution noise

Ingestion MUST occur only via `memory-ingest.skill`.

### R5 — Discovery Is the Gatekeeper

Only the **Discovery Agent** may:
- approve memory ingestion
- promote session knowledge to long-term memory
- ingest decisions or summaries

Delivery MUST NOT ingest memory.

## 🗂️ Memory Categories (Mandatory)

Memory MUST be classified into one of:
- `project` — product vision & scope
- `decisions` — validated choices
- `summaries` — compacted long-term knowledge
- `sessions` — temporary exploration
- `archive` — historical storage

## ⏳ Memory Lifecycle Rules

### R6 — Session Memory Is Temporary

All files under `contexts/memory/sessions/` MUST:
- be summarized within 24–48 hours
- then archived or deleted

Session memory MUST NEVER be treated as durable knowledge.

### R7 — Compaction Is Category-Aware

Memory categories have different durability:

**Durable memory** (decisions, patterns, project, ops, contacts, domains):
- Entries MUST NEVER be archived based on file size alone
- Only entries with an explicit supersession marker (R7b) may be archived
- Oversized files → domain-split (e.g., `decisions/_log.md` → `decisions/{domain}.decisions.md`)
- Summaries are INDEX-ONLY — they list entries for quick scanning but MUST NOT substitute for full text

**Ephemeral memory** (sessions):
- Standard 24–48h compaction applies (R6)
- Summaries replace originals after compaction
- Originals archived

### R7b — Supersession Is the Only Archive Gate for Durable Memory

Machine-readable markers determine archivability:
- `> SUPERSEDED by DEC-XX` — replaced by a newer decision
- `> RETRACTED` — withdrawn, no replacement
- `> OBSOLETE — {reason}` — no longer applicable

Rules:
- No marker → ACTIVE → MUST NOT be archived
- Marker present → may be moved to `archive/` during compaction
- Oversized durable files → domain-split, never archive active entries

### R7c — Contexts Lifecycle Guards

**Backlog:**
- Done items removed from `active.backlog.yaml` only when: (1) done ≥30 days, AND (2) no non-done item depends on it
- Items with active dependents MUST remain visible regardless of age

**Artefacts:**
- Story and epic artefacts are permanent (reference material for future agents)
- Strategy artefacts archive only when explicitly superseded by a newer version

**Rules:**
- Core rules (`core/contexts/rules/`) are never archived

## 🔁 Memory Maintenance

### R8 — Maintenance Is Non-Creative

`memory-refresh.skill` and `memory-compact.skill` are **maintenance-only**.

They MAY: summarize, prune, archive, update indexes.
They MUST NOT: create new knowledge, introduce decisions, reinterpret meaning.

## 🚫 Forbidden Memory Behaviors (Hard Fail)

The following are **explicitly forbidden**:
- auto-loading memory
- loading full memory sets
- skills accessing memory
- storing raw chat logs
- duplicating backlog state
- using memory to trigger execution
- implicit memory injection

## 🧠 Final Rule

**If memory influences behavior without an explicit agent decision,**
**the system is out of compliance.**

Memory exists to **support reasoning across time** — never to replace it.
