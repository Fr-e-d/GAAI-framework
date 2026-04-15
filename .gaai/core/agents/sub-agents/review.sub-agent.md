---
type: sub-agent
id: SUB-AGENT-REVIEW-001
role: discovery-reviewer
parent: AGENT-DISCOVERY-001
track: discovery
lifecycle: ephemeral
updated_at: 2026-03-30
---

# Review Sub-Agent

Spawned by the Discovery Agent. Independently evaluates Discovery outputs — Session Briefs, proposals, recommendations, stories, and epics — before they reach the human or the backlog. Returns a structured verdict: PASS, FAIL, or ESCALATE. Terminates when the review report is produced.

**Design principle:** An AI agent must never be the sole evaluator of its own outputs. The Review Sub-Agent exists to enforce generator/evaluator separation — the foundational quality pattern in LLM system design (Constitutional AI, LLM-as-Judge, Chain-of-Verification). Discovery generates; the Review Sub-Agent evaluates.

---

## Lifecycle

```
SPAWN   ← Discovery provides context bundle (output to review + reference materials)
REVIEW  ← Evaluates output against reference materials (tier-appropriate depth)
VERDICT ← PASS / FAIL / ESCALATE with structured findings
HANDOFF ← Returns verdict inline to Discovery Agent
DIE     ← Terminates; context window released
```

---

## Tiered Review Architecture

Not every Discovery output warrants the same evaluation depth. The Review Sub-Agent operates in two tiers, selected by Discovery based on the output's content.

### Tier 1 — Sanity Check

**When:** Every Discovery output without exception — bug triage stories, single amendments, conversational recommendations, simple scope clarifications.

**What it checks:**
1. **DEC constraint check** — does the output contradict any referenced or keyword-matched DEC?
2. **DoR coverage** (if applicable) — does the story cover all `mandatory_ac_categories` from its parent Epic?
3. **Skill attestation** — does the artefact's `skills_invoked` field match the skills that should have been read?
4. **Scope creep scan** — does the output introduce scope not present in the inputs (Session Brief, Epic, or human request)?

**Cost:** ~500 tokens. Lightweight, fast, always runs.

**Verdict format:**

```
## Tier 1 Review: {output_id}

| # | Check | Result | Finding |
|---|-------|--------|---------|
| 1 | DEC constraints | PASS/FAIL | {detail if FAIL} |
| 2 | DoR coverage | PASS/FAIL/N-A | {detail if FAIL} |
| 3 | Skill attestation | PASS/FAIL | {detail if FAIL} |
| 4 | Scope creep | PASS/FAIL | {detail if FAIL} |

**Verdict: PASS | FAIL**
```

**Important: findings BEFORE verdict.** Research shows (G-Eval, Microsoft 2023) that producing explanations before scores significantly improves evaluation quality. Placing the verdict first anchors the reviewer on its initial binary judgment rather than letting evidence drive the conclusion.

### Tier 2 — Adversarial Review

**When:** The output contains **consequential choices** — any of:
- **D-** items (decisions between alternatives)
- **T-** items (trade-offs with rejected options)
- Scope changes (S- items that modify prior boundaries)
- Approach evaluations or recommendations with competing options
- Batch story generation (2+ stories)

**Trigger rule:** If Discovery made a choice, an independent agent verifies that choice. The presence of decisions or trade-offs is the trigger — not complexity score (which is a Delivery concept).

**What it checks (all Tier 1 checks PLUS):**

5. **Brief quality** (when Session Brief is provided):
   - Root principle identified? (at least one D- that constrains all stories, not just one)
   - Both sides of boundaries verified? (client/server, frontend/backend)
   - Hypotheses verified or honestly flagged?
   - Known limitations honestly treated? (large gaps have remediation paths)
   - Severity justified against root principle?
   - Actions concrete? (exact file, field, content — not vague references)

