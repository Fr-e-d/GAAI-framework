---
name: approach-evaluation
description: Research industry standards and best practices, identify viable approaches for a given technical or architectural problem, and produce a structured factual comparison against project-specific constraints. Reports options — does not decide.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-APPROACH-EVALUATION-001
  updated_at: 2026-02-20
inputs:
  - problem_statement                      (what needs to be solved)
  - contexts/memory/project/context.md     (stack, constraints, architecture)
  - contexts/memory/patterns/conventions.md (established patterns to check against)
  - contexts/memory/decisions/_log.md      (prior decisions on similar topics)
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
2. Extract relevant constraints from project context:
   - Tech stack (from `project/context.md`)
   - Established patterns (from `conventions.md`)
   - Prior decisions on related topics (from `decisions/_log.md`)
   - Architectural boundaries (layer rules, async patterns, domain-agnostic requirement)
3. Define evaluation criteria specific to this problem. Always include:
   - **Stack compatibility** — does it work with our stack (CF Workers, Supabase, TypeScript, edge compute)?
   - **Constraint alignment** — does it respect our architectural boundaries?
   - **Operational fit** — solo founder maintainability, deployment complexity, debugging surface
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

## Output Format

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
