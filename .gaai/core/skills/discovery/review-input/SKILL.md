---
name: review-input
description: Adversarial review of any input (human idea, agent analysis, research report, feedback, observation) BEFORE it mutates persistent project state. Universal interceptor with domain auto-detection, 2-phase classification + evaluation, and triple-verdict output (veracity / fit / actionability). Anti-girouette guardrail that distinguishes drift from pivot — preserves human decisional authority. Manual invocation only (no hooks, no enforcement). Activate when an input may affect strategic-frame.md, a DEC, an OT, an architecture/pattern doc, an agent definition, a backlog story scope/AC/wedge field, or user-facing copy.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: discovery
  track: discovery
  id: SKILL-RIN-001
  updated_at: 2026-04-27
  status: stable
  tags: [review, adversarial, anti-girouette, anti-drift, universal-interceptor, three-verdict, pivot-vs-drift, veracity, governance, decision-filter]
inputs:
  - "Input text — any origin (human idea, agent proposal, research excerpt, feedback, bug observation, external signal)"
  - "Optional intent declaration — drift_check (default) | pivot | refinement | exploration"
  - "Optional targets hint — DEC IDs, file paths, OT IDs the input may affect"
outputs:
  - "Triple-verdict JSON report (veracity / fit / actionability) with confidence and rationale"
  - "Domain auto-detected + governance docs cited"
  - "Cost-of-not-pivoting mirror question (forces symmetry, counter to status-quo bias)"
  - "Override path documented (human can always proceed with traced rationale)"
  - "Recommendation : ACCEPT | EXPERIMENT | DEFER | DOCUMENT_ONLY | REJECT (advisory, not gate)"
  - "Sources with tool_call_id when web/MCP verification was performed"
---

# Review Input — Universal Anti-Girouette Reviewer (SKILL-RIN-001)

## Purpose

Intercept ANY input — human or agent — that may mutate persistent project state, BEFORE it becomes a DEC, an OT amendment, a strategic-frame edit, an architectural pattern, or a backlog story scope change. Produce a structured 3-verdict report that **eclaire** the human decision without **replacing** it.

**This skill is anti-girouette, not anti-pivot.** It distinguishes :
- **Drift** (small reactive changes accumulating without rationale) → freined.
- **Pivot** (deliberate, articulated change with rationale + falsifiability) → eclaired, not blocked.

The human is always the final decider. The skill produces recommendation + traceability ; override is first-class and structurally low-friction.

---

## When to Activate

**Manual invocation only — no hooks, no automatic enforcement.** The agent (typically Discovery Agent) invokes this skill when :

- Human introduces a strategic-level idea ("on devrait pivoter sur X", "et si on changeait Y")
- Agent surfaces an analysis or recommendation that could amend a DEC / OT / Non-Goal
- A research report or external signal is being evaluated for inclusion in memory
- Before formalizing a draft DEC as `candidate` or transitioning `candidate` → `active`
- Before amending strategic-frame.md §3 Non-Goals, §6 Open Tensions, or §8 override
- Before writing to memory/strategy/, memory/architecture/, patterns/, or rules/
- Before backlog refinement of a story whose scope/AC/wedge implies governance impact
- Founder feels "drifting" or "lost" (per strategic-frame.md §7.1 trigger)

**Do NOT activate** for :
- Bug fixes with no design choice
- Refactor mécanique (rename, extract function, format)
- Dependency bumps without API change
- Format/lint corrections
- Conventions already established in `patterns/conventions.md`

If unsure → run Phase 1 only ; the classifier will return `out_of_scope` if appropriate.

---

## Architecture — Two Phases

### Phase 1 — Classification (always runs, deterministic, ~30 seconds)

Phase 1 is **lightweight pattern-matching**. It produces no LLM-generated verdicts ; it identifies what kind of input this is and whether Phase 2 evaluation is warranted.

### Phase 2 — Evaluation (conditional on Phase 1 verdict)

Phase 2 loads domain-specific governance, applies Decision Filters, and produces the triple-verdict report. Skipped if Phase 1 returns `out_of_scope`.

---

## Phase 1 — Classification

For the input received, deterministically identify :

### A. Type of input

```
human_idea | human_directive | agent_analysis | agent_proposal
research_report | feedback_user | bug_report | observation
external_signal (competitor launch, blog post, paper)
todo | cleanup | housekeeping
```

### B. Potential targets (state mutation candidates)

