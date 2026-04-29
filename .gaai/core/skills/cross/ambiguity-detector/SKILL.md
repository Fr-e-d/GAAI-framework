---
name: ambiguity-detector
description: Takes surface scan results, optional LLM synthesis open-question entries, and optional tree-sitter AST signals to score project ambiguities (1-10). Outputs structured ambiguity_feed for smart-question-generator. Pure heuristic — no LLM calls. Designed for Stage 3.5 of the /gaai:bootstrap pipeline (between LLM synthesis and Q&A).
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-AMBIGUITY-DETECTOR-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - surface_scan_result      # from project-surface-scan (required)
  - synthesis_entries        # Array of open-question clarity entries from bootstrap-llm-synthesis (optional, may be [])
  - ast_signals              # from tree-sitter Stage 0c / E107a (optional, null if unavailable)
outputs:
  - ambiguity_feed           # Array<{topic, ambiguity_score, evidence_pro[], evidence_against[]}>
---

# Ambiguity Detector

## Purpose / When to Activate

Activate:
- As Stage 3.5 of the `/gaai:bootstrap` pipeline — after `bootstrap-llm-synthesis` returns results and before `smart-question-generator` is called
- The bootstrap orchestrator filters `synthesis_result.entries[]` to `clarity: "open-question"` and passes them as `synthesis_entries`
- When `synthesis_entries` is empty and `ast_signals` is null, the skill runs heuristic-only analysis on `surface_scan_result` and may still produce entries from language distribution

This skill is **pure heuristic** — it makes no LLM calls. It scores ambiguities deterministically from structural signals. All scoring logic executes client-side before the Q&A stage (DEC-13 client-side principle, DEC-48 instructions-client).

---

## Input Schema

```yaml
surface_scan_result:              # required — output of project-surface-scan
  total_file_count: number
  languages: Array<{
    language: string
    file_count: number
    rank: number
  }>
  ext_counts: { [ext: string]: number }   # e.g. { ".ts": 142, ".vue": 3 }
  dir_counts: { [dir: string]: number }   # depth-1 directory file counts

synthesis_entries:                # optional — null or empty array acceptable
  # Array of entries from bootstrap-llm-synthesis filtered to clarity="open-question"
  # Pass [] or null when synthesis stage was skipped or produced no open-questions
  - topic: string                 # e.g. "What framework is this project using?"
    content: string               # the ambiguity question or description
    sources: Array<string>        # file:line references or descriptors

ast_signals:                      # optional — null if E107a stories not yet delivered
  import_patterns:
    has_esm: boolean              # ESM (import/export) patterns detected
    has_commonjs: boolean         # CommonJS (require/module.exports) patterns detected
    conflict_count: number        # files containing both ESM and CommonJS patterns
    conflict_files: Array<string> # sample of conflicting file paths
  directory_signals:
    has_src_dir: boolean          # src/ directory exists and is non-trivial
    has_app_dir: boolean          # app/ directory exists and is non-trivial
    src_file_count: number | null # files under src/ (null if not scanned)
    app_file_count: number | null # files under app/ (null if not scanned)
```

---

## Process

### Step 1 — Heuristic analysis from surface_scan_result

#### Step 1a — Language distribution analysis

Compute the ratio of each detected language over total language-attributed files:

```
total_lang_files = sum(l.file_count for l in surface_scan_result.languages)

if total_lang_files == 0:
  skip language heuristics   # no language data — not an error
  log: "[ambiguity-detector] no language data in surface_scan_result — skipping language heuristics"
else:
  lang_ratios = [
    { language: l.language, ratio: l.file_count / total_lang_files, count: l.file_count }
    for l in surface_scan_result.languages
  ]
  
  top1 = lang_ratios[0] if len >= 1 else null
  top2 = lang_ratios[1] if len >= 2 else null
  top3 = lang_ratios[2] if len >= 3 else null
```

Apply scoring rules in order (first match wins):

| Condition | Score | Topic | Rationale |
|---|---|---|---|
| top1.ratio >= 0.80 | 1–2 | `primary_language` | Dominant single language — low ambiguity |
| top1.ratio >= 0.50 AND top2 is null OR top2.ratio < 0.25 | 3 | `primary_language` | Clear majority — minor presence of secondary |
| top1 AND top2 both >= 0.30 AND abs(top1.ratio – top2.ratio) < 0.20 | 7–9 | `language_ecosystem` | Near-parity — ambiguous which is primary |
| top1 AND top2 AND top3 all >= 0.15 | 5–6 | `language_ecosystem` | Mixed polyglot project |
| default (top1 >= 0.50, top2 >= 0.25) | 4 | `language_ecosystem` | Moderate secondary presence |

