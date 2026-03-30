---
type: rules
category: base
id: RULES-BASE-001
tags:
  - universal
  - conversational
  - governance
created_at: 2026-03-15
updated_at: 2026-03-23
---

# GAAI Base Rules (Universal)

These rules apply **at all times** — in structured GAAI flows AND in conversational mode.
They are loaded at session startup via the tool adapter.

For flow-specific rules (agent responsibilities, context isolation, branch rules, cron, capability readiness), see `orchestration.rules.md`.

---

## Core Governance Rules

1. **Backlog-first.** Every execution unit must be in the backlog. No work without a backlog entry.
2. **Skill-first.** Every agent action must reference a skill. Read the skill file before invoking it. **Never produce artefacts or execute processes from cached knowledge** — the skill file is the single source of truth for process steps, not just output format. Format familiarity does not substitute for reading. Every artefact must declare `skills_invoked` in its frontmatter to attest which skill files were read. An artefact without `skills_invoked` fails validation.
3. **Memory is the source.** GAAI memory (`contexts/memory/`) is the authoritative source for project context, decisions, and patterns. Load relevant memory before any planning or artefact production. Never rely on internal/cached knowledge about the project — read the files. Memory retrieval discipline:
   - Retrieval MUST start from `contexts/memory/index.md` — this is the authoritative registry
   - Retrieval MUST be selective (by category / tags) — never auto-load entire folders
   - Only the Discovery Agent (or Bootstrap Agent during initialization) may trigger `memory-ingest`
   - Delivery may only write memory via `decision-extraction` after QA PASS (governed exception)
4. **Artefacts document — they do not authorize.** Only the backlog authorizes execution.
5. **Independent evaluation.** An agent must never be the sole evaluator of its own consequential outputs. Every consequential output — recommendations, proposals, Session Briefs, stories, epics — must be independently evaluated by a separate agent instance before reaching the human or the backlog. Self-assessment (Critical Self-Assessment, Brief Self-Assessment) is retained as draft preparation but is never the authoritative quality gate.
   - **Minimum:** Spawn a sub-agent in an isolated context window with an adversarial prompt. The reviewer must NOT receive the conversation history (prevents confirmation bias) or the generator's self-assessment (prevents anchoring).
   - **Better:** Use model diversity — route evaluation to a different model than the generator. Self-preference bias is perplexity-driven (in the model weights, not the context), so same-model isolation reduces but does not eliminate bias.
   - **Proportionality:** Mechanical checks (format validation, collision guards) do not require independent evaluation. The trigger is the presence of **consequential choices** — decisions between alternatives (D-), trade-offs (T-), scope changes, or recommendations that constrain future decisions.
   - **Implementation:** The Review Sub-Agent (SUB-AGENT-REVIEW-001) enforces this principle. See `agents/sub-agents/review.sub-agent.md` for the tiered architecture (Tier 1: governance sanity, Tier 2: adversarial substance review) and `orchestration.rules.md` § Independent Review Gate for the mandatory gates.

   **Why this is a core principle (research foundation):**
   - Self-preference bias is quantified and perplexity-driven — LLMs systematically prefer outputs familiar to their own distribution, regardless of quality (Wataoka et al., arXiv:2410.21819, 2024)
   - Generator/evaluator separation is foundational to Constitutional AI (Anthropic, 2022), LLM-as-Judge (Zheng et al., NeurIPS 2023), and Chain-of-Verification (Meta, ACL 2024)
   - 12 distinct evaluation biases are documented, many amplified when judge = generator (CALM framework, Li et al., NeurIPS 2024)
   - Multi-agent debate with heterogeneous agents consistently outperforms self-evaluation (Du et al., ICML 2024; DMAD, ICLR 2025)
   - Cascaded evaluation (light first, adversarial when needed) reduces cost by 40% without quality loss (Trust or Escalate, ICLR 2025 Oral)

6. **Artefacts are never overwritten blindly.** Before writing any artefact file (story, epic, decision), check if the file already exists on disk. If it exists and belongs to a different entity (different epic, different intent), **STOP and escalate** — this is an ID collision. Never silently overwrite an existing artefact. This rule is absolute and applies even in conversational mode.

---

## Language Rule

Agents address the human in the human's language. All artefacts, backlog entries, commit messages, and governance files are written in English regardless of conversation language.

---

## Recommendation Validation

When any agent proposes a recommendation that implies a **choice between viable alternatives** (architecture, library, pattern, service), the agent must validate against industry standards and best practices BEFORE presenting the recommendation. If the recommendation diverges from an established standard, this must be signaled explicitly with justification.

This rule does NOT apply to: obvious choices with no viable alternative, bug fixes, minor refactoring, or conventions already established in `patterns/conventions.md`. Proportionality governs — do not slow down routine work with unnecessary research.

---

## Backlog State Lifecycle

Backlog items MUST follow this lifecycle:

```
draft → refined → in_progress → done | failed
```

Auxiliary states: `deferred`, `blocked`, `cancelled`, `superseded`, `escalated`.

- `draft` — Story created but not yet validated or acceptance-criteria complete
- `refined` — Story is validated, acceptance criteria are present and unambiguous, ready for Delivery
- `in_progress` — Delivery is actively executing the Story
- `done` — Story passed QA
- `failed` — Story failed and cannot be retried without human intervention
- `deferred` — Story is intentionally held back by a business gate (phase gate, data threshold, go-live prerequisite) — not a technical dependency

### Transition Rules

- Only Discovery may move items from `draft` to `refined`
- Only Discovery may set `deferred` status (business decision, not technical)
- Delivery may only consume items in `refined` or `in_progress`
- Delivery must update status to `in_progress` when execution begins, then `done` on PASS
- Failed executions must be marked `failed` with artefact notes
- No agent may skip states (e.g., `draft` directly to `in_progress` is forbidden)

---

## Backlog Archiving Rules

A `done` item may only be archived (moved from `active.backlog.yaml` to `done/`) if **no non-done item depends on it** — directly or transitively. Before archiving:

1. Collect all `dependencies` from every item in the active backlog (regardless of status)
2. Resolve transitively: if a dep itself has deps, include those too
3. Any `done` item found in this transitive set **must stay in the active backlog** with its original `dependencies` intact (traceability)
4. After archiving, verify: every `dependencies` entry across the entire active backlog must resolve to an item present in the active backlog. **Zero broken refs allowed.**

Dependencies on `done` items are historical (execution order) but must be preserved for traceability — never cleared or stripped.

---

## Conflict & Escalation Protocol

When an agent encounters a conflict between a human instruction and an existing rule:
- Stop immediately. Do not attempt to resolve it silently.
- Surface the conflict explicitly: name the instruction, name the rule, state what they contradict.
- Wait for human resolution. Do not proceed until the conflict is resolved.

When an agent encounters ambiguity in a request or acceptance criteria:
- Stop. Do not interpret intent.
- Escalate for clarification.

**If in doubt: stop and ask. Always.**

---

## Forbidden Patterns (Universal)

The following are explicitly forbidden in all contexts — structured flows and conversational mode:

- Auto-loading full memory (folders, entire categories)
- Skills accessing memory implicitly (without explicit `memory-retrieve` call)
- Bypassing backlog states (skipping lifecycle transitions)
- Producing artefacts without reading the governing skill file first
- Silently overwriting existing artefacts without checking for ID collisions

For additional flow-specific forbidden patterns (Delivery memory ingestion, direct human→Delivery interaction), see `orchestration.rules.md` § Forbidden Patterns.

---

## Default Deny

**If a behavior is not explicitly allowed by these rules or by `orchestration.rules.md`, it is forbidden.**
