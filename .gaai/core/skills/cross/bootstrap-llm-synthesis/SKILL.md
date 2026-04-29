---
name: bootstrap-llm-synthesis
description: Construct the LLM synthesis prompt from project surface scan + optional tree-sitter context + optional Q&A answers. Call the LLM. Parse and validate the response into 6-8 structured memory entries with clarity tags and source traceability. Used as Stage 3 of the /gaai:bootstrap pipeline.
license: ELv2
compatibility: Works with any OpenAI-compatible LLM API from an AI coding agent context
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-BOOTSTRAP-LLM-SYNTHESIS-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - surface_scan_result
  - tree_sitter_context       # optional — null if Stage 0c unavailable
  - qa_answers                # optional — null if Stage 4 not yet run
  - anthropic_api_key         # BYOK — from local Claude Code env
outputs:
  - synthesis_result          # { entries[], token_usage, parse_errors[], entry_count_distribution }
---

# Bootstrap LLM Synthesis

## Purpose / When to Activate

Activate:
- As Stage 3 of the `/gaai:bootstrap` pipeline (after `project-surface-scan` and optional tree-sitter parse)
- When the bootstrap orchestrator is ready to distill raw project signals into structured memory entries
- Re-run if Q&A answers (Stage 4) are incorporated after an initial synthesis pass

Produces `synthesis_result` — structured memory entries ready for consent gate (Stage 5 pre-write gate) and memory ingest.

---

## Clarity Tag Semantics

Each entry carries a `clarity` field. Use these definitions consistently:

| Value | Meaning |
|---|---|
| `confirmed` | Evidence found directly in source files (imports, config, explicit declarations). Source[] must include file:line reference. |
| `inferred` | Reasonable conclusion from structural patterns (directory layout, naming conventions, dep graph). Source[] should list supporting files. |
| `open-question` | Significant ambiguity remains. Formulate as a question in `content`. Source[] may be empty. |
| `declared-by-user` | User stated this explicitly in Q&A answers. Source[] should reference the Q&A input. |

---

## Process

### Step 1 — Assemble synthesis context

Build the `synthesis_context` object that will be injected into the prompt:

```
synthesis_context:
  project_summary:
    total_files: surface_scan_result.total_file_count
    size_class:  surface_scan_result.size_class
    estimated_loc: surface_scan_result.estimated_loc
    top_languages: surface_scan_result.languages[0..4]   # top 5 only
    top_directories: surface_scan_result.dir_counts      # depth-1 map
  ast_context:
    available: (tree_sitter_context != null)
    symbol_table_summary: tree_sitter_context.symbol_table_summary ?? null
    import_graph_summary: tree_sitter_context.import_graph_summary ?? null
    hot_entry_points:     tree_sitter_context.entry_points[0..9] ?? []
  qa_context:
    available: (qa_answers != null)
    answers: qa_answers ?? []
```

Log: `[bootstrap-llm-synthesis] context assembled — AST: {available}, Q&A: {available}`

### Step 2 — Build synthesis prompt

Construct the prompt using the template below. Apply `cache_control: {type: "ephemeral"}` on the system prompt block (DEC-82 Principle 11 — prompt caching at static prefixes).

**System prompt (static — cache this block):**

```
You are a precision technical analyst. Your task is to distill raw project signals into
structured memory entries that will serve as the permanent shared brain for an AI
delivery team working on this project.

Requirements:
- Produce between 6 and 8 entries. Never fewer than 4, never more than 10.
- Each entry must be independently useful — no cross-entry dependencies.
- Clarity is non-negotiable: every claim must be traceable to evidence.
- Prefer confirmed over inferred. Flag gaps as open-question.
- Write for a senior developer who has never seen this codebase.

Output format: a JSON array. Each element is an object with exactly these fields:
{
  "title": "<short descriptive title, ≤ 80 chars>",
  "content": "<body text, ≤ 2000 chars, markdown allowed>",
  "category": "<one of: project | architecture | patterns | domains | map | lexicon | decisions>",
  "tags": ["<tag1>", "<tag2>"],
  "clarity": "<confirmed | inferred | open-question | declared-by-user>",
  "source": ["<file:path:line-range or 'qa:question-N' or evidence descriptor>"]
}

Return ONLY the JSON array. No prose before or after. No code fences.
```

**User message (dynamic — include synthesis_context):**

```
Analyze the following project signals and produce distilled memory entries.

## Project surface scan
- Total files: {synthesis_context.project_summary.total_files}
- Size class: {synthesis_context.project_summary.size_class}
- Estimated LOC: {synthesis_context.project_summary.estimated_loc}
- Top languages: {synthesis_context.project_summary.top_languages formatted as "Language (N files)"}
- Directory structure (depth-1):
{synthesis_context.project_summary.top_directories formatted as YAML block}

{if synthesis_context.ast_context.available}
## AST analysis (tree-sitter)
### Symbol summary
{synthesis_context.ast_context.symbol_table_summary}

### Import graph (top entry points)
{synthesis_context.ast_context.hot_entry_points formatted as list}
{endif}

{if synthesis_context.qa_context.available}
## User Q&A answers
{for answer in synthesis_context.qa_context.answers}
Q: {answer.question}
A: {answer.answer}
{endfor}
{endif}

Produce 6-8 memory entries now.
```

### Step 3 — LLM call with retry

Call the Anthropic Messages API with the constructed prompt.

**Model:** use the primary model available in the current session (Claude Sonnet or equivalent). Do NOT hardcode a model string — use the session default.

**Parameters:**
```
max_tokens: 4096
temperature: 0          # deterministic output for caching coherence
```

