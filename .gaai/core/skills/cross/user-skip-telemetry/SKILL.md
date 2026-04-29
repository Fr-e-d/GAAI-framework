---
name: user-skip-telemetry
description: Counts Q&A skip events from the abort-safe-handler and qa-loop-ui outputs. Shows an optional skip-reason dropdown when a user-initiated skip occurred. Produces a structured skip_metrics_record suitable for PostHog ingestion. Used in Stage 4 of the /gaai:bootstrap pipeline after abort-safe-handler returns.
license: ELv2
compatibility: Works in any interactive AI coding agent context (Claude Code, Cursor) where inline Q&A is supported
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-USER-SKIP-TELEMETRY-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - abort_safe_result     # output of abort-safe-handler — contains skip_telemetry
  - qa_session_result     # output of qa-loop-ui — optional; null when user skipped at entry gate
  - workspace_id          # string — workspace scope
  - workspace_size_class  # optional string: "solo" | "small" | "medium" | null
outputs:
  - skip_metrics_record   # structured telemetry record for PostHog ingestion
---

# User-Skip Telemetry

## Purpose / When to Activate

Activate:
- Immediately after `abort-safe-handler` returns — the orchestrator invokes this skill to capture skip event counts before proceeding to synthesis
- Works for all return paths: pre-loop skip, mid-loop skip-all, per-question skips, and no-skip sessions
- One invocation per bootstrap session

When `abort_safe_result.abort_reason == "no_questions"` (no questions were generated), return a
`{skip_occurred: false, skip_type: "no_questions"}` record with zero counts. No reason dropdown is
shown (no user-facing skip choice was presented).

**What this skill does NOT do:**
- Persist or accumulate counts across sessions (orchestrator responsibility — forward to PostHog)
- Display Q&A questions (that is `qa-loop-ui`)
- Wrap or gate the Q&A loop (that is `abort-safe-handler`)
- Enrich or analyse skip patterns across workspaces (V1.5+ analytics)

---

## Input Schema

```yaml
abort_safe_result:
  skipped: bool
  qa_answers: array | null
  skip_telemetry:                        # null only on no-questions shortcut
    skip_reason: string | null           # "user_skip_entire" | "user_abort" | null
    skipped_at: string | null            # ISO 8601 UTC
    workspace_id: string
    response_time_ms: number | null
  abort_reason: string | null            # "user_abort" | "no_questions" | null

qa_session_result:                       # null when skipped at entry gate
  answers:
    - question_id: string
      answer_text: string
      skipped: bool
      response_time_ms: number
  partial: bool
  skipped_all: bool
  abort_reason: string | null
  qa_duration_ms: number

workspace_id: string
workspace_size_class: string | null      # "solo" | "small" | "medium" | null
```

---

## Process

### Step 0 — No-questions shortcut

```
if abort_safe_result.abort_reason == "no_questions":
  log: "[user-skip-telemetry] no questions were generated — Stage 4 was a no-op"
  return {
    skip_occurred: false,
    skip_type: "no_questions",
    skip_reason: null,
    per_question_skips: [],
    questions_presented: 0,
    questions_skipped: 0,
    questions_answered: 0,
    workspace_id: workspace_id,
    workspace_size_class: workspace_size_class ?? null,
    recorded_at: iso_timestamp()
  }
```

### Step 1 — Classify skip type

Determine `skip_type` using the following priority order:

```
if abort_safe_result.skip_telemetry?.skip_reason == "user_abort":
  skip_type = "user_abort"             # involuntary — Ctrl+C / context terminated

elif abort_safe_result.skip_telemetry?.skip_reason == "user_skip_entire":
  skip_type = "pre_loop"               # user chose [N] at the Stage 4 entry gate

elif qa_session_result != null AND qa_session_result.skipped_all == true:
  skip_type = "mid_loop_skip_all"      # user typed "skip all" during the Q&A loop

elif qa_session_result != null AND
     qa_session_result.answers.some(a => a.skipped == true):
  skip_type = "per_question_only"      # some questions skipped individually, no skip-all

else:
  skip_type = "none"                   # user answered all questions
```

