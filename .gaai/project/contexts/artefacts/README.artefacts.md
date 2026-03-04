# GAAI Artefacts

Artefacts provide **evidence, structure, and traceability** — they never drive orchestration.

> Artefacts describe. Backlog governs. Agents decide.

## Artefact Types

| Type | Folder | Purpose |
|---|---|---|
| Epic | `epics/` | High-level product intent |
| Story | `stories/` | Intent and acceptance criteria for a backlog item |
| Plan | `plans/` | How Delivery intends to execute a Story |
| PRD | `prd/` | Product requirements for major initiatives |
| Report | `reports/` | QA results, findings, post-mortems |

## Structure

All artefacts: YAML frontmatter (machine-readable) + Markdown body (human-readable).

```yaml
---
type: artefact
artefact_type: epic | story | plan | report | prd
id: UNIQUE-ID
track: discovery | delivery
related_backlog_id: BACKLOG-ID
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---
```

## Templates

- [_template.story.md](stories/_template.story.md)
- [_template.epic.md](epics/_template.epic.md)
- [_template.plan.md](plans/_template.plan.md)
- [_template.prd.md](prd/_template.prd.md)
