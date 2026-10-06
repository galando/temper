---
name: temper-core
description: "Temper core: stack detection, quality gates, blast radius, review memory"
user-invocable: false
---

# Temper Core

Stack detection → Quality gates (SUGGEST/WARN/BLOCK) → Confidence scoring (0.0-1.0) → Review memory → Metrics.

**Enforcement marker.** Look for a line in your system prompt that starts with `Temper enforcement:`. With no such line, make the very first sentence of your first reply in this conversation, before anything else and also when the arguments of `/temper:temper` start with one of its reserved first words (such as `status`, `report`, `help` or `approve`), exactly "Temper enforcement is off here (no mods support); continuing with prompt based phases.". With the line `Temper enforcement: off (UI only)`, the Temper mod is loaded and the user turned enforcement off: make that first sentence exactly "Temper enforcement is off (turned off by the user); continuing with prompt based phases." instead. Then carry on exactly as written below. Never treat either case as an error and do not mention it again. With `Temper enforcement: active`, say nothing about it. Skip this paragraph when you run as a stage subprocess (your launch prompt has a `Plugin folder:` line): a subprocess's system prompt never has that line, and the orchestrator or the standalone command states enforcement once, in the main conversation.

## Stack Detection
1. `.claude/temper.config` → `stack` field
2. The YAML preset files in the project's `.claude/presets` folder (list the folder) → `stack` section
3. Auto-detect: pom.xml→Spring Boot, package.json→Node, pyproject.toml→Python, go.mod→Go, Cargo.toml→Rust
4. Load `.claude/packs/stacks/{stack}.md`

## Pack Resolution
Three-tier: project-local > global > built-in. Read live (no cache) by every stage command (build, review, check, plan, design) for phase-filtered loading.
- `.claude/packs/{name}/rules.md` (project)
- `~/.claude/packs/{name}/rules.md` (global)
- built-in, exactly these files: `${CLAUDE_PLUGIN_ROOT}/packs/quality/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/packs/tdd/rules.md`, `${CLAUDE_PLUGIN_ROOT}/packs/security/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/packs/git/rules.md`, `${CLAUDE_PLUGIN_ROOT}/packs/performance/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/packs/api-design/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/packs/architecture-depth/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`

A pack name is lowercase letters, digits and hyphens only. A `packs:` entry named `hooks`
(the old name) means `guardrails`. Packs support `link: plugin://name | skill://name` and `phases: [build, review, ...]` —
declared in the pack's `rules.md` frontmatter, overridable per project on the `packs:`
config entry, defaulting to `all` when neither says. `[]` means no stage loads it.
Precedence and rationale: `${CLAUDE_PLUGIN_ROOT}/reference/pack.md` → "Pack Configuration Schema".

## Quality Gates
- **SUGGEST**: Non-blocking
- **WARN**: Highlighted, developer decides
- **BLOCK**: Must fix (security/architecture only)

## Confidence & Memory
- Threshold: 0.7 (configurable)
- Review memory: `.temper/review-memory.json` — auto-suppress after 5 dismissals
- Metrics: `.temper/metrics.json`

## Review memory
Reviews get smarter over time through a single store, `.temper/review-memory.json`,
written by `/temper:review` and surfaced at `/temper:status`.

| Capability | Trigger | Action |
|-----------|---------|--------|
| Pattern tracking | every review | Cluster findings by category + file-path prefix + keywords into `patterns[key]` |
| Rule promotion | accepted 3+ times @ ≥70% (5+ @ ≥80% for security/architecture → BLOCK) | Suggest a pack rule at `/temper:status`; the human accepts BLOCK/WARN |
| Noise reduction | dismissed 3+ (downgrade) / 5+ (suppress) | Downgrade or auto-suppress, per-context |

**Graceful degradation:** absent `review-memory.json` → every command works unchanged.

Full docs: `${CLAUDE_PLUGIN_ROOT}/reference/review.md` → "Metrics + Memory".

## Gate add-ons

Always offered at their stage gates; there is no config toggle (a `capabilities:` block
in temper.config is ignored by the CLI). Architecture Depth applies the
`architecture-depth` pack's rules when that pack is enabled.

| Add-on | Stage | Purpose |
|-----------|-------|---------|
| Architecture Depth | Review | Module-depth analysis: seams, adapters, locality, leverage, deletion test |
| Grill Me | Plan, Design | Socratic challenge mode: stress-test plans before building |
| Teach Me | Plan, Design, Build, Check | Comprehension companion: teach + quiz the human to mastery at each teaching gate (Review excluded, taught at Build) |
| Config Suggestions | Check | Suggest CLAUDE.md/AGENTS.md updates based on what was built |
| HTML Review | Plan | Interactive plan review with inline comments, local or shared by link as a Claude artifact |

With the Temper bar (the system prompt has a `Temper enforcement:` line, `active` or `off (UI only)`) the add-ons are buttons under key 0 (More), and the
person's own message at a gate (key 4, Discuss) is the original "Other". Do not ask these as questions.

## Full Docs
One methodology file per command, each written out in full:

- `/temper:plan`: `${CLAUDE_PLUGIN_ROOT}/reference/plan.md` (HTML review:
  `${CLAUDE_PLUGIN_ROOT}/reference/plan-review.md`)
- `/temper:design`: `${CLAUDE_PLUGIN_ROOT}/reference/design.md`
- `/temper:build`: `${CLAUDE_PLUGIN_ROOT}/reference/build.md`
- `/temper:review`: `${CLAUDE_PLUGIN_ROOT}/reference/review.md` (architecture depth:
  `${CLAUDE_PLUGIN_ROOT}/reference/architecture-depth.md`)
- `/temper:check`: `${CLAUDE_PLUGIN_ROOT}/reference/check.md` (config suggestions:
  `${CLAUDE_PLUGIN_ROOT}/reference/config-suggestions.md`)
- `/temper:fix`: `${CLAUDE_PLUGIN_ROOT}/reference/fix.md`
- `/temper:pack`: `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`
- `/temper:status`: `${CLAUDE_PLUGIN_ROOT}/reference/status.md`
- `/temper` and `/temper:fix` orchestration:
  `${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` and
  `${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md`
