---
description: "Temper core: stack detection, quality gates, blast radius, learning"
triggers:
  - file_pattern: "*.java;*.ts;*.tsx;*.js;*.jsx;*.py;*.go;*.rs"
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

## Full Docs
`$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/{command}.md`
