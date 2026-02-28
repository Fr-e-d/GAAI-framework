# Design Decisions

Why GAAI is structured the way it is. Each decision is an Architecture Decision Record (ADR).

---

## ADR-001: File-Based, Not SDK-Based

**Decision:** GAAI is Markdown + YAML + bash scripts. No code library, no npm package, no SDK.

**Reasoning:**
- Zero-friction installation: `cp -r .gaai/ <project>`
- No dependency management, no version conflicts, no security surface
- Works with any AI tool that can read files (Claude Code, Cursor, Windsurf, any future tool)
- Users own the files completely — fork and modify without waiting for upstream changes
- Transparent: every rule, every constraint, every workflow is readable in plain text

**Trade-off accepted:** No programmatic enforcement. The framework relies on agents following the files. A badly configured AI tool can ignore them. Mitigation: the `health-check.sh` CI gate validates structure integrity.

---

## ADR-002: The Backlog as Sole Authorization Mechanism

**Decision:** The Delivery Agent may only act on backlog items. Nothing outside the backlog is executed.

**Reasoning:**
- Prevents "do things you didn't explicitly decide" — the most common AI coding failure mode
- Makes authorization auditable: you can always trace why something was built
- Forces Discovery to happen before Delivery — Discovery creates the backlog items
- Gives teams a single source of truth for what is authorized

**Trade-off accepted:** Overhead for trivial tasks (a one-line fix requires a backlog item). Mitigation: backlog items can be minimal (one-liner YAML with basic acceptance criteria).

---

## ADR-003: Explicit Memory, Never Auto-Loaded

**Decision:** Memory files exist. Agents select what they need. Nothing auto-loads.

**Reasoning:**
- Auto-loading all memory into every context window wastes tokens and introduces noise
- Context pollution causes drift: the agent contradicts earlier decisions because old and new are both present
- Explicit selection makes agent behavior reproducible: same context in → same reasoning out
- Auditable: you can see exactly what the agent knew when it made a decision

**Trade-off accepted:** Agents must invoke `memory-retrieve` explicitly. This adds a step but removes unpredictability.

---

## ADR-004: Agents Reason, Skills Execute — Never Both

**Decision:** The agent-skills separation is strict. Agents decide what to do. Skills do it. A skill that makes decisions is wrongly designed.

**Reasoning:**
- Predictability: given a skill with defined inputs, the output is deterministic
- Isolation: skills run in isolated context windows — no state bleeds between them
- Testability: skills can be validated independently of the agent that invokes them
- Composability: an agent can assemble different skill sequences for different situations

**Trade-off accepted:** More files, more explicit invocation. The verbosity is intentional — it makes what's happening observable.

---

## ADR-005: Fork & Own Distribution Model

**Decision:** GAAI is a GitHub template repo. Users fork and adapt. No community skill contributions. Community limited to bug reports and doc fixes.

**Reasoning:**
- A community skill marketplace creates governance risk: untrusted skills get ingested into production workflows
- User projects have wildly different conventions and domains — shared skills would be too generic to be useful
- Fork & Own means the framework serves the project, not the community
- ELv2 license: users can do anything with their fork except offer it as a competing hosted service

**Trade-off accepted:** No ecosystem effect. No skill sharing between projects. This is acceptable for v1.0.

---

## ADR-006: Dual Track (Discovery vs Delivery)

**Decision:** Discovery and Delivery are separate tracks with a formal handoff gate. Planning and execution never share a context window.

**Reasoning:**
- The most common AI failure mode: building the wrong thing fast
- Discovery is human-facing and produces artefacts that document decisions
- Delivery is autonomous and executes only validated decisions
- The separation forces the right question first: "is this the right thing to build?" before "how do we build it?"
- Mixing planning and execution in a single LLM context degrades output quality and introduces cascading errors

**Research basis:**

- **GoalAct** — Chen et al. (2025). *Enhancing LLM-Based Agents via Global Planning and Hierarchical Execution.* NCIIP 2025 Best Paper. Demonstrates that separating global planning from hierarchical execution achieves +12.22% success rate on LegalAgentBench. [arXiv:2504.16563](https://arxiv.org/abs/2504.16563)

- **Plan-then-Execute (P-t-E)** — Del Rosario et al. (2025). *Architecting Resilient LLM Agents: A Guide to Secure Plan-then-Execute Implementations.* Shows that separating the Planner from the Executor provides control-flow integrity, reduces prompt injection risk, and improves predictability over reactive (single-context) approaches like ReAct. [arXiv:2509.08646](https://arxiv.org/abs/2509.08646)

- **ACE** — Zhang et al. (2025). *Agentic Context Engineering: Evolving Contexts for Self-Improving Language Models.* ICLR 2026. Demonstrates that context collapse and brevity bias degrade LLM agent performance when context management is not deliberate and structured. Explicit context engineering yields +10.6% on agent benchmarks. [arXiv:2510.04618](https://arxiv.org/abs/2510.04618)

**Trade-off accepted:** Discovery adds time before any code is written. This is the point — it prevents rework.

---

## ADR-007: YAML Backlog, Not Markdown Per Item

**Decision:** The backlog is a single YAML file (`active.backlog.yaml`), not one Markdown file per item.

**Reasoning:**
- YAML is machine-readable — `backlog-scheduler.sh` parses it natively
- A single file is easier to diff, review, and merge
- One file per backlog item creates 50+ files for an active project — maintenance overhead with no benefit
- Status transitions are visible in a single file view

**Trade-off accepted:** Large backlogs in a single file. Mitigation: done items are archived monthly (`done/YYYY-MM.done.yaml`), keeping the active file small.

---

## ADR-008: Directory Index Files Named README.{type}.md

**Decision:** Index files inside `.gaai/` subdirectories are named `README.agents.md`, `README.skills.md`, etc. — not `README.md`.

**Reasoning:**
- `README.md` is auto-rendered by GitHub only at the repo root level, not in subdirectories
- `README.agents.md` makes the file type explicit — it's the agents readme, not a generic readme
- Consistent with the `{name}.{type}.md` naming convention throughout the framework

**Trade-off accepted:** GitHub won't auto-render these files as directory descriptions. Acceptable — this is a developer-facing framework.

---

## ADR-009: SKILL.md Directory Structure (agentskills.io Spec)

**Decision:** Skills live in `{skill-name}/SKILL.md` directories, not flat files.

**Reasoning:**
- agentskills.io spec requires this structure for tool auto-discovery
- AI tools (Claude Code, Cursor, VS Code extensions) scan for `SKILL.md` files to auto-discover available skills
- The directory enables optional `references/` and `assets/` subdirectories per skill
- Flat files like `generate-stories.skill.md` would not be discovered by any tool

**Trade-off accepted:** More directories. Consistent and spec-compliant.

---

## ADR-010: English Only

**Decision:** All framework files are in English. No localization.

**Reasoning:**
- GAAI is a developer tool. The global developer community works in English.
- Localization would double the maintenance surface for v1.0
- User projects can write memory and artefact content in any language — the framework scaffolding stays in English

**Trade-off accepted:** Non-English native users must read framework files in English. Acceptable for v1.0.

---

→ [Memory Model](memory-model.md)
→ [Agent-Skills Spec](agent-skills-spec.md)
