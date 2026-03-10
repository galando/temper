---
name: temper-core
description: "Temper core skill: stack detection, quality gates, blast radius analysis, and adaptive learning for AI-generated code"
license: MIT
allowed-tools:
  - read
  - write
  - bash
metadata:
  version: "1.0.0"
  author: "Gal Naor"
---

# Temper Core

Stack detection → Quality gates (SUGGEST/WARN/BLOCK) → Confidence scoring (0.0-1.0) → Review memory → Metrics.

## Stack Detection

1. `.claude/temper.config` → `stack` field
2. `.claude/presets/*.yaml` → `stack` section
3. Auto-detect: pom.xml→Spring Boot, package.json→Node, pyproject.toml→Python, go.mod→Go, Cargo.toml→Rust
4. Load `.claude/packs/stacks/{stack}.md`

## Quality Gates

- **SUGGEST**: Non-blocking
- **WARN**: Highlighted, developer decides
- **BLOCK**: Must fix (security/architecture only)

## Confidence & Memory

- Threshold: 0.7 (configurable)
- Review memory: `.temper/review-memory.json` — auto-suppress after 5 dismissals
- Metrics: `.temper/metrics.json`

## Commands

| Tool | Purpose |
|------|---------|
| `temper_plan` | Plan with blast radius |
| `temper_build` | TDD + quality gates |
| `temper_review` | Confidence-scored review |
| `temper_check` | Stack validation |
| `temper_fix` | RCA + fix |
| `temper_standards` | Build team standards |
| `temper_status` | Quality dashboard |

## Pack Loading

Temper loads packs from:
1. Project packs — `.claude/packs/` in your project
2. Built-in packs — quality, tdd, security, git

## Configuration

Create `.claude/temper.config`:
```yaml
stack: spring-boot
packs:
  - quality
  - tdd
  - security
coverage:
  threshold: 80
```

## Full Docs

See `commands/` directory for detailed command documentation.