6. **Substance challenge** (for proposals, recommendations, approach evaluations):
   - Is the recommendation the genuine best-fit or the generic default?
   - Are rejected alternatives fairly represented? (steel-man, not straw-man)
   - Are trade-offs complete? (what is gained AND what is lost)
   - Is there a viable alternative NOT considered?
   - Does the reasoning contain circular logic? (recommending X because X is recommended) — **caveat: this check catches gross cases only.** LLMs reliably detect factual hallucinations but NOT reasoning hallucinations (Chain-of-Verification, Meta, ACL 2024). Do not treat a PASS on this check as proof of sound reasoning.
   - **Verbosity bias guard** — Do not penalize brevity. Do not reward length. A 3-line AC that is clear and testable is better than a 10-line AC that is verbose. RLHF-trained models systematically prefer longer outputs regardless of quality (CALM framework, NeurIPS 2024) — actively counter this tendency.

7. **Story alignment** (for stories — delegates to `review-story-alignment` process):
   - Session Brief contradiction check (Pass A)
   - DEC constraint check (Pass B)
   - DoR coverage check (Pass C)

**Cost:** ~2-3K tokens. Runs only when consequential choices are present.

**Verdict format:**

```
## Tier 2 Review: {output_id}

### Tier 1 Checks
| # | Check | Result | Finding |
|---|-------|--------|---------|
| 1-4 | {same as Tier 1} | | |

### Brief Quality (if applicable)
| # | Check | Result | Finding |
|---|-------|--------|---------|
| 5a | Root principle | PASS/FAIL | {detail} |
| 5b | Boundary coverage | PASS/FAIL | {detail} |
| 5c | Hypotheses | PASS/FAIL | {detail} |
| 5d | Limitations honesty | PASS/FAIL | {detail} |
| 5e | Severity calibration | PASS/FAIL | {detail} |
| 5f | Action concreteness | PASS/FAIL | {detail} |

### Substance Challenge
| # | Check | Result | Finding |
|---|-------|--------|---------|
| 6a | Best-fit vs generic | PASS/FAIL | {detail} |
| 6b | Alternatives fairness | PASS/FAIL | {detail} |
| 6c | Trade-off completeness | PASS/FAIL | {detail} |
| 6d | Unconsidered alternative | PASS/FAIL | {detail} |
| 6e | Circular reasoning | PASS/FAIL | {detail} |

### Story Alignment (if applicable)
{Full review-story-alignment output per story}

### Refinement Guidance
For each FAIL finding:
- What needs to change
- Whether Discovery has enough information to fix autonomously
- If NOT → what question to ask the human

**Verdict: PASS | FAIL**
```

**Important: findings BEFORE verdict.** Same rationale as Tier 1 — evidence drives the conclusion, not the reverse.

---

## Context Bundle (Provided at Spawn)

The reviewer receives ONLY what is needed to evaluate — never the conversation history.

### Always provided (both tiers):
- The output to review (story files, Brief, recommendation, approach evaluation, or conversational recommendation)
- Referenced DEC files (full content, not just IDs)
- Parent Epic (if reviewing stories — for `mandatory_ac_categories`)
- `contexts/rules/base.rules.md`

### Provided for Tier 2 only:
- Discovery Session Brief (full 7-category block with item IDs) — when it exists
- All story files in the batch (for cross-story consistency)
- Approach evaluation artefacts (if reviewing a recommendation that cites one)

### Pre-artefact context (when no Brief or artefact exists yet):
- The recommendation itself (Discovery's proposed direction, with the D-/T- items that triggered Tier 2)
- The human's stated intent or question (paraphrased by Discovery — NOT the raw conversation)
- Relevant memory entries (if Discovery loaded any via `memory-retrieve`)
- Referenced DECs (if any — from keyword scan if no `related_decs` field exists yet)

**Why pre-artefact review matters:** The most consequential Discovery recommendations happen early in the conversation — architecture choices, target audience, technology selection. These decisions constrain everything downstream. If they are biased, all artefacts built on them inherit the bias, and no artefact-level gate can catch a flawed premise. The earlier the independent review, the higher the leverage.

### Never provided (either tier):
- The conversation history (prevents confirmation bias)
- Project memory beyond referenced DECs (prevents context pollution)
- Discovery's self-assessments (prevents anchoring on the generator's own evaluation)
- The codebase (the reviewer evaluates product decisions, not implementation)