Inspect the input for references to :
- Active DEC IDs (DEC-1 through DEC-79 ; check `memory/index.md` for current registry)
- `strategic-frame.md` sections (Non-Goals §3, OT §6, Decision Filters §5)
- Files in `memory/architecture/`, `memory/strategy/`, `patterns/`
- `base.rules.md`, `orchestration.rules.md`, agent definitions
- Backlog stories with scope / AC / wedge / pricing / ICP impact
- Source code paths in `gaai-cloud/`, `gaai-oss/`, `workers/`
- User-facing copy (landing, emails, docs publics)

If no target identified → input is purely conversational (no mutation candidate).

### C. Domain auto-detection

```
strategy | architecture | patterns | governance | security
product_ux | pricing | content_marketing | data_model
ops_infra | tooling | bug_fix | refactor | docs
```

If multiple domains → list them all ; primary = the one most affected by mutation.
If none clear → ask the human, do not guess.

### D. Intent declaration (input or inferred)

```
drift_check  : default. Standard adversarial review against current state.
pivot        : input EXPLICITLY proposes changing direction. Reviewer mode shifts —
               Non-Goals become artefacts to interrogate, not constraints to enforce.
               Question = "is the pivot WELL-FORMED ?" (not "does it violate Non-Goals ?").
refinement   : input refines a previously-reviewed insight in same session — light review.
exploration  : input is exploratory, not yet engaging persistent state.
               Output max = DOCUMENT_ONLY or EXPERIMENT, never REJECT.
```

If `intent` not declared → default to `drift_check`.

### E. Phase 1 verdict

```
out_of_scope    → Pass-through. No mutation candidate, or mutation purely mechanical
                  (typo, lint, dep bump, mechanical refactor). Stop here.
lightweight     → Local + reversible mutation, 1 file, no DEC amendment, no Non-Goal
                  touched. Continue Phase 2 in light mode (compress §3 + §6 in 1 line).
full_review     → Touches DEC / OT / Non-Goal / strategic-frame / pattern transverse /
                  scope V1 / pricing / wedge / ICP / agent definition. Continue Phase 2.
escalate_now    → Input demands an irréversible / destructive action (drop table, delete
                  branch, force push, supersede active DEC without formal amendment).
                  STOP. Demand written human confirmation before any further processing.
```

---

## Phase 2 — Evaluation (when lightweight or full_review)

### Step 2.1 — Load domain governance

Always load :
- `.gaai/core/contexts/rules/base.rules.md`
- `.gaai/project/contexts/memory/index.md` (DEC registry — find current count + active DECs)
- `.gaai/project/contexts/memory/strategy/strategic-frame.md` (§3 Non-Goals, §5 Decision Filters, §6 Open Tensions, §8 override protocol)

Then load **domain-specific** anchors per Phase 1 detection :

| Detected domain | Mandatory reads |
|---|---|
| strategy | `strategy/mission-and-v1-wedge.md`, `strategy/pareto-product-philosophy.md` |
| architecture | `architecture/<relevant>.md` + cited DECs (read DEC files, check status field) |
| patterns | `patterns/conventions.md` + the existing pattern being amended |
| governance | `orchestration.rules.md`, `decisions/DEC-69.md`, `decisions/DEC-20.md` |
| security | `decisions/DEC-65.md`, `decisions/DEC-66.md`, `project/security-compliance-requirements.md` |
| product_ux | `strategy/positioning-layered-naming.md`, `project/brand-identity.md`, `patterns/conventions.md` |
| pricing | `decisions/DEC-71.md`, `decisions/DEC-77.md` (candidate) |
| content_marketing | `strategy/competitor-*.md`, `project/brand-identity.md`, `domains/content-production/voice-guide.md` |
| data_model | `architecture/cf-bindings-audit.md`, `decisions/DEC-3.md`, `decisions/DEC-18.md` |
| ops_infra | `decisions/DEC-3.md`, `decisions/DEC-23.md`, `decisions/DEC-64.md`, `decisions/DEC-78.md` |
| tooling | `decisions/DEC-34.md`, `architecture/claude-cli-dependency-analysis.md` |

If domain unknown → ask the human, do not invent governance docs.

### Step 2.2 — Veracity Gate (skip if zero factual claim detected)

Detect factual claims in the input — pattern-match on : product/competitor names, version numbers, dates, citations of standards (RFC/ISO/NIST/OWASP), technical capability assertions, regulatory facts, market data, benchmarks.

