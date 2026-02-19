---
name: memory-ingest
description: Transform validated knowledge into structured long-term memory. Activate after Bootstrap scan, after Discovery produces validated artefacts, or after architecture insights are available.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-INGEST-001
  updated_at: 2026-01-27
inputs:
  - discovery_outputs  (validated)
  - architecture_insights
  - validated_decisions
  - project_knowledge
  - marketing_observation_logs  (validated hypotheses, promise drafts — from contexts/artefacts/marketing/**)
  - strategy_artefacts  (validated GTM decisions — from contexts/artefacts/strategy/**)
outputs:
  - contexts/memory/project/**
  - contexts/memory/decisions/**
  - contexts/memory/patterns/**
  - contexts/memory/index.md  (updated)
---

# Memory Ingest

## Purpose / When to Activate

Activate after:
- Bootstrap scan produces architecture insights
- Discovery produces validated artefacts or decisions
- New validated project knowledge needs to be persisted

**Only ingest validated knowledge — never raw session output.**

---

## Process

1. Read new validated knowledge (discovery results, decisions, architecture insights, validated hypotheses, GTM decisions)
2. Classify knowledge by memory category: project / decisions / summaries
3. Create or update corresponding memory files using standard templates
4. Register all new entries in memory index
5. Ensure memory files remain structured and minimal

---

## Output

Memory files created at:
- `contexts/memory/project/` — project-level facts, architecture, constraints
- `contexts/memory/decisions/` — governance decisions
- `contexts/memory/patterns/` — coding conventions, procedural knowledge
- `contexts/memory/index.md` — updated index

---

## Quality Checks

- Knowledge is stored in correct memory category
- Memory files remain structured and minimal
- Index reflects all active memory
- No duplication or raw session data
- Only validated knowledge enters long-term memory

---

## Non-Goals

This skill must NOT:
- Store raw session conversations
- Ingest speculative or unvalidated information
- Duplicate existing memory entries

**No knowledge enters memory without explicit validation. Raw exploration belongs to session memory only.**
