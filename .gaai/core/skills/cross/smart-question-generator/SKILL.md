---
name: smart-question-generator
description: Takes aggregated ambiguity insights from the LLM synthesis stage and produces ≤5 ranked questions to surface to the user. Applies a two-layer anti-fabrication filter (pre-LLM exclusion of score<3 insights + post-LLM structural strip) so that Q&A surfaces only genuine ambiguities. Used as Stage 4 of the /gaai:bootstrap pipeline.
license: ELv2
compatibility: Works with any OpenAI-compatible LLM API from an AI coding agent context
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-SMART-QUESTION-GENERATOR-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - ambiguity_feed        # Array<{topic, ambiguity_score, evidence_pro[], evidence_against[]}>
  - anthropic_api_key     # BYOK — from local Claude Code env
outputs:
  - question_result       # {questions[], error, fallback}
---

# Smart Question Generator

## Purpose / When to Activate

Activate:
- As Stage 4 of the `/gaai:bootstrap` pipeline, after `bootstrap-llm-synthesis` produces entries with `clarity: open-question`
- The bootstrap orchestrator transforms `open-question` entries from `synthesis_result.entries[]` into the `ambiguity_feed` input (mapping `content` → `topic`, assigning `ambiguity_score` from its own confidence heuristic, populating `evidence_pro[]`/`evidence_against[]` from `source[]` fields)
- When `ambiguity_feed` is empty or all scores are <3, this skill returns `{questions: [], error: null, fallback: false}` — not an error, a legitimate empty result
- Re-run is NOT expected: one call per bootstrap session (Q&A is one-shot per Stage 4 invocation)

---

## Input Schema

```yaml
ambiguity_feed: Array of insight objects, each:
  topic: string                   — short label for the ambiguity (e.g. "project_type")
  ambiguity_score: number (1–10)  — raw confidence gap; higher = more ambiguous
  evidence_pro: Array<{
    source: string,               — file:path:line or descriptor
    snippet: string,              — relevant excerpt from the source
    weight: number                — 0.0–1.0 relative weight of this piece of evidence
  }>
  evidence_against: Array<{
    source: string,
    snippet: string,
    weight: number
  }>
```

**Input constraint:** insights are provided as-is from the synthesis stage; the skill does NOT validate `ambiguity_score` range beyond the ≥3 threshold applied in the pre-filter.

---

## Process

### Step 1 — Pre-filter: exclude low-confidence insights (AC4 — CLIENT-SIDE, before LLM call)

This is deterministic code, NOT a prompt instruction. It executes before the LLM call (DEC-13: client-side filter; DEC-48: orchestrator-enforced).

```
eligible_insights = ambiguity_feed.filter(i => i.ambiguity_score >= 3)

log: "[smart-question-generator] pre-filter: {ambiguity_feed.length} insights in, {eligible_insights.length} eligible (score>=3)"

if eligible_insights.length == 0:
  log: "[smart-question-generator] no eligible insights — returning legitimate empty"
  return {questions: [], error: null, fallback: false}
```

### Step 2 — Build question-generation prompt

Construct the LLM prompt using only `eligible_insights` (the pre-filtered array).

Apply `cache_control: {type: "ephemeral"}` on the system prompt block (DEC-82 Principle 11 — prompt caching at static prefixes).

**System prompt (static — cache this block):**

```
You are a precise technical interviewer. Your task is to convert a set of code analysis
ambiguities into clear, specific questions to ask a developer about their project.

Requirements:
- Produce AT MOST 5 questions. Never produce more than the number of eligible insights.
- Each question must correspond to exactly one insight topic from the input.
- Questions must be actionable: the developer's answer must be able to resolve the ambiguity.
- Prefer finite-choice questions where the options are bounded (e.g. "Is this a SaaS, library,
  or CLI?"). For open-ended ambiguities, use open questions.
- For finite-choice questions, populate the "options" array. For open-ended, omit "options".
- ONLY generate questions for topics you were given. Do not invent new topics.
- Do NOT ask questions about topics with low ambiguity scores. All topics in this input
  are already filtered to score >= 3, but apply editorial judgment — if two insights overlap,
  merge them into one question.

Output format: a JSON array. Each element:
{
  "question_text": "<the question to ask the user, ≤ 200 chars>",
  "topic": "<must match the topic field from the input insight exactly>",
  "severity": <copy the ambiguity_score integer from the matching input insight>,
  "options": [{"label": "<human label>", "value": "<machine value>"}]  // omit if open-ended
}

Return ONLY the JSON array. No prose before or after. No code fences.
```