Log classification:
```
log: "[user-skip-telemetry] skip_type={skip_type}  workspace_id={workspace_id}"
```

### Step 2 — Per-question skip metrics (AC1)

Compute per-question metrics from `qa_session_result.answers` if available. **Record position only —
no question content or question_id text must appear in the metrics record** (privacy-respecting aggregate).

```
per_question_skips = []
questions_presented = 0
questions_skipped = 0
questions_answered = 0

if qa_session_result != null AND qa_session_result.answers != null:
  for i, answer in enumerate(qa_session_result.answers):
    questions_presented++
    if answer.skipped == true:
      questions_skipped++
      per_question_skips.push({position: i + 1, skipped: true})
    else:
      questions_answered++
      per_question_skips.push({position: i + 1, skipped: false})
```

`per_question_skips` contains only position integers and boolean flags — no text, no topic names,
no question IDs that could be reverse-mapped to question content.

### Step 3 — Optional reason capture (AC2)

Show the reason dropdown ONLY when skip_type is `"pre_loop"` or `"mid_loop_skip_all"` (user made
a deliberate skip choice). Do NOT show for `"user_abort"` (involuntary) or `"per_question_only"`
(individual question skips, covered by per_question_skips already) or `"none"`.

```
skip_reason = null

if skip_type == "pre_loop" OR skip_type == "mid_loop_skip_all":
  display:
    "(Optional) Why did you skip the Q&A? Press Enter to skip this.
       1. not relevant
       2. too vague
       3. time-pressed
       4. other"

  raw_input = trim(await_user_input())
  normalized = lowercase(raw_input)

  skip_reason = match normalized:
    "1" | "not relevant"  → "not_relevant"
    "2" | "too vague"     → "too_vague"
    "3" | "time-pressed"  → "time_pressed"
    "4" | "other"         → "other"
    ""                    → null    # user skipped the reason prompt
    _                     → null    # unrecognised input treated as no reason
```

If `skip_type` is NOT `"pre_loop"` or `"mid_loop_skip_all"`, set `skip_reason = null` and do NOT
prompt the user.

### Step 4 — Produce skip_metrics_record (AC3)

```
recorded_at = iso_timestamp()

skip_metrics_record = {
  event: "bootstrap.qa_skip",
  skip_occurred: (skip_type != "none" AND skip_type != "no_questions"),
  skip_type: skip_type,
  skip_reason: skip_reason,
  per_question_skips: per_question_skips,
  questions_presented: questions_presented,
  questions_skipped: questions_skipped,
  questions_answered: questions_answered,
  workspace_id: workspace_id,
  workspace_size_class: workspace_size_class ?? null,
  recorded_at: recorded_at
}

log: "[user-skip-telemetry] metrics record produced:
  skip_type={skip_type}  skip_reason={skip_reason ?? "none"}
  questions={questions_presented}  skipped={questions_skipped}  answered={questions_answered}"

return skip_metrics_record
```

---

## Orchestrator responsibility after this skill (AC3)

The orchestrator MUST forward `skip_metrics_record` to PostHog as a fire-and-forget event:

```
gaai_admin(action: "log_posthog",
           event: skip_metrics_record.event,
           props: skip_metrics_record)
```

This call is non-blocking. If PostHog is unreachable or `POSTHOG_API_KEY` is absent, the event is
silently dropped — never block bootstrap continuation on telemetry delivery.

The orchestrator then proceeds to `bootstrap-llm-synthesis` regardless of telemetry outcome.

---

## Output Schema

