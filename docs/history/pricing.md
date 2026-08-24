---
description: "Retired in v7 — cost_usd estimation was part of the observability.json system this file supported"
nav_exclude: true
---

# Pricing Table (retired, v7.0.0)

This table fed a `cost_usd` estimate in `observability.json` that was, at best, a
plausible guess derived from a price table — never a measured, mechanically-verified
number. v7's whole thesis is that a number without mechanical backing shouldn't be
presented as fact, so the estimate is gone along with the table that fed it.

Temper doesn't track spend for you in v7. What it tracks instead — `.temper/evidence/`
and `.temper/gates.json` — is exactly what it can actually prove: which command ran,
what it returned, and whether a gate's requirement was met. See
`reference/orchestrator-patterns.md` → "Context Accumulation Patterns".
