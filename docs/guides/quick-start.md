# Quick Start

**From zero to your first working Story in under 30 minutes.**

No theory. Just the steps.

---

## Before You Begin

You have:
- GAAI installed (`bash install.sh` from the repo root)
- Your AI tool open (Claude Code, Cursor, or Windsurf)
- A project — existing codebase or new idea

---

## Step 1 — Initialize (5 minutes)

### Existing codebase

Your AI needs context about your project before it can help.

**Claude Code:**
```
/gaai-bootstrap
```

**Other tools:**
> "Read `.gaai/core/agents/bootstrap.agent.md`, then follow `.gaai/core/workflows/context-bootstrap.workflow.md`."

The Bootstrap Agent will scan your codebase, extract architecture decisions, and fill in your memory files. It will tell you when it's done:

```
✅ Bootstrap PASS — context ready.
```

### New project (no codebase yet)

Skip Bootstrap. Go straight to Discovery:

**Claude Code:**
```
/gaai-discover
```

**Other tools:**
> "Read `.gaai/core/agents/discovery.agent.md`. I'm starting a new project: [describe your idea]. Help me define the first Epics and Stories."

The Discovery Agent will ask questions about your project — what it does, who it's for, what constraints apply — and use your answers to seed the project memory automatically. No manual file editing required.

---

## Step 2 — Describe What You Want to Build (10 minutes)

This is where you talk to the **Discovery Agent** — the only agent you interact with directly.

The Discovery Agent's job: take your rough idea and turn it into clear, executable Stories with acceptance criteria.

**How to activate it:**

**Claude Code:**
```
/gaai-discover
```

**Other tools:**
> "Read `.gaai/core/agents/discovery.agent.md`. I want to build [your idea]. Help me create the first Epics and Stories."

### What to say

You don't need to be precise. Describe the problem or the outcome you want:

> "I want users to be able to reset their password via email."

> "The dashboard is too slow when loading 10,000 rows. I want it to load under 2 seconds."

> "I want to add a subscription tier to this SaaS — free and paid, with Stripe."

The Discovery Agent will ask clarifying questions, surface risks, and produce:
- An **Epic** — the outcome (e.g. "User can self-serve password recovery")
- One or more **Stories** — executable contracts with acceptance criteria

### What happens next

The Discovery Agent runs a validation loop automatically:
1. Generates Epics and Stories
2. Runs risk analysis
3. Checks consistency
4. Validates artefacts against governance rules
5. If something is wrong, it refines and repeats
6. When everything passes: Stories move to `status: refined` in the backlog

You don't drive this loop. You only intervene when the agent asks a question it can't resolve.

---

## Step 3 — Run the Delivery Loop (15 minutes)

When Stories are `refined`, they're ready. One command delivers them.

**Claude Code:**
```
/gaai-deliver
```

**Other tools:**
> "Read `.gaai/core/agents/delivery.agent.md` and `.gaai/core/workflows/delivery-loop.workflow.md`. Execute the next ready backlog item."

### What happens automatically

The Delivery Agent runs the full loop without you:

```
Pick highest-priority Story
       ↓
Build execution context (loads memory + rules)
       ↓
Plan implementation
       ↓
Implement
       ↓
QA Review
       ↓
PASS → mark done → move to next Story
FAIL → remediate → re-run QA (up to 3 attempts)
ESCALATE → stop and ask you
```

You wait. The agent reports back when:
- A Story is **done** (QA passed)
- Something needs your decision (escalation)

### The only time you intervene

