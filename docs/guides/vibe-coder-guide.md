# Vibe Coder Guide

**You want to build things fast. This guide keeps you moving.**

No governance theory. Just the workflow that works.

---

## The One-Line Mental Model

Tell Discovery what to build. Let Delivery build it. Repeat.

---

## Your Daily Flow

### Starting a session

**Claude Code:**
```
/gaai-status
```

This shows you:
- What's in the backlog and what's ready
- Recent decisions
- Whether anything needs your attention

For a quick look at what's ready to work on right now:

```bash
.gaai/core/scripts/backlog-scheduler.sh --list .gaai/project/contexts/backlog/active.backlog.yaml
```

Example:
```
Ready items (3):

  [HIGH] BL-003 — Auth middleware (complexity: 5)
  [HIGH] BL-007 — Password reset email (complexity: 3)
  [MEDIUM] BL-011 — Export to CSV (complexity: 2)
```

If nothing is ready to deliver and you have new ideas, go to Discovery.
If Stories are ready, go directly to Delivery.

---

### When you have a new idea

Activate Discovery:

**Claude Code:** `/gaai-discover`

**Other tools:** "Read `.gaai/core/agents/discovery.agent.md`. I want to build [your idea]."

Then just describe what you want. Be as rough as you like:

> "I want a dark mode"
> "The sign-up flow is broken on mobile, let's fix it"
> "Add export to CSV"

Discovery will ask you questions if it needs clarity. Answer them. When it's done, your backlog has new refined Stories.

> **What's a Story?** A Story is a small, executable piece of work with a clear outcome and acceptance criteria — the exact conditions that make it "done". Think of it as a well-defined task the Delivery Agent can run autonomously, without needing to ask you clarifying questions.

---

### When you want to build

Activate Delivery:

**Claude Code:** `/gaai-deliver`

**Other tools:** "Read `.gaai/core/agents/delivery.agent.md`. Execute the next ready backlog item."

Then go do something else. The Delivery Agent runs the full loop:
- Plans
- Implements
- Tests
- Marks done

It will come back to you only if it hits a real blocker. Otherwise it reports when it's done.

---

## When You Don't Need Discovery

Not everything needs full Discovery. For some things, you can add a backlog item directly:

- Bug fixes with clear symptoms and expected behavior
- Tiny chores (update a dependency, fix a typo, rename a method)
- Work where you already know exactly what "done" looks like

Add to `active.backlog.yaml`:

```yaml
- id: BL-042
  title: Fix button label on checkout page
  status: refined
  priority: low
  track: delivery
  complexity: 1
  acceptance_criteria: |
    - Button reads "Complete order" (not "Submit")
    - Change is visible on checkout step 3
```

Then run `/gaai-deliver`.

---

## Keeping Memory Fresh

GAAI remembers what matters. But it only knows what you tell it.

After a significant session, capture what was decided:

**Claude Code:** tell your AI: "Extract decisions from this session and update `.gaai/project/contexts/memory/decisions/_log.md`."

Or just let the Discovery and Delivery Agents do it automatically — they invoke `decision-extraction` when something notable is decided.

---

## What to Do When Something Goes Wrong

The Delivery Agent escalates when it can't proceed. It tells you exactly why.

Common situations:
- **Acceptance criteria are ambiguous** → go back to Discovery, clarify the Story, update the backlog item
- **Rule violation** → check `contexts/rules/` — maybe a rule needs updating
- **Scope creep implied** → the agent won't guess. Tell it explicitly what to do, or update the Story via Discovery

---

## Tips

**Keep Stories small.** A Story that takes 30 minutes to implement is better than one that takes 3 days. More Stories = more feedback loops = less drift.

**Fill in memory/project/context.md well.** The better the project context, the less the agent has to ask. 15 minutes here saves hours later.

**When in doubt, ask Discovery first.** Even if you think you know what to build, Discovery's questions surface the things you didn't think about.

---

→ [Quick Start](quick-start.md) — the minimal flow
→ [Senior Engineer Guide](senior-engineer-guide.md) — when you want full control
