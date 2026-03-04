# Agent Skills — Loading & Resolution

## Skill Indexes

Agents discover available skills via two independent indexes:

| Scope | Index | Contents |
|---|---|---|
| **Core** (framework) | `.gaai/core/skills/skills-index.yaml` | Generic, reusable skills — synced to OSS |
| **Project** (local) | `.gaai/project/skills/skills-index.yaml` | Domain-specific skills — never synced |

## Loading Sequence

When an agent starts:

1. **Load core skills index** (`.gaai/core/skills/skills-index.yaml`)
2. **Load project skills index** (`.gaai/project/skills/skills-index.yaml`) — project takes precedence if same ID exists in both
3. **Read agent definition** (`{agent}.agent.md`) — lists required and recommended skills per agent
4. **Preload required skills** (read SKILL.md for each)
5. **Load optional skills on-demand** (when task context matches)

## Required vs Optional

Each agent definition (`.gaai/core/agents/{agent}.agent.md`) lists its skills:

- **Required:** Must preload before agent begins work (non-negotiable)
- **Optional:** Load on-demand when task context matches

## Customization Per Project

Project teams can extend agent behavior by adding project skills:
- Add skills to `.gaai/project/skills/` with their own SKILL.md
- They appear automatically in the project skills index
- Agents pick them up at load time (Phase 2)

## Notes

- Agent definitions are the single source of truth for which skills each agent uses
- Skills indexes are catalogs for discovery — agents reference them to resolve skill IDs to file paths
- Agents can use any skill from either index if the task demands it
