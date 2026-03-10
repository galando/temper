# Changelog

All notable changes to Temper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-03-10

### Added
- **Parallel task detection** in `/temper:plan` — tasks.md marks independent tasks with `[PARALLEL: with Task X]` for human-directed parallelism, with "when in doubt keep sequential" guard
- **Build checkpoint resume** in `/temper:build` — persists progress to `.temper/build-state.json` after each task; offers resume on next invocation
- **Diff-aware review** in `/temper:review` — subagent prompt weights changed lines at full scrutiny; classifies findings as REGRESSION / NEW ISSUE / PRE-EXISTING
- **Performance pattern detection** in `/temper:review` — catches N+1 queries, unbounded results, sync I/O in hot path, large objects in memory
- **Multi-hypothesis RCA** in `/temper:fix` — enumerates up to 5 ranked hypotheses before committing to a fix; falls back to next hypothesis if regression test denies the first
- **Hotspot map** in `/temper:status` — scans `.temper/reviews/*.md` to compute issue density per file; HOTSPOTS section in dashboard
- New docs page `docs/why-temper.md` — answers "Why not just tell Claude to be careful?"

### Changed
- README rewritten: pain → before/after story → comparison table → value by audience → install
- `docs/index.md` and `docs/index.html` updated to match pain → solution → proof → install narrative
- `docs/commands.md` extended with realistic terminal output examples

## [1.0.0] - 2025-03-09

### Added
- Initial release of Temper plugin
- **7 Commands:**
  - `/temper:plan` - Feature planning with blast radius analysis
  - `/temper:build` - TDD execution with quality gates
  - `/temper:review` - Confidence-scored code review
  - `/temper:check` - Stack-aware validation pipeline
  - `/temper:fix` - Root cause analysis + bug fix
  - `/temper:standards` - Interactive standards builder
  - `/temper:status` - Quality metrics dashboard
- **4 Built-in Packs:**
  - `quality` - Code quality rules
  - `tdd` - Test-driven development
  - `security` - OWASP Top 10 security
  - `git` - Git workflow conventions
- **6 Stack Definitions:**
  - Spring Boot (Java)
  - React + TypeScript
  - Node.js + Express
  - FastAPI (Python)
  - Go
  - Rust
- **Core Features:**
  - Auto-detection of project stack
  - Blast radius analysis for changes
  - Confidence scoring for review findings
  - Review memory for noise reduction
  - Learning loop for auto-rule suggestions
  - Technical debt tracking
  - Context-efficient architecture (~2KB always-on)
- **Templates:**
  - spec.md, plan.md, tasks.md, quickstart.md
- **Examples:**
  - Company pack example (Acme Corp)
  - Company preset example (YAML)

### Documentation
- Full README with quick start guide
- CONTRIBUTING guide for developers
- MIT License
