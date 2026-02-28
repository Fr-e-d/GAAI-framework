---
name: create-skill
description: Guide creation of a new GAAI skill following the agentskills.io spec and GAAI best practices. Activate when adding a new skill to the .gaai/core/skills/ catalog.
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-CRS-016
  updated_at: 2026-02-26
  status: stable
inputs:
  - skill_intent: description of what the skill should do
  - skill_category: discovery|delivery|cross
  - skill_track: discovery|delivery|cross-cutting
  - existing_skills: list of current skills to check for overlap
outputs:
  - .gaai/core/skills/{category}/{skill-name}/SKILL.md
  - updated .gaai/core/skills/README.skills.md entry
---

# Create Skill

## Purpose / When to Activate

Activate when:
- A new capability is needed that no existing skill covers
- A skill is being extracted from agent logic that has become reusable
- Extending a forked GAAI installation with project-specific skills

This skill is self-referential: it uses the agentskills.io spec to author a spec-compliant skill.

---

## Prerequisites

Before activating:
1. Confirm no existing skill already covers the intended capability (check `README.skills.md`)
2. Confirm the new skill is a **pure execution unit** — it executes, it does not reason
3. Confirm the skill belongs to exactly one category (discovery / delivery / cross)
4. Have a clear, one-sentence description of: WHAT it does and WHEN to activate it

If a skill "appears to think" in the design, it is wrongly scoped. Redesign or split.

---

## Process

### Step 1 — Name and classify

Derive the skill name from the action it performs:
- Use lowercase kebab-case
- Name should be a verb phrase: `generate-stories`, `qa-review`, `memory-compact`
- Category: discovery (produces artefacts) | delivery (implements/validates) | cross (shared utility)

Verify name does not conflict with an existing skill in `README.skills.md`.

### Step 2 — Define inputs and outputs explicitly

List every input the skill requires. Be specific:
- What file paths does it read?
- What structured data does it receive from the invoking agent?
- What context is assumed to be present?

List every output the skill produces:
- File paths created or modified
- Structured data returned to the agent
- Side effects (backlog state changes, memory updates)

If inputs or outputs are unclear, the skill is not ready to be written. Clarify first.

### Step 3 — Write the SKILL.md frontmatter

```yaml
---
name: {skill-name}                  # matches directory name exactly
description: {one sentence}         # WHAT it does + WHEN to activate
license: ELv2
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: {author}
  version: "1.0"
  category: {discovery|delivery|cross}
  track: {discovery|delivery|cross-cutting}
  id: SKILL-{CAT}-{NNN}
  updated_at: {YYYY-MM-DD}
  status: stable|experimental       # use experimental for new/unproven skills
inputs:
  - {input_1}: {description}
  - {input_2}: {description}
outputs:
  - {output_path_or_description}
---
```

**Description rule:** Must be one sentence, ≤ 1024 characters. Format:
> "{Verb phrase that describes the output} when {activation condition}."

Example: "Generate Stories from an Epic with testable acceptance criteria when Discovery is refining a new feature scope."

### Step 4 — Write the skill body

Required sections:

```markdown
# {Skill Title}

## Purpose / When to Activate
When and why an agent should invoke this skill. Be explicit.

## Process
Numbered steps. Each step produces a specific output or advances the state.
Steps must be deterministic: same inputs → same outputs.

## Quality Checks
What must be true for the output to be acceptable.
List as assertions, not descriptions.

## Outputs
Exact file paths or structured outputs produced.

## Non-Goals
What this skill must NOT do. Prevents scope creep.
```

Add a final line if applicable:
> **No silent assumptions. Every {X} becomes explicit and governed.**

### Step 5 — Create directory and file

```
.gaai/core/skills/{category}/{skill-name}/SKILL.md
```

`SKILL.md` filename is always uppercase (spec requirement).

Optional subdirectories (create only if needed):
- `references/` — supporting documents the skill references
- `assets/` — templates or static files the skill produces

### Step 6 — Regenerate the skills index

Invoke `build-skills-index` (`.gaai/core/skills/cross/build-skills-index/SKILL.md`) to regenerate `.gaai/core/skills/skills-index.yaml` from the updated frontmatter.

Do not manually edit `skills-index.yaml` — it is a derived artifact.

### Step 7 — Reference in agent file

If the skill is intended for a specific agent (Discovery or Delivery), add it to the agent's skill list in:
- `.gaai/core/agents/discovery.agent.md` — Skills Used section
- `.gaai/core/agents/delivery.agent.md` — Skills Used section
- Or neither, if it's a general cross skill invoked opportunistically

---

## Quality Checks

- Skill name matches directory name exactly
- `SKILL.md` frontmatter has `name` and `description` at top level (spec requirement)
- Description is ≤ 1024 characters, one sentence
- All inputs are explicitly declared
- All outputs are explicitly declared with file paths where applicable
- Skill body has all 5 required sections
- Non-Goals section explicitly prevents scope creep
- `README.skills.md` updated
- `health-check.sh` passes after creation

---

## Non-Goals

This skill must NOT:
- Design agent behavior or orchestration logic (that is an agent concern)
- Make decisions about when to activate the skill (the invoking agent decides)
- Merge or replace an existing skill (deprecation requires explicit human decision)

**A skill that appears to think is wrongly designed. Redesign before authoring.**
