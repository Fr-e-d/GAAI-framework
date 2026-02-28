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
  updated_at: 2026-02-26
  status: stable
inputs:
  - discovery_outputs  (validated)
  - architecture_insights
  - validated_decisions
  - project_knowledge
  - marketing_observation_logs  (validated hypotheses, promise drafts — from contexts/artefacts/marketing/**)
  - strategy_artefacts  (validated GTM decisions — from contexts/artefacts/strategy/**)
outputs:
  - contexts/memory/**  (any category registered in index.md)
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
2. Read `contexts/memory/index.md` to discover available categories (shared and domain). Classify knowledge into the most appropriate existing category. If no existing category fits, create a new one — name it clearly, create the directory, and register it in `index.md` before writing any file.
3. Create or update corresponding memory files using standard templates
4. Register all new or modified entries in `contexts/memory/index.md` — this is mandatory, not optional. Any file not in the index is invisible to all other memory skills.
5. **Domain dual-index rule:** When ingesting into a domain category (`domains/{domain}/`), also update the domain's own `index.md` (e.g., `domains/content-production/index.md`). Both the master index AND the domain index must reflect the new entry. Failure to update both causes silent drift — the domain sub-agent won't see entries missing from its domain index.
6. Ensure memory files remain structured and minimal

---

## Outputs

Memory files created at any registered category path (see `contexts/memory/index.md`). Current categories as of last update:
- `contexts/memory/project/` — project-level facts, architecture, constraints
- `contexts/memory/decisions/` — governance decisions
- `contexts/memory/patterns/` — coding conventions, procedural knowledge
- `contexts/memory/ops/` — platform operations, DNS, providers, infra procedures
- `contexts/memory/contacts/` — experts and leads identified during Discovery
- `contexts/memory/domains/content-production/` — domain-scoped: research AKUs, sources, voice guide, gap analysis for content blueprint
- `contexts/memory/index.md` — updated (always, mandatory)
- Domain `index.md` — updated when ingesting into a domain (mandatory, see Process step 5)

> **Governance rule:** Any new category must be registered in `index.md` before use. Never write a memory file to an unregistered path.

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