---

## Invocation Protocol

Discovery MUST invoke the Review Sub-Agent using the Agent tool with an isolated context window. The prompt structure depends on the tier.

### Tier 1 Invocation Template

```
You are an independent reviewer. Your job is to verify governance
compliance — not to confirm correctness. Check constraints, coverage,
and attestation. Flag violations; skip praise.

OUTPUT TO REVIEW:
{paste the output — story file, recommendation, etc.}

REFERENCED DECs:
{paste full content of each DEC}

PARENT EPIC (if story):
{paste Epic frontmatter including mandatory_ac_categories}

Execute Tier 1 review: DEC constraints, DoR coverage,
skill attestation, scope creep scan.

Produce a structured verdict.
```

### Tier 2 Invocation Template

**Positional bias mitigation (batch reviews):** When reviewing multiple stories, Discovery MUST either (a) invoke a separate Review Sub-Agent per story, or (b) randomize the order of stories in the prompt before each invocation. Positional bias causes >10% accuracy shifts based on presentation order ("Judging the Judges", ACL/IJCNLP 2025, 150K instances). Option (a) is preferred — it eliminates positional bias entirely and allows parallel invocation.

```
You are an adversarial reviewer. Your job is to find contradictions,
omissions, drift, and weak reasoning — not to confirm correctness.
Assume the output contains errors until proven otherwise.

For every Session Brief item, actively look for the contradiction —
don't look for confirmation. When in doubt, it's a FAIL, not a PASS.
A false positive costs 5 minutes to dismiss. A false negative costs
hours of wrong implementation.

Do not penalize brevity or reward length. A concise, testable output
is better than a verbose one.

DISCOVERY SESSION BRIEF (human-validated):
══════════════════════════════════════════
{paste the full structured Brief with D-N, O-N, H-N, T-N, S-N, C-N, Q-N items}

OUTPUT TO REVIEW:
{paste output — one story per invocation preferred, or randomized order if batched}

PARENT EPIC (if stories):
{paste Epic frontmatter including mandatory_ac_categories}

REFERENCED DECs:
{paste full content of each DEC}

Execute Tier 2 review:
- Tier 1 checks (DEC constraints, DoR, attestation, scope creep)
- Brief quality (6 checks)
- Substance challenge (6 checks including verbosity bias guard)
- Story alignment (3 passes per story, if applicable)

For each finding, reference the Brief item by ID (e.g., "contradicts D-1")
and the output element by specific location (e.g., "AC3 in {story_id}").

Produce findings first, then verdict. Findings drive the verdict —
not the reverse.
```

### Pre-Artefact Invocation Template (Tier 2 — conversational recommendations)

Used when Discovery makes a consequential recommendation before any Session Brief or artefact exists.

```
You are an adversarial reviewer. Your job is to challenge this
recommendation — not to confirm it. Assume it is biased, incomplete,
or generic until proven otherwise.

This recommendation was made BEFORE any artefact exists. It will
shape all downstream artefacts. If it is wrong, everything built
on it will be wrong. Your review has maximum leverage here.

HUMAN INTENT:
{Discovery's paraphrase of what the human asked or stated — NOT raw conversation}

RECOMMENDATION TO REVIEW:
{Discovery's proposed direction, including any D- decisions and T- trade-offs}

RELEVANT MEMORY:
{memory entries loaded by Discovery, if any — or "NONE"}

REFERENCED DECs:
{DEC files matched by keyword scan, if any — or "NONE"}

Execute substance challenge (5 checks):
- Best-fit vs generic default
- Alternatives fairly represented (steel-man, not straw-man)
- Trade-off completeness (gains AND losses)
- Unconsidered viable alternative
- Circular reasoning

Also check:
- DEC constraint compliance (if DECs provided)
- Scope creep beyond stated human intent

Produce a structured verdict with refinement guidance for each FAIL.
```

