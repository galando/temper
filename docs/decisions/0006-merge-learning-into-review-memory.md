# ADR-0006: Merge adaptive learning into review memory

**Status:** Accepted
**Date:** 2026-08-24
**Supersedes:** [ADR-0001](0001-separate-learning-state-file.md)

## Context

Temper had accumulated two overlapping finding-memory systems:

- **`review-memory.json`** — per-pattern accept/dismiss counts, promotion of a
  repeatedly-accepted pattern to a pack rule, per-context auto-suppression of a
  repeatedly-dismissed one.
- **`learning.json`** (ADR-0001) plus `packs/adaptive-learning/rules.md` and
  `reference/learning.md` — a "passive intelligence layer" that clustered findings,
  tracked acceptance, and ran the *same* promotion (3+ @70% → WARN, 5+ @80% → BLOCK)
  and suppression (3+ / 5+ dismissals) thresholds, into a second store with a
  `suggestion_queue`, a `learning_curve`, and a `.temper/learning/suggestions/`
  directory of rule templates.

Two systems remembered the same thing. Every review updated both; `/temper:status`
rendered both; a contributor reading the code had to hold both models. ADR-0001's
justification — a hard "zero breaking changes" constraint on `review-memory.json` —
was specific to a v4.x that no longer exists (v7 and v8 were deliberate breaking
releases built around removing exactly this kind of duplicated machinery).

## Decision

One finding memory: `review-memory.json`. Fold adaptive learning's promotion and
suppression thresholds into `reference/review.md` → "Metrics + Memory" (they were
already the thresholds review-memory used). Delete the parallel store and everything
that existed only to serve it:

- `reference/learning.md` (the algorithm — now stated inline in review.md)
- `packs/adaptive-learning/` (promoted rules go into the *active* pack's `rules.md`)
- `.temper/learning.json`, `.temper/learning/suggestions/`, the `suggestion_queue`
- the `learning_curve` trend (the dashboard's coverage and issues/review arrows
  already show direction)

Config-update suggestions (from Check) are shown once at the Check gate and their
rejections recorded in `review-memory.json` under a `config:` key — no separate queue.

## Alternatives considered

### Keep both, document the boundary better
- **Pros:** no migration; each file's schema evolves independently.
- **Cons:** the boundary was the problem, not the documentation of it — two stores of
  the same accept/dismiss data drift, and the second one earned its keep only through
  a `learning_curve` and a re-offer queue that a single prompt at the gate replaces.
- **Why not chosen:** the maintenance cost (two write paths, two dashboard panels, two
  mental models) is paid every review for a derived view that adds no capability the
  surviving store lacks.

## Consequences

- **Positive:** one write path, one dashboard panel, one file a contributor learns;
  a whole pack and reference doc deleted; promotion still works, unchanged in behavior.
- **Neutral:** a stale `learning.json` in an existing project is simply ignored (no
  reader remains) — it can be deleted at leisure; nothing migrates it.
- **Negative:** the `learning_curve` trend line is gone. It was informational only and
  not wired to any gate; the coverage/issues arrows cover the same intent.

## References

- [ADR-0001](0001-separate-learning-state-file.md) (superseded) — why the split was originally made
- `reference/review.md` → "Metrics + Memory" — the merged promote/suppress logic
