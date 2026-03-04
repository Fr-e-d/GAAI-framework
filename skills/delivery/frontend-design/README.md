# Frontend Design Skill

> **Source**: Claude Marketplace `frontend-design@claude-plugins-official`
> **Extracted**: 2026-03-01

## Overview

The **Frontend Design** skill guides the creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. It activates automatically when building web components, pages, or applications.

## What It Does

Claude uses this skill to create production-ready code with:

- **Bold aesthetic choices** — committed, intentional design directions
- **Distinctive typography and color palettes** — memorable, context-specific
- **High-impact animations and visual details** — strategic micro-interactions
- **Context-aware implementation** — tailored to purpose, audience, and constraints

## Usage Examples

```
"Create a dashboard for a music streaming app"
"Build a landing page for an AI security startup"
"Design a settings panel with dark mode and glassmorphism"
"Build a component library with a brutalist aesthetic"
```

Claude will choose a clear aesthetic direction and implement production code with meticulous attention to detail.

## Integration in GAAI

This skill is invoked as part of the **Delivery agent** workflow when:

1. A Story requires frontend implementation
2. The execution plan includes UI/UX components
3. Visual design and code generation are needed

### Relationship to Other Skills

- **`implement`** (sibling) — General code implementation
- **`frontend-design`** (this) — Specialized for distinctive frontend work
- **`browser-journey-test`** (sibling) — Testing the implemented frontend

### When to Use This Over `implement`

Use `frontend-design` when:
- ✓ Aesthetic quality and visual distinctiveness are critical
- ✓ The interface needs to stand out and avoid generic AI aesthetics
- ✓ Custom typography, color systems, and animations are required
- ✓ User-facing components (landing pages, dashboards, product UIs)

Use `implement` when:
- ✓ Backend/infrastructure code
- ✓ Generic CRUD forms where aesthetics are not a priority
- ✓ Performance-critical logic

## Core Principles

1. **No Generic AI Aesthetics** — Avoid overused fonts, clichéd color schemes, predictable layouts
2. **Intentional Design Direction** — Bold maximalism or refined minimalism, executed with precision
3. **Context-Specific Character** — Design tailored to purpose, audience, and brand
4. **Meticulous Execution** — Every detail matters: typography, spacing, animations, visual effects
5. **Production-Ready Code** — Fully functional, maintainable, framework-compliant

## Documentation Files

- **`SKILL.md`** — Comprehensive process, guidelines, and quality checks
- **`README.md`** — This file; overview and integration guide

---

**Source Attribution**: Anthropic (Prithvi Rajasekaran, Alexander Bricken)
**Reference**: [Frontend Aesthetics Cookbook](https://github.com/anthropics/claude-cookbooks/blob/main/coding/prompting_for_frontend_aesthetics.ipynb)