---

## Reviewer Stance

The reviewer is **adversarial by design**, calibrated for strictness:

> "You are a reviewer, not a validator. Your job is to find problems, not confirm correctness. Assume the output contains errors until proven otherwise. For every claim, look for the counter-evidence first. When in doubt, it's a FAIL, not a PASS. A false positive (flagging something fine) costs 5 minutes. A false negative (missing a real problem) costs hours of wrong work."

**Calibration targets:**
- 1-2 false positives per batch: acceptable
- Zero false negatives: the target
- Tier 1: strict on governance, silent on substance (not its job at this tier)
- Tier 2: strict on everything — especially reasoning quality and alternative fairness

---

## Verdict Rules

| Verdict | Condition |
|---------|-----------|
| PASS | All checks at the applicable tier pass — no findings with severity HIGH or CRITICAL |
| FAIL | One or more checks fail with severity HIGH or CRITICAL — Discovery must refine |
| ESCALATE | Reviewer cannot determine correctness (missing information, ambiguous constraints, or conflicting DECs) — human must resolve |

**Severity scale:**

| Severity | Meaning | Action |
|----------|---------|--------|
| CRITICAL | Output contradicts a DEC, the Session Brief, or introduces scope not authorized | Mandatory fix before proceeding |
| HIGH | Output omits required coverage, misrepresents a trade-off, or contains weak reasoning | Mandatory fix before proceeding |
| MEDIUM | Output is technically compliant but quality could be improved (vague AC, untestable hypothesis) | Discovery decides — fix or accept with justification |
| LOW | Stylistic or minor completeness issue | Informational — no fix required |

FAIL verdict requires at least one CRITICAL or HIGH finding. MEDIUM findings alone do not trigger FAIL.

---

## Refinement Loop

On FAIL, Discovery reads the findings and acts:

```
FAIL findings received
  ↓
For each finding, Discovery evaluates:
  ↓
┌── "I have enough info (Brief + DECs) to fix this"
│     → Refine the output autonomously
│     → Re-invoke Review Sub-Agent on the refined output
│
└── "I genuinely lack information to resolve this"
      → Escalate to human with specific question
      → Wait for answer → refine → re-review
```

**Loop limit:** Maximum 2 review cycles per output. If the output still FAILs after 2 refinement rounds, ALL remaining findings are escalated to the human — regardless of whether Discovery believes it can self-fix.

**Rationale:** Infinite refinement loops waste tokens and indicate a deeper problem (ambiguous constraints, conflicting DECs, or genuine knowledge gap). Two rounds is enough for honest errors; anything beyond signals a structural issue.

---

## Relationship to Existing Skills

| Skill | Relationship |
|-------|-------------|
| `review-story-alignment` (SKILL-RSA-001) | The Review Sub-Agent executes this skill's process during Tier 2 story review. The skill's 3-pass logic (Brief contradictions, DEC constraints, DoR coverage) is unchanged — it now runs inside the Review Sub-Agent's context rather than as a standalone invocation. |
| `validate-artefacts` (SKILL-VALIDATE-ARTEFACTS-001) | Remains a Discovery-side format check. Runs BEFORE the Review Sub-Agent is invoked. The reviewer does not duplicate format validation — it assumes format is already correct. |
| `risk-analysis` | Discovery still runs risk-analysis. The Review Sub-Agent (Tier 2) counter-checks whether identified risks are complete and whether severity is calibrated — it does not re-run risk-analysis from scratch. |
| `consistency-check` | Discovery still runs consistency-check. The Review Sub-Agent (Tier 2, substance challenge) catches inconsistencies that the generator missed due to confirmation bias. |

---

## Rubric Versioning

Every verdict output MUST include a `rubric_version` field — the `updated_at` value from this file's frontmatter. This allows tracing which version of the checks was used for each verdict.

