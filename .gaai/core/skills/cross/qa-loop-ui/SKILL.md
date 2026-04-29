---
name: qa-loop-ui
description: Presents up to 5 questions from smart-question-generator one at a time, records answers, handles per-question skip and skip-all, captures per-question response time and total session duration. Renders a streaming progress header with question count and time estimate. Used as the interaction layer of Stage 4 of the /gaai:bootstrap pipeline.
license: ELv2
compatibility: Works in any interactive AI coding agent context (Claude Code, Cursor) where inline Q&A is supported
metadata:
  author: gaai-framework
  version: "1.1"
  category: cross
  track: cross-cutting
  id: SKILL-QA-LOOP-UI-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - question_result       # {questions[], error, fallback} — output of smart-question-generator
outputs:
  - qa_session_result     # {answers[], partial: bool, skipped_all: bool, abort_reason: string|null, qa_duration_ms: number}
---

# Q&A Loop UI

## Purpose / When to Activate

Activate:
- As Stage 4 of the `/gaai:bootstrap` pipeline, immediately after `smart-question-generator` returns a `question_result` with `questions.length > 0`
- When the bootstrap orchestrator needs to surface ambiguities as a conversational Q&A with the user
- Re-run is NOT expected: one call per bootstrap session (Q&A is one-shot)

When `question_result.questions` is empty (legitimate empty OR fallback), the orchestrator MUST skip this skill entirely and proceed to Stage 5 — do NOT activate with empty questions.

---

## Input Schema

```yaml
question_result:
  questions:                   # from smart-question-generator — already ≤5 items
    - question_text: string    # ≤200 chars
      topic: string            # used as question_id in answers output
      severity: number         # 1–10 — not shown to user; used for future sorting
      options:                 # optional — omitted for open-ended questions
        - label: string        # human-readable option label
          value: string        # machine value
  error: string | null
  fallback: bool
```

**Precondition check (before entering loop):**

```
if question_result.questions.length == 0:
  log: "[qa-loop-ui] no questions to ask — skip loop"
  return {answers: [], partial: false, skipped_all: false, abort_reason: "no_questions", qa_duration_ms: 0}
```

---

## Process

### Step 1 — Initialize session

```
session_start_ts = current_timestamp_ms()
answers = []
current_index = 0
total_questions = question_result.questions.length
```

Display intro message to user (inline, before first question):

```
Bootstrap found {total_questions} point(s) needing clarification.
I'll ask up to {total_questions} question(s) — you can type "skip" to skip a question
or "skip all" to skip the entire Q&A.
```

### Step 2 — Question loop (sequential)

For each question at `current_index` in `question_result.questions`:

#### Step 2a — Compute time estimate (AC2)

Compute a best-effort estimate of time remaining before displaying the question:

```
if current_index >= 1:
  # Use elapsed time over completed questions as running average
  elapsed_ms = current_timestamp_ms() - session_start_ts
  avg_per_q_ms = elapsed_ms / current_index
  questions_left = total_questions - current_index   # includes current question
  estimated_remaining_ms = questions_left * avg_per_q_ms
  estimated_remaining_s = Math.ceil(estimated_remaining_ms / 1000)
  rounded_s = Math.max(5, Math.ceil(estimated_remaining_s / 5) * 5)  # round up to nearest 5s

  if rounded_s < 60:
    time_label = "  |  ~{rounded_s}s remaining"
  else:
    time_label = "  |  ~<{Math.ceil(rounded_s / 60)} min remaining"
else:
  time_label = ""   # no estimate for the first question
```

#### Step 2b — Display question with progress header (AC1)

Display the progress header and active question in bold, then options if applicable:

**Without options (open-ended):**

```
**📋 Q&A Progress — Question {current_index + 1} of {total_questions}{time_label}**

**{question.question_text}**
```

**With options:**

