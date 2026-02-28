---
type: memory_index
id: MEMORY-INDEX
updated_at: YYYY-MM-DD
---

# Memory Map

> Always keep this index current. Agents use it to know what exists before calling `memory-retrieve`.
> Update when files are added, archived, or compacted.

---

## Categories

| Category | Path | Purpose | Load frequency |
|---|---|---|---|
| `project/` | `project/context.md` | Product vision, scope, constraints | Every session |
| `decisions/` | `decisions/_log.md` | Validated choices (append-only) | Selective |
| `patterns/` | `patterns/conventions.md` | Coding conventions, procedural knowledge | Every Delivery session |
| `summaries/` | *(empty — add as project grows)* | Compacted episodic knowledge | Selective |
| `sessions/` | *(empty — add temporary notes here)* | Short-term session exploration | Never (source for summaries) |
| `archive/` | *(empty — moved here after compaction)* | Historical storage | Rarely |

---

## Active Files

| File | Category | ID | Last updated |
|---|---|---|---|
| `project/context.md` | project | PROJECT-001 | — |
| `decisions/_log.md` | decisions | DECISIONS-LOG | — |
| `patterns/conventions.md` | patterns | PATTERNS-001 | — |

---

## Memory Principles

- **Retrieve selectively** — never load entire folders
- **Prefer summaries** over raw session notes
- **Archive aggressively** — move compacted content to `archive/`
- **Sessions are temporary** — always summarize before closing
- **Memory is distilled knowledge — not history**
