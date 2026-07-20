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

In CI: `.github/workflows/eval-fixtures.yml`, nightly + on-demand (`workflow_dispatch`) +
a lightweight PR check (one fixture, on PRs touching `commands/`, `reference/`,
`agents/`, `skills/`, or `scripts/temper`). It checks for `secrets.ANTHROPIC_API_KEY`
first and skips cleanly if absent — it never fails CI for a fork or a PR without the
secret configured.

## Scope note: the autonomy tripwire

The v7 plan called for each fixture to also plant a change under `**/auth/**`, to prove
autonomy parks mechanically. That's deliberately **not** in these three fixtures:
`park-on-touch` is a pure `temper gate commit` property (matching changed file paths
against config globs) that needs zero model judgment to verify — spinning up a live
`claude -p` run against it would cost real tokens to re-prove something a shell script
already proves for free. It's covered instead in `scripts/tests/test-temper.sh`
("autonomous commit gate parks on a park-on-touch path"), which runs on every push.
If an end-to-end "the *agent* correctly triggers a park mid-run" fixture is wanted, that
needs a fourth fixture shaped differently from these three (a full `/temper` pipeline
run that touches `auth/`, not a single-stage `/temper:check`/`/temper:review` run) —
tracked here as a follow-up, not built in this pass.

## Baseline pinning — run for real (2026-07-20)

Ran live: `evals/run-all.sh` against a `v6.0.1` worktree (`TEMPER_PLUGIN_DIR` override
— see below) and against this branch. Both catch **3/3**:

| Fixture | v6.0.1 | v7 (this branch) |
|---|---|---|
| `password-reset` | CAUGHT (transcript) | CAUGHT (**evidence-ledger**) |
| `orders-api` | CAUGHT (transcript) | CAUGHT (**evidence-ledger**) |
| `notifications` | CAUGHT (transcript) | CAUGHT (**evidence-ledger**) |

"transcript" vs "evidence-ledger" is the source column `run-fixture.sh` prints — v6.0.1
has no `temper` CLI at all, so its catches can only ever be the transcript-grep
fallback (the agent's own narrated summary mentioned the defect). v7's catches are
confirmed via the **evidence ledger** — meaning `temper gate {stage}` mechanically
FAILed with the defect named in its own detail line, e.g.:

```
temper gate check -> FAIL
  [x] scenarios traced to tests — 1/2 covered — missing: Rate limiting on reset requests
```

That's a strictly stronger guarantee than v6.0.1 ever had, not just parity.

**A real bug this baseline run found and fixed:** the first live pass on `orders-api`
and `notifications` caught the defect only via transcript-fallback *on v7 too* — the
standalone `/temper:review`/`/temper:check` commands (as opposed to the unified
`/temper`'s `agents/*.md` path) were never wired to call `temper evidence add` or
`temper gate`, so a real run left `.temper/evidence/` empty. `commands/{plan,build,
review,check,eval}.md` now each carry a "Deterministic Gate" step pointing back at the
matching `agents/*.md` steps, plus explicit `--spec-path` (state isn't necessarily
initialized in standalone use, so `temper state get spec_path` can be empty). Re-run
after the fix: `orders-api` now confirms `evidence-ledger`. This is exactly the kind of
bug a synthetic CLI test can't find — only running the real thing did.

**To reproduce:**
```bash
git worktree add /tmp/temper-v601 <v6.0.1-commit-or-tag>
TEMPER_PLUGIN_DIR=/tmp/temper-v601 bash evals/run-fixture.sh password-reset
bash evals/run-fixture.sh password-reset   # v7, no override needed
```

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