Score refinements:
- For `primary_language` with ratio >= 0.80: `score = max(1, round((1 - top1.ratio) * 20))`  
  (e.g., 95% → 1, 85% → 3, 80% → 4 → capped at 2)  
  Use: `score = 1 if top1.ratio >= 0.90 else 2`
- For near-parity: `score = 7 + round((0.20 - abs(top1.ratio - top2.ratio)) * 10)`, clamped to 7–9

Build evidence arrays:
```
for primary_language low-ambiguity:
  evidence_pro = [{ source: "surface_scan.languages", snippet: "{top1.language}: {top1.ratio*100:.0f}% of detected files", weight: 1.0 }]
  evidence_against = []

for language_ecosystem high-ambiguity (near-parity):
  evidence_pro = [
    { source: "surface_scan.languages", snippet: "{top1.language}: {top1.ratio*100:.0f}%", weight: top1.ratio },
    { source: "surface_scan.languages", snippet: "{top2.language}: {top2.ratio*100:.0f}%", weight: top2.ratio }
  ]
  evidence_against = [
    { source: "surface_scan.languages", snippet: "Secondary language may be tooling/tests only", weight: 0.30 }
  ]
```

#### Step 1b — Framework conflict detection

Detect framework markers from `ext_counts`:

```
vue_count   = surface_scan_result.ext_counts[".vue"]  ?? 0
jsx_count   = surface_scan_result.ext_counts[".jsx"]  ?? 0
tsx_count   = surface_scan_result.ext_counts[".tsx"]  ?? 0
react_count = jsx_count + tsx_count
```

Framework conflict scoring:

```
if vue_count > 0 AND react_count > 0:
  # Both Vue (.vue files) and React (.jsx/.tsx) detected simultaneously
  score = 8
  topic = "frontend_framework"
  evidence_pro = [
    { source: "ext_counts[.vue]",      snippet: ".vue files detected: {vue_count}",       weight: 0.85 },
    { source: "ext_counts[.jsx/.tsx]", snippet: ".jsx/.tsx files detected: {react_count}", weight: 0.85 }
  ]
  evidence_against = [
    { source: "ext_counts", snippet: ".tsx may be non-React TypeScript components", weight: 0.25 }
  ]
  add to heuristic_topics

elif vue_count > 0 AND react_count == 0:
  # Vue-only — low ambiguity, skip (score ≤ 2; smart-question-generator filters score < 3)

elif react_count > 5 AND vue_count == 0:
  # React-only — low ambiguity, skip
```

**Note:** Framework detection intentionally limited to extension-based signals only. Config file inspection (webpack.config.js vs vite.config.ts) requires file reads outside this skill's scope. If synthesis open-question entries surface framework conflicts, those will be scored in Step 3.

---

### Step 2 — AST signal analysis (skipped if ast_signals is null)

```
if ast_signals == null:
  log: "[ambiguity-detector] ast_signals not available — skipping AST heuristics (E107a stories not yet delivered)"
  skip to Step 3
```

#### Step 2a — Module system conflict

```
if ast_signals.import_patterns.has_esm AND ast_signals.import_patterns.has_commonjs:
  conflict_count = ast_signals.import_patterns.conflict_count
  total_files = surface_scan_result.total_file_count
  conflict_ratio = conflict_count / max(1, total_files)
  
  # Score: base 5, +1 per 5% of conflicting files, capped at 8
  score = min(8, 5 + round(conflict_ratio * 20))
  
  topic = "module_system"
  evidence_pro = [
    { source: "ast_signals.import_patterns", snippet: "ESM (import/export) patterns detected",                        weight: 0.75 },
    { source: "ast_signals.import_patterns", snippet: "CommonJS (require/module.exports) patterns detected",           weight: 0.75 },
    { source: "ast_signals.import_patterns", snippet: "{conflict_count} files with mixed ESM+CJS patterns",            weight: min(1.0, conflict_ratio * 5) }
  ]
  
  # Sample up to 3 conflict files as evidence snippets
  for f in ast_signals.import_patterns.conflict_files[0..2]:
    evidence_pro.push({ source: f, snippet: "file contains both import and require", weight: 0.60 })
  
  evidence_against = [
    { source: "convention", snippet: "Config files (.cjs, jest.config.js) may legitimately use require()", weight: 0.30 }
  ]
  add to ast_topics
```

#### Step 2b — Directory structure conflict