**Retry policy (AC4):**
```
max_attempts = 3
backoff_seconds = [2, 5, 12]   # exponential backoff

for attempt in 1..max_attempts:
  try:
    response = anthropic_messages_create(...)
    break   # success
  except (RateLimitError, ServiceUnavailableError, TimeoutError) as e:
    if attempt == max_attempts: raise RetryExhaustedError(e)
    sleep(backoff_seconds[attempt - 1])
    continue
  except (AuthenticationError, InvalidRequestError) as e:
    raise immediately   # non-retryable
```

Log each attempt: `[bootstrap-llm-synthesis] LLM call attempt {N} — {status}`

### Step 4 — Parse LLM response

**Tolerant parsing (AC2):**

The LLM may wrap the JSON in markdown code fences (```json ... ```) or include leading/trailing whitespace. Apply this extraction sequence before `JSON.parse`:

```
1. Strip leading/trailing whitespace
2. If starts with "```": extract content between first "```" and last "```"
   (handle both ```json and ``` variants)
3. Strip any trailing comma before closing `]` (common LLM formatting artifact)
4. Attempt JSON.parse
5. If parse fails: try extracting the largest [...] block via regex /\[[\s\S]*\]/
6. If still fails: raise ParseError with raw response excerpt (first 500 chars) for logging
```

**Schema validation (AC2):**

For each parsed element, validate:
```
required_fields = ["title", "content", "category", "tags", "clarity", "source"]
valid_categories = ["project", "architecture", "patterns", "domains", "map", "lexicon", "decisions"]
valid_clarity    = ["confirmed", "inferred", "open-question", "declared-by-user"]

for entry in parsed_array:
  errors = []
  if missing required_field: errors += ["missing: {field}"]
  if category not in valid_categories: errors += ["invalid category: {value}"]
  if clarity not in valid_clarity: errors += ["invalid clarity: {value}"]
  if typeof tags != "array": errors += ["tags must be array"]
  if typeof source != "array": errors += ["source must be array"]

  if errors is empty:
    valid_entries.append(entry)
  else:
    parse_errors.append({ entry_index: i, raw: entry, errors: errors })
    log: "[bootstrap-llm-synthesis] entry {i} invalid: {errors}"
```

**Partial recovery (AC4):** if some entries are invalid, continue with valid_entries. Do NOT abort unless valid_entries is empty.

### Step 5 — Apply bounds

**Hard cap (AC3):**
```
if len(valid_entries) > 10:
  valid_entries = valid_entries[0:10]
  log: "[bootstrap-llm-synthesis] WARNING: LLM returned {original_count} entries — capped at 10"
```

**Per-entry length cap (AC3):**
```
for entry in valid_entries:
  if len(entry.content) > 2000:
    entry.content = entry.content[0:1997] + "…"
    log: "[bootstrap-llm-synthesis] entry '{entry.title}' truncated to 2000 chars"
```

### Step 6 — Observability summary

Record token usage from API response (AC5):
```
token_usage:
  prompt_tokens:     response.usage.input_tokens
  completion_tokens: response.usage.output_tokens
  total_tokens:      response.usage.input_tokens + response.usage.output_tokens
  cached_tokens:     response.usage.cache_read_input_tokens ?? 0   # prompt cache hit
```

Build entry count distribution (AC5):
```
entry_count_distribution:
  total_produced:   len(parsed_array)     # before bounds/validation
  total_valid:      len(valid_entries)    # after validation
  total_invalid:    len(parse_errors)
  by_category:      { "project": N, "architecture": N, ... }
  by_clarity:       { "confirmed": N, "inferred": N, "open-question": N, "declared-by-user": N }
```

Log (stdout):
```
[bootstrap-llm-synthesis] synthesis complete
  entries produced: {total_produced} → {total_valid} valid, {total_invalid} invalid
  token usage: {prompt_tokens} in / {completion_tokens} out (cache hit: {cached_tokens})
  by category: {by_category}
  by clarity: {by_clarity}
```

---

## Output Schema (`synthesis_result`)

```yaml
synthesis_result:
  synthesized_at: "2026-04-29T12:00:00Z"     # ISO timestamp
  entries:
    - title: "TypeScript monorepo with pnpm workspaces"
      content: "Project uses pnpm workspaces with 4 packages: ..."
      category: project
      tags: [typescript, pnpm, monorepo]
      clarity: confirmed
      source: ["package.json:1-5", "pnpm-workspace.yaml:1-10"]
    # ... 5-9 more entries
  token_usage:
    prompt_tokens: 1840
    completion_tokens: 612
    total_tokens: 2452
    cached_tokens: 1240
  parse_errors:
    - entry_index: 3
      errors: ["invalid category: infrastructure"]
  entry_count_distribution:
    total_produced: 8
    total_valid: 7
    total_invalid: 1
    by_category:
      project: 2
      architecture: 2
      patterns: 1
      map: 1
      decisions: 1
    by_clarity:
      confirmed: 4
      inferred: 3
      open-question: 0
      declared-by-user: 0
```

---

## Quality Checks

- `valid_entries` count ≥ 4 (synthesis failed if fewer than 4 valid entries)
- Each valid entry has all 6 required fields
- `token_usage.total_tokens` > 0 (LLM was actually called)
- `synthesized_at` is present
- `parse_errors` is a list (may be empty — that is fine)
- No entry `content` exceeds 2000 chars after bounds step

---

## Non-Goals

This skill must NOT:
- Write to memory directly (use `memory-ingest` after Stage 5 consent gate)
- Make decisions about which entries to persist (that is the consent gate's job)
- Run tree-sitter parsing (use `tree-sitter-parse` for Stage 0c)
- Ask the user questions (Q&A is Stage 4, inputs arrive pre-answered)
- Modify the surface scan result (read-only input)

**Synthesizes signals into structured entries. Does not persist them.**
