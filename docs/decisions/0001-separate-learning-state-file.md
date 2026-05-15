# ADR-0001: Separate Learning State File

**Status:** Proposed
**Date:** 2026-05-14
**Supersedes:** (none)

## Context

Temper already has two persistent state files: `review-memory.json` (tracks per-pattern accept/dismiss counts) and `metrics.json` (accumulates review statistics). The new Adaptive Learning feature needs to track detected patterns, suggestion queues, suppression rules, context-specific breakdowns, and learning curve data.

The question is whether to extend `review-memory.json` with these new fields, or create a new `learning.json` file.

## Decision

Use a separate `.temper/learning.json` file for all adaptive learning state, reading from (but not modifying) `review-memory.json` and `metrics.json`.

This keeps learning.json as the single source of truth for the learning intelligence layer, while review-memory.json remains focused on its existing role: per-pattern accept/dismiss tracking.

## Alternatives Considered

### Extend review-memory.json
- **Pros:** Single file to manage, no new file, existing consumers already read it
- **Cons:** Schema migration risk on an existing file that all review flows depend on. Mixing two concerns (raw pattern tracking vs derived intelligence). If learning.json schema changes, review-memory.json should not be affected.
- **Why not chosen:** The constraint "Zero Breaking Changes" in intent.md means review-memory.json schema must not break. Adding learning fields increases the surface area for accidental breakage.

### Store learning state in metrics.json
- **Pros:** Metrics already accumulates statistics, natural home for learning curve data
- **Cons:** metrics.json is a counter/aggregation file, not a pattern analysis file. Learning state includes complex nested objects (detected patterns with context breakdowns, suggestion queues with rule templates). These don't fit the flat counter structure of metrics.json.
- **Why not chosen:** Semantic mismatch. metrics.json is "how many X happened"; learning.json is "what patterns emerged from X happening."

## Consequences

### Positive
- Zero risk to existing review-memory.json consumers
- Clean separation: review-memory = raw data, learning = derived intelligence
- learning.json can be deleted without affecting any existing functionality
- Schema can evolve independently

### Negative
- One more file in `.temper/` to manage
- review Step 8.5 needs to read both review-memory.json and learning.json
- Duplicate data (accept/dismiss counts appear in both files) — but learning.json derives from review-memory.json, so it's computed, not duplicated

### Neutral
- First sub-directory in `.temper/` (`.temper/learning/suggestions/`) — sets a precedent for directory-based state organization

## References

- intent.md: constraint "Zero Breaking Changes"
- plan.md: learning.json schema definition
- design.md: Component inventory and data flow
