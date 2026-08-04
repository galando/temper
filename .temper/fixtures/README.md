# `.temper/fixtures/` — Reference Fixtures

This directory holds **reference fixtures**: redacted, non-live sample files that
document the shape of Temper's runtime state for contributors and tests.

## Files

| File | Documents |
|------|-----------|
| `learning.sample.json` | Shape of `.temper/learning.json` (adaptive-learning flywheel) |

## `learning.sample.json`

A redacted sample of the adaptive-learning state file. It is **not** live data —
all timestamps are placeholder zeros, identifiers are illustrative, and no
project-specific paths or secrets appear. It demonstrates:

- `detected_patterns[]` with one **promoted** rule (version-stamp drift, met the
  3+ accepts threshold) and one **active** rule (stale derived docs, approaching
  promotion)
- `suppressed_patterns[]` noise reduction
- `suggestion_queue[]` with a rule-template entry and a `config-update` entry
- `learning_curve` in the `insufficient_data` state (live dogfooding deferred)

### Why a fixture and not live data?

The adaptive-learning loop (G-6) populates `learning.json` only after real
`/temper:review` cycles run against real changes. This Phase 0 batch was built
as a doc/tooling change in a build subprocess where interactive review cycles
cannot run. **Live dogfooding is explicitly deferred to a follow-up session** —
G-6 is opportunistic and non-blocking per the spec (`intent.md` "G-6 is
opportunistic"). The fixture commits the *shape* so the loop's existence is
documented; live promotion is a downstream benefit.

### Regenerating from live data

After running real `/temper:review` cycles:

1. Copy `.temper/learning.json` here: `cp .temper/learning.json .temper/fixtures/learning.sample.json`
2. **Redact**: replace real timestamps with `2026-06-17T00:00:00Z`-style zeros,
   strip any project-specific file paths or identifiers, confirm no secrets.
3. Update this README's "Why a fixture" note to reflect that live data backs it.
4. Do **not** commit a real working `.temper/learning.json` — it is runtime state.
