# GAAI Memory System

The GAAI Memory system provides **long-term structured context** for AI-assisted development —
without flooding the LLM context window.

Memory preserves knowledge, decisions, and product context in a form that remains:
- selective
- cheap in tokens
- governance-friendly
- scalable over long projects

---

## Golden Rule

> **Memory is never auto-loaded.**
> **Memory is always agent-selected.**

Agents control memory. Skills never load memory implicitly.

1. Agent determines what context is needed
2. Agent invokes `memory-retrieve` skill
3. Skill returns a focused context bundle
4. Agent injects selected memory into the next skill

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
├── summaries/            ← compacted episodic knowledge
├── sessions/             ← working: temporary session notes
└── archive/              ← historical storage
```

| Category | Purpose | Load frequency |
|---|---|---|
| `project/` | Product vision, scope, constraints | Every session |
| `decisions/` | Validated choices, append-only | Selective |
| `patterns/` | Coding conventions, proven approaches | Every Delivery session |
| `summaries/` | Distilled knowledge from sessions/decisions | Selective |
| `sessions/` | Temporary session exploration | Never (source for summaries) |
| `archive/` | Old entries after compaction | Rarely |

---

## Best Practices

- Always retrieve selectively — never load entire folders
- Prefer summaries over raw session history
- Archive aggressively — move compacted content to `archive/`
- Session notes are temporary — summarize before closing a session
- Treat memory as knowledge — not logs

---

## Filled Examples

Not sure what good memory looks like? Read these:

- [project/context.example.md](project/context.example.md) — filled project memory after ~4 weeks
- [decisions/_log.example.md](decisions/_log.example.md) — three real decision entries
- [patterns/conventions.example.md](patterns/conventions.example.md) — conventions after several confirmed patterns

These are read-only illustrations. Your actual memory lives in the non-`.example` files.
