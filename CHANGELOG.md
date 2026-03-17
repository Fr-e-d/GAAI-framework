# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.2.0] - 2026-03-16

### Added
- Mandatory Memory Check in Discovery Agent — MUST scan memory index before producing any plan or artefact
- Mandatory Memory Check in Delivery Agent — MUST scan memory index before composing context bundles for sub-agents
- Automated CHANGELOG updates on framework sync (sync-framework-to-oss.sh)

### Changed
- fix(governance): anti-collision guards + E52→E53 renumbering + CI/CD docs
- chore(ci): CF Workers Builds for staging + skills cleanup (DEC-197, DEC-198)
- chore(gaai): anonymize sync script + skills/scripts updates
- Memory retrieval upgraded from optional skill to mandatory workflow step in both agents (DEC-195)

---

## [2.1.1] - 2026-03-13

### Changed
- README sections reordered: Install moved after value proposition (See It in Action → Problem → How It Works → Who This Is For → Install)
- README: merged "The Problem It Solves", "Who This Is For", and "Compared to Other Approaches" into a single "Why GAAI" section (less redundancy with the demo)
- BMAD-METHOD comparison updated for v6 accuracy (generalized persona list, removed outdated Node.js claim)

### Added
- "Honest Trade-offs" section in README — 4 limitations stated upfront
- Research basis sections in ADRs 002, 003, 004, 006, 009 (15 verified sources across 5 ADRs)

### Removed
- `docs/hackernews-post.md` — distribution content, not documentation (useful sections absorbed into README)
- 7 niche/duplicate skills pruned from core (47 → 40): i18n-extract, i18n-validate, i18n-glossary-sync, idiomatique-translate, build-skills-index, generate-build-in-public-content, frontend-design

---

## [2.1.0] - 2026-03-04

### Changed
- README.md rewritten for conversion: session example moved to position 2, install condensed to single primary method, problem section shortened to bullets
- Skill count corrected: 37 → 47 (6 Discovery + 11 Delivery + 30 Cross)
- GAAI.md post-install links fixed: relative `../../docs/` paths replaced with absolute GitHub URLs
- Contributor CLAUDE.md moved to `docs/contributing/DEVELOPMENT.md` to avoid collision with user-deployed CLAUDE.md

### Added
- `.gaai/QUICK-REFERENCE.md` — single-page cheat sheet accessible post-install

### Removed
- 7 duplicate root directories (`agents/`, `skills/`, `contexts/`, `compat/`, `scaffolding/`, `scripts/`, `workflows/`) accidentally merged from contrib flat subtree
- 2 duplicate root files (`GAAI.md`, `VERSION`) — canonical copies live in `.gaai/core/`
- `.gaai/core/scaffolding/` eliminated — `.gaai/project/` now ships ready-to-use in the repo (plug & play)
- README sections: "Five Rules", "Fork & Own", "Branches" (moved to framework docs / CONTRIBUTING.md)

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
