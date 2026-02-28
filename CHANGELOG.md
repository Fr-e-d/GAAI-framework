# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Interactive installer (`install.sh`) with pre-flight check (`install-check.sh`)
- Full documentation in `docs/`
