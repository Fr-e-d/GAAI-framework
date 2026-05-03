#!/usr/bin/env bash
# daemon-prompt-construct.sh — Canonical impl prompt construction helper
#
# Outputs the impl prompt to stdout.
# Caller captures with: PROMPT_CONTENT=$(bash daemon-prompt-construct.sh)
#
# Required env vars:
#   GAAI_STORY_ID        — story identifier
#   GAAI_STORY_PATH      — absolute path to {id}.story.md
#   GAAI_PLAN_PATH       — absolute path to {id}.execution-plan.md
#   GAAI_EPIC_PATH       — absolute path to {epic_id}.epic.md (may be empty)
#   GAAI_WORKSPACE_PATH  — absolute worktree root (for NOTES_PATH substitution)
#   SECONDARY_ROUTE      — "true" or "false" (default: "false")
#   PROJECT_DIR          — repo root (for resolving DEC file paths)

set -euo pipefail

# ── Validate required env vars ─────────────────────────────────────────────
: "${GAAI_STORY_ID:?daemon-prompt-construct.sh: GAAI_STORY_ID is required}"
: "${GAAI_STORY_PATH:?daemon-prompt-construct.sh: GAAI_STORY_PATH is required}"
: "${GAAI_PLAN_PATH:?daemon-prompt-construct.sh: GAAI_PLAN_PATH is required}"
: "${GAAI_WORKSPACE_PATH:?daemon-prompt-construct.sh: GAAI_WORKSPACE_PATH is required}"
: "${PROJECT_DIR:?daemon-prompt-construct.sh: PROJECT_DIR is required}"

SECONDARY_ROUTE="${SECONDARY_ROUTE:-false}"
NOTES_PATH="${GAAI_WORKSPACE_PATH}/.gaai/project/contexts/artefacts/notes/${GAAI_STORY_ID}.notes.md"

# ── Section 1: R1-R6 context discipline preamble (secondary route only) ───
if [[ "$SECONDARY_ROUTE" == "true" ]]; then
  cat <<PREAMBLE
=== CONTEXT DISCIPLINE (MANDATORY for this delivery) ===

You operate in a long-running agentic session with a 200K context window
and aggressive autocompaction. Failure to follow these rules causes session
termination via rapid_refill_breaker (Claude Code internal safety) — observed
empirically at 43% fail rate on this routing path.

These rules are derived from Anthropic's "Effective Context Engineering for
AI Agents" guidance. They apply throughout this session.

## R1 — Persistent notes file (MOST IMPORTANT)

Maintain a working-memory file at this exact path :
${NOTES_PATH}

This file is filesystem-persistent and survives autocompaction. It is your
SINGLE SOURCE OF TRUTH for state recovery. The file is committed as a
delivery artefact alongside execution-plan, impl-report, and qa-report.

### Initial creation (on your very first action)

If the file does not yet exist, create it with the EXACT bootstrap template
below. Then proceed with the actual work.