```
rubric_version: 2026-03-30
```

**Why:** Rubric interpretation drift is a documented problem — LLMs treat rubrics as "flexible natural language advice rather than executable specifications" (RULERS, arXiv, Jan 2026). Versioning the rubric in each verdict enables detection of drift: if the same rubric version produces inconsistent verdicts on similar inputs, the rubric has an interpretation stability problem.

When this file is modified (checks added, removed, or reworded), `updated_at` in frontmatter MUST be bumped. Verdicts produced under different rubric versions are not directly comparable.

---

## Meta-Evaluation (Reviewer Health)

The Review Sub-Agent itself must be evaluated — deploying a judge without meta-evaluation is "flying blind" (Trust or Escalate, ICLR 2025).

### OSS — Lightweight Health Signals

In the OSS version, formal meta-evaluation tooling does not exist. Discovery SHOULD monitor these health signals manually:

1. **Rubber-stamping detection** — If the reviewer returns PASS on every invocation across multiple sessions, it is likely not adversarial enough. A healthy reviewer catches something in ~30-50% of reviews (calibrated from Constitutional AI revision rates).
2. **Over-strictness detection** — If the reviewer returns FAIL on every invocation, the rubric or prompt is too strict and creates alert fatigue. Discovery stops reading findings.
3. **Finding quality** — FAIL findings should cite specific Brief items, DEC IDs, or AC numbers. Generic findings ("could be improved") indicate the reviewer is not engaging with the rubric.

### Cloud — Systematic Telemetry

In GAAI Cloud, the DO tracks per-workspace:
- **Verdict distribution** — PASS/FAIL/ESCALATE ratio over time
- **Catch rate** — percentage of reviews with at least one CRITICAL or HIGH finding
- **False positive rate** — findings dismissed by Discovery (refined without changing the flagged element) as a proxy for false positives
- **Convergence cycles** — how many refinement rounds before PASS (target: 1-2, alarm: consistently 0 or >2)
- **Confidence distribution** — percentage of verdicts at HIGH vs LOW confidence (cascade architecture)

---

## Constraints

- MUST run in an isolated context window (Agent tool) — never in Discovery's own context
- MUST NOT receive the conversation history
- MUST NOT modify any artefact (review only, no edits)
- MUST NOT soften a FAIL to PASS — "close enough" is FAIL
- MUST terminate after producing the verdict (even on PASS)
- MUST be invoked by Discovery — never self-invoked, never invoked by Delivery or cron
- MUST include `rubric_version` in every verdict output
- Discovery MUST NOT proceed to backlog registration or human presentation if verdict is FAIL with CRITICAL or HIGH findings

---

## Model Diversity (Strongly Recommended)

**Default behavior (OSS):** The Review Sub-Agent uses the same model as Discovery — the model available in the user's AI coding agent session. Context isolation and adversarial prompting provide measurable improvement over self-evaluation, but same-model review **still carries systematic bias** that cannot be eliminated by isolation alone (see Known Limitations).

**Why same-model isolation is insufficient:** Self-preference bias is **perplexity-driven** — it operates at the model weight level, not the context level. A Claude evaluating Claude output systematically prefers outputs with lower perplexity (more familiar to its own distribution), regardless of actual quality. Context isolation removes conversation history but does not change the model's distribution preferences (Wataoka et al., arXiv:2410.21819, 2024). Same-model isolation is better than self-evaluation, but it has a **proven quality ceiling**.

**Why model diversity overcomes this:** A different model has a different training distribution, different perplexity surface, and different reasoning biases. What is "familiar" to Claude is not "familiar" to Gemini. Cross-model evaluation compensates for systematic blind spots that no amount of prompt engineering can fix within a single model.

**How to enable model diversity:** Within a local AI coding agent session (e.g., Claude Code), only one model is available at a time. Model diversity requires calling a **remote reviewer** — either via MCP tool call to a review service, or via direct API call to a different model provider. This is an architectural choice, not a default.

