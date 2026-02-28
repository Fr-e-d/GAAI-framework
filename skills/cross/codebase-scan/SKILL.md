---
name: codebase-scan
description: Create a high-level map of the project structure and identify architectural pillars, entry points, and module boundaries. Activate at Bootstrap initialization or before architecture extraction.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CODEBASE-SCAN-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - repository/**
outputs:
  - codebase_tree
  - key_files_list
---

# Codebase Scan

## Purpose / When to Activate

Activate:
- During Bootstrap initialization (before architecture extraction)
- When onboarding GAAI onto an existing codebase
- When the project structure is unknown

---

## Process

1. Recursively list directories and files
2. Identify entry points, config files, manifests, and core modules
3. Highlight likely architecture boundaries
4. Output a structured project tree and key file list

---

## Outputs

**`codebase_tree`** — structured directory tree with annotations for key files

**`key_files_list`** — list of significant files: entry points, configs, manifests, core modules, test runners

---

## Quality Checks

- Repository structure is fully visible
- Core technical pillars are identified
- No blind spots remain
- Output is structured for use by `architecture-extract`

---

## Non-Goals

This skill must NOT:
- Interpret architecture decisions (use `architecture-extract`)
- Read file contents in depth
- Make recommendations

**Maps the terrain. Does not interpret it.**
