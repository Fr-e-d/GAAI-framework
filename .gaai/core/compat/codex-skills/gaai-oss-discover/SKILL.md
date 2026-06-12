---
name: gaai-oss:discover
description: Activate the GAAI OSS Discovery Agent to clarify intent and produce governed artefacts such as PRDs, Epics, Stories, and decisions.
---

# GAAI OSS Discovery

Use this skill when the user wants to define what to build, refine scope, create or update backlog items, write Discovery artefacts, evaluate a pivot, or answer product strategy questions.

## Procedure

1. Read `.gaai/core/GAAI.md`.
2. Read `.gaai/core/contexts/rules/base.rules.md`.
3. Read `.gaai/core/contexts/rules/orchestration.rules.md`.
4. Read `.gaai/core/agents/discovery.agent.md`.
5. Read `.gaai/project/contexts/memory/index.md` if present, then load only the memory files relevant to the stated intent.
6. Ask for missing intent only when it cannot be discovered locally and a reasonable assumption would be risky.
7. Produce or update governed artefacts through the Discovery workflow.
8. Validate artefacts before handing off to Delivery.

Respect the backlog as the execution authorization mechanism. Discovery can clarify and authorize work; Delivery implements validated Stories.
