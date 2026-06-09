# ADR-0002: Nested Subagent Support

**Status:** Proposed
**Date:** 2026-06-09
**Supersedes:** (none)

## Context

Claude Code now supports **nested subagents** — an agent launched via the Agent
tool can itself launch further agents, up to a platform hard cap of **depth 5**.
Before this change, a subagent could not spawn another subagent; delegation was a
single level deep.

This matters to Temper more than it first appears, because **Temper's reference
docs already describe a two-level agent topology that the platform could not
previously execute when commands were composed.**

When you run `/temper`, the topology is:

```
depth 0   /temper orchestrator (runs in the main session)
depth 1   stage agent — Plan / Design / Build / Review / Check (Agent subprocess)
depth 2   helpers each stage already tries to launch
```

The depth-2 layer is documented throughout the reference set:

- **Review** Step 2 — "Launch Parallel Review Subagents" (up to 3, split by
  domain) — `reference/review.md:143`
- **Plan** Phase 1 — "Launch an Explore subagent" to auto-prime — `reference/plan.md:85`
- **Fix** — "Launch an Explore subagent" — `reference/fix.md:71`
- **architecture-depth** — `Agent tool with subagent_type=Explore` — `reference/architecture-depth.md:46`

Run **standalone** (`/temper:review` directly), these are depth 0→1 calls and have
always worked. Run **through the `/temper` orchestrator**, the same calls become
depth 0→1→2 — an agent spawning an agent — which the platform did not allow until
now. So the composed pipeline has been silently degrading these helpers to inline
work (or failing to launch them), meaning `/temper` did not actually deliver what
its standalone commands claimed.

Nested subagent support closes that gap, and additionally unblocks fan-out patterns
Temper has annotated but never executed (e.g. `[PARALLEL: with Task X]` markers
emitted by Plan at `reference/plan.md:714`, which Build runs serially today).

The question this ADR settles: **how should Temper adopt nested subagents without
hitting the depth-5 ceiling unpredictably, and in what order should the capability
roll out?**

## Decision

Adopt nested subagents in Temper governed by an explicit **depth budget**, surfaced
through a new `agents` config block and a shared section in
`reference/orchestrator-patterns.md`.

### 1. Config (`.claude/temper.config`)

```yaml
# Nested agents (v5.1.0)
agents:
  nested: true          # allow stages to spawn child agents
  max-depth: 4          # Temper's self-imposed cap (platform hard cap = 5)
  parallel-width: 3     # max concurrent children per stage (matches review's existing cap)
  on-budget-exhausted: inline   # within 1 of cap → run helper work inline instead of spawning
```

Defaults are conservative: `max-depth: 4` leaves one level of platform headroom
below the hard cap of 5, and `parallel-width: 3` generalizes the existing "max 3
parallel" rule already in `reference/review.md:285`.

Graceful degradation: a missing `agents` block means nesting is enabled with these
defaults — consistent with how every other v5.x capability is default-on.

### 2. Depth-budget accounting

The Stage Agent Launch Template in `reference/orchestrator-patterns.md` is extended
to pass a `depth_remaining` value into each subprocess prompt. Each stage, before
fanning out, applies one rule:

- `depth_remaining > 1` → spawn child agents (parallel up to `parallel-width`)
- `depth_remaining <= 1` → run the helper work **inline** (no spawn)

This makes degradation deterministic and local: a stage never needs global knowledge
of the tree, only the budget handed to it.

### 3. Rollout order

| Phase | Slice | Why first |
|-------|-------|-----------|
| 1 | Depth governance + unblock existing depth-2 helpers (Review/Plan/Fix/arch-depth) | Foundation; turns documented-but-dormant patterns into real ones |
| 2 | Parallel Build execution of `[PARALLEL]` tasks | Highest new capability; depends on Phase 1 budget plumbing |
| 3 | Fix RCA hypothesis fan-out (one child per suspected root cause) | Naturally parallel, isolates dead-end-hypothesis noise |
| 4 | Plan blast-radius fan-out (one Explore per module for large radius) | Deep-research-style; lowest urgency |

## Alternatives Considered

### Use the platform hard cap (depth 5) directly, no self-imposed budget
- **Pros:** Simplest; no config, no accounting. Maximum nesting available.
- **Cons:** Feedback loops (Review→Build, Check→Build) re-enter stages and can
  deepen the tree unpredictably; hitting the platform cap mid-pipeline produces an
  opaque failure rather than a graceful inline fallback. No knob for users who want
  to constrain concurrency or cost.
- **Why not chosen:** Temper's value is predictable, governed SDLC. An ungoverned
  cap trades that for occasional hard failures deep in a run.

### Keep delegation single-level; never let stages spawn
- **Pros:** Zero change; no depth risk at all.
- **Cons:** Leaves the documented parallel-review / Explore-prime patterns
  permanently degraded when composed, and abandons the `[PARALLEL]` task markers
  Plan already produces. The gap the platform just fixed stays unfixed in Temper.
- **Why not chosen:** Forfeits the entire point of the platform change.

### Per-stage hardcoded nesting rules instead of a passed budget
- **Pros:** No new config field; each stage knows its own depth statically.
- **Cons:** Static depth assumptions break under feedback-loop re-entry and future
  composition (e.g. `/temper:fix` invoked from within another flow). Fragile and
  non-composable.
- **Why not chosen:** A passed `depth_remaining` budget is composition-safe; static
  assumptions are not.

## Consequences

### Positive
- The composed `/temper` pipeline finally executes the depth-2 helpers its docs
  already describe — parity between standalone and composed commands.
- Build can parallelize independent tasks, redeeming the dormant `[PARALLEL]`
  annotation.
- Depth exhaustion degrades **deterministically to inline work** instead of failing.
- One small config block; everything default-on and graceful when absent.

### Negative
- Stage launch prompts grow slightly (the `depth_remaining` plumbing).
- Parallel children running concurrently raise peak token/cost usage within a
  stage — bounded by `parallel-width`.
- Merge-back logic for parallel Build tasks is new surface area (Phase 2) and must
  handle partial failure of one child without losing the others' work.

### Neutral
- Establishes a depth-budget convention that future capabilities must respect.
- `parallel-width` overlaps conceptually with the existing per-command "max 3
  parallel" prose; that prose should eventually be pointed at this config field.

## References

- `reference/orchestrator-patterns.md`: Stage Agent Launch Template, Context Efficiency Table
- `reference/review.md:143`, `:285`: parallel review subagents + max-3 rule
- `reference/plan.md:85`, `:714`: Explore auto-prime + `[PARALLEL]` task markers
- `reference/fix.md:71`: Explore subagent in RCA
- `reference/architecture-depth.md:46`: Explore-based module walk
- `.claude/temper.config`: proposed `agents` block
