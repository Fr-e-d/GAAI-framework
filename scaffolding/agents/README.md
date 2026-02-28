# Project Agents

Custom agent definitions specific to this project.

Framework agents live in `.gaai/core/agents/`. This directory extends them with project-specific agents.

## When to Add a Custom Agent

- When you need a specialist agent not covered by the framework (e.g., a domain-specific reviewer)
- When you want to override or extend a framework agent's behavior for this project

## Naming Convention

```
{role}.agent.md
```

Example: `content-reviewer.agent.md`

## Resolution Order

The framework loads `core/agents/` first, then `project/agents/` as extensions. Project agents can reference core agents but not override them by filename — use a distinct name.

## Template

```markdown
---
type: agent
id: AGENT-PROJECT-{NNN}
role: {role-slug}
responsibility: {one-line}
track: {discovery|delivery|cross}
---

# {Agent Name}

{Description of what this agent does and when it is activated.}

## Core Mission

- {bullet points}

## Skills Used

- `{skill-name}` — {purpose}
```
