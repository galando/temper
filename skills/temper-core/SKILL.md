---
description: "Temper core: stack detection, quality gates, blast radius, review memory"
---

# Temper Core

Stack detection → Quality gates (SUGGEST/WARN/BLOCK) → Confidence scoring (0.0-1.0) → Review memory → Metrics.

## Stack Detection
1. `.claude/temper.config` → `stack` field
2. `.claude/presets/*.yaml` → `stack` section
3. Auto-detect: pom.xml→Spring Boot, package.json→Node, pyproject.toml→Python, go.mod→Go, Cargo.toml→Rust
4. Load `.claude/packs/stacks/{stack}.md`

## Pack Resolution (v4.3.0)
Three-tier: project-local > global > built-in. Read live (no cache) by every stage command (build, review, check, plan, design) for phase-filtered loading.
- `.claude/packs/{name}/rules.md` (project)
- `~/.claude/packs/{name}/rules.md` (global)
- `$CLAUDE_PLUGIN_ROOT/packs/{name}/rules.md` (built-in)
Packs support `link: plugin://name | skill://name` and `phases: [build, review, ...]` —
declared in the pack's `rules.md` frontmatter, overridable per project on the `packs:`
config entry, defaulting to `all` when neither says. `[]` means no stage loads it.
Precedence and rationale: `reference/pack.md` → "Pack Configuration Schema".

## Quality Gates
- **SUGGEST**: Non-blocking
- **WARN**: Highlighted, developer decides
- **BLOCK**: Must fix (security/architecture only)

## Confidence & Memory
- Threshold: 0.7 (configurable)
- Review memory: `.temper/review-memory.json` — auto-suppress after 5 dismissals
- Metrics: `.temper/metrics.json`

## Review memory — the one finding memory
Reviews get smarter over time through a single store, `.temper/review-memory.json`
(there is no separate learning file). Written by `/temper:review`, surfaced at
`/temper:status`.

| Capability | Trigger | Action |
|-----------|---------|--------|
| Pattern tracking | every review | Cluster findings by category + file-path prefix + keywords into `patterns[key]` |
| Rule promotion | accepted 3+ times @ ≥70% (5+ @ ≥80% for security/architecture → BLOCK) | Suggest a pack rule at `/temper:status`; the human accepts BLOCK/WARN |
| Noise reduction | dismissed 3+ (downgrade) / 5+ (suppress) | Downgrade or auto-suppress, per-context |

**Graceful degradation:** absent `review-memory.json` → every command works unchanged.

Full docs: `$CLAUDE_PLUGIN_ROOT/reference/review.md` → "Metrics + Memory".

## Capabilities (v5.0.0)

Four independently optional capabilities, all enabled by default. Controlled via `capabilities` section in temper.config.

| Capability | Stage | Purpose |
|-----------|-------|---------|
| Architecture Depth | Review | Module-depth analysis: seams, adapters, locality, leverage, deletion test |
| Grill Me | Plan, Design | Socratic challenge mode — stress-test plans before building |
| Teach Me | Plan, Design, Build, Check | Comprehension companion — teach + quiz the human to mastery at each teaching gate (Review excluded — taught at Build) |
| Config Suggestions | Check | Suggest CLAUDE.md/AGENTS.md updates based on what was built |
| HTML Review | Plan | Interactive browser-based plan review with inline comments |

**Graceful degradation:** Each capability checks its config flag. Missing config = all enabled (default-on).

## Full Docs
`$CLAUDE_PLUGIN_ROOT/reference/{command}.md`
