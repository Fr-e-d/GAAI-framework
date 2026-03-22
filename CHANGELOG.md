# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.8.6] - 2026-03-22

### Changed
- fix(governance): sync templates + add DoR (Definition of Ready) per Epic


## [2.8.5] - 2026-03-22

### Changed
- chore(governance): refactor base.rules.md — backlog lifecycle, archiving, memory discipline, forbidden patterns


## [2.8.4] - 2026-03-22

### Changed
- feat(E64S03): lead with 4 commands + add Core Skills section to README.skills.md
- chore: daemon backlog hygiene — archiving rules + dependency cleanup


## [2.8.3] - 2026-03-22

### Changed
- chore: sync framework v2.8.2 artifacts and project indices


## [2.8.1] - 2026-03-22

### Changed
- fix: align license declarations to ELv2 and correct HackerNoon draft factual errors


## [2.8.0] - 2026-03-21

### Changed
- feat(governance): enforce skill attestation — skills_invoked + audit skill (CRS-028)


## [2.7.4] - 2026-03-21

### Changed
- fix(governance): add Mandatory Skill Read guard to Discovery Agent


## [2.7.3] - 2026-03-21

### Changed
- chore: version sync v2.7.2 + gotrue bump + billing badge color swap


## [2.7.2] - 2026-03-21

### Changed
- chore: sync local VERSION to v2.7.1 after OSS auto-bump


## [2.7.1] - 2026-03-21

### Changed
- chore: version bump v2.7.0 + skills index refresh + Facebook engage session notes


## [2.7.0] - 2026-03-20

### Changed
- feat(skill): add skill-optimize (CRS-026) + pattern-transfer (CRS-027) — self-improvement loop axes 2 & 3


## [2.6.7] - 2026-03-20

### Changed
- chore(content): YouTube session 4 — scan + reply + 5 new outbound comments


## [2.6.6] - 2026-03-19

### Changed
- chore(gaai): bump framework v2.6.5 + update retry counts


## [2.6.5] - 2026-03-19

### Changed
- chore: E55S04 provisioning + DEC-203 route migration discovery + memory refresh + admin RBAC


## [2.6.4] - 2026-03-19

### Changed
- fix(governance): enforce DECs across Discovery, Delivery, and code — 4-level protection


## [2.6.3] - 2026-03-18

### Changed
- chore(E56S02): done [delivery]
- docs(memory): full memory refresh — fix stale data across 6 files


## [2.6.2] - 2026-03-18

### Changed
- fix(core): remove all project-specific DEC references from framework files


## [2.6.1] - 2026-03-18

### Changed
- fix(hooks): never overwrite existing .githooks/ files — append GAAI dispatcher


## [2.5.2] - 2026-03-18

### Changed
- docs: simplify daemon docs — /gaai-daemon as single entry point


## [2.5.1] - 2026-03-18

### Changed
- docs: update daemon docs — default concurrency, monitoring dashboard


## [2.5.0] - 2026-03-18

### Changed
- feat(daemon): 2-column monitor banner with fixed header


## [2.4.0] - 2026-03-18

### Changed
- feat(daemon): route /gaai-daemon through daemon-start.sh with auto-monitor


## [2.3.2] - 2026-03-18

### Changed
- chore(daemon): set --max-concurrent default to 3 and add auto-monitor launch


## [2.3.1] - 2026-03-18

### Changed
- chore: consolidate daemon log path + relocate sync artifacts to .github/


## [2.3.0] - 2026-03-18

### Changed
- fix(sync): escape variable names adjacent to unicode in auto-bump log
- docs(gaai-core): update framework link wording in GAAI.md
- fix(gaai-core): capture delivery metadata in daemon wrapper (stop hook doesn't fire in -p mode)
- fix(gaai-core): cost avg uses tracked stories only, not total done
- fix(gaai-core): correct cost avg to divide by total done, not just tracked stories
- fix(gaai-core): audit resolution — align authority boundaries, formalize lifecycle, add tooling
- docs: contributions → issues and feedback welcome (ELv2 IP protection)
- fix(daemon): status bar improvements + sync script immediate merge
- feat(daemon): tmux monitor dashboard, cross-OS fixes, dependency checks
- fix(governance): anti-collision guards + E52→E53 renumbering + CI/CD docs
- fix(daemon): prefer tmux over Terminal.app, remove focus-stealing activate
- chore(governance): reset interrupted deliveries E52S02 + update stories & skills
- chore(ci): CF Workers Builds for staging + skills cleanup (DEC-197, DEC-198)
- chore(gaai): anonymize sync script + skills/scripts updates


## [2.2.0] - 2026-03-16

### Added
- Mandatory Memory Check in Discovery Agent — MUST scan memory index before producing any plan or artefact
- Mandatory Memory Check in Delivery Agent — MUST scan memory index before composing context bundles for sub-agents
- Automated CHANGELOG updates on framework sync (sync-framework-to-oss.sh)

### Changed
- fix(gaai-core): capture delivery metadata in daemon wrapper (stop hook doesn't fire in -p mode)
- fix(gaai-core): cost avg uses tracked stories only, not total done
- fix(gaai-core): correct cost avg to divide by total done, not just tracked stories
- fix(gaai-core): audit resolution — align authority boundaries, formalize lifecycle, add tooling
- docs: contributions → issues and feedback welcome (ELv2 IP protection)
- fix(daemon): status bar improvements + sync script immediate merge
- feat(daemon): tmux monitor dashboard, cross-OS fixes, dependency checks
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
