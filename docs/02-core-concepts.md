# Core Concepts

Five concepts. That's all you need to understand GAAI.

---

## 1. Dual Track

GAAI separates two fundamentally different activities:

**Discovery Track** — figuring out what to build and why
- Human-facing. Produces artefacts. Asks questions. Validates intent.
- Owned by the **Discovery Agent**

**Delivery Track** — building it correctly and verifiably
- Execution-focused. Implements. Tests. Passes QA.
- Owned by the **Delivery Agent**

Discovery must complete before Delivery begins. This prevents the most common AI failure mode: building the wrong thing fast.

These two tracks are not just different phases — they are architecturally different systems:

| Dimension | Discovery Agent | Delivery Agent |
|-----------|----------------|----------------|
| Primary interlocutor | The human | The backlog |
| Nature of work | Conversation + clarification + artefact generation | Deterministic execution against a plan |
| Output | PRDs, Epics, Stories (~short, structured) | Code, tests, QA reports |
| Expected interruptions | Frequent — asks the human questions | Rare — only escalates when blocked |
| Context requirement | Conversational continuity is critical | Phase isolation improves quality |
| Authorization source | Human intent + project constraints | Backlog item with `status: refined` |
| When it stops | Never stops mid-conversation | Stops on QA failure or ambiguity |

This asymmetry is why Discovery and Delivery have different agents, different authority models, and different activation patterns. They are not interchangeable.

---

## 2. The Backlog (The Only Authorization Mechanism)

> If it's not in the backlog, it must not be executed.

The backlog is not a to-do list. It is the **only authority** that permits the Delivery Agent to act.

- Location: `.gaai/project/contexts/backlog/active.backlog.yaml`
- Format: YAML (one file for all active items)
- States: `draft` → `needs-refinement` → `refined` → `in-progress` → `done`

The Delivery Agent reads the backlog, picks the next `refined` item, and executes it. Nothing else.

---

## 3. Agents vs Skills

**Agents** reason, decide, and orchestrate. They have authority.

**Skills** execute. They do one thing and produce explicit output. They never decide anything.

| | Agent | Skill |
|---|---|---|
| Interprets intent | Yes | No |
| Selects context | Yes | No |
| Decides strategy | Yes | No |
| Executes procedure | No | Yes |
| Produces artefacts | No | Yes |

The Delivery Agent invokes the `implement` skill. The `implement` skill cannot decide what to implement. That separation is what makes AI execution predictable.

> If a skill appears to think, it is wrongly designed.

---

## 4. Explicit Memory

Memory in GAAI is **never automatically loaded**. Agents select what context they need. Always.

This matters because:
- Auto-loading all memory wastes tokens and introduces noise
- Context pollution leads to drift and contradictions
- Explicit selection makes agent behavior predictable and auditable

Memory lives in `.gaai/project/contexts/memory/`. The structure — project context, decisions log, patterns, summaries — is defined in `.gaai/project/contexts/memory/README.memory.md`. You can add domain-specific memory files; agents select them explicitly using `memory-retrieve`.

---

## 5. Artefacts as Evidence (Not Authority)

Artefacts (Epics, Stories, Plans) are documentation. They explain intent and decisions. They are not the authorization mechanism.

| Documents intent | Authorizes execution |
|---|---|
| Epic artefact | Backlog item |
| Story artefact | Backlog item with `status: refined` |
| PRD | Backlog items it generates |

An artefact with no backlog item cannot trigger execution. A backlog item with no artefact can still be executed (though artefacts are strongly recommended for clarity).

---

## Putting It Together

```
Human intent
    ↓
Discovery Agent (reasons, produces artefacts, validates)
    ↓
Backlog items (status: refined — authorization granted)
    ↓
Delivery Agent (invokes skills, executes plan, runs QA)
    ↓
Done items (move to done/)
    ↓
Memory captures decisions for future sessions
```

→ [Getting Started](03-getting-started.md) — set it up
→ [Quick Start](guides/quick-start.md) — try it now
