---
name: project-surface-scan
description: Scan project root for file tree, dominant languages, and LOC estimate. Produces structured baseline context for Stage 2 LLM synthesis during bootstrap. Respects .gitignore and standard exclusions. Outputs per-directory file counts, ranked language list, size class, and observability summary.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-PROJECT-SURFACE-SCAN-001
  updated_at: 2026-04-29
  status: stable
inputs:
  - project_root_path
outputs:
  - surface_scan_result
---

# Project Surface Scan

## Purpose / When to Activate

Activate:
- As Stage 1 of the `/gaai:bootstrap` workflow (before LLM synthesis)
- When the bootstrap orchestrator needs quantitative project baseline
- When re-running bootstrap after major structural changes

Produces `surface_scan_result` — a structured object consumed by Stage 2 LLM synthesis.

---

## Exclusions (always skip)

```
node_modules/   .git/   dist/   build/   .next/   .nuxt/
out/            .cache/ coverage/ .turbo/ .wrangler/
__pycache__/    .venv/  venv/   target/ vendor/
*.lock          *.log
```

Additionally: respect any `.gitignore` present at the project root. Use the `Glob` tool with explicit exclusion patterns — do NOT use `find` or `rg` (permission-error-safe tools only).

---

## Process

### Step 1 — Timed scan start

Record wall-clock start time before any file operations:

```
scan_start_ms = Date.now()   # conceptual — note the start time
```

Log: `[project-surface-scan] scan started at {ISO timestamp}`

### Step 2 — File tree walk

Use the `Glob` tool with pattern `**/*` from the project root.

Apply exclusion filter: skip any path segment matching the exclusion list above.

Build per-directory count map:
```
dir_counts: { "<directory>": <file_count> }
```

Aggregate at depth-1 and depth-2 only (to avoid noise from deep nesting). If a directory has > 500 files, record `"<dir>": ">500"` and do not recurse further.

**Permission errors:** if the Glob tool returns an error for a path, log the error as a warning and continue. Never abort on permission errors. Partial scan is acceptable.

### Step 3 — Extension frequency map

From the file list obtained in Step 2, build:
```
ext_counts: { ".ts": 42, ".md": 18, ".json": 12, ... }
```

Exclude paths without extension (binaries, lock files, dotfiles) from this map.

### Step 4 — Language detection

Map extensions to languages using this heuristic table:

| Extension(s) | Language |
|---|---|
| `.ts`, `.tsx` | TypeScript |
| `.js`, `.mjs`, `.cjs`, `.jsx` | JavaScript |
| `.py` | Python |
| `.go` | Go |
| `.rs` | Rust |
| `.java` | Java |
| `.kt`, `.kts` | Kotlin |
| `.rb` | Ruby |
| `.php` | PHP |
| `.cs` | C# |
| `.cpp`, `.cc`, `.cxx`, `.c`, `.h` | C/C++ |
| `.swift` | Swift |
| `.sh`, `.bash`, `.zsh` | Shell |
| `.sql` | SQL |
| `.yaml`, `.yml` | YAML |
| `.json` | JSON |
| `.md`, `.mdx` | Markdown |
| `.html`, `.htm` | HTML |
| `.css`, `.scss`, `.sass`, `.less` | CSS/SCSS |
| `.toml` | TOML |
| `.graphql`, `.gql` | GraphQL |

Aggregate by language (sum all matching extensions). Produce a ranked list:
```
languages: [
  { language: "TypeScript", file_count: 42, rank: 1 },
  { language: "Markdown",   file_count: 18, rank: 2 },
  ...
]
```

Include only languages with ≥ 2 files. Unknown extensions are grouped as `"Other"`.

### Step 5 — LOC estimation

For the top 5 languages by file count (up to 20 files each, sampled uniformly if more), use the `Read` tool to count lines. Sum line counts across all sampled files.

Project total LOC = (sampled_lines / sampled_files) × total_files

**Permission errors on individual files:** log as warning, skip file, do not abort.

Size class determination:
```
if total_estimated_loc < 10_000:    size_class = "small"
elif total_estimated_loc < 100_000: size_class = "medium"
else:                                size_class = "large"
```

### Step 6 — Observability summary

Record:
```
scan_duration_ms = Date.now() - scan_start_ms   # conceptual
```

Log (stdout):
```
[project-surface-scan] done in {scan_duration_ms}ms
  files: {total_file_count}
  languages: {len(languages)} detected
  estimated LOC: {total_estimated_loc} ({size_class})
  errors: {permission_error_count} permission errors skipped
```

---

## Output Schema (`surface_scan_result`)

```yaml
surface_scan_result:
  scanned_at: "2026-04-29T12:00:00Z"       # ISO timestamp
  scan_duration_ms: 1234
  total_file_count: 247
  permission_errors: 0                       # count of skipped paths
  size_class: "medium"                       # small | medium | large
  estimated_loc: 42800
  dir_counts:                                # depth-1 directories
    src: 183
    tests: 41
    docs: 23
  languages:                                 # ranked by file count
    - language: TypeScript
      file_count: 142
      rank: 1
    - language: Markdown
      file_count: 38
      rank: 2
  ext_counts:                                # raw extension map
    .ts: 142
    .md: 38
    .json: 27
```

---

## Quality Checks

- `total_file_count` > 0 (non-empty scan)
- At least 1 language detected
- `scan_duration_ms` is recorded (non-zero)
- `size_class` is one of `small | medium | large`
- Permission errors logged but did not abort scan

---

## Non-Goals

This skill must NOT:
- Interpret architecture decisions (use `architecture-extract`)
- Read file contents beyond LOC sampling
- Write to memory directly (use `memory-ingest` after Stage 2 synthesis)
- Make recommendations about the codebase

**Scans the terrain quantitatively. Does not interpret it.**
