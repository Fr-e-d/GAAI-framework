---
type: workflow
id: WORKFLOW-EMERGENCY-ROLLBACK-001
track: cross
updated_at: 2026-02-18
---

# Emergency Rollback Workflow

## Purpose

Define what to do when Delivery goes wrong and normal remediation is insufficient.

This workflow handles: unrecoverable failures, out-of-scope drift, corrupted context, or situations requiring human judgment.

---

## When to Use

Activate this workflow when:
- QA fails after 3 remediation attempts
- Implementation has drifted from product intent
- A fix requires changing Story scope or design
- Rules are being violated and cannot be resolved within current context
- Context is corrupted or memory is unreliable
- An irreversible destructive action was taken by mistake

---

## Escalation Signals

The Delivery Agent MUST surface these to a human:
- `ESCALATE: scope-change-required`
- `ESCALATE: rule-violation-unresolvable`
- `ESCALATE: context-gap-detected`
- `ESCALATE: max-retries-exceeded`
- `ESCALATE: destructive-action-detected`

---

## Rollback Steps

### 1. Stop All Execution

Immediately halt the Delivery Agent. No further code changes.

### 2. Assess the Situation

Human reviews:
- What was the last PASS state?
- What changed since then?
- Is the change reversible via git?

### 2b. Clean Up Active Worktrees

If the affected story was running in an isolated worktree:

```bash
# List active worktrees
git worktree list

# Remove worktrees for affected stories
git worktree remove ../{id}-workspace

# Delete story branches if no longer needed
git branch -d story/{id}
```

Worktree cleanup prevents ghost worktrees from interfering with subsequent deliveries.

### 3. Revert if Possible

```bash
# Identify last clean commit
git log --oneline

# Revert to last known good state
git revert <commit> --no-edit
# or
git reset --hard <commit>  # only if changes are not pushed
```

### 4. Diagnose Root Cause

4. Invoke `post-mortem-learning` on the failure (if experimental skills are available)
5. Identify: was this a Story ambiguity? A rule gap? A context failure? A decision error?

### 5. Fix the Root Cause

Depending on diagnosis:

| Root Cause | Action |
|---|---|
| Story was ambiguous | Return to Discovery — use `refine-scope` |
| Acceptance criteria were missing | Return to Discovery — update Story |
| Rule was missing or weak | Invoke `rules-normalize`, update `contexts/rules/` |
| Memory was stale or wrong | Invoke `memory-refresh`, correct memory |
| Architectural decision needed | Surface to human, record in `decision-extraction` |

### 6. Re-validate Before Resuming

Before restarting Delivery:
- Run `validate-artefacts` on affected Stories
- Confirm root cause is resolved
- Update backlog status accordingly

### 7. Resume Delivery

Only resume `delivery-loop.workflow.md` when:
- ✅ Root cause is resolved
- ✅ Artefacts are re-validated
- ✅ Memory reflects current state
- ✅ Human has confirmed it is safe to proceed

---

## Governance Principle

> When in doubt, stop and ask.

No automation overrides human judgment on irreversible actions. The cost of pausing is always lower than the cost of compounding a mistake.
