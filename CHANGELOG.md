# Changelog

All notable changes to Temper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