```
**📋 Q&A Progress — Question {current_index + 1} of {total_questions}{time_label}**

**{question.question_text}**

Options:
  {for i, opt in enumerate(question.options)}
  {i+1}. {opt.label}  ({opt.value})
  {endfor}

(Type your answer, a number to pick an option, "skip", or "skip all")
```

#### Step 2c — Record question start time

```
question_start_ts = current_timestamp_ms()
```

#### Step 2d — Wait for user input

Await one line of user input. Trim leading/trailing whitespace from the response.

#### Step 2e — Classify response

```
raw_input = trim(user_input)
normalized = lowercase(raw_input)

if normalized == "skip all" OR normalized == "s all":
  # User wants to exit the entire Q&A loop early
  log: "[qa-loop-ui] user requested skip-all at question {current_index + 1}/{total_questions}"
  response_time_ms = current_timestamp_ms() - question_start_ts
  # Record the current question as skipped before exiting
  answers.push({
    question_id: question.topic,
    answer_text: "",
    skipped: true,
    response_time_ms: response_time_ms
  })
  qa_duration_ms = current_timestamp_ms() - session_start_ts
  return {
    answers: answers,
    partial: true,          # not all questions were presented
    skipped_all: true,
    abort_reason: null,
    qa_duration_ms: qa_duration_ms
  }

elif normalized == "skip" OR normalized == "s" OR normalized == "":
  # User is skipping this specific question
  log: "[qa-loop-ui] question '{question.topic}' skipped by user"
  response_time_ms = current_timestamp_ms() - question_start_ts
  answers.push({
    question_id: question.topic,
    answer_text: "",
    skipped: true,
    response_time_ms: response_time_ms
  })
  current_index++
  continue  # advance to next question

else:
  # User provided an answer
  response_time_ms = current_timestamp_ms() - question_start_ts

  # For option-choice questions: normalize numeric input to value
  resolved_answer = raw_input
  if question.options is present AND raw_input is a digit string:
    option_index = parseInt(raw_input) - 1   # 1-based to 0-based
    if option_index >= 0 AND option_index < question.options.length:
      resolved_answer = question.options[option_index].value
      log: "[qa-loop-ui] option choice for '{question.topic}': input={raw_input} → value={resolved_answer}"
    else:
      # Out of range — treat raw input as free-text answer
      log: "[qa-loop-ui] option index out of range for '{question.topic}' (input={raw_input}) — using raw text"

  answers.push({
    question_id: question.topic,
    answer_text: resolved_answer,
    skipped: false,
    response_time_ms: response_time_ms
  })
  current_index++
  continue  # advance to next question
```

### Step 3 — Complete loop

When all questions have been presented and answered (or skipped individually):

```
qa_duration_ms = current_timestamp_ms() - session_start_ts
skipped_count = answers.filter(a => a.skipped).length
answered_count = answers.filter(a => !a.skipped).length
log: "[qa-loop-ui] Q&A complete — {answers.length} answers recorded ({skipped_count} skipped, {answered_count} answered), duration={qa_duration_ms}ms"

return {
  answers: answers,
  partial: false,
  skipped_all: false,
  abort_reason: null,
  qa_duration_ms: qa_duration_ms
}
```

### Step 4 — Abort handling (AC5)

If the user terminates the session mid-loop (e.g., Ctrl+C, process signal, or the agent context
is interrupted before all questions are answered), the partially-collected `answers[]` array MUST
be preserved as-is. The orchestrator receives whatever answers were collected up to the interrupt.

Abort is signaled by catching the interrupt and returning:

```
qa_duration_ms = current_timestamp_ms() - session_start_ts
return {
  answers: answers,         # partial — contains only answers collected before abort
  partial: true,
  skipped_all: false,
  abort_reason: "user_abort",
  qa_duration_ms: qa_duration_ms
}
```

**Critical:** never discard partial answers on abort. The orchestrator can use partial Q&A answers
for a degraded-mode synthesis pass via `bootstrap-llm-synthesis` (the `qa_answers` input accepts
partial arrays).

