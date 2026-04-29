---
name: abort-safe-handler
description: Orchestrator-level Stage 4 entry gate for /gaai:bootstrap. Presents a pre-loop "Skip Q&A entirely" option, delegates to qa-loop-ui when the user proceeds, and returns a unified abort_safe_result with telemetry on every path. Guarantees no partial state on skip or abort.
license: ELv2
compatibility: Works in any interactive AI coding agent context (Claude Code, Cursor) where inline Q&A is supported
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-ABORT-SAFE-HANDLER-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - question_result     # {questions[], error, fallback} — output of smart-question-generator
  - workspace_id        # string — workspace scope for per-workspace telemetry (AC5)
outputs:
  - abort_safe_result   # {skipped, qa_answers, skip_telemetry, abort_reason}
---

# Abort-Safe Handler

## Purpose / When to Activate

Activate:
- As the **Stage 4 entry gate** of the `/gaai:bootstrap` pipeline, immediately after `smart-question-generator` returns a `question_result`
- Before `qa-loop-ui` is invoked — this skill decides WHETHER the loop runs at all
- The bootstrap orchestrator MUST call this skill instead of calling `qa-loop-ui` directly

When `question_result.questions` is empty (legitimate empty OR fallback), skip Stage 4 entirely — return the no-questions shortcut without showing the entry gate. Do NOT activate `qa-loop-ui` in this case.

**What this skill does NOT do:**
- Generate questions (`smart-question-generator`)
- Run the Q&A loop itself (`qa-loop-ui`, invoked BY this skill when user proceeds)
- Write to memory (orchestrator responsibility after Stage 5 consent gate)
- Accumulate skip counts over time (telemetry counting is `E107bS08`)

---

## Input Schema

```yaml
question_result:
  questions:                   # from smart-question-generator — already ≤5 items
    - question_text: string
      topic: string
      severity: number
      options:                 # optional
        - label: string
          value: string
  error: string | null
  fallback: bool

workspace_id: string           # for per-workspace telemetry (AC5)
```

---

## Process

### Step 0 — No-questions shortcut

```
if question_result.questions.length == 0:
  log: "[abort-safe-handler] no questions from smart-question-generator — Stage 4 skipped"
  return {
    skipped: false,
    qa_answers: [],
    skip_telemetry: null,
    abort_reason: "no_questions"
  }
```

This path produces no telemetry event (no user-facing choice was presented — skip is structural,
not a user decision). The orchestrator proceeds to Stage 5 with an empty `qa_answers` array.
`bootstrap-llm-synthesis` with an empty answers list behaves identically to `qa_answers: null`
for the purposes of clarity tagging — ambiguous fields will receive `clarity: open-question`.

### Step 1 — Stage 4 entry gate (AC1)

Display the entry gate message inline:

```
📋 Bootstrap found {question_result.questions.length} clarifying question(s) about your project.

Answering them improves entry accuracy — ambiguities that go unanswered will be marked
as open-question in your workspace memory and flagged for Discovery review.

  [Y] Answer questions now  (recommended)
  [N] Skip Q&A and continue with default bootstrap

Press Enter or type Y to proceed, N to skip entirely.
```

Record gate presentation timestamp:
```
gate_presented_at = current_timestamp_ms()
```

### Step 2 — Await user choice

Await one line of user input. Trim whitespace.

```
raw_input = trim(user_input)
normalized = lowercase(raw_input)
```

### Step 3 — Route on choice

#### Path A — User skips (AC2, AC3, AC4)

```
if normalized == "n" OR normalized == "no" OR normalized == "skip":
  skipped_at_ts = current_timestamp_ms()
  log: "[abort-safe-handler] user chose skip-entire at Stage 4 entry — proceeding without Q&A"
  log: "  workspace_id={workspace_id}  response_time_ms={skipped_at_ts - gate_presented_at}"

  return {
    skipped: true,
    qa_answers: null,                # null → synthesis uses clarity: open-question for ambiguous fields
    skip_telemetry: {
      skip_reason: "user_skip_entire",
      skipped_at: iso_timestamp(),   # ISO 8601 UTC
      workspace_id: workspace_id,
      response_time_ms: skipped_at_ts - gate_presented_at
    },
    abort_reason: null
  }
```

**AC4 guarantee:** on Path A, zero Q&A state is created. No answers array is initialized, no
`qa-loop-ui` invocation occurs. The return is atomic — the only side effect is the log entry.

#### Path B — User proceeds (delegates to qa-loop-ui)

```
elif normalized == "y" OR normalized == "yes" OR normalized == "":
  log: "[abort-safe-handler] user chose proceed — delegating to qa-loop-ui"

  qa_session_result = invoke qa-loop-ui(question_result)

  # Forward qa-loop-ui result transparently; add telemetry marker for no-skip path
  return {
    skipped: (qa_session_result.skipped_all == true),
    qa_answers: qa_session_result.answers,      # may be partial if user skip-all'd mid-loop
    skip_telemetry: {
      skip_reason: null,                        # null = user engaged with Q&A
      skipped_at: null,
      workspace_id: workspace_id,
      response_time_ms: null
    },
    abort_reason: qa_session_result.abort_reason
  }
```

