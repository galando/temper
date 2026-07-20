# Temper self-evals — seeded-defect fixtures

Move 3 of [`docs/plans/v7-deterministic-spine.md`](../docs/plans/v7-deterministic-spine.md):
Temper ships an eval stage for *your* features (`/temper:eval`) but, before v7, had no
behavioral regression harness for its own prompts — `scripts/quality-check.sh` and
friends check structure, never behavior. Every prompt edit was a blind change to a
multi-thousand-line program. This is the fix: three fixture projects, each with one
seeded, known defect, run through the real pipeline in CI, asserting against the
evidence ledger (`.temper/evidence/`, written by `scripts/temper`) — not by grepping a
transcript for hopeful phrases.

## Fixtures

| Fixture | Stack | Seeded defect | Stage that should catch it |
|---|---|---|---|
| `password-reset` | node-express | No test covers the "rate limit resets" scenario, even though it's written in `intent.md` | `/temper:check` — scenario-coverage verification |
| `orders-api` | fastapi | `orders.find(...)` — Python `list` has no `.find()`, that's a JS `Array` method | `/temper:review` — defect detection |
| `notifications` | react-ts | `NotificationBell` is fully implemented but never imported/rendered in `App.tsx` | `/temper:review` — intent/consumer validation |

Each fixture directory has `SEEDED_DEFECT.md` (human-readable: what's wrong, why, which
gate should catch it) and `expect.json` (machine-readable: which stage/command to run,
and the keywords that count as "caught" — matched against the evidence ledger first,
the raw transcript only as a fallback). `expect.json` and `SEEDED_DEFECT.md` are
stripped from the copy the agent actually sees (`run-fixture.sh` deletes them from its
throwaway working copy) — the agent has to find the defect itself, not read the answer key.

## Running it

```bash
# One fixture:
bash evals/run-fixture.sh password-reset

# All fixtures, with the aggregate catch rate:
bash evals/run-all.sh
```

Requires the `claude` CLI on `PATH`, authenticated (`ANTHROPIC_API_KEY` or equivalent).
Runs with `--dangerously-skip-permissions` against a throwaway `mktemp -d` copy of the
fixture only — never point it at a real project.

In CI: `.github/workflows/eval-fixtures.yml`, nightly + on-demand (`workflow_dispatch`).
It checks for `secrets.ANTHROPIC_API_KEY` first and skips cleanly if absent — it never
fails CI for a fork or a PR without the secret configured.

## Baseline pinning (how this guards quality during a prompt diet)

The design intent, per the v7 plan: before any prompt-diet deletion lands (Move 2), run
this suite against the pre-diet version and record the catch rate as the baseline; the
diet is only allowed to land once the suite matches that baseline against the new
prompts. That baseline run is a **deliberate follow-up, not done as part of this PR** —
authoring the harness and cutting the prompts happened in the same pass here, so
"same quality" for this specific change is asserted based on the reasoning in the
CHANGELOG and PR description (which lines were mechanism vs. judgment), not yet backed
by a recorded pre/post fixture run. Treat the harness in this state as: *ready to run,
not yet run.* Running `evals/run-all.sh` against `v6.0.1` and against this branch, and
recording both catch rates, is the next honest step — do that before trusting this
badge in the README.

## Adding a fixture

1. `evals/fixtures/<name>/` — a minimal real project with one seeded defect.
2. `.temper/specs/<name>/intent.md` — success criteria + scenarios that make the defect
   *visible* to Temper's methodology (not just "the code is wrong" — the spec has to
   describe the behavior the defect violates).
3. `SEEDED_DEFECT.md` — what's wrong, why, which gate should catch it, in plain English.
4. `expect.json` — `{"stage": "...", "command": "/temper:...", "catch_keywords": [...]}`.
   Keywords are regexes, ORed together, case-insensitive.
5. Confirm `bash evals/run-fixture.sh <name>` actually fails today (MISSED) if you
   revert the fix, and passes (CAUGHT) against the real pipeline — a fixture that
   passes unconditionally isn't testing anything.
