# Project Rule Overrides

Rule files here override or extend the framework rules in `.gaai/core/contexts/rules/`.

## Resolution Order

Agents load `core/contexts/rules/` first, then `project/contexts/rules/`. A project rule with the same filename as a core rule overrides it entirely.

## When to Add an Override

- When the project needs stricter or relaxed constraints on a specific rule
- When a domain-specific governance rule applies only to this project
