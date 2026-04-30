# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.22.0] - 2026-04-30

### Changed
- chore: reconcile stale in_progress + add GLM baseline analyzer
- fix(delivery-loop): preamble fires on env-driven default secondary routing
- chore: bump local VERSION to v2.23.0 [sync]
- feat(scripts): observe-secondary.sh — live R1-R5 compliance + outcomes
- fix(daemon-monitor): cap activity line at 280 chars to prevent heredoc flooding
- chore: bump local VERSION to v2.22.0 [sync]
- feat(delivery-loop): NOTES.md self-bootstrapping + artefact-first-class path
- chore: bump local VERSION to v2.26.0 [sync]
- feat(delivery-loop): upgrade GLM context-discipline preamble per Anthropic guidance
- chore: bump local VERSION to v2.25.0 [sync]
- feat(delivery-loop): GLM context-discipline preamble for secondary routing
- fix(analyzer): surface stdout terminal_reason + jq capture no-match handling
- chore: bump local VERSION to v2.24.0 [sync]
- fix(scripts): clean routing summary in fail-debug analyzer
- feat(E107bS04): severity-weighted tie-breaker — top 5 by severity (#582)
- chore: bump local VERSION to v2.28.0 [sync]
- feat(scripts): minimal fail-debug analyzer
- chore: bump local VERSION to v2.27.0 [sync]
- feat(nested-claude-spawn): forensic dump on EXIT_CODE_NON_ZERO catch-all
- fix(daemon-monitor): persist max-rank phase across tail-window refreshes
- fix(scheduler): make YAML parser indent-aware
- feat(daemon): add --exit-when-idle auto-stop when backlog drained
- feat(E107bS08): User-skip telemetry — count + skip reason (#557)
- fix(workflow): restore secondary path — strengthen CLI invocation mandate + remove orphan Task spawn instruction
- fix(impl-routing): apply Claude Code proxy / gateway compat flags for secondary path
- fix(impl-routing): add Haiku model mapping for secondary path Task sub-agents
- fix(impl-routing): apply Z.AI-recommended CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.23.0] - 2026-04-30

### Changed
- feat(scripts): observe-secondary.sh — live R1-R5 compliance + outcomes


## [2.22.0] - 2026-04-30

### Changed
- fix(daemon-monitor): cap activity line at 280 chars to prevent heredoc flooding
- chore: bump local VERSION to v2.22.0 [sync]
- feat(delivery-loop): NOTES.md self-bootstrapping + artefact-first-class path
- chore: bump local VERSION to v2.26.0 [sync]
- feat(delivery-loop): upgrade GLM context-discipline preamble per Anthropic guidance
- chore: bump local VERSION to v2.25.0 [sync]
- feat(delivery-loop): GLM context-discipline preamble for secondary routing
- fix(analyzer): surface stdout terminal_reason + jq capture no-match handling
- chore: bump local VERSION to v2.24.0 [sync]
- fix(scripts): clean routing summary in fail-debug analyzer
- feat(E107bS04): severity-weighted tie-breaker — top 5 by severity (#582)
- chore: bump local VERSION to v2.28.0 [sync]
- feat(scripts): minimal fail-debug analyzer
- chore: bump local VERSION to v2.27.0 [sync]
- feat(nested-claude-spawn): forensic dump on EXIT_CODE_NON_ZERO catch-all
- fix(daemon-monitor): persist max-rank phase across tail-window refreshes
- fix(scheduler): make YAML parser indent-aware
- feat(daemon): add --exit-when-idle auto-stop when backlog drained
- feat(E107bS08): User-skip telemetry — count + skip reason (#557)
- fix(workflow): restore secondary path — strengthen CLI invocation mandate + remove orphan Task spawn instruction
- fix(impl-routing): apply Claude Code proxy / gateway compat flags for secondary path
- fix(impl-routing): add Haiku model mapping for secondary path Task sub-agents
- fix(impl-routing): apply Z.AI-recommended CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- chore: bump local VERSION to v2.23.0 [sync]
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.22.0] - 2026-04-30

### Changed
- feat(delivery-loop): NOTES.md self-bootstrapping + artefact-first-class path
- chore: bump local VERSION to v2.26.0 [sync]
- feat(delivery-loop): upgrade GLM context-discipline preamble per Anthropic guidance
- chore: bump local VERSION to v2.25.0 [sync]
- feat(delivery-loop): GLM context-discipline preamble for secondary routing
- fix(analyzer): surface stdout terminal_reason + jq capture no-match handling
- chore: bump local VERSION to v2.24.0 [sync]
- fix(scripts): clean routing summary in fail-debug analyzer
- feat(E107bS04): severity-weighted tie-breaker — top 5 by severity (#582)
- chore: bump local VERSION to v2.28.0 [sync]
- feat(scripts): minimal fail-debug analyzer
- chore: bump local VERSION to v2.27.0 [sync]
- feat(nested-claude-spawn): forensic dump on EXIT_CODE_NON_ZERO catch-all
- fix(daemon-monitor): persist max-rank phase across tail-window refreshes
- fix(scheduler): make YAML parser indent-aware
- feat(daemon): add --exit-when-idle auto-stop when backlog drained
- feat(E107bS08): User-skip telemetry — count + skip reason (#557)
- fix(workflow): restore secondary path — strengthen CLI invocation mandate + remove orphan Task spawn instruction
- chore: bump local VERSION to v2.22.0 [sync]
- fix(impl-routing): apply Claude Code proxy / gateway compat flags for secondary path
- fix(impl-routing): add Haiku model mapping for secondary path Task sub-agents
- fix(impl-routing): apply Z.AI-recommended CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- chore: bump local VERSION to v2.23.0 [sync]
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.26.0] - 2026-04-30

### Changed
- feat(delivery-loop): upgrade GLM context-discipline preamble per Anthropic guidance
- chore: bump local VERSION to v2.25.0 [sync]


## [2.25.0] - 2026-04-30

### Changed
- feat(delivery-loop): GLM context-discipline preamble for secondary routing
- fix(analyzer): surface stdout terminal_reason + jq capture no-match handling


## [2.24.0] - 2026-04-30

### Changed
- fix(scripts): clean routing summary in fail-debug analyzer
- feat(E107bS04): severity-weighted tie-breaker — top 5 by severity (#582)
- docs(E107bS04): delivery artefacts — micro-delivery-report


## [2.23.0] - 2026-04-30

### Changed
- feat(E107bS04): severity-weighted tie-breaker — top 5 by severity


## [2.22.0] - 2026-04-30

### Changed
- chore: bump local VERSION to v2.28.0 [sync]
- feat(scripts): minimal fail-debug analyzer
- chore: bump local VERSION to v2.27.0 [sync]
- feat(nested-claude-spawn): forensic dump on EXIT_CODE_NON_ZERO catch-all
- fix(daemon-monitor): persist max-rank phase across tail-window refreshes
- fix(scheduler): make YAML parser indent-aware
- chore: bump local VERSION to v2.26.0 [sync]
- feat(daemon): add --exit-when-idle auto-stop when backlog drained
- feat(E107bS08): User-skip telemetry — count + skip reason (#557)
- fix(workflow): restore secondary path — strengthen CLI invocation mandate + remove orphan Task spawn instruction
- chore: bump local VERSION to v2.22.0 [sync]
- fix(impl-routing): apply Claude Code proxy / gateway compat flags for secondary path
- fix(impl-routing): add Haiku model mapping for secondary path Task sub-agents
- fix(impl-routing): apply Z.AI-recommended CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
- chore: bump local VERSION to v2.24.0 [sync]
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- chore: bump local VERSION to v2.23.0 [sync]
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.29.0] - 2026-04-30

### Changed
- chore: bump local VERSION to v2.28.0 [sync]
- feat(scripts): minimal fail-debug analyzer


## [2.28.0] - 2026-04-30

### Changed
- feat(scripts): minimal fail-debug analyzer
- chore: bump local VERSION to v2.27.0 [sync]


## [2.27.0] - 2026-04-30

### Changed
- feat(nested-claude-spawn): forensic dump on EXIT_CODE_NON_ZERO catch-all
- fix(daemon-monitor): persist max-rank phase across tail-window refreshes
- fix(scheduler): make YAML parser indent-aware


## [2.26.0] - 2026-04-30

### Changed
- feat(daemon): add --exit-when-idle auto-stop when backlog drained
- feat(E107bS08): User-skip telemetry — count + skip reason (#557)


## [2.25.0] - 2026-04-29

### Changed
- feat(E107bS08): user-skip telemetry — count + skip reason


## [2.24.0] - 2026-04-29

### Changed
- feat(E107bS08): user-skip telemetry — count + skip reason


## [2.23.0] - 2026-04-29

### Changed
- feat(E107bS08): user-skip telemetry — count + skip reason
- fix(workflow): restore secondary path — strengthen CLI invocation mandate + remove orphan Task spawn instruction


## [2.22.0] - 2026-04-29

### Changed
- fix(impl-routing): apply Claude Code proxy / gateway compat flags for secondary path
- fix(impl-routing): add Haiku model mapping for secondary path Task sub-agents
- fix(impl-routing): apply Z.AI-recommended CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
- chore: bump local VERSION to v2.24.0 [sync]
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- chore: bump local VERSION to v2.22.0 [sync]
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- chore: bump local VERSION to v2.23.0 [sync]
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.24.0] - 2026-04-29

### Changed
- fix(impl-routing): apply Z.AI-recommended API_TIMEOUT_MS=3000000 for secondary path
- feat(E107bS09): streaming progress UX during Q&A (#543)
- chore: bump local VERSION to v2.22.0 [sync]
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation


## [2.23.0] - 2026-04-29

### Changed
- feat(E107bS09): streaming progress UX during Q&A — AC1/AC2/AC3


## [2.22.0] - 2026-04-29

### Changed
- fix(monitor): monotone phase state machine + tighten nested regex + (sub) model annotation
- chore: bump local VERSION to v2.23.0 [sync]
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting
- chore: bump local VERSION to v2.22.0 [sync]
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.23.0] - 2026-04-29

### Changed
- feat(monitor): add WORKING fallback phase for active coding without specific marker
- fix(monitor): render model id as-is instead of short-label formatting


## [2.22.0] - 2026-04-29

### Changed
- feat(monitor): show active model on Phase line + double-space emoji gap
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.22.0] - 2026-04-29

### Changed
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.25.0] - 2026-04-29

### Changed
- feat(E107bS05): abort-safe handler — Stage 4 pre-loop skip option (#518)
- feat(E107bS03): ambiguity detector — heuristic + AST signal severity scoring (#516)


## [2.24.0] - 2026-04-29

### Changed
- feat(E107bS05): abort-safe-handler skill — Stage 4 pre-loop skip option


## [2.23.0] - 2026-04-29

### Changed
- feat(E107bS03): ambiguity detector skill — heuristic + AST signal severity scoring
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation (#514)


## [2.22.0] - 2026-04-29

### Changed
- feat(E107bS02): qa-loop-ui skill — sequential Q&A loop with skip, skip-all, partial-answer preservation
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed (#500)
- chore(daemon): add agent_exit phase logging for DEC-72 wrapper audit trail


## [2.22.0] - 2026-04-29

### Changed
- feat(E107bS01): smart-question-generator skill — ranked questions from ambiguity feed
- discovery(E121-E125): Phase D2 — 17 stories Pro multi-user collaboration


## [2.21.0] - 2026-04-28

### Changed
- feat(daemon-monitor): show pipeline phase per active delivery
- chore: regenerate skills indices + framework sync trace post SKILL-RIN-001


## [2.20.0] - 2026-04-27

### Changed
- feat(governance): SKILL-RIN-001 review-input + anti-girouette research bundle
- feat(E101S07a): daemon HMAC signing + webhook secret provisioning (#466)


## [2.19.0] - 2026-04-25

### Changed
- feat(E101S07a): daemon HMAC signing + webhook secret provisioning endpoint
- fix(daemon-monitor): classify nested claude -p (Implement Agent) as sub-agent
- feat(daemon-monitor): surface sub-agent activity + fix "Bash null" rendering
- fix(framework): use .gaai-worktrees/ naming to avoid in-project .gaai/ collision
- chore(framework): group delivery worktrees under <parent>/.gaai/<repo>/worktrees/
- feat(impl-routing): DEC-72 — env-driven default (secondary when configured)
- chore: bump local VERSION to v2.19.0 [sync]
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.19.0] - 2026-04-23

### Changed
- fix(daemon-monitor): classify nested claude -p (Implement Agent) as sub-agent
- feat(daemon-monitor): surface sub-agent activity + fix "Bash null" rendering
- fix(framework): use .gaai-worktrees/ naming to avoid in-project .gaai/ collision
- chore(framework): group delivery worktrees under <parent>/.gaai/<repo>/worktrees/
- feat(impl-routing): DEC-72 — env-driven default (secondary when configured)
- chore: bump local VERSION to v2.19.0 [sync]
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.19.0] - 2026-04-22

### Changed
- feat(daemon-monitor): surface sub-agent activity + fix "Bash null" rendering
- fix(framework): use .gaai-worktrees/ naming to avoid in-project .gaai/ collision
- chore(framework): group delivery worktrees under <parent>/.gaai/<repo>/worktrees/
- feat(impl-routing): DEC-72 — env-driven default (secondary when configured)
- chore: bump local VERSION to v2.19.0 [sync]
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.19.0] - 2026-04-22

### Changed
- chore(framework): group delivery worktrees under <parent>/.gaai/<repo>/worktrees/
- feat(impl-routing): DEC-72 — env-driven default (secondary when configured)
- chore: bump local VERSION to v2.19.0 [sync]
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.19.0] - 2026-04-20

### Changed
- feat(impl-routing): DEC-72 — env-driven default (secondary when configured)
- chore: bump local VERSION to v2.19.0 [sync]
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.19.0] - 2026-04-20

### Changed
- feat(delivery-loop): §7c unify non-.gaai deletions into sub-agent reviewer


## [2.18.0] - 2026-04-20

### Changed
- feat(E95): memory catalog saillance — cloud MCP metadata + OSS installer adapters


## [2.17.0] - 2026-04-15

### Changed
- feat(daemon): classify Anthropic rate-limit as transient, revert to refined
- chore(backlog): reset 7 stories failed by Anthropic rate-limit → refined
- chore(qa-gate): add Build/Type Integrity step to qa-review skill
- wip(E63S03): snapshot validate-memory-deltas scaffolding
- docs(core): extend memory-alignment-check category enum to match operational reality
- fix(core): context-bootstrap checks canonical memory path project/context.md
- chore(memory): Discovery ingestion pass + architecture governance
- fix: prevent silent daemon orphans + sub-agent reviewer for diff-scope


## [2.17.0] - 2026-04-05

### Changed
- feat: extend memory freshness checks to docs and README


## [2.16.0] - 2026-03-30

### Changed
- fix(monitor): adjust bottom pane split to 60%
- fix(monitor): increase bottom pane split to 65% for active deliveries visibility
- fix(governance): add Epic dependency propagation rule to generate-stories + validate-artefacts
- chore: update gaai-status command (add done/archive step) + clear daemon log
- fix(core): update --max-concurrent example to 5 (default is now 3)
- fix: default daemon concurrency is 3 slots, not 1
- fix(core): clarify /gaai-deliver vs /gaai-daemon — not aliases
- feat(core): harden Review Sub-Agent against LLM evaluation research findings
- fix(core): enforce YAML safety rules in delivery daemon (validate after every backlog write)
- fix(core): add write safety rules to generate-stories skill (never yaml.dump, match native indent)
- fix(core): add exponential backoff between daemon delivery retries
- fix(core): sync local VERSION with OSS + recursion guard for version bump commits


## [2.15.0] - 2026-03-26

### Fixed
- fix(core): revert daemon-setup to auto-set skipDangerousModePermissionPrompt
- fix(core): daemon-setup asks for confirmation before modifying global settings
- fix(core): stop auto-modifying global Claude Code settings
- refactor(core): make /gaai-deliver an alias of /gaai-daemon
- fix(gaai): monitor pane layout — 55% split, mouse scroll, clear scrollback
- fix(core): remove all project-specific references from .gaai/core/
- fix(discovery): add Brief Self-Assessment checklist to discovery.agent.md
- **Absolute worktree paths** — resolve once via `git rev-parse --show-toplevel`, use `$WORKTREE_PATH` everywhere (#128)
- **Mandatory worktree validation gate** — delivery fails explicitly if worktree missing after creation (#127)
- **Remove Tier 1 solo-founder shortcut** — worktree isolation is now unconditional regardless of tier (#125)
- **Fail-fast remote guard** — Step 0 checks for `origin` remote before any git operation (#126)
- **`GAAI_WORKTREE_BASE` env var** — configurable worktree location for cloud-synced repos (Dropbox/OneDrive)
- **Validation gate fix** — use `-e` (file exists) not `-d` (directory) for worktree `.git` check
- fix(delivery): CI advisory mode — don't block merge when no branch protection

## [2.14.0] - 2026-03-23

### Changed
- fix(sync): defer marker+tag until after successful PR merge
- feat(governance): content-review specialist — post-implementation copy quality gate


## [2.13.0] - 2026-03-23

### Changed
- feat(core): add language rule to base rules — agents match human language, artefacts stay English


## [2.12.0] - 2026-03-23

### Changed
- fix(governance): DEC-208 D2 amended — self-merge on staging PERMITTED
- feat(governance): Mission Brief — tailored context per sub-agent invocation
- fix(security): prevent E64S03-class incidents — 4 hardening measures
- fix(core): remove French from framework — English-only for OSS reuse

## [2.11.0] - 2026-03-23

### Changed
- feat(governance): scope-filtered Session Brief per sub-agent

## [2.10.0] - 2026-03-22

### Changed
- feat(governance): structured context passing — Session Brief with typed item IDs
- fix(governance): escalation is last resort — resolve with Brief + DECs first

## [2.9.0] - 2026-03-22

### Changed
- feat(governance): SKILL-RSA-001 review-story-alignment — adversarial story review gate
- fix(governance): human validates Session Brief + explicit reviewer invocation template

## [2.8.0] - 2026-03-21

### Changed
- feat(governance): enforce skill attestation — skills_invoked + audit skill (CRS-028)
- feat: lead with 4 commands + add Core Skills section to README.skills.md
- fix: align license declarations to ELv2 and correct factual errors
- fix(governance): Discovery Session Brief — capture ALL session intelligence, not just decisions
- fix(governance): prevent Discovery decision drift — 3 systemic fixes
- fix(governance): add Definition of Ready (DoR) per Epic
- chore(governance): refactor base.rules.md — backlog lifecycle, archiving, memory discipline, forbidden patterns
- docs: mention Discovery Session Brief in README + QUICK-REFERENCE

## [2.7.0] - 2026-03-20

### Changed
- feat(skill): add skill-optimize (CRS-026) + pattern-transfer (CRS-027) — self-improvement loop axes 2 & 3
- fix(governance): add Mandatory Skill Read guard to Discovery Agent

## [2.6.0] - 2026-03-18

### Changed
- fix(hooks): never overwrite existing .githooks/ files — append GAAI dispatcher
- fix(core): remove all project-specific DEC references from framework files
- fix(governance): enforce DECs across Discovery, Delivery, and code — 4-level protection

## [2.5.0] - 2026-03-18

### Changed
- feat(daemon): 2-column monitor banner with fixed header
- docs: simplify daemon docs — /gaai-daemon as single entry point

## [2.4.0] - 2026-03-18

### Changed
- feat(daemon): route /gaai-daemon through daemon-start.sh with auto-monitor

## [2.3.0] - 2026-03-18

### Changed
- feat(daemon): tmux monitor dashboard, cross-OS fixes, dependency checks
- fix(daemon): status bar improvements + sync script immediate merge
- fix(daemon): prefer tmux over Terminal.app, remove focus-stealing activate
- fix(sync): escape variable names adjacent to unicode in auto-bump log
- fix(governance): anti-collision guards
- fix(gaai-core): capture delivery metadata in daemon wrapper
- fix(gaai-core): audit resolution — align authority boundaries, formalize lifecycle, add tooling
- chore(daemon): set --max-concurrent default to 3 and add auto-monitor launch
- chore: consolidate daemon log path + relocate sync artifacts to .github/
- docs: contributions → issues and feedback welcome (ELv2 IP protection)

## [2.2.0] - 2026-03-16

### Added
- Mandatory Memory Check in Discovery Agent — MUST scan memory index before producing any plan or artefact
- Mandatory Memory Check in Delivery Agent — MUST scan memory index before composing context bundles for sub-agents
- Automated CHANGELOG updates on framework sync

### Changed
- Memory retrieval upgraded from optional skill to mandatory workflow step in both agents (DEC-195)

---

## [2.1.1] - 2026-03-13

### Changed
- README sections reordered: Install moved after value proposition
- README: merged "The Problem It Solves", "Who This Is For", and "Compared to Other Approaches" into a single "Why GAAI" section
- BMAD-METHOD comparison updated for v6 accuracy

### Added
- "Honest Trade-offs" section in README — 4 limitations stated upfront
- Research basis sections in ADRs 002, 003, 004, 006, 009 (15 verified sources across 5 ADRs)

### Removed
- `docs/hackernews-post.md` — distribution content, not documentation
- 7 niche/duplicate skills pruned from core (47 → 40)

---

## [2.1.0] - 2026-03-04

### Changed
- README.md rewritten for conversion: session example moved to position 2, install condensed to single primary method
- Skill count corrected: 37 → 47 (6 Discovery + 11 Delivery + 30 Cross)
- GAAI.md post-install links fixed: relative paths replaced with absolute GitHub URLs
- Contributor CLAUDE.md moved to `docs/contributing/DEVELOPMENT.md`

### Added
- `.gaai/QUICK-REFERENCE.md` — single-page cheat sheet accessible post-install

### Removed
- 7 duplicate root directories accidentally merged from contrib flat subtree
- `.gaai/core/scaffolding/` eliminated — `.gaai/project/` now ships ready-to-use
- Redundant README sections moved to framework docs

---

## [2.0.0] - 2026-02-28

### Changed
- Restructured `.gaai/` into `core/` (framework) + `project/` (user data via scaffolding)
- License changed from MIT to ELv2 (Elastic License 2.0)
- Install.sh updated for core/project split with scaffolding system
- Added git subtree support for syncing framework updates into consumer projects
- 37 skills across Discovery (6), Delivery (9), and Cross (22) categories
- Added AGENTS.md adapters for OpenCode, Codex CLI, Gemini CLI, Antigravity

---

## [1.0.0] - 2026-02-18

### Added
- `.gaai/` core framework folder
- Three agents: Discovery, Delivery, Bootstrap
- 31 skills across Discovery (6), Delivery (9), and Cross (16) categories
- Context system: rules, memory, backlog, artefacts
- Four workflows: delivery loop, context bootstrap, discovery-to-delivery, emergency rollback
- Six bash utility scripts
- Tool compatibility adapters: Claude Code, Cursor, Windsurf
- Interactive installer (`.gaai/core/scripts/install.sh`) with pre-flight check (`install-check.sh`)
- Full documentation in `docs/`
