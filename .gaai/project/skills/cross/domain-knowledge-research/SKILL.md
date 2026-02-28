---
name: domain-knowledge-research
description: Research current industry best practices and standards for a given domain, structure findings into GAAI-compatible Atomic Knowledge Units (AKUs) with evidence grading and anti-hallucination safeguards, and produce a classified knowledge report. Activate when Discovery identifies a knowledge gap during capability readiness assessment or before designing skills in an unfamiliar domain.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "2.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-023
  updated_at: 2026-02-26
  status: stable
  tags: [knowledge, research, best-practices, capability-readiness]
inputs:
  - domain: target domain to research (e.g. "SEO technique", "booking systems", "content repurposing")
  - research_scope: specific questions or sub-topics to cover (provided by the invoking agent)
  - depth: surface | standard | comprehensive
  - contexts/memory/index.md (to check existing knowledge coverage)
  - contexts/memory/** (relevant existing entries, loaded selectively via memory-retrieve beforehand)
  - skills/skills-index.yaml (to produce GAAI mappings for each AKU)
  - contexts/rules/** (to verify compatibility — especially orchestration.rules.md, README.skills.md principles)
outputs:
  - contexts/artefacts/research/{domain-slug}.knowledge-report.md
---

# Domain Knowledge Research

## Purpose / When to Activate

Activate when:
- The **Capability Readiness rule** (orchestration.rules.md) identifies a knowledge gap — no relevant entries in memory, or existing entries are stale
- Discovery is preparing to design skills in a domain where no knowledge base exists yet
- A prior `approach-evaluation` revealed that a broader domain investigation is needed (not just comparing 2-3 approaches)
- Existing memory entries for a domain are flagged as potentially outdated (>30 days for fast-moving domains, >90 days for stable domains)

Do NOT activate when:
- A narrow approach comparison is sufficient — use `approach-evaluation` instead
- The domain is already well-covered in memory with recent entries
- The research would delay delivery without reducing meaningful uncertainty

**This skill researches, structures, and filters — it does not decide what to persist or what skills to create.** The invoking agent reads the report and decides next actions.

---

## Epistemic Rules (Mandatory)

These rules apply to ALL phases of this skill. Violations produce unreliable knowledge.

1. **Never treat correlational thresholds as guarantees.** A correlation (even strong) is not causation.
2. **Never imply causality without evidence.** If the source does not establish a causal mechanism, classify as correlational or observational.
3. **Convert narrative claims into operational mechanisms.** Strip rhetoric, marketing language, and motivational tone. Preserve only quantified findings and documented patterns.
4. **Distinguish platform-specific from universal mechanisms.** A pattern observed on Google may not apply to Bing, ChatGPT, or Perplexity. Label scope explicitly.
5. **Preserve quantified findings verbatim.** Do not round, paraphrase, or editorialize data points. Cite the exact metric.
6. **Flag data sparsity.** If a finding is based on a single source, small sample, or limited geography, the confidence ceiling is `moderate` regardless of claim strength.

---

## Process

### Phase 1 — Scope & Existing Knowledge Check

1. Read the `domain`, `research_scope`, and `depth` inputs from the invoking agent
2. Read `contexts/memory/index.md`. Identify all existing entries related to the target domain
3. For each existing entry: note its date, coverage, and confidence level
4. Identify what is already covered vs what the research scope requires that is NOT covered
5. Focus research effort on **uncovered areas only** — do not re-research what already exists with high confidence

### Phase 2 — Source Collection

6. Research using available tools based on depth level:
   - `surface`: agent's existing knowledge + 2-3 targeted web searches
   - `standard`: web search + documentation tools (Context7) + 5-10 sources
   - `comprehensive`: deep search (gemini-deepsearch if available) + web search + documentation tools + 10-20 sources

7. **Inclusion criteria** — prioritize sources that have:
   - Peer-reviewed methodology
   - Transparent data collection
   - Large or representative datasets
   - Platform-authored documentation
   - Quantified case studies with measurable results

8. **Exclusion criteria** — discard sources that are:
   - Opinion-only blog posts without data
   - Vendor marketing without independent evidence
   - Generic listicles or compilations without primary sources
   - Undocumented claims or unverifiable anecdotes

9. For each retained source, record the full source profile:

```yaml
- id: S{NNN}
  title: "{source title}"
  author: "{author(s) or organization}"
  year: YYYY
  url: "{URL}"
  source_type: Academic Paper | Platform Documentation | Industry Report | Case Study | Conference Paper | Expert Analysis
  authority_tier: 1 | 2 | 3
  credibility_signal: Peer-reviewed | Data-backed | Platform-authored | Industry-recognized | Anecdotal
  key_findings:
    - "{finding 1}"
    - "{finding 2}"
    - "{finding 3}"
  quantitative_data: "{specific metrics, percentages, or data points cited}"
  methodology_notes: "{how the data was collected, sample size, limitations — if available}"
  relevance: high | medium
```

Authority tiers:
- **Tier 1:** Official documentation, academic research, verified industry reports, RFCs, government sources
- **Tier 2:** Reputable tech blogs, industry publications, conference talks, reputable media
- **Tier 3:** Community consensus, Stack Overflow patterns, internal proprietary data, surveys

10. Discard sources with relevance: low. Proceed with high and medium only.

### Phase 3 — AKU Extraction

11. For each source, extract actionable knowledge units. Each AKU must have the full structured format:

```yaml
- id: AKU-{DOMAIN}-{NNN}
  title: "{concise mechanism name}"
  knowledge_type: Normative Principle | Structural Best Practice | Operational Heuristic | Strategic Trend | Conceptual Framework
  evidence_type: Causal | Correlational | Observational | Normative | Experimental
  confidence: high | moderate | emerging
  causality: established | probable | correlated | unknown
  source: S{NNN}
  source_tier: 1 | 2 | 3
  domain: "{domain code}"
  platform_scope: universal | "{specific platform(s)}"
```

**Field definitions:**

- `knowledge_type` — what kind of knowledge this is:
  - **Normative Principle:** an accepted standard or rule (e.g., "HTTPS is a ranking signal")
  - **Structural Best Practice:** a documented effective pattern (e.g., "section-by-section long-form generation")
  - **Operational Heuristic:** a practical rule-of-thumb from field observation (e.g., "FAQ schema increases snippet selection")
  - **Strategic Trend:** a directional market or technology shift (e.g., "AI-generated content saturation increasing")
  - **Conceptual Framework:** a model for understanding a domain (e.g., "E-E-A-T as trust proxy system")

- `evidence_type` — how the evidence was produced:
  - **Causal:** controlled experiment or mechanism with established cause-effect
  - **Correlational:** observed co-occurrence without proven mechanism
  - **Observational:** field observation or case study without controlled conditions
  - **Normative:** industry standard, official documentation, or regulatory requirement
  - **Experimental:** emerging test with preliminary results

- `causality` — strength of the causal link:
  - **established:** mechanism confirmed by multiple independent sources or official documentation
  - **probable:** strong evidence from multiple sources but no definitive controlled test
  - **correlated:** co-occurrence observed but mechanism not proven
  - **unknown:** insufficient evidence to classify

12. For each AKU, write the full body:

```markdown
#### AKU-{DOMAIN}-{NNN} — {Title}

**Knowledge type:** {type}
**Evidence type:** {type}
**Confidence:** {level}
**Causality:** {level}
**Source:** {S# reference}
**Platform scope:** {universal or specific}
**Directional trend:** {↑ increases / ↓ decreases / → stable / ↕ mixed}

{Claim — clear, operational statement of the mechanism in precise language.}

**Mechanism:** {How it works — 2-3 sentences explaining the underlying process or logic.}

**Operational implications:** {What this means for execution — how an agent or skill should use this knowledge. Actionable, not abstract.}

**Guardrails:**
- {Constraint 1 — what NOT to overgeneralize from this finding}
- {Constraint 2 — conditions where this does NOT apply}
- {Constraint 3 — risk of misapplication}

**Evidence:** {Specific data point, quote, or quantified finding from source — verbatim where possible.}

**GAAI mapping:** {Which skill(s) or rule(s) this informs, and how — referencing actual skills from skills-index.yaml.}
```

13. Detect contradictions between sources. When two AKUs conflict:
    - Record both with a `contradicts: AKU-{ID}` field
    - Note the evidence strength on each side
    - Do NOT resolve the contradiction — the agent decides

14. Detect trade-offs (distinct from contradictions). When a mechanism has both benefits and costs:
    - Record the trade-off explicitly: what is gained, what is lost
    - Note conditions under which the trade-off tilts one way or the other

### Phase 4 — GAAI Compatibility Filtering

This phase ensures all AKUs are compatible with GAAI principles before inclusion in the report. Apply the following filters sequentially:

**Filter 1 — Agent/Skill boundary:**
- If an AKU proposes creating a new agent type (e.g., "Research Agent", "SEO Agent") → **Reframe** as skill specialization or execution pattern. Agents are domain-agnostic in GAAI.
- Record original framing and reframed version in the compatibility notes.

**Filter 2 — Duplicate detection:**
- Compare each AKU against existing knowledge in memory (from Phase 1 check)
- If an AKU duplicates an existing entry with equal or lower confidence → **Exclude** with note
- If an AKU updates or strengthens an existing entry → **Flag as update** with reference to the existing entry

**Filter 3 — Scope classification:**
- If an AKU covers infrastructure, ops, or off-page concerns outside the research scope → **Flag as out-of-scope context** (kept for awareness, not as skill input)
- If an AKU is too generic to be actionable for skill design → **Exclude** with note

**Filter 4 — GAAI mapping:**
- For each surviving AKU, check `skills/skills-index.yaml`
- Map the AKU to the specific skill(s) it informs (by skill name and how it applies)
- If no existing skill maps → note as "potential new skill input"
- If the AKU informs a rule rather than a skill → note as "potential rule input"

**Filter 5 — Autonomy violation check:**
- If an AKU suggests autonomous decision-making by a skill (e.g., "the skill should decide which approach to use") → **Reframe** to separate decision (agent) from execution (skill)
- If an AKU suggests bypassing the backlog or auto-generating artifacts without governance → **Exclude** with note

Record all filtering decisions in a **Compatibility Notes** section (see output format).

### Phase 5 — Report Assembly

15. Assemble the knowledge report following the output format below
16. Group AKUs into structured categories (not arbitrary themes):
    - **I. Core Mechanisms** — fundamental principles and how they work
    - **II. Performance Patterns** — quantified relationships and measurable trends
    - **III. Evidence-Graded Best Practices** — operational recommendations with evidence backing
    - **IV. Trade-offs & Contradictions** — competing findings, context-dependent results, weak evidence areas
    - **V. Risk & Failure Patterns** — documented failure modes, misapplication risks, platform dependencies
17. Produce the Evidence Distribution Summary
18. Produce the Confidence Calibration Layer
19. Produce the Safe Generation Protocol
20. Produce the gap assessment: what the research scope asked for vs what was found
21. List recommended next actions (without deciding — the agent decides):
    - Which AKUs are candidates for `memory-ingest`
    - Which AKUs suggest a new skill may be needed
    - Which AKUs update existing skill references
    - Which gaps remain unresolved and may require deeper research

---

## Output Format

```markdown
# {Domain} — Knowledge Report

> **Domain:** {domain code}
> **Research scope:** {scope as provided by agent}
> **Depth:** {surface | standard | comprehensive}
> **Sources analyzed:** {count}
> **AKUs produced:** {count total} ({count} included, {count} excluded, {count} reframed)
> **Date:** {YYYY-MM-DD}
> **Existing coverage:** {summary of what already existed in memory}

---

## Source Registry

| # | Title | Author/Org | Year | Type | Tier | Credibility | Relevance |
|---|-------|-----------|------|------|------|-------------|-----------|
| S1 | ... | ... | ... | ... | 1/2/3 | ... | high/medium |

### Source Details

#### S1 — {Title}

**Author:** {author/organization}
**URL:** {url}
**Type:** {Academic Paper | Platform Documentation | Industry Report | Case Study | Conference Paper | Expert Analysis}
**Credibility signal:** {Peer-reviewed | Data-backed | Platform-authored | Industry-recognized | Anecdotal}
**Key findings:**
- {finding 1}
- {finding 2}
- {finding 3}
**Quantitative data:** {specific metrics cited}
**Methodology:** {how data was collected, sample size, limitations}

---

## I. Core Mechanisms

{AKUs that describe fundamental principles and how they work.}

#### AKU-{DOMAIN}-001 — {Title}

**Knowledge type:** {type}
**Evidence type:** {type}
**Confidence:** {level}
**Causality:** {level}
**Source:** {S# reference}
**Platform scope:** {universal or specific}
**Directional trend:** {↑/↓/→/↕}

{Claim — clear, operational statement.}

**Mechanism:** {How it works — 2-3 sentences.}

**Operational implications:** {What this means for execution.}

**Guardrails:**
- {Constraint preventing overgeneralization}
- {Conditions where this does NOT apply}

**Evidence:** {Specific data point or quote — verbatim.}

**GAAI mapping:** {Which skill(s) or rule(s) this informs, and how.}

---

## II. Performance Patterns

{AKUs describing quantified relationships and measurable trends.}

---

## III. Evidence-Graded Best Practices

{AKUs providing operational recommendations with evidence backing.}

---

## IV. Trade-offs & Contradictions

### Contradictions

| AKU A | AKU B | Nature of conflict | Evidence balance |
|-------|-------|--------------------|------------------|

### Trade-offs

| Mechanism | Benefit | Cost | Tilt condition |
|-----------|---------|------|----------------|

### Context-Dependent Results

{AKUs where outcomes vary significantly by platform, scale, or domain.}

### Weak/Incomplete Evidence Areas

{Topics where findings exist but evidence is thin, single-source, or anecdotal.}

---

## V. Risk & Failure Patterns

{Documented failure modes, misapplication risks, and platform dependencies.}

| Risk | Failure mode | Impact | Evidence type | Mitigation |
|------|-------------|--------|---------------|------------|

---

## Evidence Distribution Summary

| Evidence type | Count | Percentage |
|---------------|-------|------------|
| Causal | | |
| Correlational | | |
| Observational | | |
| Normative | | |
| Experimental | | |

| Confidence level | Count | Percentage |
|------------------|-------|------------|
| High | | |
| Moderate | | |
| Emerging | | |

| Causality level | Count | Percentage |
|-----------------|-------|------------|
| Established | | |
| Probable | | |
| Correlated | | |
| Unknown | | |

**Strongest mechanisms:** {top 3-5 AKUs with highest evidence strength}
**Weakest areas:** {domains or topics with lowest confidence / fewest sources}

---

## Confidence Calibration Layer

This section defines what confidence levels mean in operational terms — for any agent or skill consuming this report.

| Level | Meaning | Operational guidance |
|-------|---------|---------------------|
| **High** | Consistent across multiple independent sources. Replicated in field or documented in official references. Stable over time. | Can be used as default execution rule in skills. Guardrails still apply. |
| **Moderate** | Multi-source correlation without longitudinal data, OR single high-authority source without independent replication. | Use as guidance, not as absolute rule. Flag uncertainty when applying. Cross-reference with domain context. |
| **Emerging** | Early signal with limited validation. Single source, small sample, or recent finding without replication. | Do NOT use as execution rule. Treat as hypothesis for future validation. Flag explicitly if referenced. |

---

## Safe Generation Protocol

Rules for how agents and skills should consume the AKUs in this report:

1. **High-confidence AKUs with causality: established** may be used as execution rules in skill process steps, with their guardrails included.
2. **Correlational findings** must be presented as probabilistic ("tends to", "is associated with"), never as deterministic rules ("always", "guarantees", "will").
3. **Avoid numeric absolutism.** A finding of "38% improvement" means "approximately 38% improvement was observed in the cited study under specific conditions" — not "this technique produces 38% improvement."
4. **Platform-specific findings** must not be generalized to other platforms without explicit evidence. A Google ranking signal is not automatically a Bing or AI search signal.
5. **Emerging-confidence AKUs** must never be embedded directly into skill execution steps. They inform agent reasoning only.
6. **When two AKUs contradict,** neither may be treated as authoritative. The agent must choose based on project context, or defer to the human.
7. **Guardrails are not optional.** Any AKU consumed without its guardrails is a misapplication.

---

## Compatibility Notes

### Excluded ({count})

| AKU | Reason |
|-----|--------|

### Reframed ({count})

| Original | Reframed as | Reason |
|----------|-------------|--------|

### Flagged as out-of-scope ({count})

| AKU | Reason | Kept as context for |
|-----|--------|---------------------|

---

## Gap Assessment

| Scope item requested | Coverage | Notes |
|----------------------|----------|-------|
| {topic from research_scope} | COVERED / PARTIAL / NOT FOUND | {detail} |

---

## Recommended Actions (for agent decision)

- **Memory candidates:** {list of AKU IDs suitable for memory-ingest}
- **Skill input candidates:** {list of AKU IDs that inform existing skill references/}
- **New skill signals:** {list of AKU IDs suggesting a capability gap}
- **Rule input candidates:** {list of AKU IDs that inform governance rules}
- **Update candidates:** {list of AKU IDs that strengthen or update existing memory entries}
- **Unresolved gaps:** {topics from scope that need deeper or targeted research}

---

## Metadata Tags

{Machine-ingestible classification for the overall report.}

[Domain: {domain_code}]
[Evidence_Profile: {Causal-heavy | Correlational-heavy | Mixed | Normative-heavy}]
[Primary_Levers: {top 3-5 mechanism names}]
[System_Risk_Level: Low | Moderate | High]
[Platform_Dependencies: {list of platform-specific findings or "None"}]
[Data_Sparsity_Areas: {topics with insufficient evidence}]
```

Saves to `contexts/artefacts/research/{domain-slug}.knowledge-report.md`.

---

## Quality Checks

- Every AKU has a source reference — no unsourced claims
- Every AKU has both `knowledge_type` and `evidence_type` — these are distinct fields, never conflated
- Every AKU has a `causality` classification — no AKU omits this field
- **Every AKU with `causality: correlated` must have guardrails preventing absolute interpretation**
- Every AKU has `mechanism` and `operational_implications` — bare claims without explanation are insufficient
- Every AKU has at least one guardrail — even high-confidence findings have boundaries
- Evidence Distribution Summary tallies match actual AKU counts
- GAAI compatibility filtering is applied to ALL AKUs — no AKU bypasses Phase 4
- Excluded/reframed AKUs are documented with reasons (traceability)
- GAAI mappings reference actual skills from `skills-index.yaml`, not invented skill names
- Contradictions and trade-offs are surfaced, not silently resolved
- Gap assessment covers every item in the original `research_scope`
- Safe Generation Protocol is present and reflects the actual evidence profile of the report
- The report does not contain recommendations phrased as decisions — only candidates for agent evaluation
- No AKU proposes autonomous agent creation, backlog bypass, or ungoverned skill generation
- Source registry includes author, methodology, and quantitative data for every source

---

## Non-Goals

This skill must NOT:
- Decide which AKUs to persist in memory — the agent invokes `memory-ingest` after reading the report
- Create or modify skills — the agent invokes `create-skill` if warranted
- Modify existing memory entries — the agent decides what to update
- Resolve contradictions between sources — surface them, let the agent decide
- Resolve trade-offs — document both sides, let the agent decide based on project context
- Evaluate strategic priority of findings — the agent reasons about priorities
- Research without a defined scope — the agent must provide `research_scope`
- Simplify findings into blog-style prose — precision over readability
- Strip quantified data in favor of qualitative summaries — preserve the numbers

**Research informs. The agent decides. Knowledge enters the system only through governed channels.**
