---
name: approach-evaluation
description: Research industry standards and best practices, identify viable approaches for a given technical or architectural problem, and produce a structured factual comparison against project-specific constraints. Reports options — does not decide.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-APPROACH-EVALUATION-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - problem_statement                      (what needs to be solved)
  - contexts/memory/index.md               (registry — resolve project context, patterns, decisions files)
  - contexts/memory/**                     (categories resolved from index.md — project, patterns, decisions)
  - contexts/artefacts/stories/**          (the Story driving the evaluation, if in Delivery)
outputs:
  - contexts/artefacts/evaluations/{id}.approach-evaluation.md
---

# Approach Evaluation

## Purpose / When to Activate

Activate when the invoking agent identifies a technical or architectural decision point where:
- Multiple viable implementation approaches exist and the best choice is non-obvious
- A technology, library, or service is being introduced for the first time in the project
- No established convention exists in `conventions.md` for the problem domain
- The problem touches a domain with well-known industry standards that should be considered
- A prior approach failed or showed limitations (post-mortem driven re-evaluation)

Do NOT activate when:
- A convention already exists in `conventions.md` for this exact problem
- The approach is explicitly defined in the Story or a prior decision
- The Story is Tier 1 / MicroDelivery with obvious implementation
- The evaluation would delay delivery without reducing meaningful uncertainty

**This skill researches and compares — it does not decide.** The invoking agent (Planning Sub-Agent or Discovery Agent) reads the output and makes the decision.

---

## Process

### Phase 1 — Problem Framing

1. State the problem precisely: what capability is needed, what constraints apply
2. Read `contexts/memory/index.md`. Resolve and load:
   - The `project` category file → extract tech stack, architectural boundaries, known constraints
   - The `patterns` category file → extract established patterns and conventions
   - The `decisions` category file → extract prior decisions on related topics
   Do not assume specific file paths — resolve from index.
3. Define evaluation criteria specific to this problem. Always include:
   - **Stack compatibility** — does it work with the project's tech stack? (read from project context file, not hardcoded here)
   - **Constraint alignment** — does it respect the architectural boundaries described in the project context?
   - **Operational fit** — maintainability given team size and constraints described in project context
   - **Maturity** — production readiness, community support, documentation quality
4. Add problem-specific criteria as needed (performance, cost, security, scalability, etc.)

### Phase 2 — Industry Research

5. Research current industry standards and best practices for the problem:
   - Use web search for current state-of-the-art and community consensus
   - Use Context7 or documentation tools for library/framework specifics
   - Check for established patterns in similar projects or architectures
6. Identify 2-3 viable approaches — not one, not ten
   - Each approach must be genuinely viable (not a strawman)
   - Include the "obvious" approach (what the LLM would default to) even if it may not be best
   - Include at least one alternative that challenges the default
7. For each approach, gather factual evidence:
   - How it works (brief mechanism description)
   - Where it is used successfully (real examples, not hypothetical)
   - Known limitations or failure modes
   - Compatibility with edge compute / serverless environments (if relevant)

### Phase 3 — Structured Comparison

8. Evaluate each approach against every criterion from Phase 1
9. Use factual evidence only — no "this feels better" reasoning
10. Flag any criterion where information is uncertain or unavailable
11. Note any approach that would require violating an existing convention or decision

### Phase 4 — Trade-off Surfacing

12. For each approach, state explicitly:
    - What you gain by choosing it
    - What you lose or accept as a trade-off
    - What it implies for future decisions (lock-in, reversibility)
13. If one approach is clearly dominated (worse on all criteria), note it but do not eliminate it — the agent decides

---

## Outputs

```markdown
# Approach Evaluation — {Story ID or Decision Context}: {Problem Title}

## Problem Statement

{What needs to be solved, in one paragraph}

## Evaluation Criteria

| # | Criterion | Weight | Source |
|---|-----------|--------|--------|
| C1 | {criterion} | must-have / important / nice-to-have | {project context reference} |
| C2 | {criterion} | must-have / important / nice-to-have | {project context reference} |

## Approaches Identified

### Approach A — {Name}

**Mechanism:** {how it works — 2-3 sentences}
**Evidence:** {where it's used, maturity signals}
**Limitations:** {known failure modes or constraints}

### Approach B — {Name}

**Mechanism:** {how it works — 2-3 sentences}
**Evidence:** {where it's used, maturity signals}
**Limitations:** {known failure modes or constraints}

### Approach C — {Name} (if applicable)

**Mechanism:** {how it works — 2-3 sentences}
**Evidence:** {where it's used, maturity signals}
**Limitations:** {known failure modes or constraints}

## Comparison Matrix

| Criterion | Approach A | Approach B | Approach C |
|-----------|-----------|-----------|-----------|
| C1: {name} | {factual assessment} | {factual assessment} | {factual assessment} |
| C2: {name} | {factual assessment} | {factual assessment} | {factual assessment} |

## Trade-offs

### Approach A
- **Gains:** {what you get}
- **Costs:** {what you accept}
- **Lock-in:** {reversibility assessment}

### Approach B
- **Gains:** {what you get}
- **Costs:** {what you accept}
- **Lock-in:** {reversibility assessment}

## Open Questions

- {Any criterion where evidence is uncertain or missing}
- {Any constraint that needs human clarification}

## Sources

- {URL or reference for each factual claim}
```

Saves to `contexts/artefacts/evaluations/{id}.approach-evaluation.md`.

---

## Quality Checks

- Every criterion has a clear source (project context, not invented)
- Every assessment in the comparison matrix is factual, not opinion
- No approach is dismissed without evidence
- No approach is favored without evidence
- Trade-offs are explicit and symmetric (gains AND costs for each)
- Sources are provided for industry claims
- The evaluation does not contain a recommendation or decision
- Uncertain information is flagged as uncertain, not presented as fact

---

## Non-Goals

This skill must NOT:
- Recommend or decide — the agent decides after reading the evaluation
- Invent criteria not grounded in project context
- Hallucinate library capabilities or industry practices — cite sources
- Evaluate more than 3 approaches (focus drives quality)
- Produce vague assessments ("this is generally good") — every claim must be specific and evidence-backed
- Skip the "obvious" approach — even if the default seems suboptimal, it must be evaluated fairly

**The best approach is the one that survives honest comparison — not the one that arrives first.**
