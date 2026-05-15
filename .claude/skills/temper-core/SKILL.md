---
description: "Temper core: stack detection, quality gates, blast radius, adaptive learning"
---

# Temper Core

Stack detection → Quality gates (SUGGEST/WARN/BLOCK) → Confidence scoring (0.0-1.0) → Review memory → Adaptive learning → Metrics.

## Stack Detection
1. `.claude/temper.config` → `stack` field
2. `.claude/presets/*.yaml` → `stack` section
3. Auto-detect: pom.xml→Spring Boot, package.json→Node, pyproject.toml→Python, go.mod→Go, Cargo.toml→Rust
4. Load `.claude/packs/stacks/{stack}.md`

## Pack Resolution (v4.3.0)
Three-tier: project-local > global > built-in. Cached in `.temper/pack-manifest.json`.
- `.claude/packs/{name}/rules.md` (project)
- `~/.claude/packs/{name}/rules.md` (global)
- `$CLAUDE_PLUGIN_ROOT/.claude/packs/{name}/rules.md` (built-in)
Packs support `link: plugin://name | skill://name` and `phases: [build, review, ...]`.

## Quality Gates
- **SUGGEST**: Non-blocking
- **WARN**: Highlighted, developer decides
- **BLOCK**: Must fix (security/architecture only)

## Confidence & Memory
- Threshold: 0.7 (configurable)
- Review memory: `.temper/review-memory.json` — auto-suppress after 5 dismissals
- Metrics: `.temper/metrics.json`

## Adaptive Learning (v4.6.0)
Post-review intelligence layer that makes reviews smarter over time. Runs as Step 8.5 in `/temper:review` and displays in `/temper:status`.

**Three capabilities:**

| Capability | Trigger | Action |
|-----------|---------|--------|
| Pattern Detection | Post-review hook (Step 8.5) | Cluster recurring findings by category + file pattern + keywords |
| Rule Suggestions | Pattern accepted 3+ times at 70%+ rate | Generate pack rule template, queue for promotion |
| Noise Reduction | Pattern dismissed 5+ times | Auto-suppress, reduce false positives |

**Key files:**
- `.temper/learning.json` — Learning state (detected patterns, suppressions, suggestions, learning curve)
- `.temper/learning/suggestions/` — Generated rule suggestion templates
- `.claude/packs/adaptive-learning/rules.md` — Promoted rules (user-accepted suggestions)

**Graceful degradation:** If `learning.json` is absent, all commands work unchanged. No errors, no warnings.

Full docs: `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/learning.md`

## Full Docs
`$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/{command}.md`