**If zero factual claim → skip this step.** This is the Pareto hot path — the majority of inputs (refactor, design choice between existing patterns, internal scope decisions) have no external claim and avoid verification cost entirely.

**If claims present** → for each claim, run graduated verification :

1. **Memory check** — internal_project claim → grep `.gaai/project/contexts/memory/`. Cite DEC/pattern + status (active / superseded / draft / candidate).
2. **Code + git** — technical claim on GAAI codebase → grep code + `git log`. Read DEC files cited.
3. **MCP docs tools** — claim on lib/framework → `context7` (resolve-library-id + query-docs). For Cloudflare specifics → `cloudflare` MCP. For analytics → `posthog` MCP. **Prefer these over WebSearch when domain matches** (per MCP server instructions : "fetch current documentation … even well-known ones … your training data may not reflect recent changes").
4. **WebFetch primary** — known canonical URL (RFC, MDN, vendor doc, OWASP, NIST, regulator). Cite document date.
5. **WebSearch cross-ref** — last resort. Minimum 2 independent sources (not syndicated). Reject : forums as primary, marketing pages, undated blogs, AI-generated content.

If all 5 steps fail → mark claim `UNVERIFIED`. **Do not hallucinate URLs, quotes, or dates.**

For each claim, output :
```
{
  "claim": "<neutral reformulation>",
  "type": "factual_external | technical | regulatory | benchmark | historical | internal_project | opinion",
  "criticality": "load_bearing | supporting | flavor",
  "verdict": "VERIFIED | PARTIALLY_VERIFIED | UNVERIFIED | CONTRADICTED | NEEDS_NUANCE | OUT_OF_SCOPE",
  "confidence": "high | medium | low",
  "sources": [{"url": "...", "type": "primary|secondary", "date": "YYYY-MM-DD or undated", "quote": "<literal>", "tool_call_id": "<id>"}],
  "verification_method": "memory | code | docs_tool | webfetch_primary | websearch_crossref | not_attempted"
}
```

**Anti-hallucination rules (strict)** :
- No invented URL. If you have not fetched it, `verification_method: not_attempted`.
- No paraphrased quote. Literal extract from fetched content, or empty quote field.
- No invented date. If source has no visible date → `"undated"` (never an estimate).
- One source insufficient for `load_bearing factual_external` → minimum 2 independent (not temporally clustered, not syndicated). Otherwise cap at `PARTIALLY_VERIFIED`.
- Do NOT cite the input itself as source (circular).
- Do NOT cite other LLM output as source.
- Legal / fiscal / médical / financial claims → confidence ≤ medium regardless. Note : "human expert review required".
- Stale-knowledge guard : claims on current state of products/services/pricing/versions → training data PROHIBITED as source. MUST go through context7 / WebFetch / WebSearch.
- Confidence laundering : do not reformulate a claim with more assertive tone than its source. Preserve "may", "is expected to", "in some cases".

### Step 2.3 — Decision Filters check (universal, all domains)

For each filter from `strategic-frame.md §5`, output PASS / FAIL / N/A + 1-line justification :

- **5.1 Pareto 90-day** — will a paying customer see value within 90 days, directly or as enabler ?
- **5.2 Non-goal check** — does input violate any Non-Goal in §3 ? Cite §.
- **5.3 Complexity budget** — does input exceed 1/5-day solo founder capacity (DEC-69 C-1) ?
- **5.4 ICP alignment** — serves V1 wedge or explicitly-declared V2+ upsell ?
- **5.5 Assumption disclosure** — input treats unvalidated assumption as fact ?
- **5.6 Competitor differentiation** — if Devin / Factory / Cursor bg / Claude Code Skills can do it, why GAAI ?

If `intent = pivot`, treat Non-Goals as **artefacts to interrogate**, not constraints to enforce. The question shifts from "violates ?" to "does the pivot WARRANT amending the Non-Goal ?".

### Step 2.4 — Triple verdict (the core output — replaces single ACCEPT/REJECT)

Produce 3 INDEPENDENT verdicts. **Do not collapse into one.** The human combines them.

```
veracity_verdict     : VERIFIED | NEEDS_NUANCE | CONTRADICTED | UNVERIFIABLE | NOT_APPLICABLE
fit_verdict          : ALIGNED | TENSION | VIOLATES_NON_GOAL
actionability_verdict: READY | NEEDS_REFINEMENT | TOO_VAGUE
```

