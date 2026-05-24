---
name: memory-ingest
description: Transform validated knowledge into structured long-term memory. Activate after Bootstrap scan, after Discovery produces validated artefacts, or after architecture insights are available.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-MEMORY-INGEST-001
  updated_at: 2026-04-05
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

**CRITICAL — Anti-Collision Guard (MUST execute before writing any memory file):**
Before writing any file under `contexts/memory/**`, check if the target file already exists on disk:
- If it does NOT exist → proceed normally.
- If it DOES exist → **read the existing file first**. Then decide:
  - If the existing content covers a **different topic or entity** than what you are about to write → **STOP immediately**, surface the collision to the human, do not proceed.
  - If the existing content covers the **same topic** and an update is warranted → proceed, but preserve any human edits or prior knowledge that remains valid. Treat this as an **update**, not a replacement.
  - If the existing content is identical or still valid → skip writing, report "no changes needed".
This guard prevents the silent data loss incident of 2026-03-17 where concurrent sessions overwrote memory files.

1. Read new validated knowledge (discovery results, decisions, architecture insights, validated hypotheses, GTM decisions)
2. Read `contexts/memory/index.md` to discover available categories (shared and domain). Classify knowledge into the most appropriate existing category. If no existing category fits, create a new one — name it clearly, create the directory, and register it in `index.md` before writing any file.
3. Create or update corresponding memory files using standard templates
4. Register all new or modified entries in `contexts/memory/index.md` — this is mandatory, not optional. Any file not in the index is invisible to all other memory skills.
5. **Domain dual-index rule:** When ingesting into a domain category (`domains/{domain}/`), also update the domain's own `index.md` (e.g., `domains/content-production/index.md`). Both the master index AND the domain index must reflect the new entry. Failure to update both causes silent drift — the domain sub-agent won't see entries missing from its domain index.
<!-- Impact Scan added to surface drift risk after ingest. Addresses the gap where ingested
     content can silently invalidate assumptions in related memory files. Provides informational
     ripple-effect visibility for OSS Discovery Agent (Cloud enforcement not required). -->
6. **Impact Scan (post-write) (informational — does not block ingestion).** After writing new memory
   files and updating all indexes (steps 3–5):
   - Re-read `contexts/memory/index.md` and collect all entries whose `tags` overlap with the tags
     of the ingested content.
   - For each matching entry, check whether the ingested content changes or invalidates assumptions
     described in that file (load the file, compare topic overlap).
   - List any potentially stale entries in the session output: entry path, reason suspected stale.
   - **If `index.md` is missing or a referenced file is unreadable:** skip the Impact Scan and note
     `"Impact Scan skipped: {reason}"` in session output — do not fail the ingestion.
6b. **Architecture file gate (applies ONLY to writes under `contexts/memory/architecture/`).**
   Before writing or updating any file in that folder:
   - Read `contexts/rules/memory-architecture.rules.md` in full
   - Apply the **Content Principle** (§1) — if the content is a code snapshot rather than a conceptual invariant, STOP and reclassify (either rewrite at the invariant level or discard — do not weaken the rule)
   - Apply the **Verify-Before-Update Protocol** (§2) — load each path in `depends_on.code_paths`, confirm every claim in the content still matches current code; on divergence, escalate (never silent-rewrite)
   - Populate the attestation fields in frontmatter: `verified_against_commit_sha: <40-char sha>` and `verified_at: <ISO 8601 timestamp>`
   - Writing an architecture file without running this gate, or writing content copied from a memory-delta without independent code verification, is forbidden
7. **Freshness metadata governance (Tier 1–2 files)** After writing any memory file under `architecture/`, `patterns/conventions.md`, or `project/context.md`, verify that both `depends_on` and `refresh_tier` are present in the file's YAML frontmatter before proceeding.
   - If both are present → continue.
   - If either is absent → **add them before this step completes**. Do not exit the skill without freshness metadata on a Tier 1–2 file.
   - If the code paths are unknown, use the safe fallback:
     ```yaml
     depends_on:
       code_paths: []
       decisions: []
       epics: []
     refresh_tier: 2
     ```
     Then add a session note: `"[FRESHNESS TODO] {file_path}: depends_on.code_paths not populated — manual enrichment required."`
   - **All other memory files** (outside the three paths above): `depends_on` is optional. If present, validate that `refresh_tier` is also declared and is a value 1–4. If `refresh_tier` is absent but `depends_on` is present, default to `refresh_tier: 2` and note for review.
   - Rule reference: `contexts/rules/memory-freshness.rules.md` §3 (which files must declare) and §4 (graceful degradation).
8. Ensure memory files remain structured and minimal

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
