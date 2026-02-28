# GAAI Memory System

The GAAI Memory system provides **long-term structured context** for AI-assisted development —
without flooding the LLM context window.

Memory preserves knowledge, decisions, and product context in a form that remains:
- selective
- cheap in tokens
- governance-friendly
- scalable over long projects

---

## Why Memory Exists

Without structured memory, AI systems suffer from:
- context loss
- repeated decisions
- drifting priorities
- exploding token usage

GAAI memory ensures:
- ✅ durable knowledge
- ✅ explicit decisions
- ✅ minimal context injection
- ✅ predictable reasoning

---

## Golden Rule

> **Memory is never auto-loaded.**
> **Memory is always agent-selected.**

---

## Memory Ownership Model

In GAAI:
- **Agents control memory.**
- **Skills never load memory implicitly.**

### Canonical Flow

1. Agent determines what context is needed
2. Agent invokes `memory-retrieve` skill
3. Skill returns a focused context bundle
4. Agent injects selected memory into the next skill

Skills operate in **isolated context windows** and only process what is explicitly provided.

This guarantees:
- no hidden context pollution
- deterministic reasoning
- strict token control
- long-term scalability

---

## Folder Structure

```
contexts/memory/
├── README.memory.md      ← you are here
├── index.md              ← memory map (always maintained)
├── _template.md          ← template for new memory files
├── project/              ← semantic: product vision & scope
│   └── context.md
├── decisions/            ← episodic: validated choices (append-only)
│   └── _log.md
├── patterns/             ← procedural: conventions & coding rules
│   └── conventions.md
├── domains/              ← domain-scoped memory (DEC-93)
│   └── content-production/
│       ├── index.md      ← domain registry (sources, gaps)
│       ├── sources/      ← research AKUs
│       └── voice-guide.md
├── summaries/            ← compacted episodic knowledge
├── sessions/             ← working: temporary session notes
└── archive/              ← historical storage
```

### Shared Categories

| Category | Memory type | Purpose | Load frequency |
|---|---|---|---|
| `project/` | Semantic | Product vision, scope, constraints | Every session |
| `decisions/` | Episodic | Validated choices, append-only | Selective |
| `patterns/` | Procedural | Coding conventions, proven approaches | Every Delivery session |
| `summaries/` | Compacted episodic | Distilled knowledge from sessions/decisions | Selective |
| `sessions/` | Working | Temporary session exploration | Never (source for summaries) |
| `archive/` | Historical | Old entries after compaction | Rarely |

### Domain Memory

Domain memory is scoped to domain sub-agents (DEC-93). A domain qualifies for its own `domains/{domain}/` folder when it has **≥5 skills AND its own knowledge base**.

| Domain | Memory type | Purpose | Load frequency |
|---|---|---|---|
| `domains/content-production/` | Mixed (research + patterns) | AKUs, sources, voice guide, gap analysis for content blueprint | When content domain sub-agent active |

**Convention for new domains:**
1. Create `domains/{domain-name}/index.md` with standard YAML frontmatter (`type: memory`, `category: domain`, `domain: {name}`)
2. Register the domain in `index.md` → Domain Memory table
3. When ingesting into a domain, update BOTH the master `index.md` AND the domain `index.md`

---

## Universal YAML Frontmatter

Every memory file starts with:

```yaml
---
type: memory
category: project | decision | summary | session
id: UNIQUE-ID
tags:
  - product
  - architecture
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---
```

This enables:
- selective retrieval
- filtering by relevance
- governance & traceability

---

## Always Maintain `index.md`

`index.md` is the memory map. Agents check it first to know what files exist before invoking `memory-retrieve`. Keep it current: add new files when created, update timestamps, mark files moved to `archive/`.

---

## Best Practices

- Always retrieve selectively — never load entire folders
- Prefer summaries over raw session history
- Archive aggressively — move compacted content to `archive/`
- Session notes are temporary — summarize before closing a session
- Split large decision logs by domain: `decisions/auth.md`, `decisions/api.md`
- Treat memory as knowledge — not logs

## Anti-Patterns (Avoid)

- ❌ loading entire memory folders
- ❌ storing raw chat transcripts long-term
- ❌ skipping summarization of session notes
- ❌ implicit context injection

---

## Final Principle

**Memory is distilled knowledge — not history.**

If a file is not useful for future reasoning:
→ summarize it
→ archive it

Never let context grow uncontrolled.

---

## Memory Specimens (Filled Examples)

Not sure what good memory looks like after a real project? Read these:

- [project/context.example.md](project/context.example.md) — filled project memory after ~4 weeks of development
- [decisions/_log.example.md](decisions/_log.example.md) — three real decision entries with context and impact
- [patterns/conventions.example.md](patterns/conventions.example.md) — conventions file after several confirmed patterns

These are read-only illustrations. Your actual memory lives in the non-`.example` files.

---

→ [project/context.md](project/context.md) — fill this in first (project name, purpose, constraints)
→ [decisions/_log.md](decisions/_log.md) — append-only decision log
→ [Back to README.contexts.md](../README.contexts.md)
→ [Back to GAAI.md](../../GAAI.md)
