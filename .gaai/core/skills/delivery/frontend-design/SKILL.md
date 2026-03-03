---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, or applications. Generates creative, polished code that avoids generic AI aesthetics.
license: Complete terms in LICENSE.txt
compatibility: HTML/CSS/JS, React, Vue, Svelte, and other frontend frameworks
metadata:
  author: Anthropic
  source: claude-plugins-official
  version: "1.0"
  category: delivery
  track: delivery
  id: SKILL-FRONTEND-DESIGN-001
  updated_at: 2026-03-01
  status: stable
inputs:
  - user_requirements (component, page, app, or interface description)
  - technical_constraints (framework, performance, accessibility)
  - design_context (purpose, audience, brand guidelines)
outputs:
  - production_grade_code (HTML/CSS/JS or framework-specific)
  - design_system_documentation
  - aesthetic_rationale
---

# Frontend Design

## Purpose / When to Activate

Activate when:
- User requests to build a web component, page, application, or interface
- Frontend requirements are provided with context about purpose, audience, or constraints
- Goal is to create distinctive, visually striking code that avoids generic AI aesthetics

---

## Design Thinking Process

Before coding, commit to a BOLD aesthetic direction:

### 1. **Understand Context**
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone/Aesthetic**: Pick an extreme direction (brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc.)
- **Technical Constraints**: Framework, performance, accessibility requirements
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

### 2. **Choose a Clear Conceptual Direction**

CRITICAL: Execute with precision. Bold maximalism and refined minimalism both work—the key is intentionality, not intensity.

### 3. **Implement Working Code**

Production-grade implementation (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and fully functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

---

## Frontend Aesthetics Guidelines

### Typography
- Choose fonts that are beautiful, unique, and interesting
- Avoid generic fonts (Arial, Inter, system fonts)
- Opt for distinctive, characterful font choices
- Pair a distinctive display font with a refined body font
- Unexpected and unexpected font combinations elevate the design

### Color & Theme
- Commit to a cohesive aesthetic vision
- Use CSS variables for consistency
- Dominant colors with sharp accents outperform timid, evenly-distributed palettes
- Create atmosphere and depth with creative color application

### Motion & Animation
- Use animations for effects and micro-interactions
- Prioritize CSS-only solutions for HTML; use Motion library for React when available
- Focus on high-impact moments: one well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions
- Use scroll-triggering and hover states that surprise and delight

### Spatial Composition
- Unexpected layouts with asymmetry
- Overlap elements for depth
- Diagonal flow and grid-breaking elements
- Generous negative space OR controlled density
- Avoid predictable, cookie-cutter layouts

### Backgrounds & Visual Details
- Create atmosphere and depth rather than defaulting to solid colors
- Add contextual effects and textures matching the overall aesthetic
- Apply creative forms: gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, grain overlays

---

## Anti-Patterns: What NOT to Do

NEVER use generic AI-generated aesthetics:
- ❌ Overused font families (Inter, Roboto, Arial, system fonts)
- ❌ Clichéd color schemes (particularly purple gradients on white backgrounds)
- ❌ Predictable layouts and component patterns
- ❌ Cookie-cutter design lacking context-specific character
- ❌ Convergence on common choices across generations

**DO**: Interpret creatively and make unexpected choices that feel genuinely designed for the context.

---

## Implementation Strategy

1. **Interpret requirements creatively**
2. **Commit to a distinctive aesthetic vision** (not "safe" or middle-ground)
3. **Implement with meticulous attention to detail**
4. **Match implementation complexity to aesthetic vision**:
   - Maximalist designs need elaborate code with extensive animations and effects
   - Minimalist designs need restraint, precision, careful attention to spacing, typography, and subtle details
   - Elegance comes from executing the vision well

---

## Quality Checks

- ✓ Code is production-grade and fully functional
- ✓ Design has a clear, intentional aesthetic direction
- ✓ Typography is distinctive and purpose-driven
- ✓ Color palette is cohesive with dominant/accent structure
- ✓ Spacing and composition feel intentional, not generic
- ✓ Animations and micro-interactions have high-impact moments
- ✓ Visual details (backgrounds, textures, effects) support the aesthetic
- ✓ Code is clean, maintainable, and follows framework conventions
- ✓ Design differentiates from generic AI aesthetics
- ✓ All constraints (accessibility, performance, framework) are respected

---

## Non-Goals

This skill must NOT:
- Default to safe, middle-ground design choices
- Use generic fonts and color palettes
- Create predictable layouts that lack distinctive character
- Ignore the context and audience
- Prioritize speed over deliberate aesthetic choices

**"I create interfaces that are bold, intentional, and genuinely memorable."**

---

## References

- [Frontend Aesthetics Cookbook](https://github.com/anthropics/claude-cookbooks/blob/main/coding/prompting_for_frontend_aesthetics.ipynb)
- Authors: Prithvi Rajasekaran, Alexander Bricken (Anthropic)