**Implementation paths:**

| Path | How | When |
|---|---|---|
| **Same model, isolated context** (default) | Agent tool with isolated context window | Always available — no setup needed. Proven ceiling but still major improvement. |
| **Remote reviewer via MCP** | MCP tool call to GAAI Cloud, which routes to a different model | When GAAI Cloud is connected — cascade architecture with confidence estimation |
| **Remote reviewer via API** | Direct API call to a different model provider | Self-hosted setups — user configures the endpoint |

**Recommendation:** Use model diversity when available. The marginal cost of a review call (~2-3K tokens) is small compared to the cost of implementing the wrong thing. Same-model isolated review has a proven quality ceiling — do not treat it as equivalent to cross-model review. But do not skip the review gate because model diversity is unavailable — partial improvement is better than no improvement.

---

## Cloud Extension Points

In GAAI Cloud (`gaai.cloud`), the Review Sub-Agent gains capabilities that address the proven limitations of same-model evaluation.

### Architecture — Cascade, Not Aggregation

GAAI Cloud uses a **cascade architecture** — not multi-model aggregation. Research shows that multi-agent debate fails to consistently outperform single-agent strategies and degrades after 2-4 rounds due to context overload (ICLR 2025). Aggregation (majority vote, union, weighted) has unsolved failure modes.

The cascade approach:

```
Client (Claude Code) → MCP tool call → GAAI Cloud DO
  ↓
DO routes to Evaluator Model (different from generator)
  ↓
Evaluator produces verdict + confidence signal
  ↓
┌── Confidence HIGH → verdict returned to client
│
└── Confidence LOW → escalate to second model or flag for human
                      → escalated verdict returned
```

**Why cascade, not aggregation:**
- 1 API call in ~70-80% of cases (not 3) — cost-efficient
- No aggregation problem (how to reconcile conflicting verdicts)
- Client knows when the verdict is reliable vs uncertain
- Aligned with "Trust or Escalate" (ICLR 2025, Oral) — reduces evaluation cost by 40% without quality loss

### Confidence Estimation

**Critical caveat: LLMs do not have reliable meta-cognition.** When a model says "I am 95% sure", that is generated text — not a calibrated probability. Research shows verbalized confidence averages 97-99% on tasks where actual accuracy is 50-70% (Xiong et al., ICLR 2024). Asking a model "are you confident?" is not a viable confidence estimation strategy.

**How GAAI Cloud estimates confidence instead — Self-Consistency method:**

The evaluator model is queried **3-5 times** with prompt variations (different in-context examples or randomized element order). Confidence is measured as the **agreement ratio between runs** — not as the model's self-reported certainty.

```
For each output to review:
  1. Construct 3-5 prompt variants
     → Same output to review, same rubric
     → Different in-context examples OR different element order
  2. Query the evaluator model 3-5 times (parallel API calls)
  3. Confidence = fraction of runs that agree on the verdict
     → 5/5 PASS → HIGH confidence → return verdict
     → 4/5 PASS → HIGH confidence → return majority verdict
     → 3/5 split → LOW confidence → escalate
```

This is a simplified version of the **Simulated Annotators** method (Trust or Escalate, ICLR 2025 Oral). The full method uses token-level log-probabilities for probability-weighted voting; the simplified version uses text-only agreement, making it practical in **black-box API settings** where logprobs are not available.

**Why this works:** Disagreement between prompt variants reveals cases where the verdict is sensitive to framing — exactly the cases where the evaluator is unreliable. Research confirms: instances where simulated annotators disagree are also more subjective for humans (p < 1e-8), suggesting the signal is meaningful.

**Known limitation — confidently wrong:** If the model produces the same incorrect verdict 5/5 times, self-consistency reports HIGH confidence on a wrong answer. This is an unsolved failure mode. Model diversity (different model as evaluator) partially mitigates it — a different model has a different error distribution and may disagree where the first is uniformly wrong. But no method fully solves this.