```yaml
skip_metrics_record:
  event: "bootstrap.qa_skip"           # PostHog event name
  skip_occurred: bool                  # false only for "none" and "no_questions" skip_types
  skip_type:
    "pre_loop"         # user chose [N] at the Stage 4 entry gate
    | "mid_loop_skip_all"   # user typed "skip all" during Q&A loop
    | "per_question_only"   # some individual questions skipped, no skip-all
    | "none"                # user answered all questions
    | "user_abort"          # involuntary — Ctrl+C / process signal
    | "no_questions"        # no questions were generated; Stage 4 was skipped entirely
  skip_reason: "not_relevant" | "too_vague" | "time_pressed" | "other" | null
  per_question_skips:
    - position: number    # 1-based question index — NO question content
      skipped: bool
  questions_presented: number
  questions_skipped: number
  questions_answered: number
  workspace_id: string
  workspace_size_class: "solo" | "small" | "medium" | null
  recorded_at: string     # ISO 8601 UTC

# Example — pre-loop skip with reason:
skip_metrics_record:
  event: "bootstrap.qa_skip"
  skip_occurred: true
  skip_type: "pre_loop"
  skip_reason: "time_pressed"
  per_question_skips: []
  questions_presented: 0
  questions_skipped: 0
  questions_answered: 0
  workspace_id: "ws_abc123"
  workspace_size_class: "solo"
  recorded_at: "2026-04-29T10:32:15Z"

# Example — user answered 3 of 4 questions, skipped 1:
skip_metrics_record:
  event: "bootstrap.qa_skip"
  skip_occurred: true
  skip_type: "per_question_only"
  skip_reason: null             # no dropdown shown for per-question-only skips
  per_question_skips:
    - {position: 1, skipped: false}
    - {position: 2, skipped: true}
    - {position: 3, skipped: false}
    - {position: 4, skipped: false}
  questions_presented: 4
  questions_skipped: 1
  questions_answered: 3
  workspace_id: "ws_abc123"
  workspace_size_class: null
  recorded_at: "2026-04-29T10:40:22Z"

# Example — user answered all 3 questions (no skip):
skip_metrics_record:
  event: "bootstrap.qa_skip"
  skip_occurred: false
  skip_type: "none"
  skip_reason: null
  per_question_skips:
    - {position: 1, skipped: false}
    - {position: 2, skipped: false}
    - {position: 3, skipped: false}
  questions_presented: 3
  questions_skipped: 0
  questions_answered: 3
  workspace_id: "ws_abc123"
  workspace_size_class: "small"
  recorded_at: "2026-04-29T10:45:00Z"
```

---

## Quality Checks

- `skip_occurred: true` implies `skip_type` is NOT `"none"` and NOT `"no_questions"`
- `skip_type: "pre_loop"` implies `per_question_skips == []` and `questions_presented == 0`
- `skip_type: "no_questions"` implies all counts are 0 and `per_question_skips == []`
- `skip_reason` is non-null ONLY for `skip_type` in `["pre_loop", "mid_loop_skip_all"]`
- `questions_skipped + questions_answered == questions_presented`
- `per_question_skips.length == questions_presented`
- `per_question_skips[i].position` is 1-based and sequential (1, 2, 3, …)
- No `question_id`, `question_text`, `topic`, or `answer_text` fields in `per_question_skips`
- `recorded_at` is always a non-null ISO 8601 UTC string

---

## Non-Goals

This skill MUST NOT:
- Aggregate or persist skip counts across multiple bootstrap sessions (orchestrator / PostHog responsibility)
- Compare skip rates across workspaces or flag anomalies (V1.5+ analytics)
- Block bootstrap continuation when PostHog delivery fails (fire-and-forget, non-blocking)
- Capture answer content or question text in the metrics record (privacy invariant)
- Prompt for skip reason on `"user_abort"` or `"per_question_only"` skip types
- Invoke `abort-safe-handler` or `qa-loop-ui` (this skill is post-loop only)
- Make governance decisions based on skip patterns (observe, not decide — DEC-82 Principle 1)
