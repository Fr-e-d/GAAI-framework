# Project Workflows

Custom workflow definitions specific to this project.

Framework workflows live in `.gaai/core/workflows/`. This directory extends them with project-specific multi-skill orchestrations.

## When to Add a Custom Workflow

- When a recurring process chains multiple skills in a project-specific way
- When the project has a domain workflow not covered by the framework (e.g., content publishing pipeline)

## Naming Convention

```
{workflow-name}.workflow.md
```
