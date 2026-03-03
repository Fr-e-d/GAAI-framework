# Agent Skills — Per-Agent Recommendations

Each agent has a skill index recommending which skills to load and when.

## Agent Skill Indices

| Agent | File | Skills | Required |
|---|---|---|---|
| **Discovery** | `.gaai/core/agents/discovery.agent-skills.yaml` | 10 available | 2 required |
| **Delivery** | `.gaai/core/agents/delivery.agent-skills.yaml` | 11 available | 2 required |
| **Bootstrap** | `.gaai/core/agents/bootstrap.agent-skills.yaml` | 4 available | 2 required |

## How to Use These Indices

### Agent Startup

When an agent starts (e.g., Discovery Agent invoked):

1. **Load agent skills index:**
   ```yaml
   load: .gaai/core/agents/{agent}.agent-skills.yaml
   ```

2. **Identify required skills:**
   ```
   required_skills: [SKILL-VALIDATE-ARTEFACTS-001, ...]
   action: Preload these (non-negotiable)
   ```

3. **Scan available skills:**
   ```
   project_skills: [SKILL-DOMAIN-KNOWLEDGE-001, SKILL-ANALYTICS-QUERY-001, ...]
   action: Load on demand (when task matches "when" condition)
   ```

### Example: Discovery Agent Startup

```
1. Agent: discovery
2. Load index: discovery.agent-skills.yaml
3. Preload required:
   - validate-artefacts (before handing off to Delivery)
4. Available on demand:
   - idiomatique-translate (IF writing international copy)
   - domain-knowledge-research (IF researching market)
   - analytics-query (IF analyzing user behavior)
   - ... (8 more)
```

## Skill Categories

### Core Skills
Skills from `.gaai/core/skills/` (framework-level, generic)

### Project Skills
Skills from `.gaai/project/skills/` (project-specific, domain knowledge)

### Cross Skills
Reusable across agents (content, analysis, validation, governance)

## Required vs Optional

- **Required:** Must preload before agent begins
- **Optional:** Load on-demand when task context matches "when" condition

Example from Delivery Agent:
```yaml
required_skills:
  - remediate-failures  (always needed for QA loop)
  - framework-sync      (always needed for compliance)

optional_skills:
  - frontend-design     (only if building UI)
  - idiomatique-translate (only if translating copy)
```

## Customization Per Project

Project teams can extend or override agent skills:
- Create `.gaai/project/agents/discovery.agent-skills.yaml`
- Override or add project-specific skills
- Example: Add `content-plan` as required for Discovery Agent on this project

## Loading Sequence

1. **Phase 1:** Load global skills index (`.gaai/skills-index.yaml`)
2. **Phase 2:** Load agent skills index (`.gaai/core/agents/{agent}.agent-skills.yaml`)
3. **Phase 3:** Preload required skills (SKILL.md frontmatter)
4. **Phase 4:** Load optional skills on-demand (when task triggers "when" condition)

## Notes

- Agent skills indices are **recommendations**, not requirements
- Agents can deviate if task demands it (e.g., Delivery Agent using `domain-knowledge-research` if needed)
- Indices are maintained manually (by project team) or via `build-agents-index` skill
- Enables **fast agent startup** (preload known essentials, load others on-demand)