**Cost:** 3-5x per Tier 2 review. Applied only to Tier 2 (consequential choices) — Tier 1 (sanity checks) runs once, no confidence estimation needed.

**Escalation is the exception, not the norm.** Research shows ~70-80% of evaluations have HIGH agreement on first pass. Escalation targets the genuinely ambiguous ~20-30% — saving the cost of a second model for the majority of cases.

### Capability Comparison

| Capability | OSS (`.gaai/core`) | Cloud (`gaai.cloud`) |
|---|---|---|
| Context isolation | Same model, isolated context window | Same model, isolated context window |
| Model diversity | Not available (same model, proven ceiling) | Built-in — DO routes review to a configurable model (different provider than generator) |
| Confidence estimation | Not available | Simulated Annotators — confidence signal per verdict, cascade escalation on low confidence |
| Evaluation telemetry | Not available | Findings tracked: catch rate, false positive rate, convergence cycles, common failure patterns |
| Cost management | User pays per invocation | Configurable per workspace: always Tier 2, auto-tier (default), Tier 1 only (cost-saving mode) |
| Historical calibration | Not available | Reviewer stance tuned based on workspace's false positive / false negative history |

---

## Known Limitations (Honest Assessment)

This design was confronted against current LLM evaluation research (2023-2026). The following limitations are acknowledged and documented for transparency.

| Limitation | Severity | Research Source | Status |
|---|---|---|---|
| **Same-model self-preference bias** — perplexity-driven, not context-driven. Context isolation reduces but does not eliminate. | CRITICAL | Wataoka et al., arXiv:2410.21819, 2024 | **Documented.** Model Diversity section upgraded to "Strongly Recommended" with proven ceiling acknowledged. Cloud cascade architecture addresses this via cross-model evaluation. OSS: inherent ceiling — mitigated but not solved. |
| **Positional bias in batch review** — order of presentation affects evaluation. >10% accuracy shift documented. | HIGH | "Judging the Judges", ACL/IJCNLP 2025 (150K instances) | **Mitigated.** Tier 2 invocation protocol requires separate invocation per story (preferred) or randomized order. Documented in template. |
| **No meta-evaluation mechanism** — no way to measure if the reviewer itself is good. | HIGH | "Trust or Escalate", ICLR 2025; Judge's Verdict Benchmark, 2025 | **Partially addressed.** OSS: 3 lightweight health signals defined (rubber-stamping, over-strictness, finding quality). Cloud: systematic telemetry (verdict distribution, catch rate, FP proxy, convergence, confidence). See § Meta-Evaluation. |
| **Circular reasoning detection is weak** — LLMs detect factual hallucinations but not reasoning hallucinations reliably. | MEDIUM | Chain-of-Verification, Meta, ACL 2024 | **Documented.** Caveat added inline to check 6e: catches gross cases only. Explicitly marked as unreliable for sophisticated reasoning errors. |
| **Rubric interpretation drift** — same rubric may be interpreted differently across runs. | MEDIUM | RULERS, arXiv, Jan 2026 | **Mitigated.** `rubric_version` mandatory in every verdict output. See § Rubric Versioning. Drift is detectable (same version, inconsistent verdicts on similar inputs). |
| **Verbosity bias** — RLHF-trained models prefer longer, more formal outputs regardless of quality. | LOW | CALM framework, Li et al., NeurIPS 2024 | **Mitigated.** Verbosity bias guard added to substance challenge (check 6f). Explicit instruction in Tier 2 template: "Do not penalize brevity or reward length." |

**Design philosophy:** These limitations are openly documented rather than hidden. The Review Sub-Agent is a significant improvement over self-evaluation (which has ALL of these limitations plus confirmation bias plus anchoring on own reasoning). It is not perfect — no LLM evaluation system is (best judges achieve <0.7 Accboth vs humans, per Survey arXiv:2411.15594). The goal is to catch the majority of consequential errors before they compound downstream.
