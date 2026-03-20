---
type: reference
skill: skill-optimize
id: SKILL-OPT-AP-001
updated_at: 2026-03-20
---

# Skill Optimize — Anti-Patterns and Mitigations

This document catalogs known anti-patterns in skill quality optimization loops. Each pattern was identified through research across evaluation frameworks (OpenAI Evals Flywheel, SkillsBench, AgentBench, SWE-bench) and documented to prevent regression in the skill-optimize protocol.

---

## AP-1: Self-Model Bias

**Pattern:** The same LLM that produced the output also judges the output via `llm-judge` assertions.

**Risk:** The judge shares the model's blind spots. It will approve outputs that "sound right" to the same architecture, even when a human would flag issues. Studies show same-model evaluation inflates pass rates by 10-15%.

**Mitigation:**
- Require a mix of `code` and `llm-judge` assertion types in every evals.yaml (minimum 2 `code` assertions)
- `code` assertions act as ground-truth anchors that the model cannot rationalize away
- When pass rates are suspiciously high (>95%) on first baseline, investigate whether `llm-judge` assertions are too permissive
- Consider cross-model judging for high-stakes skills if available

---

## AP-2: Goodhart's Law (Teaching to the Test)

**Pattern:** Repeated optimization cycles cause SKILL.md instructions to overfit to the specific evals.yaml assertions rather than improving general quality.

**Risk:** The skill scores 95% on its eval set but produces mediocre output on new, unseen inputs. The eval set becomes the ceiling, not the floor.

**Mitigation:**
- Limit optimization to 3 cycles per session before human review of the direction
- Rotate corpus inputs periodically (every 3-5 optimization sessions)
- After major improvements, add 1-2 new assertions that test for generalization
- Watch for instructions that reference specific assertion IDs or test patterns — this is a red flag
- The human checkpoint at Step 5 exists precisely to catch this

---

## AP-3: Eval Inflation (Always-Pass Assertions)

**Pattern:** Assertions are written so broadly that virtually any output passes them.

**Risk:** A 100% pass rate gives false confidence. The ledger shows "stable" or "improving" while actual output quality has not changed. The eval set becomes a rubber stamp.

**Mitigation:**
- Every `llm-judge` assertion must have a concrete `fail_if` condition (not just "fails to meet quality")
- Every `code` assertion must have bounds that would realistically fail on poor output
- If baseline pass rate is 100%, the eval set is likely too permissive — add harder assertions
- Review failed assertions from the first baseline: if zero failures, the bar is too low

---

## AP-4: Self-Generated Skills Are Worthless

**Pattern:** An LLM generates skill instructions without human expertise, then evaluates and "improves" those instructions in a closed loop.

**Risk:** SkillsBench research (2025) found that fully self-generated skill instructions performed -1.3 percentage points WORSE than no skill instructions at all. The model generates plausible-sounding but non-functional instructions. Self-optimization amplifies these flaws.

**Mitigation:**
- SKILL.md creation always requires human expertise and approval (create-skill protocol)
- The skill-optimize protocol NEVER auto-applies changes — human gate at Step 5 is mandatory
- Improvement proposals must be specific and minimal (targeted instruction changes, not rewrites)
- If the error analysis shows >50% `instruction-gap` failures, the skill likely needs human redesign, not automated patching

---

## AP-5: Assertion Count Inflation

**Pattern:** Each optimization cycle adds more assertions to improve "coverage," leading to an ever-growing eval set that becomes expensive and noisy.

**Risk:** Diminishing returns per assertion. Maintenance burden grows. New assertions may conflict with existing ones. The eval set becomes a maintenance liability rather than a quality tool.

**Mitigation:**
- Target 5-10 assertions per skill — sufficient for signal, manageable for maintenance
- Before adding a new assertion, verify it tests something no existing assertion covers
- If an assertion hasn't failed in 5+ iterations, consider whether it still adds value
- Prefer sharpening existing assertions over adding new ones

---

## AP-6: Ignoring Model Limitations

**Pattern:** Optimization cycles keep trying to "fix" failures that are inherent model limitations (hallucination patterns, specific reasoning gaps, format compliance issues).

**Risk:** Wasted cycles. The SKILL.md accumulates workaround instructions that increase complexity without improving outcomes. The model's instruction-following has limits.

**Mitigation:**
- The error analysis step (Step 4) explicitly classifies `model-limitation` failures
- `model-limitation` failures are documented but NOT addressed with SKILL.md changes
- If >30% of failures are `model-limitation`, the skill may need architectural changes (different model, different pipeline) rather than instruction optimization
- Track model limitations in the ledger for future reference when models improve

---

## AP-7: Catastrophic Forgetting (Regression Introduction)

**Pattern:** A SKILL.md change that fixes one failure introduces a new failure elsewhere. The net score stays flat or improves, but the regression is hidden.

**Risk:** Whack-a-mole optimization. Each cycle fixes one thing and breaks another. Overall quality oscillates rather than improving.

**Mitigation:**
- Per-assertion tracking in every score report (not just aggregate pass rate)
- Compare per-assertion results between iterations, not just totals
- A newly failed assertion that was previously passing is a regression — flag it explicitly
- The human checkpoint at Step 5 reviews sample outputs AND the score delta — both are required
- If 2+ regressions occur in consecutive iterations, STOP and reassess the approach

---

## AP-8: Metric Aggregation Hiding Regressions

**Pattern:** Reporting only aggregate pass rates (e.g., "85%") instead of per-assertion results. A new failure is masked by a new pass elsewhere.

**Risk:** The ledger shows "stable" while quality is actually oscillating. Individual assertion failures become invisible. Root cause analysis becomes impossible.

**Mitigation:**
- Every score report lists per-assertion results (Step 3 and Step 5)
- The ledger records `failed_assertions` as a list of assertion IDs per iteration
- Trend detection (Step 7) examines per-assertion history, not just aggregate pass rate
- The `delta_vs_previous` field in the ledger reflects the directional change, not just the absolute rate
