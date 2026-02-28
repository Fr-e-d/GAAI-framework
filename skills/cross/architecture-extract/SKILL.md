---
name: architecture-extract
description: Convert raw project structure into clear architectural understanding — module boundaries, data flows, service relationships, and architectural patterns. Activate after codebase-scan during Bootstrap.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-ARCHITECTURE-EXTRACT-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - codebase_tree
  - key_files_list
outputs:
  - architecture_insights
---

# Architecture Extract

## Purpose / When to Activate

Activate:
- After `codebase-scan` during Bootstrap initialization
- When architectural understanding is needed before memory ingestion

---

## Process

1. Analyze module boundaries and layering
2. Identify data flow and service interactions
3. Detect architectural patterns (monolith, services, event-driven, etc.)
4. Produce a concise architecture summary

---

## Outputs

**`architecture_insights`** — concise summary including:
- System structure overview
- Module boundaries and responsibilities
- Key data flows
- Architectural pattern identified
- Major dependencies
- Notable constraints or risks

---

## Quality Checks

- System structure is understandable in one view
- Major dependencies are explicit
- Architecture style is clearly identified
- Output is suitable for ingestion via `memory-ingest`

---

## Non-Goals

This skill must NOT:
- Make architectural recommendations
- Propose changes
- Read deeply into implementation details

**Converts terrain map into architectural understanding. Feeds directly into memory-ingest.**
