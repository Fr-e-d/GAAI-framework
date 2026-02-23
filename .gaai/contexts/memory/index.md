---
type: memory_index
id: MEMORY-INDEX
updated_at: 2026-02-23
---

# Memory Map

> Always keep this index current. Agents use it to know what exists before calling `memory-retrieve`.
> Update when files are added, archived, or compacted.

---

## Categories

| Category | Path | Purpose | Load frequency |
|---|---|---|---|
| `project/` | `project/context.md` | Product vision, scope, stack, constraints, SMART objectives | Every session |
| `decisions/` | `decisions/_log.md` | Validated choices — append-only | Selective |
| `patterns/` | `patterns/conventions.md` | Coding conventions, procedural knowledge | Every Delivery session |
| `ops/` | `ops/platform.md` | Platform operations — DNS, email, providers, procedures | When onboarding team or making infra changes |
| `contacts/` | `contacts/leads.md` | Experts identifiés pendant Discovery — à contacter au lancement | Delivery phase |
| `summaries/` | `summaries/decisions-01-59.summary.md` | Compacted decision summaries | Selective |
| `sessions/` | *(empty — add temporary notes here)* | Short-term session exploration | Never (source for summaries) |
| `archive/` | `archive/decisions-01-59.archive.md` | Full text of archived decisions | Rarely |

---

## Active Files

| File | Category | ID | Last updated |
|---|---|---|---|
| `project/context.md` | project | PROJECT-001 | 2026-02-22 (updated: pricing DEC-67, billing DEC-68, scalable matching DEC-60–69) |
| `decisions/_log.md` | decisions | DECISIONS-LOG | 2026-02-23 (10 active entries — DEC-60 to DEC-69. Older entries compacted.) |
| `patterns/conventions.md` | patterns | PATTERNS-001 | 2026-02-23 (OpenAI function calling pattern replaces Anthropic — E06S12/DEC-2026-02-23-01) |
| `ops/platform.md` | ops | OPS-001 | 2026-02-22 |
| `contacts/leads.md` | contacts | CONTACTS-001 | 2026-02-19 |
| `summaries/decisions-01-59.summary.md` | summaries | SUMMARY-DECISIONS-01-59 | 2026-02-23 |
| `archive/decisions-01-59.archive.md` | archive | ARCHIVE-DECISIONS-01-59 | 2026-02-23 |

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
| `artefacts/stories/E06S09.story.md` | Story | Done — composite score worker |
| `artefacts/stories/E06S10.story.md` | Story | Done — Google Calendar OAuth layer |
| `artefacts/stories/E06S11.story.md` | Story | Refined — booking engine |
| `artefacts/stories/E06S12.story.md` | Story | Refined — GPT-4o-mini migration |
| `artefacts/stories/E06S13.story.md` | Story | Refined — satellite_configs schema extension |
| `artefacts/stories/E06S14.story.md` | Story | Refined — satellite Worker multi-tenant |
| `artefacts/stories/E06S15.story.md` | Story | Refined — email deliverability hardening |
| `artefacts/stories/E06S16.story.md` | Story | Backlog → Refined — CF Workflows (n8n replacement) |
| `artefacts/stories/E06S17.story.md` | Story | Refined — survey submission endpoints |
| `artefacts/stories/E06S18.story.md` | Story | Refined — Hyperdrive + postgres.js foundation (DEC-66) |
| `artefacts/stories/E06S19.story.md` | Story | CANCELLED — merged into E06S23 |
| `artefacts/stories/E06S20.story.md` | Story | Refined — Rate Limiting + Turnstile (DEC-63/64) |
| `artefacts/stories/E06S21.story.md` | Story | Refined — Vectorize infra + embeddings (DEC-62) |
| `artefacts/stories/E06S22.story.md` | Story | Refined — Semantic scoring integration (DEC-62) |
| `artefacts/stories/E06S23.story.md` | Story | Refined — D1 edge serving + Cache API L1 + Cron sync (absorbs E06S19) (DEC-61) |
| `artefacts/stories/E06S24.story.md` | Story | Refined — Service Bindings Worker split |
| `artefacts/stories/E06S25.story.md` | Story | Refined — Durable Objects write coordinator |
| `artefacts/stories/E06S26.story.md` | Story | Refined — Analytics Engine observability (DEC-65) |
| `artefacts/stories/E03S05.story.md` | Story | Refined — crawler access policy |
| `artefacts/strategy/GTM-001.md` | Strategy | GTM plan — 4 phases, binary PASS/FAIL gates, J0–J90 — Phase 0 restructurée (DEC-31) |
| `artefacts/manifesto/MANIFESTO-001.md` | Manifesto | Manifeste public Callibrate — draft FR — pay-for-value + game theory + invitation |
| `artefacts/marketing/E01S01-reddit-posts.md` | Marketing | Reddit discussion posts + observation log |
| `artefacts/marketing/E01S01-community-posts.md` | Marketing | Slack/Discord engagement messages + observation log |

---

## Memory Principles

- **Retrieve selectively** — never load entire folders
- **Prefer summaries** over raw session notes
- **Archive aggressively** — move compacted content to `archive/`
- **Sessions are temporary** — always summarize before closing
- **Memory is distilled knowledge — not history**