Mapping to recommendation (advisory) :

| Combination | Recommendation |
|---|---|
| All 3 positive (VERIFIED + ALIGNED + READY) | **ACCEPT** |
| Veracity OK + fit TENSION + actionability READY | **EXPERIMENT** (limited, measurable, reversible) |
| Veracity NEEDS_NUANCE + fit ALIGNED + actionability NEEDS_REFINEMENT | **DEFER** (refine then re-review) |
| Veracity UNVERIFIABLE + fit unknown | **DEFER** until verifiable, OR **DOCUMENT_ONLY** |
| Veracity CONTRADICTED on load_bearing claim | **REJECT** (epistemic, not governance) |
| Fit VIOLATES_NON_GOAL without override declaration | **REJECT** (governance) |
| Intent = exploration | max = **DOCUMENT_ONLY** or **EXPERIMENT**, never REJECT |
| Intent = pivot AND well-formed (rationale + falsifiability + DECs touched) | **ACCEPT** even if Non-Goals touched (override is structural) |

### Step 2.5 — Past↔Present symmetry (mandatory question)

Always answer this mirror question BEFORE producing recommendation :

> "If this input became ground truth, which active DECs / Non-Goals / OTs would become obsolete or need revision ? What is the COST of NOT pivoting if the input is true ?"

Without this question, the reviewer is structurally biased toward status quo (confirmation bias on the corpus of past decisions). With it, both sides of the trade are visible.

### Step 2.6 — Falsifiability check

Can you write : "This input is wrong if `<signal>` measured `< Y` within delay `Z`" ?

- If YES → falsifiability passes. Note the conditions for V1+8w decision-gate or future re-eval.
- If NO → input is intuition, not hypothesis. Default to `DEFER` or `DOCUMENT_ONLY`. Cannot ACCEPT.

---

## Output Format (always JSON-compatible)