The Delivery Agent stops and asks you when:
- Acceptance criteria are ambiguous
- A fix would require changing scope (that's a Discovery decision, not Delivery)
- Three remediation attempts have failed

Everything else is handled automatically.

---

## Check Your Status Anytime

**Claude Code:**
```
/gaai-status
```

**Other tools:**
> "Read `.gaai/project/contexts/backlog/active.backlog.yaml` and give me a summary."

---

## Manage Your Backlog Directly

The backlog scheduler gives you four views into `.gaai/project/contexts/backlog/active.backlog.yaml`:

```bash
# What should be worked on next?
.gaai/core/scripts/backlog-scheduler.sh --next active.backlog.yaml

# What's ready right now? (sorted by priority, then complexity)
.gaai/core/scripts/backlog-scheduler.sh --list active.backlog.yaml

# What's blocked and why? (full dependency tree)
.gaai/core/scripts/backlog-scheduler.sh --graph active.backlog.yaml

# Are any high-priority items blocked by lower-priority dependencies?
.gaai/core/scripts/backlog-scheduler.sh --conflicts active.backlog.yaml
```

**When to use each:**

| Command | When |
|---------|------|
| `--next` | Before starting a new delivery session |
| `--list` | When you want to see all options and choose |
| `--graph` | When something feels stuck and you need to see why |
| `--conflicts` | During sprint planning or priority reviews |

The `--graph` output uses four indicators:

```
✅ BL-003 [high] — Auth middleware   (ready to work on)
🔄 BL-001 [high] — Login flow        (in progress)
🔒 BL-004 [medium] — Dashboard       (blocked by dependency)
⏳ BL-005 [low] — Reports page       (not yet refined)
```

---

## Use Cases

### Use Case 1 — Adding a feature to an existing app

You have a Node.js API. You want to add rate limiting.

1. **Bootstrap** — the agent scans your codebase, finds your middleware pattern, records it in memory.
2. **Discover** — you say: "Add rate limiting to all API endpoints. 100 req/min per user, 429 on exceeded."
   - Agent generates: Epic "API is protected from abuse", Story "Rate limiting middleware applied to all routes", acceptance criteria: 429 returned when exceeded, headers include retry-after, tests pass.
3. **Deliver** — agent picks the Story, reads your middleware conventions from memory, implements using your existing pattern, runs QA. Done.

Total interaction: ~15 minutes.

---

### Use Case 2 — Starting a new product

You have an idea: a CLI tool that generates commit messages from git diff.

1. **No bootstrap** (no codebase yet). Go straight to Discovery.
2. **Discover** — you say: "I want a CLI that takes a git diff and suggests a commit message using an LLM."
   - Agent asks: which LLM? fallback if no API key? output format? target users?
   - You answer. The Discovery Agent seeds project memory from your answers, then produces: PRD, 3 Epics, 7 Stories across two sprints.
3. **Deliver** — you run the delivery loop. Agent works through Stories one by one. You review output between sessions.

Total hands-on time: 30 minutes setup. Then autonomous.

---

### Use Case 3 — Fixing a complex bug

A bug with unclear root cause. You know the symptom but not the cause.

Skip Discovery (bugs go directly to Delivery).

Add a backlog item manually:

```yaml
# in .gaai/project/contexts/backlog/active.backlog.yaml
- id: BL-042
  title: Fix race condition in order processing
  status: refined
  priority: high
  track: delivery
  complexity: 5
  acceptance_criteria: |
    - Orders are processed exactly once under concurrent load
    - No duplicate charges observed in test suite
    - All existing order tests pass
```

Run `/gaai-deliver`. The agent reads the criteria, investigates, implements, runs QA.

---

## The Mental Model

```
You ←→ Discovery Agent       (what to build — human-facing)
            ↓
       active backlog         (the authorization gate)
            ↓
       Delivery Agent →       (how to build it — autonomous)
            ↓
        Working code
```

**You only talk to Discovery.** Delivery runs on its own.

**The backlog is the contract.** Nothing gets built that isn't in it.

---

## What's Next

- Refine your rules in `.gaai/core/contexts/rules/` — this is how you teach GAAI your team's conventions
- Read [Core Concepts](../02-core-concepts.md) to understand why the framework is designed this way
- Read [Senior Engineer Guide](senior-engineer-guide.md) for governance customization and CI integration