```
d = ast_signals.directory_signals

if d.has_src_dir AND d.has_app_dir:
  src_count = d.src_file_count ?? 0
  app_count = d.app_file_count ?? 0
  
  if src_count > 5 AND app_count > 5:
    # Both directories are substantive — potential layout ambiguity
    ratio_diff = abs(src_count - app_count) / max(src_count, app_count)
    
    if ratio_diff < 0.25:
      score = 6    # nearly equal counts — genuinely ambiguous
    elif ratio_diff < 0.50:
      score = 4    # one is larger but both active
    else:
      score = 3    # significant size difference — one is likely primary
    
    topic = "source_layout"
    evidence_pro = [
      { source: "directory_signals.src", snippet: "src/ directory: {src_count} files", weight: 0.70 },
      { source: "directory_signals.app", snippet: "app/ directory: {app_count} files", weight: 0.70 }
    ]
    evidence_against = [
      { source: "convention", snippet: "One directory may be legacy code or framework convention (e.g., Next.js app/)", weight: 0.35 }
    ]
    add to ast_topics
```

---

### Step 3 — Score synthesis open-question entries

For each entry in `synthesis_entries` (skip if null or empty):

```
for entry in (synthesis_entries ?? []):
  topic_key = derive_topic_key(entry.topic)
  # Normalization: lowercase, replace spaces/special chars with underscores, max 30 chars
  # e.g. "What framework is this project using?" → "framework"
  # e.g. "Is this a SaaS or a CLI tool?"        → "project_type"
  # Simple approach: take significant nouns from the question if it's a question,
  # or use the content directly if it's a noun phrase (≤ 30 chars → keep as-is after normalization)
  
  # Check for existing entry with matching topic key from heuristic analysis
  existing = heuristic_topics.concat(ast_topics).find(t => t.topic == topic_key)
  
  if existing is found:
    # Synthesis confirms an existing heuristic ambiguity — boost score
    synthesis_score = base_synthesis_score(entry)
    existing.ambiguity_score = max(existing.ambiguity_score, synthesis_score)
    existing.evidence_pro.push({
      source: "llm_synthesis.open_question",
      snippet: entry.content[0..120],
      weight: 0.60
    })
    for s in entry.sources[0..2]:
      existing.evidence_pro.push({ source: s, snippet: "synthesis source", weight: 0.40 })
      
  else:
    # New topic from synthesis — create entry
    synthesis_score = base_synthesis_score(entry)
    new_entry = {
      topic: topic_key,
      ambiguity_score: synthesis_score,
      evidence_pro: [
        { source: "llm_synthesis.open_question", snippet: entry.content[0..120], weight: 0.60 }
      ] + entry.sources[0..2].map(s => ({ source: s, snippet: "synthesis source", weight: 0.40 })),
      evidence_against: []
    }
    synthesis_topics.push(new_entry)
```

**`base_synthesis_score` helper:**

```
base_synthesis_score(entry):
  # Open-question entries from LLM synthesis start at 5 (moderate ambiguity)
  # Adjust based on source evidence density
  source_count = entry.sources.length
  bonus = min(2, source_count)                 # 0-2 bonus based on cited sources
  return min(8, 5 + bonus)                     # range: 5-8
```

**`derive_topic_key` helper:**

```
derive_topic_key(topic_string):
  # If short noun phrase (≤ 30 chars, no question mark): normalize directly
  # If question string: extract key nouns
  # Fallback: lowercase + replace non-alphanumeric with underscores + truncate to 30 chars
  normalized = topic_string.toLowerCase()
                            .replace(/[^a-z0-9]+/g, '_')
                            .replace(/^_+|_+$/g, '')
                            .slice(0, 30)
  return normalized
```

---

### Step 4 — Merge, deduplicate, and finalize

Merge all topic sources:
```
all_topics = heuristic_topics + ast_topics + synthesis_topics
```

Deduplicate by topic key (keep the entry with the highest `ambiguity_score` when duplicates exist):
```
deduped = {}
for t in all_topics:
  if t.topic in deduped:
    if t.ambiguity_score > deduped[t.topic].ambiguity_score:
      deduped[t.topic] = t
    else:
      # Merge evidence from lower-score duplicate into winner
      deduped[t.topic].evidence_pro += t.evidence_pro
      deduped[t.topic].evidence_against += t.evidence_against
  else:
    deduped[t.topic] = t

ambiguity_feed = sorted(deduped.values(), key=lambda t: (-t.ambiguity_score, t.topic))
```

Secondary sort by `topic` alphabetically ensures deterministic output for equal scores.

Clamp all scores to [1, 10]:
```
for t in ambiguity_feed:
  t.ambiguity_score = max(1, min(10, round(t.ambiguity_score)))
```

---

### Step 5 — Observability (AC4)

Log score distribution to stdout:

