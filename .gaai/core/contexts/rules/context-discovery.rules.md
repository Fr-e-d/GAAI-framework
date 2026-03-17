---
type: rules
category: context-discovery
id: RULES-CONTEXT-DISCOVERY-001
tags:
  - discovery
  - context
  - activation
  - governance
created_at: 2026-02-09
updated_at: 2026-02-09
---

# 🔍 GAAI Context Discovery Rules

This document defines **when and how the Discovery track is activated**
and what context conditions must be met before Discovery begins.

## 🎯 Purpose

Context discovery rules ensure that:
- Discovery only activates on appropriate inputs
- Context is explicit before reasoning begins
- The right track (Discovery vs Delivery) is selected deliberately

## 🧠 Core Principle

**Track selection is an explicit decision — never implicit.**

## 🔀 Track Selection Rules

### R1 — Use Discovery Track When

The Discovery track MUST be activated when:
- user intent is vague, ambiguous, or exploratory
- a new feature, product, or epic is being initiated
- scope is undefined or disputed
- acceptance criteria do not exist
- an existing story requires revalidation

### R2 — Use Delivery Track When

The Delivery track MUST be activated when:
- a backlog item exists with status `refined`
- acceptance criteria are explicit and approved
- scope is locked

### R3 — When in Doubt, Use Discovery

If track selection is ambiguous:
- default to Discovery
- never default to Delivery
- never execute without a governed backlog item

## 📋 Discovery Activation Context

Before the Discovery Agent begins, it MUST have:
- explicit human intent (written or verbal)
- access to `.gaai/project/contexts/memory/project/context.md`
- access to current backlog state (`contexts/backlog/active.backlog.yaml`)

The Discovery Agent MAY retrieve additional memory selectively.
It MUST NOT auto-load full memory.

## 🚫 Forbidden Activation Patterns

The following are **explicitly forbidden**:
- Delivery activating without a `refined` backlog item
- Discovery activating without a human intent input
- Auto-switching between tracks without agent decision
- Implicit track inference from file state

## 🧠 Final Rule

**If the track is unclear, stop and ask the human.**

Track selection is the first governance gate in every GAAI session.
