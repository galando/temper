---
title: History (retired systems)
nav_exclude: true
---

# Retired systems

Docs for systems Temper has removed, kept for the record. Nothing here is loaded into a
session or wired to a gate — `reference/` is live methodology only; this directory is
where a retired-system explainer goes so a reader doesn't mistake it for current
behavior.

- [`tokenomics.md`](tokenomics.md) — the token-efficiency levers (cache/adaptive-depth/
  feedback tiers) retired in v7, when gate logic moved into `scripts/temper`.
- [`pricing.md`](pricing.md) — the price table that fed a `cost_usd` estimate in the
  removed `observability.json`; retired in v7 (an unbacked estimate isn't a fact).
- `changelog-before-9.7.md`: the changelog entries from v9.6.8 back to v5.0.1, moved out of
  `CHANGELOG.md` unchanged in 9.8.5 so that file keeps room under the size limit of the plugin directory.
- `build-9.8.5.md`: the summary of the build of 9.8.5: what changed, the numbers before and after, the plan item by
  item, and what is left for the owner.

See `CHANGELOG.md` for what replaced each.