```
high_count   = ambiguity_feed.filter(t => t.ambiguity_score >= 7).length
medium_count = ambiguity_feed.filter(t => t.ambiguity_score >= 4 AND t.ambiguity_score <= 6).length
low_count    = ambiguity_feed.filter(t => t.ambiguity_score <= 3).length

log (stdout):
[ambiguity-detector] analysis complete
  topics: {ambiguity_feed.length} total
    heuristic: {heuristic_count} (language: {lang_count}, framework: {fw_count})
    AST-derived: {ast_count}
    synthesis open-questions: {synthesis_count}
  score distribution:
    high   (7-10): {high_count}   topics
    medium (4-6):  {medium_count} topics
    low    (1-3):  {low_count}    topics
  ast_signals_available: {ast_signals != null}
  synthesis_entries_processed: {len(synthesis_entries ?? [])}
```

---

## Output Schema

```yaml
ambiguity_feed:
  - topic: string              # short key, e.g. "language_ecosystem", "frontend_framework"
    ambiguity_score: number    # 1-10 (integer after clamp); higher = more ambiguous
    evidence_pro:              # signals supporting the ambiguity claim
      - source: string         # e.g. "surface_scan.languages", "ext_counts[.vue]", "ast_signals.import_patterns"
        snippet: string        # short human-readable description of the evidence
        weight: number         # 0.0-1.0 relative confidence weight
    evidence_against:          # signals that temper or contradict the ambiguity claim
      - source: string
        snippet: string
        weight: number

# Example outputs:

# 1. Near-parity language ecosystem (high ambiguity)
ambiguity_feed:
  - topic: "language_ecosystem"
    ambiguity_score: 8
    evidence_pro:
      - source: "surface_scan.languages"
        snippet: "Python: 42%"
        weight: 0.42
      - source: "surface_scan.languages"
        snippet: "JavaScript: 40%"
        weight: 0.40
    evidence_against:
      - source: "surface_scan.languages"
        snippet: "Secondary language may be tooling/tests only"
        weight: 0.30

# 2. Framework conflict (high ambiguity)
  - topic: "frontend_framework"
    ambiguity_score: 8
    evidence_pro:
      - source: "ext_counts[.vue]"
        snippet: ".vue files detected: 12"
        weight: 0.85
      - source: "ext_counts[.jsx/.tsx]"
        snippet: ".jsx/.tsx files detected: 34"
        weight: 0.85
    evidence_against:
      - source: "ext_counts"
        snippet: ".tsx may be non-React TypeScript components"
        weight: 0.25

# 3. Module system conflict from AST signals
  - topic: "module_system"
    ambiguity_score: 6
    evidence_pro:
      - source: "ast_signals.import_patterns"
        snippet: "ESM (import/export) patterns detected"
        weight: 0.75
      - source: "ast_signals.import_patterns"
        snippet: "CommonJS (require/module.exports) patterns detected"
        weight: 0.75
      - source: "ast_signals.import_patterns"
        snippet: "3 files with mixed ESM+CJS patterns"
        weight: 0.60
    evidence_against:
      - source: "convention"
        snippet: "Config files (.cjs, jest.config.js) may legitimately use require()"
        weight: 0.30

# 4. Dominant single language (low ambiguity — may still appear in feed)
  - topic: "primary_language"
    ambiguity_score: 1
    evidence_pro:
      - source: "surface_scan.languages"
        snippet: "TypeScript: 95% of detected files"
        weight: 1.0
    evidence_against: []
```

---

## Quality Checks

Before returning `ambiguity_feed`:
- All `ambiguity_score` values are integers in [1, 10]
- All `topic` values are non-empty strings with no spaces (underscores used as separators)
- No duplicate `topic` values in the array
- `evidence_pro` is always an array (never null; may be empty for synthesis-only entries)
- `evidence_against` is always an array (never null; may be empty)
- All `weight` values are in [0.0, 1.0]
- Output is sorted by `ambiguity_score` descending
- `ambiguity_feed` is an array (never null; may be empty if no signals detected)

---

## Non-Goals

This skill MUST NOT:
- Make LLM calls (pure deterministic heuristic — no inference)
- Read files directly (receives structured data from prior stages)
- Generate questions (that is `smart-question-generator`'s responsibility)
- Write to memory (memory ingest is the orchestrator's responsibility post-consent gate)
- Apply the `score >= 3` threshold filter (that is `smart-question-generator`'s pre-filter)
- Rank by topic importance beyond score (that is `topic-importance-ranker` / E107bS04's concern)
- Substitute for `bootstrap-llm-synthesis` — it scores ambiguities, not synthesizes project context
- Perform retries or caching — stateless, called once per bootstrap session
