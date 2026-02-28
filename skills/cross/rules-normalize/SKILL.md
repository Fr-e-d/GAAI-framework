---
name: rules-normalize
description: Convert implicit or scattered project conventions into governed GAAI rule files, and create or modify rule files with integrity. Activate during Bootstrap, when creating a new rule, or when modifying an existing rule.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-RULES-NORMALIZE-001
  updated_at: 2026-02-26
  status: stable
inputs:
  - detected_rule_files
  - existing_conventions  (linters, security configs, style guides, CI constraints)
  - project_guidelines
outputs:
  - contexts/rules/**
---

# Rules Normalize

## Purpose / When to Activate

Activate when:
- **Bootstrap** — project has existing conventions (linters, security policies, style guides, architecture docs, CI constraints) that need to become explicit governance
- **Creating a new rule** — any agent or human intends to add a new `.rules.md` file
- **Modifying an existing rule** — any agent or human intends to change the content or structure of an existing rule file

Converts all implicit conventions into explicit GAAI governance rules. Ensures rule integrity on creation and modification.

---

## Process

### When normalizing existing conventions (Bootstrap)

1. Locate all rule-like files and convention sources
2. Classify by domain: architecture / code quality / security / testing / performance
3. Translate each convention into standard GAAI rule format:
   - Explicit condition
   - Scope of application
   - Enforcement level
4. Store normalized rules under `contexts/rules/`
5. Remove ambiguity and duplication

### When creating or modifying a rule file

1. Read `contexts/rules/README.rules.md` — verify no existing rule already covers the intent
2. If creating: assign the correct `category` and next `id` in sequence; add entry to index
3. If modifying: confirm the change is a constraint refinement, not a workflow or agent behavior addition
4. Apply the standard rule file format (YAML frontmatter + markdown body)
5. Verify no overlap or contradiction with other rule files

---

## Quality Checks

- All critical project constraints are explicit
- Rules are machine-checkable
- No important convention remains implicit
- Governance coverage is clear
- No duplication across rule files

---

## Non-Goals

This skill must NOT:
- Create new architectural decisions
- Modify business logic
- Enforce rules during delivery (enforcement is handled by workflows and validation stages)

**No silent assumptions. Every constraint becomes explicit and governed.**