**User message (dynamic — include eligible_insights):**

```
Generate questions for the following project ambiguities.

## Ambiguity insights to resolve
{for insight in eligible_insights}
- topic: {insight.topic}
  ambiguity_score: {insight.ambiguity_score}
  evidence_pro:
    {for ep in insight.evidence_pro}
    - source: {ep.source} | snippet: "{ep.snippet}" | weight: {ep.weight}
    {endfor}
  evidence_against:
    {for ea in insight.evidence_against}
    - source: {ea.source} | snippet: "{ea.snippet}" | weight: {ea.weight}
    {endfor}
{endfor}

Produce at most {min(5, eligible_insights.length)} questions now.
```

**Token budget estimate:** with ≤7 eligible insights (post pre-filter) and snippet lengths bounded to ~100 chars, prompt is well within 5k input token budget per DEC-82 Principle 2.

### Step 3 — LLM call with failure handling (AC5)

```
Call Anthropic Messages API:
  max_tokens: 1024       # questions are short; 1024 is sufficient
  temperature: 0         # deterministic for consistency
  system: <static prompt above with cache_control: {type: "ephemeral"}>

Error semantics:
  NetworkError / ServiceUnavailableError:
    → return {questions: [], error: 'llm_call_failed', fallback: true}
  TimeoutError (explicitly >30s):
    → return {questions: [], error: 'llm_timeout', fallback: true}
  JSON.parse fails on response:
    → return {questions: [], error: 'llm_parse_failed', fallback: true}
  AuthenticationError / InvalidRequestError:
    → raise immediately (non-retryable, infrastructure misconfiguration)
```

**No retry on this skill** — bootstrap Q&A is session-interactive. A retry delay would stall the user. A single call with explicit failure semantics is the correct contract: the orchestrator handles degraded mode (`fallback: true` → skip Q&A → continue with `clarity: open-question` flagged entries).

Log on failure: `[smart-question-generator] LLM call failed: {error_code} — returning fallback=true`

### Step 4 — Parse LLM response

Apply tolerant parsing (same pattern as `bootstrap-llm-synthesis`):

```
1. Strip leading/trailing whitespace
2. If starts with "```": extract content between first "```" and last "```"
   (handle both ```json and ``` variants)
3. Strip any trailing comma before closing `]`
4. Attempt JSON.parse
5. If parse fails → return {questions: [], error: 'llm_parse_failed', fallback: true}
```

**Schema validation per parsed element:**

```
required_fields = ["question_text", "topic", "severity"]
valid_topic_values = Set(eligible_insights.map(i => i.topic))   # exact match against input

for item in parsed_array:
  errors = []
  if missing required_field: errors += ["missing: {field}"]
  if item.topic not in valid_topic_values: errors += ["unknown topic: {item.topic}"]
  if typeof item.severity != "number": errors += ["severity must be number"]

  if errors is empty:
    valid_questions.push(item)
  else:
    log: "[smart-question-generator] question dropped (schema error): {errors}"
    # drop silently — do not abort
```

### Step 5 — Post-generation structural filter (AC4 — CLIENT-SIDE, after LLM call)

This is the second layer of the anti-fabrication filter. Deterministic code, runs after LLM returns.

```
# Build lookup from original ambiguity_feed (pre-filter) for topic→ambiguity_score
score_lookup = { i.topic: i.ambiguity_score for i in ambiguity_feed }

# Strip any question whose topic maps to score < 3 in the original input
# (defense-in-depth: the pre-filter should have caught these, but the LLM
# might still mention topics not in eligible_insights if it "remembers" context)
filtered_questions = valid_questions.filter(q => {
  score = score_lookup[q.topic] ?? 0
  if score < 3:
    log: "[smart-question-generator] post-filter: dropped question for topic '{q.topic}' (score={score} < 3)"
    return false
  return true
})

# E107bS04: Sort by severity desc → topic_importance desc → topic alphabetical asc
# BEFORE applying the cap, so the top-5 are deterministic.
TOPIC_IMPORTANCE_ORDER = {project_type: 3, architecture: 2, naming: 1}  # others: 0

has_tie = any two questions share the same severity
filtered_questions = filtered_questions.sort((a, b) => {
  severity_diff = b.severity - a.severity
  if severity_diff != 0: return severity_diff
  importance_diff = (TOPIC_IMPORTANCE_ORDER[b.topic] ?? 0) - (TOPIC_IMPORTANCE_ORDER[a.topic] ?? 0)
  if importance_diff != 0: return importance_diff
  return a.topic.localeCompare(b.topic)
})
if has_tie:
  log: "[smart-question-generator] severity tie-break applied: topic_importance (project_type>architecture>naming>others) then alphabetical"