\`\`\`markdown
# Working Memory — ${GAAI_STORY_ID}

## ⚠ RULES (re-read these every time you read this file)

R1 : Append updates to this file after every meaningful tool result.
     Never overwrite — append/update sections in place.
R2 : Never re-read a file listed under "Files read" — the summary is canonical.
R3 : After every tool result, write 1 structured sentence summary in your reply.
R4 : Read files in chunks ≤200 lines (offset/limit). Bash verbose → tail -100.
R5 : Work on ONE acceptance criterion at a time. Commit before next AC.
R6 : If your context feels gappy (autocompact occurred), re-read THIS file +
     the execution-plan.md FIRST. Do NOT re-execute steps already marked done.

## Current step

<one sentence — update continuously>

## Files read (canonical — do NOT re-read)

- path/to/file.ts (lines X-Y) : <one-line summary of what matters>
- ...

## Decisions made

- <decision + brief rationale>

## Acceptance criteria status

- AC1 : <pending|in-progress|done|blocked>
- AC2 : ...

## Open questions / blockers

- <if any>

## Tool calls made (running log — append-only)

- T1 : Read auth.ts L23-67 → exports validateSession(token), HMAC-SHA256
- T2 : Edit membership.ts L102 → added workspace_id field
- ...
\`\`\`

### Re-entry pattern (post-autocompact recovery)

Whenever you suspect autocompaction just occurred (sudden gap in context),
your FIRST action MUST be:

1. Read ${NOTES_PATH}
2. Read ${GAAI_WORKSPACE_PATH}/.gaai/project/contexts/artefacts/plans/${GAAI_STORY_ID}.execution-plan.md
3. Resume from "Current step" without re-executing prior tool calls

### Append-only retry semantics

If this delivery is a retry (e.g., second nested-claude-spawn for ${GAAI_STORY_ID} after
a prior failure), the existing notes file represents your prior attempt's
findings. PRESERVE all "Files read" and "Decisions made" entries — they
remain valid. Only update "Current step", AC status, and append new tool
calls. Append-tolerant by design.

## R2 — Never re-read

Never re-read a file already listed under "Files read" in your notes file.
The summary IS canonical. If you doubt the summary, re-read the file ONLY
WITH a tighter offset/limit on the specific lines you need (not the whole
file again).

## R3 — Self-summarize after every tool result

After each Read / Bash / Glob / Grep, write ONE structured sentence in your
reply BEFORE the next tool call. Format:

"<file/result> contains <fact>. Now <next intended action>."

Example :
"auth.ts L23-67 exports validateSession(token), HMAC-SHA256 over headers,
no rate limiting. Now editing membership.ts to call it from hasAccess()."

## R4 — Just-in-time chunked retrieval

- Read files in chunks ≤200 lines using offset/limit. Use Glob/Grep
  first to locate exact line ranges. Never Read a file >300 lines
  without offset/limit.
- For Bash with verbose output (tests, builds, logs), always pipe through
  head/tail to bound output : \`pnpm test 2>&1 | tail -100\`
- Prefer file paths and grep patterns over loading full content.

## R5 — Single-feature focus

Per Anthropic's harness guidance : work on ONE acceptance criterion at a
time, commit before advancing. Do not parallelize ACs across multiple
files in flight — context bloat is fatal here.

## Few-shot example — good cycle

You are about to fix a bug in membership validation. Below is the PATTERN
to follow (one example turn) :

> [agent thinks] "Need to understand current validation. Let me check
> if I've already seen this file in my notes."
>
> Read ${NOTES_PATH}
> [observes : "Files read: empty" — first turn]
>
> Glob "**/membership*.ts" → 2 hits
> [agent reply : "Found 2 membership files : api/membership.ts and
> shared/membership-types.ts. Reading the api one first L1-100 to see
> the validation entry point."]
>
> Read api/membership.ts L1-100 → finds validateMembership() at L34
> [agent reply : "validateMembership() at L34 calls hasAccess() which is
> imported from auth.ts. Edit notes file to record this, then read auth.ts
> at the import line."]
>
> Edit ${NOTES_PATH} → append to "Files read" : "api/membership.ts L1-100
> : validateMembership at L34, calls hasAccess from auth.ts"
> Edit ${NOTES_PATH} → update "Current step" : "Reading auth.ts hasAccess()"

Notice the discipline : every tool result triggers (a) one structured
summary in the reply, (b) a notes file update.

=== END CONTEXT DISCIPLINE ===

PREAMBLE
fi

# ── Sections 2-4: input artefact handoff ─────────────────────────────────
# Two strategies based on route :
#  - SECONDARY (e.g. GLM with smaller effective context window): emit PATH
#    references only. Agent reads via Read tool with offset/limit per R4
#    chunked-retrieval rule. Keeps the upfront prompt minimal so the
#    autocompact threshold is not consumed before the agent has even acted.
#    Avoids the "double inlining" trap where the prompt has the full plan
#    AND the agent re-Reads the same file in chunks (observed empirically).
#  - PRIMARY (Sonnet): full inline. Sonnet has more context headroom and
#    benefits from upfront context — matches the prior unconditional
#    behaviour for backwards compatibility.
if [[ ! -f "$GAAI_STORY_PATH" ]]; then
  echo "[daemon-prompt-construct] ERROR: story file not found: $GAAI_STORY_PATH" >&2
  exit 1
fi
if [[ ! -f "$GAAI_PLAN_PATH" ]]; then
  echo "[daemon-prompt-construct] ERROR: plan file not found: $GAAI_PLAN_PATH" >&2
  exit 1
fi

if [[ "$SECONDARY_ROUTE" == "true" ]]; then
  cat <<INPUT_REFS
=== INPUT ARTEFACTS — READ THESE FIRST (chunked, per R4) ===

Your initial actions, in this order, are :

  1. Read ${GAAI_STORY_PATH}                           — the validated story
  2. Read ${GAAI_PLAN_PATH}                            — the execution plan from the planning phase
INPUT_REFS
  if [[ -n "${GAAI_EPIC_PATH:-}" && -f "$GAAI_EPIC_PATH" ]]; then
    echo "  3. Read ${GAAI_EPIC_PATH}                            — parent epic (optional context)"
  fi
  cat <<INPUT_REFS_TAIL

Read each in chunks of ≤200 lines (offset/limit) per R4. Summarise each
chunk in your reply BEFORE the next tool call (R3). Append entries to
your notes file (R1) so you never re-read.

DO NOT expect any of the above artefacts to be inlined in this prompt.
The path references above ARE your input — read them via the Read tool.

=== END INPUT ARTEFACTS ===

INPUT_REFS_TAIL
else
  # Primary route — full inline (legacy behaviour, Sonnet-friendly)
  echo "=== STORY: ${GAAI_STORY_ID} ==="
  cat "$GAAI_STORY_PATH"
  echo ""
  echo "=== EXECUTION PLAN ==="
  cat "$GAAI_PLAN_PATH"
  echo ""
  if [[ -n "${GAAI_EPIC_PATH:-}" && -f "$GAAI_EPIC_PATH" ]]; then
    echo "=== EPIC CONTEXT ==="
    cat "$GAAI_EPIC_PATH"
    echo ""
  fi
fi

# ── Section 5: DEC reads instruction ─────────────────────────────────────
# Parse related_decs from story YAML frontmatter (--- block).
# Format in frontmatter: related_decs: [DEC-NN, DEC-MM, ...]
# or:
# related_decs:
#   - DEC-NN
#   - DEC-MM
_related_decs=""
_in_frontmatter=0
_frontmatter_done=0
_yaml_block_line=0
_in_related=0
while IFS= read -r _line; do
  _yaml_block_line=$(( _yaml_block_line + 1 ))
  if [[ $_yaml_block_line -eq 1 && "$_line" == "---" ]]; then
    _in_frontmatter=1
    continue
  fi
  if [[ $_in_frontmatter -eq 1 && "$_line" == "---" ]]; then
    _frontmatter_done=1
    break
  fi
  if [[ $_in_frontmatter -eq 1 ]]; then
    # Inline list form: related_decs: [DEC-NN, DEC-MM, ...]
    if echo "$_line" | grep -qE '^related_decs:[[:space:]]*\['; then
      _related_decs=$(echo "$_line" | sed 's/related_decs:[[:space:]]*//' | tr -d '[]' | tr ',' '\n' | tr -d ' ' | grep -v '^$' || true)
    # Multiline list form: - DEC-XX (after related_decs: line)
    elif echo "$_line" | grep -qE '^related_decs:[[:space:]]*$'; then
      _in_related=1
    elif [[ "${_in_related:-0}" -eq 1 ]]; then
      if echo "$_line" | grep -qE '^[[:space:]]*-[[:space:]]+(DEC-[0-9]+)'; then
        _dec=$(echo "$_line" | sed 's/.*-[[:space:]]*//')
        _related_decs="${_related_decs}${_dec}"$'\n'
      elif echo "$_line" | grep -qE '^[^[:space:]]'; then
        _in_related=0
      fi
    fi
  fi
done < "$GAAI_STORY_PATH"

if [[ -n "$_related_decs" ]]; then
  echo "=== MANDATORY DEC READS ==="
  echo "Before implementing, read each of the following decision files to understand the constraints:"
  echo ""
  while IFS= read -r _dec_id; do
    [[ -z "$_dec_id" ]] && continue
    echo "  Read ${PROJECT_DIR}/.gaai/project/contexts/memory/decisions/${_dec_id}.md"
  done <<< "$_related_decs"
  echo ""
  echo "These DECs contain binding constraints for this story. Non-compliance = implementation failure."
  echo ""
fi

# ── Section 6: Worktree scope (universal soft gate) ──────────────────────
cat <<WORKTREE_SCOPE
=== WORKTREE SCOPE ===

All Write/Edit operations and Bash commands with side effects (file writes,
deletions, network calls beyond Anthropic API + standard package registries)
MUST stay within ${GAAI_WORKSPACE_PATH}. Reads outside the worktree are
allowed for repo and framework context. The daemon audits the per-phase log
post-completion and writes any out-of-worktree paths to <log>.audit.json
(advisory).

=== END WORKTREE SCOPE ===

WORKTREE_SCOPE