```json
{
  "skill_invocation": {
    "skill_id": "SKILL-RIN-001",
    "invoked_at": "<ISO 8601 timestamp>",
    "session_id": "<if available>",
    "input_hash": "<sha256 of input text, for idempotence within session>"
  },
  "phase_1": {
    "type": "<see §A>",
    "targets": ["<DEC-ID | path | OT-ID>"],
    "domain_primary": "<see §C>",
    "domains_secondary": ["..."],
    "intent": "drift_check | pivot | refinement | exploration",
    "classification": "out_of_scope | lightweight | full_review | escalate_now"
  },
  "phase_2": {
    "governance_loaded": ["<doc1>", "<doc2>"],
    "veracity_report": {
      "claims": [/* per Step 2.2 */],
      "load_bearing_status": "all_verified | some_unverified | some_contradicted | not_applicable",
      "summary": "<1 line>"
    },
    "decision_filters": {
      "5.1_pareto":            "PASS | FAIL | N/A",
      "5.2_non_goal":          "PASS | FAIL | N/A",
      "5.3_complexity_budget": "PASS | FAIL | N/A",
      "5.4_icp_alignment":     "PASS | FAIL | N/A",
      "5.5_assumption":        "PASS | FAIL | N/A",
      "5.6_differentiation":   "PASS | FAIL | N/A",
      "rationale": "<1 line per filter>"
    },
    "triple_verdict": {
      "veracity":      "VERIFIED | NEEDS_NUANCE | CONTRADICTED | UNVERIFIABLE | NOT_APPLICABLE",
      "fit":           "ALIGNED | TENSION | VIOLATES_NON_GOAL",
      "actionability": "READY | NEEDS_REFINEMENT | TOO_VAGUE"
    },
    "mirror_question": {
      "if_input_true_what_becomes_obsolete": ["<DEC-X>", "<Non-Goal §3.Y>"],
      "cost_of_not_pivoting": "<1 paragraph>"
    },
    "falsifiability": {
      "can_be_falsified": true,
      "condition": "<input wrong if X < Y within Z>"
    }
  },
  "recommendation": {
    "verdict": "ACCEPT | EXPERIMENT | DEFER | DOCUMENT_ONLY | REJECT",
    "confidence": "high | medium | low",
    "rationale": "<2-3 sentences>",
    "scope_minimum": "<smallest testable version, if EXPERIMENT or ACCEPT>",
    "rollback_plan": "<how to undo, if EXPERIMENT or ACCEPT>",
    "success_metrics": "<chiffrés, if EXPERIMENT or ACCEPT>",
    "dec_proposed": "<next DEC ID + level + status, if formalization needed>"
  },
  "override": {
    "available": true,
    "instructions": "Human may proceed by adding `override: { reason: \"<rationale>\", acknowledged_verdict: \"<this verdict>\", proceeds_anyway: true, logged_at: \"<timestamp>\" }` to the artefact frontmatter. Override is logged but not blocked. Pattern of overrides is reviewed quarterly per §5 self-calibration."
  },
  "self_calibration_signals": {
    "skill_invocation_count_this_session": <int>,
    "verdict_distribution_session": {"ACCEPT": 0, "EXPERIMENT": 0, "DEFER": 0, "DOCUMENT_ONLY": 0, "REJECT": 0},
    "note": "Track empirically. Healthy bands: ACCEPT 30-60%, override 5-15%, time-to-verdict P50 < 5 min, veracity_check fresh rate > 80%."
  }
}
```

---

## Anti-Patterns (the reviewer must avoid these in itself)

- ✗ ACCEPT without success metrics + falsifiability + rollback → automatically downgrade to EXPERIMENT.
- ✗ Confound novelty with improvement.
- ✗ Treat unvalidated assumption as fact (cite OT-X if relevant).
- ✗ Ignore an Open Tension because it is uncomfortable.
- ✗ Recommend structural change without citing the impacted DEC.
- ✗ Justify ACCEPT by "more modern / industry standard" without GAAI-specific value demonstrated.
- ✗ Step out of advisory role → reviewer is NOT decider. Final decision is human.
- ✗ Produce verdict in French if input feeds a governed artefact (DEC, strategic-frame edit) → English required per `base.rules.md` Language Rule.
- ✗ Hallucinated URL, quote, or date — fail loudly (`UNVERIFIABLE`) rather than fabricate.
- ✗ Symmetry skip — Step 2.5 mirror question is mandatory, not optional.
- ✗ Confirmation laundering — restating a claim with more authority than its sources.

---

## Iteration & Caching (Pareto-aware)

- **Same input within 4h same session** → light review only. Cache verdict on `input_hash`.
- **Refinement of previously-ACCEPTED input** → focus on delta only.
- **Network/MCP tool failure during veracity** → graceful degrade. Mark `verification_method: deferred`, verdict `UNVERIFIABLE` advisory, do NOT block flow. Human can override.
- **Veracity calls cap per session** : default 10 web calls. Beyond → bypass with warning ("verification budget exhausted, advisory mode"). Forces prioritization of load_bearing claims first.

---

## Self-Calibration (V1+8w decision-gate per OT-15)

Track these metrics across sessions :

| Metric | Healthy band | Anomaly action |
|---|---|---|
| ACCEPT rate / full_review inputs | 30-60 % | < 20 % over-restrictive ; > 70 % rubber-stamp. Recalibrate. |
| Override rate executed | 5-15 % | > 25 % skill miscalibrated, freezing legitimate inputs. |
| Override → outcome positive (rétro) | > 50 % | Skill too conservative if overrides systematically succeed. |
| Time-to-verdict P50 | < 5 min | Friction kills usage beyond. |
| Veracity report fresh rate | > 80 % | Stale sources = epistemic decay. |
| Skill invocations / 30 days | > 5 | Real usage signal for OT-15 escalation to Phase 2. |

These metrics inform the **decision-gate at V1+8 weeks** (per OT-15 + §3.4 chiffré Non-Goal) on whether to escalate to Phase 2 enforcement (max 5 stories cap) or archive Prompts A/B as research preserved.

---

## Reference Artefacts (deferred, do not invoke unless decision-gate triggered)

- `.gaai/project/contexts/artefacts/research/anti-girouette-guardrail/README.md` — design context + decision-gate criteria
- `.gaai/project/contexts/artefacts/research/anti-girouette-guardrail/enforcement-prompts-deferred.md` — Prompt A (OSS hooks/skills/sub-agents enforcement design), Prompt B (Cloud hard gates + drift detector + soft-gate-as-instruction injection design), Veracity Sub-Agent prompt (isolated verification agent design)

These are NOT part of V1 scope. They are research preserved against the case where empirical data at V1+8w justifies escalation.

---

## Final Rule

> The reviewer eclaire the human ; it does not decide. Three verdicts independent, never one. Sources real, never hallucinated. Override is first-class, traced not gated. Pivot well-formed > status quo by inertia.

→ [Back to discovery skills](../README.md)
