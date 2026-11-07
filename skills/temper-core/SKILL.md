---
name: temper-core
description: "Temper core: stack detection, quality gates, blast radius, review memory"
user-invocable: false
---

# Temper Core

Stack detection → quality gates (SUGGEST, WARN, BLOCK) → confidence scoring (0.0 to 1.0) →
review memory → metrics.

This is the Markdown edition: every gate is a checklist Claude applies and a question the person
answers. Nothing is computed or blocked by a program. The full edition (github.com/galando/temper)
computes the verdicts with its CLI and blocks a commit with a hook.

## Stack Detection
1. `.claude/temper.config` → `stack` field
2. The YAML preset files in the project's `.claude/presets` folder (list the folder) → `stack` section
3. Auto-detect: pom.xml → Spring Boot, package.json → Node, pyproject.toml → Python, go.mod → Go, Cargo.toml → Rust
4. Load `.claude/packs/stacks/{stack}.md`, else the plugin's `packs/stacks/{stack}.md`

## Pack Resolution
Two tiers: project, then built-in. Read live by every stage (plan, design, build,
review, check, fix), keeping the rules whose `phases` is `all` or names the stage.
- `.claude/packs/{name}/rules.md` (project)
- built-in, in the plugin's `packs` folder: `quality`, `tdd`, `security`, `git`, `performance`,
  `api-design`, `architecture-depth`

A pack name is lowercase letters, digits and hyphens. The `packs:` list of `.claude/temper.config`
names the enabled packs; without it, `quality`, `tdd`, `security`, `git` and `performance`. A pack's
`rules.md` may declare `phases: [build, review]` in its front matter; `[]` means no stage loads it.

## Quality Gates
- **SUGGEST**: non-blocking
- **WARN**: highlighted, the developer decides
- **BLOCK**: must be fixed (security and architecture only)

## Confidence and Memory
- Threshold: 0.7 (`review.confidence-threshold`)
- Review memory: `.temper/review-memory.json`; suppress after 5 dismissals
- Metrics: `.temper/metrics.json`

## Review memory
Reviews improve over time through one store, `.temper/review-memory.json`, written by Review
and shown by `/temper:status`.

| Capability | Trigger | Action |
|-----------|---------|--------|
| Pattern tracking | every review | cluster findings by category, path prefix and keywords into `patterns[key]` |
| Rule promotion | accepted 3 or more times at 70% or more (5 or more at 80% for security or architecture: BLOCK) | suggest a pack rule at `/temper:status`; the person decides |
| Noise reduction | dismissed 3 or more (downgrade), 5 or more (suppress) | per context |

Without `review-memory.json`, every command works the same.

## Gate add-ons

Offered at the gates of their stages; each runs and then asks the same gate again; none moves
the run.

| Add-on | Stage | Purpose |
|-----------|-------|---------|
| Architecture Depth | Review | module depth: seams, adapters, locality, leverage, the deletion test |
| Grill Me | Intent, Plan, Design | Socratic challenge: stress-test the work before the next stage |
| Teach Me | any gate, typed | teach and quiz the person on what the stage produced |

## Full Docs

In the plugin folder:

- the flow and every gate question: `commands/temper.md`
- the gate checklists: `reference/gates.md`
- the run files: `reference/run-state.md`
- each stage's method: `reference/plan.md`, `reference/design.md`, `reference/build.md`,
  `reference/review.md` (and `reference/architecture-depth.md`), `reference/check.md`,
  `reference/fix.md`