# Enforce ≤5 cap (AC4, AC2) — applied after sort so top-5 are highest-severity
if filtered_questions.length > 5:
  log: "[smart-question-generator] WARNING: LLM returned {valid_questions.length} questions — capped at 5"
  filtered_questions = filtered_questions[0:5]

# AC3 enforcement — severity identity mapping
# severity MUST equal the original ambiguity_score from the input insight
# If the LLM populated a different value, correct it silently
for q in filtered_questions:
  original_score = score_lookup[q.topic]
  if q.severity != original_score:
    log: "[smart-question-generator] severity corrected for topic '{q.topic}': {q.severity} → {original_score}"
    q.severity = original_score

# Quality check: strip empty options arrays (options must be non-empty or absent)
for q in filtered_questions:
  if q.options exists and q.options.length == 0:
    log: "[smart-question-generator] empty options stripped for topic '{q.topic}'"
    delete q.options
```

### Step 6 — Build output and observability summary (AC7)

```
question_result = {
  questions: filtered_questions,
  error: null,
  fallback: false
}

# Observability counters (AC7) — three distinct counters, kept separate
obs = {
  questions_generated:    valid_questions.length,     # after schema validation, before post-filter
  questions_filtered:     valid_questions.length - filtered_questions.length,  # removed by post-filter + cap
  questions_returned:     filtered_questions.length,
  llm_failure:            false,
  pre_filter_excluded:    ambiguity_feed.length - eligible_insights.length
}

log (stdout):
[smart-question-generator] complete
  ambiguity feed: {ambiguity_feed.length} insights ({eligible_insights.length} eligible, {obs.pre_filter_excluded} pre-filtered)
  questions: {obs.questions_generated} generated → {obs.questions_filtered} post-filtered → {obs.questions_returned} returned
  llm_failure: {obs.llm_failure}
```

**On LLM failure path:** `llm_failure: true` with specific error code. `questions_generated` / `questions_filtered` = 0. These are separate from `pre_filter_excluded` (pre-LLM) and are separate from `questions_returned == 0` on legitimate empty (where `llm_failure == false`).

---

## Output Schema (`question_result`)

```yaml
# Success — with questions
question_result:
  questions:
    - question_text: "Is this project a SaaS web app, a CLI tool, or a library?"
      topic: "project_type"
      severity: 8
      options:
        - label: "SaaS web app"
          value: "saas"
        - label: "CLI tool"
          value: "cli"
        - label: "Library / SDK"
          value: "library"
    - question_text: "What is the primary deployment target?"
      topic: "deployment_target"
      severity: 6
      # no options — open-ended question
  error: null
  fallback: false

# LLM failure
question_result:
  questions: []
  error: "llm_call_failed"    # or "llm_parse_failed" or "llm_timeout"
  fallback: true

# Legitimate empty (all scores < 3 — no LLM call made)
question_result:
  questions: []
  error: null
  fallback: false
```

---

## Quality Checks

Before returning `question_result`, verify:
- `fallback: false` and `error: null` → `questions` is a valid array (possibly empty)
- `fallback: true` always paired with a non-null `error` string
- Every question in `questions` has `topic` present in original `ambiguity_feed` at score ≥ 3
- `severity` equals `ambiguity_score` from the original input (identity mapping — enforced in Step 5)
- `questions.length` ≤ 5 always (enforced in Step 5)
- `options` is either a non-empty array of `{label, value}` objects OR absent (never an empty array)

---

## Non-Goals

This skill must NOT:
- Write to memory directly (memory ingest is the orchestrator's responsibility post-consent gate)
- Ask the user questions itself — it produces questions, the orchestrator presents them
- Rank questions by topic importance (topic-importance weighting is E107bS04 tie-breaker's exclusive concern per AC3)
- Handle Q&A answer collection (that is the orchestrator's job in Stage 4)
- Re-synthesize memory entries (use `bootstrap-llm-synthesis` for that)
- Apply multi-turn conversation state — this skill is stateless, called once per bootstrap session
- Accept more than one LLM call attempt (unlike `bootstrap-llm-synthesis`, no retry — the Q&A stage is user-interactive and retry delay creates bad UX)

**Severity = identity mapping only.** No topic-importance scoring in this skill.