**Note on mid-loop `skip all`:** if the user types "skip all" during `qa-loop-ui`, the result
arrives here with `qa_session_result.skipped_all: true`. This skill sets `skipped: true` on the
output, but `skip_telemetry.skip_reason` remains null because the user DID engage with the entry
gate (they chose to proceed). The telemetry distinction matters for E107bS08 rate analysis:
`skip_reason: "user_skip_entire"` = pre-loop skip; `skip_reason: null` with `skipped: true` =
mid-loop skip-all (the two are counted separately).

### Step 4 — Abort during entry gate (AC4)

If the user interrupts (Ctrl+C, process signal, or agent context terminated) while awaiting the
Y/N choice at Step 2 — before any Q&A answers are collected:

```
catch interrupt at Step 2:
  log: "[abort-safe-handler] user aborted at Stage 4 entry gate — skip path, no partial state"

  return {
    skipped: true,
    qa_answers: null,
    skip_telemetry: {
      skip_reason: "user_abort",
      skipped_at: iso_timestamp(),
      workspace_id: workspace_id,
      response_time_ms: null
    },
    abort_reason: "user_abort"
  }
```

**AC4 guarantee:** interrupt at the entry gate leaves zero partial state. No answers have been
collected, no Q&A session has started. The return is safe for the orchestrator to handle
identically to a skip.

---

## Orchestrator responsibility after this skill (AC2)

When `abort_safe_result.skipped == true` (any path except no-questions shortcut):
- Call `bootstrap-llm-synthesis` with `qa_answers: null`
- After synthesis returns, surface entries with `clarity: open-question` explicitly:

```
After synthesis, if skipped == true:
  open_entries = synthesis_result.entries.filter(e => e.clarity == "open-question")
  if open_entries.length > 0:
    display:
      "ℹ️  {open_entries.length} topic(s) remain ambiguous (Q&A was skipped):
      {for e in open_entries}
        · {e.title}
      {endfor}
      These entries are tagged clarity: open-question in your workspace memory.
      Run a Discovery session to resolve them when ready."
```

This orchestrator step fulfills AC2's requirement that open-question entries are "clearly
visible to user". The abort-safe-handler skill provides the signal (`skipped: true`, `qa_answers:
null`); the synthesis + display is the orchestrator's responsibility.

---

## Output Schema

```yaml
abort_safe_result:
  skipped: bool                    # true = no Q&A answers will reach synthesis
  qa_answers: array | null         # null if skipped; answer array (may be partial) if proceeded
  skip_telemetry:                  # null only on no-questions shortcut (Step 0)
    skip_reason: string | null     # "user_skip_entire" | "user_abort" | null (null = proceeded)
    skipped_at: string | null      # ISO 8601 UTC; null if not skipped
    workspace_id: string           # always present — workspace scope for rate analysis (AC5)
    response_time_ms: number | null  # entry-gate response time; null if not measured
  abort_reason: string | null      # "user_abort" | "no_questions" | null (null = normal)

# Example — user skips at entry gate:
abort_safe_result:
  skipped: true
  qa_answers: null
  skip_telemetry:
    skip_reason: "user_skip_entire"
    skipped_at: "2026-04-29T10:32:00Z"
    workspace_id: "ws_abc123"
    response_time_ms: 4210
  abort_reason: null

# Example — user answers all questions:
abort_safe_result:
  skipped: false
  qa_answers:
    - question_id: "project_type"
      answer_text: "saas"
      skipped: false
      response_time_ms: 3200
  skip_telemetry:
    skip_reason: null
    skipped_at: null
    workspace_id: "ws_abc123"
    response_time_ms: null
  abort_reason: null

# Example — no questions from smart-question-generator:
abort_safe_result:
  skipped: false
  qa_answers: []
  skip_telemetry: null
  abort_reason: "no_questions"
```

---

## Quality Checks

- `skipped: true` implies `qa_answers == null`
- `skipped: false` implies `qa_answers` is an array (may be empty)
- `abort_reason: "no_questions"` implies `skip_telemetry == null` and `qa_answers == []`
- `skip_telemetry.skip_reason == "user_skip_entire"` implies `skipped_at` is a non-null ISO string
- `skip_telemetry.skip_reason == null` implies `skipped_at == null` (user proceeded, no skip event)
- `abort_reason: "user_abort"` implies `skipped: true` and `qa_answers == null`
- `workspace_id` in `skip_telemetry` is always present when `skip_telemetry != null`

---

## Non-Goals

This skill MUST NOT:
- Run the Q&A interaction loop itself (delegate to `qa-loop-ui`)
- Generate or rank questions (`smart-question-generator`, `topic-importance-ranker`)
- Accumulate skip counts or compute skip rates over time (`E107bS08` telemetry)
- Write to memory directly (orchestrator responsibility after Stage 5 consent gate)
- Decide what to do with open-question entries (orchestrator responsibility per §Orchestrator responsibility above)
- Show the open-question entries to the user (orchestrator responsibility)
- Apply any timeout at the entry gate (patience is left to user; no auto-skip on silence)
- Call the LLM (pure interaction + delegation skill; no inference calls)