---

## Orchestrator responsibility after this skill (AC3)

After receiving `qa_session_result`, the orchestrator MUST log the Q&A session duration per workspace:

```
gaai_admin(action: "log_qa_session", qa_duration_ms: qa_session_result.qa_duration_ms)
```

This applies on ALL return paths (normal completion, skip-all, abort, no-questions shortcut).
When `qa_duration_ms == 0` (no-questions shortcut), the log is still emitted — it records that
Stage 4 was a no-op, which is a useful observability signal.

---

## Output Schema

```yaml
qa_session_result:
  answers:
    - question_id: string         # equals topic from input question
      answer_text: string         # "" if skipped
      skipped: bool
      response_time_ms: number    # milliseconds from question display to input received
  partial: bool                   # true if loop ended before all questions presented
  skipped_all: bool               # true if user invoked "skip all"
  abort_reason: string | null     # "user_abort" | "no_questions" | null (null = normal completion)
  qa_duration_ms: number          # total milliseconds from session_start_ts to return; 0 for no-questions path

# Normal completion example:
qa_session_result:
  answers:
    - question_id: "project_type"
      answer_text: "saas"
      skipped: false
      response_time_ms: 3200
    - question_id: "deployment_target"
      answer_text: ""
      skipped: true
      response_time_ms: 1100
  partial: false
  skipped_all: false
  abort_reason: null
  qa_duration_ms: 18500

# Skip-all example (triggered at question 2 of 3):
qa_session_result:
  answers:
    - question_id: "project_type"
      answer_text: "saas"
      skipped: false
      response_time_ms: 4500
    - question_id: "deployment_target"
      answer_text: ""
      skipped: true
      response_time_ms: 890
  partial: true
  skipped_all: true
  abort_reason: null
  qa_duration_ms: 9100

# Abort example (mid-loop):
qa_session_result:
  answers:
    - question_id: "project_type"
      answer_text: "library"
      skipped: false
      response_time_ms: 6200
  partial: true
  skipped_all: false
  abort_reason: "user_abort"
  qa_duration_ms: 7800
```

---

## Quality Checks

- `partial: true` implies `answers.length < question_result.questions.length`
- `skipped_all: true` implies `partial: true`
- `abort_reason: null` when `partial: false` (clean completion)
- Every entry in `answers` has `question_id` matching a `topic` from the input `question_result.questions`
- `skipped: true` always paired with `answer_text: ""`
- `skipped: false` always paired with non-empty `answer_text`
- `response_time_ms` is always a non-negative integer (≥ 0)
- `answers.length` ≤ `question_result.questions.length` (never more answers than questions)
- `qa_duration_ms` is always a non-negative integer (≥ 0); 0 only on no-questions shortcut
- `qa_duration_ms` ≥ sum of all `response_time_ms` entries (session duration includes display time)

---

## Non-Goals

This skill MUST NOT:
- Generate questions (that is `smart-question-generator`'s responsibility)
- Write to memory directly (memory ingest is the orchestrator's responsibility post-consent gate)
- Rank or re-order questions (that is `topic-importance-ranker` / E107bS04's concern)
- Validate answer content for semantic correctness (answers are user-stated, treated as `declared-by-user` by `bootstrap-llm-synthesis`)
- Handle the "skip all" abort path as a separate code path requiring external coordination (per AC3 / E107bS05 note: the skip-all handler is self-contained in this skill; E107bS05 provides the orchestrator-level abort-safe wrapper)
- Re-run the Q&A loop after completion (one-shot per bootstrap session)
- Apply timeouts to individual questions (patience is left to user; no auto-skip on silence)
- Call the LLM (this is a pure interaction skill; no inference calls)
- Call `log_qa_session` itself (orchestrator responsibility — see §Orchestrator responsibility above)
