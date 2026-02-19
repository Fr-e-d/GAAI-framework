# GAAI Skills — Index

Skills are **pure execution units**. They perform a single, well-defined operation and produce explicit outputs. They never reason about intent or strategy.

> Agents decide. Skills execute.

---

## Structure

Each skill lives in its own directory with a `SKILL.md` file:

```
skills/
├── discovery/   ← produce artefacts (PRD, Epics, Stories, validation)
├── delivery/    ← orchestrate and execute (planning, implementation, QA)
└── cross/       ← memory, context, governance, analysis — usable by any agent
```

The source of truth for available skills is the directory itself.
Browse each folder to see what skills exist and read their `SKILL.md` for details.

---

## Invocation Rules

1. Skills are **never invoked implicitly** — an agent always selects and invokes explicitly
2. Skills execute in **isolated context windows** — no shared state between skills
3. Skills **never chain** other skills — only agents orchestrate
4. Skills **never access memory** autonomously — context is always provided by the agent
5. Skills **never make product or architectural decisions** — they execute only

---

## Skill Authoring Guidance

### When to add a skill vs. when to add a rule

These two are easy to confuse because both live in `.gaai/` and both govern agent behavior.

| You want to... | Use... |
|---|---|
| Add a new **execution capability** (something an agent will *do*) | `create-skill` |
| Add a new **constraint** (something an agent must *not* do, or a standard it must follow) | `rules-normalize` |

**Skills** are procedural: they perform a defined operation and produce outputs. They live in `.gaai/skills/`.

**Rules** are declarative: they state constraints, policies, and governance boundaries. They live in `.gaai/contexts/rules/`.

### Decision test

Ask: "Does this describe *how to do something*, or *whether something is allowed*?"

- "How to generate a Story from an Epic" → skill (`generate-stories`)
- "Stories must have acceptance criteria before entering the backlog" → rule (`orchestration.rules.md`)
- "How to compact memory when it exceeds a size threshold" → skill (`memory-compact`)
- "Memory must never be auto-loaded by a skill" → rule (`orchestration.rules.md`)

If your answer is "how to do something" → skill.
If your answer is "a constraint the system must enforce" → rule.

### How to create each

- New skill: invoke `create-skill` (`.gaai/skills/cross/create-skill/SKILL.md`)
- New rule: invoke `rules-normalize` (`.gaai/skills/cross/rules-normalize/SKILL.md`)

---

## Final Rule

> If a skill appears to "think", it is wrongly designed.

---

→ [discovery/](discovery/) — skills that produce artefacts
→ [delivery/](delivery/) — skills that orchestrate and execute
→ [cross/](cross/) — skills for memory, context, governance
→ [Back to GAAI.md](../GAAI.md)
