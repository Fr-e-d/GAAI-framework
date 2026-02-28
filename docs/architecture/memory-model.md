# Memory Model

How GAAI handles memory across sessions — and why.

---

## The Core Problem

AI sessions are stateless by default. Every session starts fresh. Without an explicit memory system:
- Decisions get re-made and contradicted
- Conventions drift between sessions
- Context that took an hour to establish is lost
- The AI's behavior becomes unpredictable over time

Most AI tools solve this with auto-loading: dump everything into the context window at session start. GAAI solves it differently.

---

## GAAI's Approach: Explicit, Agent-Selected Memory

**The golden rule:** Memory is never auto-loaded. Agents select what they need.

This matters because:

1. **Token efficiency** — loading all memory into every context wastes tokens. Most memory is irrelevant to any given task.

2. **Signal quality** — more context is not always better. Irrelevant memory introduces noise that leads to contradictions and drift.

3. **Reproducibility** — when you know exactly what context was loaded, you can reproduce the agent's reasoning.

4. **Auditability** — you can audit why the agent made a decision by knowing what it knew at the time.

---

## Memory Structure

```
.gaai/project/contexts/memory/
├── index.md              ← memory map, always maintained
├── _template.md          ← template for new entries
├── project/              ← semantic memory (loaded every session)
│   └── context.md
├── decisions/            ← episodic memory (append-only, loaded selectively)
│   └── _log.md
├── patterns/             ← procedural memory (loaded every Delivery session)
│   └── conventions.md
├── summaries/            ← compacted episodic (replaces session notes)
├── sessions/             ← working memory (temporary, source for summaries)
└── archive/              ← historical storage
```

This structure maps to memory science categories:

| Category | Memory type | Analogy |
|---|---|---|
| `project/` | Semantic | Stable facts about the world |
| `decisions/` | Episodic | What happened, when, why |
| `patterns/` | Procedural | How to do things |
| `summaries/` | Compacted episodic | Distilled long-term memory |
| `sessions/` | Working | Short-term, volatile |

### `project/context.md`

Always loaded. Project fundamentals every agent needs every session:
- What the project is and who it's for
- Tech stack and language
- Non-negotiable constraints
- Key dependencies

**Keep it short.** If it grows beyond 2-3 screens, move specifics to `decisions/`.

### `decisions/_log.md`

Append-only log of durable decisions. Agents append using `decision-extraction` and `memory-ingest`.

Loaded selectively — `memory-retrieve` filters by relevance to the current task. For large projects, split by domain: `decisions/auth.md`, `decisions/api.md`.

**Never delete entries** — append revisions if a decision changes.

### `patterns/conventions.md`

Coding conventions, naming rules, testing approach. The Delivery Agent loads this before every implementation task.

Procedural memory is not append-only — it's updated as conventions evolve.

### `sessions/` and `summaries/`

Sessions store temporary working notes. The `summarization` and `memory-refresh` skills distill sessions into `summaries/`, then archive the originals. Summaries become the efficient long-term source.

---

## How Agents Use Memory

### memory-retrieve

The entry point for every session. The agent invokes `memory-retrieve` with the current task context. The skill returns a filtered bundle: only memory entries relevant to the task.

This prevents the "load everything" trap.

### memory-ingest

After a significant decision or discovery, the agent uses `memory-ingest` to add new entries to the correct category folder. Entries follow the format in `_template.md`.

### memory-compact

Over time `decisions/_log.md` and session notes grow. `memory-compact` distills verbose entries into compact summaries in `summaries/`, then archives the originals.

### memory-refresh

Periodically, outdated entries need revision. `memory-refresh` identifies stale entries and updates them based on current project state.

---

## Memory Lifecycle

```
Decision made during session
           ↓
decision-extraction → structured entry
           ↓
memory-ingest → appended to decisions/_log.md
           ↓
memory-retrieve → loads relevant subset for next session
           ↓
memory-compact → distills when file grows large
           ↓
memory-snapshot → archived before risky work
```

---

## Memory Scope and Boundaries

Memory is **project-level** — it lives in `.gaai/project/contexts/memory/` alongside your code.

This means:
- Memory is versioned in git
- Memory is shared across team members (with appropriate conventions — see [Team Setup Guide](../guides/team-setup-guide.md))
- Memory survives AI tool changes (Cursor → Claude Code → anything else)
- Memory can be reviewed and edited by humans at any time

Memory is **not** conversation-level (like chat history). It's curated, structured knowledge — not a transcript.

---

## Extending Memory

For large projects, split decisions by domain within the `decisions/` folder:

```
memory/
├── project/
│   └── context.md
├── decisions/
│   ├── _log.md            ← cross-cutting decisions
│   ├── auth.md            ← authentication decisions
│   ├── payments.md        ← payments decisions
│   └── infra.md           ← infrastructure decisions
├── patterns/
│   └── conventions.md
├── summaries/
└── sessions/
```

Update `index.md` when adding new files. Agents will load domain-specific memory via `memory-retrieve` when working on related tasks.

---

→ [Contexts Reference](../reference/contexts.md)
→ [Design Decisions](design-decisions.md)
