---
type: memory_index
id: MEMORY-INDEX
updated_at: 2026-02-19
---

# Memory Map

> Always keep this index current. Agents use it to know what exists before calling `memory-retrieve`.
> Update when files are added, archived, or compacted.

---

## Categories

| Category | Path | Purpose | Load frequency |
|---|---|---|---|
| `project/` | `project/context.md` | Product vision, scope, stack, constraints, SMART objectives | Every session |
| `decisions/` | `decisions/_log.md` | Validated choices — 23 decisions logged (append-only) | Selective |
| `patterns/` | `patterns/conventions.md` | Coding conventions, procedural knowledge | Every Delivery session |
| `contacts/` | `contacts/leads.md` | Experts identifiés pendant Discovery — à contacter au lancement | Delivery phase |
| `summaries/` | *(empty — add as project grows)* | Compacted episodic knowledge | Selective |
| `sessions/` | *(empty — add temporary notes here)* | Short-term session exploration | Never (source for summaries) |
| `archive/` | *(empty — moved here after compaction)* | Historical storage | Rarely |

---

## Active Files

| File | Category | ID | Last updated |
|---|---|---|---|
| `project/context.md` | project | PROJECT-001 | 2026-02-19 (updated: Callibrate, stack, architecture) |
| `decisions/_log.md` | decisions | DECISIONS-LOG | 2026-02-19 |
| `patterns/conventions.md` | patterns | PATTERNS-001 | — |
| `contacts/leads.md` | contacts | CONTACTS-001 | 2026-02-19 |

---

## Active Artefacts (reference only — not memory)

| File | Type | Status |
|---|---|---|
| `artefacts/prd/PRD-001.prd.md` | PRD | Active — master product PRD |
| `artefacts/epics/E01.epic.md` | Epic | Active |
| `artefacts/epics/E02.epic.md` | Epic | Active — blocked until E01 + E06 PASS |
| `artefacts/epics/E03.epic.md` | Epic | Active — blocked until E02 complete |
| `artefacts/epics/E04.epic.md` | Epic | Active — blocked until E03 complete |
| `artefacts/epics/E05.epic.md` | Epic | Active — blocked until E04 complete |
| `artefacts/epics/E06.epic.md` | Epic | Active — runs parallel with E01, blocks E02–E05 |
| `artefacts/stories/E01S01.story.md` | Story | Refined — ready |
| `artefacts/stories/E01S02.story.md` | Story | Refined — ready (after E01S01) |
| `artefacts/stories/E01S03.story.md` | Story | Refined — ready (parallel with E01S02) |
| `artefacts/stories/E01S04.story.md` | Story | Refined — blocked by E01S02 + E01S03 |
| `artefacts/stories/E06S01.story.md` | Story | Refined — ready (no dependencies) |
| `artefacts/stories/E06S02.story.md` | Story | Refined — blocked by E06S01 |
| `artefacts/stories/E06S03.story.md` | Story | Refined — blocked by E06S02 |
| `artefacts/stories/E06S04.story.md` | Story | Refined — blocked by E06S03 |
| `artefacts/stories/E06S05.story.md` | Story | Refined — blocked by E06S02 (parallel with E06S03/04) |
| `artefacts/stories/E06S06.story.md` | Story | Refined — blocked by E06S03 + E06S04 + E06S05 |
| `artefacts/stories/E06S07.story.md` | Story | Refined — blocked by E06S02 + E06S05 |
| `artefacts/stories/E06S08.story.md` | Story | Refined — blocked by E06S01 + E06S02 (parallel with E06S07) |
| `artefacts/stories/E06S09.story.md` | Story | Refined — blocked by E06S02 + E06S06 |
| `artefacts/strategy/GTM-001.md` | Strategy | GTM plan — 4 phases, binary PASS/FAIL gates, J0–J90 |
| `artefacts/marketing/E01S01-reddit-posts.md` | Marketing | Reddit discussion posts + observation log |
| `artefacts/marketing/E01S01-community-posts.md` | Marketing | Slack/Discord engagement messages + observation log |

---

## Memory Principles

- **Retrieve selectively** — never load entire folders
- **Prefer summaries** over raw session notes
- **Archive aggressively** — move compacted content to `archive/`
- **Sessions are temporary** — always summarize before closing
- **Memory is distilled knowledge — not history**
