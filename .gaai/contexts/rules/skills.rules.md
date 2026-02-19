---
type: rules
category: skills
id: RULES-SKILLS-001
tags:
  - skills
  - execution
  - isolation
  - governance
  - determinism
created_at: 2026-02-09
updated_at: 2026-02-09
---

# 🛠️ GAAI Skills Rules

This document defines the **mandatory rules governing all skills**
inside the GAAI (Governed Agentic AI Infrastructure) system.

These rules are **non-negotiable**.
If a skill violates any rule in this document, it is **invalid by design**.

## 🎯 Purpose

Skills exist to provide **deterministic, procedural execution**
in service of agent decisions.

Skills are **not intelligent actors**.

## 🧠 Core Principles

**Agents decide.**
**Skills execute.**
**Skills execute in isolated context windows.**

This separation is foundational to GAAI.

## 🧭 Skill Authority Model

### R1 — Skills Never Decide

A skill MUST NOT:
- interpret user intent
- make product or technical decisions
- decide priorities or strategies
- infer missing goals

All decisions belong exclusively to **agents**.

### R2 — Explicit Invocation Only

A skill MUST:
- be explicitly selected by an agent
- receive all inputs explicitly

A skill MUST NOT:
- select itself
- auto-run
- infer when it should be invoked

Tooling MAY expose skills, but **only agents decide invocation**.

## 🧪 Execution Isolation

### R3 — Independent Context Windows (Mandatory)

Every skill MUST execute in a **fully isolated context window**.

This means:
- no inheritance of agent reasoning
- no access to previous skill contexts
- no shared memory between executions

A skill only sees its declared inputs — nothing else.

### R4 — No Implicit Context Access

A skill MUST NOT:
- auto-load memory
- read rules autonomously
- access backlog state
- inspect artefact folders
- query system state implicitly

All context must be **explicitly passed by the agent**.

## 📦 Inputs & Outputs

### R5 — Strict Input Contract

A skill MUST:
- declare its expected inputs
- fail explicitly if inputs are missing

A skill MUST NOT:
- guess missing information
- enrich inputs creatively
- expand scope beyond inputs

### R6 — Explicit Outputs Only

A skill MAY:
- produce structured data
- generate artefacts
- return execution results

A skill MUST NOT:
- modify memory directly
- update backlog state
- persist decisions
- communicate with humans

All outputs return to the **invoking agent**.

## 🔁 Skill Chaining

### R7 — No Autonomous Skill Chaining

A skill MUST NOT:
- invoke another skill
- retry itself autonomously
- orchestrate execution flows

Only agents may chain skills.

## 🚫 Forbidden Behaviors (Hard Fail)

The following behaviors are **explicitly forbidden**:
- implicit context loading
- hidden state retention
- creative interpretation
- scope expansion
- decision-making logic
- human-facing communication
- cross-skill context sharing

Any skill exhibiting these behaviors is **invalid**.

## 🧠 Final Rule

> If a skill appears to "think", it is wrongly designed.

Skills exist to **serve agent decisions**, never to replace them.
