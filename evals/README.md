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

## How a "catch" is verified — three tiers, strongest wins

`run-fixture.sh` doesn't just grep for keywords and call it a day (an earlier version
of this script effectively did, and that was a real, fixed bug — see "A bug in the
harness itself" below). It checks, strongest first:

1. **`gate-blocking-evidence`** — a recorded evidence entry matches **both** the
   fixture's `anchor_keywords` and its `signal_keywords` (not either alone — see
   "Anchor + signal keyword matching" below) AND carries the specific property that
   makes the real gate FAIL: `severity == 'critical'` for `review` (matching
   `gate_review()`'s actual check), or a `--scenario` row with a nonzero `exit_code`
   for `check` (matching `gate_check()`'s actual check). This is the only tier that
   proves "`temper gate` would have mechanically blocked a commit" — the actual claim
   v7 makes.
2. **`evidence-non-blocking`** — text matches both keyword sets, but not in a way
   that would fail the gate (e.g. recorded at a non-blocking severity).
3. **`transcript-fallback`** — only the raw transcript mentions it; no evidence was
   ever recorded, so `temper gate` never saw it at all. This is the *only* tier
   reachable for v6.0.1, which has no `temper` CLI.

**Pass bar is strict by default: only tier 1 counts.** `TEMPER_EVAL_ACCEPT_ANY_TIER=1`
relaxes it to any tier — needed to compare against v6.0.1 (tier 1 is structurally
unreachable there), never for judging v7 itself. Accepting a weaker tier there would
let a real regression — the agent still narrates the bug but stops recording it as
blocking — pass CI silently.

### Anchor + signal keyword matching (2026-07-20)

Every tier matches text with two keyword sets from `expect.json`, both required —
never a single flat `OR`ed list:

- **`anchor_keywords`** — specific enough to identify *this* defect uniquely: an exact
  scenario name (`"Rate limiting on reset requests"`), a code symbol (`"find_order"`,
  `"\\.find\\("`), a component name (`"NotificationBell"`).
- **`signal_keywords`** — generic descriptive terms (`"missing"`, `"unused"`,
  `"AttributeError"`) that mean nothing on their own — they match all kinds of
  unrelated text — but become meaningful once co-occurring with an anchor.

A claim (or, for tier 3, the transcript) must match **both** patterns, not either one.
Before this, a single flat `catch_keywords` list let a generic word alone (e.g.
`"missing"` matching some unrelated "nothing missing here" sentence) count as a catch
— a false-positive risk concentrated in tiers 2/3, since tier 1 already had the
gate-property check as a second filter. Requiring anchor+signal co-occurrence closes
that gap at every tier, including tier 1's text-matching component.

## A bug in the harness itself (2026-07-20)

Asked directly whether this eval suite is actually correct, not just useful. Re-read
`run-fixture.sh` cold and found: the original "evidence-ledger" check only tested
whether *any* evidence entry's free-text `claim` matched a keyword regex — it never
looked at `severity` or `exit_code`/`scenario`, and never ran `temper gate <stage>` or
read `.temper/gates.json`. So "confirmed via evidence-ledger" was true only in the
sense that matching text existed somewhere, not that the gate would have blocked
anything — that distinction had only ever been checked by hand during debugging, never
by the script CI actually runs. Fixed into the three-tier system above.

**Verified live, both directions, after the fix:**
- v6.0.1's `orders-api`, run **without** the override, correctly reports **MISSED** —
  proof the strict bar actually discriminates rather than rubber-stamping everything.
  This is also the first real negative-path confirmation this harness has ever
  produced; every run before this had only ever shown CAUGHT.
- v6.0.1's `password-reset`, run **with** `TEMPER_EVAL_ACCEPT_ANY_TIER=1`, correctly
  passes.

## Baseline pinning — run for real (2026-07-20)

`evals/run-all.sh` against a `v6.0.1` worktree (relaxed bar — see above) and against
this branch (strict bar, the default). **Both catch 3/3**:

| Fixture | v6.0.1 (relaxed bar) | v7 — strict bar, this branch |
|---|---|---|
| `password-reset` | CAUGHT (`transcript-fallback`) | CAUGHT (**`gate-blocking-evidence`**) |
| `orders-api` | CAUGHT (`transcript-fallback`) | CAUGHT (**`gate-blocking-evidence`**) |
| `notifications` | CAUGHT (`transcript-fallback`) | CAUGHT (**`gate-blocking-evidence`**) |

v7's catches are confirmed at the strongest tier — `temper gate {stage}` mechanically
FAILed with the defect named in its own detail line, e.g.:

```
temper gate check -> FAIL
  [x] scenarios traced to tests — 1/2 covered — missing: Rate limiting on reset requests
```

That's a strictly stronger guarantee than v6.0.1 ever had, not just parity.

**A real bug the first pass of this baseline run found and fixed** (before the harness
fix above): the standalone `/temper:review`/`/temper:check` commands (as opposed to
the unified `/temper`'s `agents/*.md` path) were never wired to call `temper evidence
add` or `temper gate` at all, so a real run left `.temper/evidence/` empty.
`commands/{plan,build,review,check,eval}.md` now each carry a "Deterministic Gate"
step pointing back at the matching `agents/*.md` steps, plus explicit `--spec-path`
(state isn't necessarily initialized in standalone use). This is exactly the kind of
bug a synthetic CLI test can't find — only running the real thing did, twice over.

**To reproduce:**
```bash
git worktree add /tmp/temper-v601 <v6.0.1-commit-or-tag>
TEMPER_PLUGIN_DIR=/tmp/temper-v601 TEMPER_EVAL_ACCEPT_ANY_TIER=1 \
  bash evals/run-fixture.sh password-reset
bash evals/run-fixture.sh password-reset   # v7, strict bar, no override needed
```

## Known limitations (still open, not hidden)

- **Only `review` and `check` are exercised by a live fixture.** `plan`'s blast-radius
  requirement, `build`'s RED/GREEN, `eval`'s threshold, and `commit`'s aggregation are
  only tested by `scripts/tests/test-temper.sh` — which tests the CLI's logic in
  isolation, not whether a real model actually calls it correctly in those stages.
  That's the same class of gap that hid the standalone-command bug above; it could be
  hiding another one in an untested stage right now.

**Fixed (2026-07-20):** tiers 2 and 3 used to match on a single flat, `OR`ed keyword
list, so a generic word alone (`"missing"`, `"unused"`) could false-positive on
unrelated text. Fixed by requiring `anchor_keywords` AND `signal_keywords` to both
match — see "Anchor + signal keyword matching" above. Residual risk: the anchor and
signal only have to appear *somewhere* in the same claim/transcript, not adjacent or
about the same clause — still weaker than tier 1's gate-property check, which is why
tiers 2/3 stay non-authoritative for CI regardless.

## Adding a fixture

1. `evals/fixtures/<name>/` — a minimal real project with one seeded defect.
2. `.temper/specs/<name>/intent.md` — success criteria + scenarios that make the defect
   *visible* to Temper's methodology (not just "the code is wrong" — the spec has to
   describe the behavior the defect violates).
3. `SEEDED_DEFECT.md` — what's wrong, why, which gate should catch it, in plain English.
4. `expect.json` — `{"stage": "...", "command": "/temper:...", "anchor_keywords": [...],
   "signal_keywords": [...]}`. Both are lists of regexes, case-insensitive, ORed
   together *within* each list — but a catch requires at least one `anchor_keywords`
   match AND at least one `signal_keywords` match (see "Anchor + signal keyword
   matching" above). Put exact scenario names/symbols/component names in
   `anchor_keywords`; put generic descriptive terms in `signal_keywords`.
5. Confirm `bash evals/run-fixture.sh <name>` actually fails today (MISSED) if you
   revert the fix, and passes (CAUGHT) against the real pipeline — a fixture that
   passes unconditionally isn't testing anything.
