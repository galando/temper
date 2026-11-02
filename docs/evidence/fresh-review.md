# Evidence: the fresh review of the plan (9.7.6)

Two questions, two experiments. Does the plan gate now stop plans it used to let through? And does what the fresh reviewer
finds matter for the code that gets built?

## 1. The same plan states, through the 9.7.5 CLI and the 9.7.6 CLI

`scripts/e2e/ab-plan-gate.sh OLD_CLI NEW_CLI` writes a medium plan that passes every 9.7.5 plan gate row, records the rows a
fresh reviewer would record, and runs `temper gate plan` with each CLI. Deterministic: the same input gives the same table.

| Plan state | 9.7.5 | 9.7.6 |
|---|---|---|
| a fresh reader found a task that leaves the expected value to the builder | PASS | FAIL |
| the reviewer stopped after two of three lenses | PASS | FAIL |
| tasks.md changed after the review | PASS | FAIL |
| the author contests a finding with no citation | refused (no such command) | refused |
| a clean review of a good plan (control) | PASS | PASS |

What it shows: in 9.7.5 nothing between Plan and Build could stop a task that leaves a decision open. In 9.7.6 each of these
reaches the person as a failed gate row that names it, and a good plan still passes.

## 2. A live run: what the reviewer finds, and what the builder does with it

The fixture is a medium change to a small Python service: limit failed logins (after 3 failures for one username within 10
minutes, refuse with status 423 and a Retry-After header; a success clears the count; one process, memory only). Two versions
of the same plan:

- **Seeded**, with five planted defects: D1 a task Case with no expected value ("rejects too many failed attempts"); D2 a file
  the task must change (`src/app.py`, where middleware is registered) missing from its `**File:**` line; D3 a new
  `src/util/clock.py` when `src/timeutil.py` already has `now()`; D4 a `RedisStore` and a store interface the intent rules
  out; D5 a term ("the bucket policy") used and never defined.
- **Fixed**, the same plan with the five defects corrected.

### The reviewer (`agents/plan-review.md`, Sonnet, no context)

| Plan | high | medium | low | Planted defects found |
|---|---|---|---|---|
| Seeded | 5 | 4 | 0 | 5 of 5 (D1, D2, D3, D4 as high; D5 as medium) |
| Fixed | 0 | 2 | 2 | (none planted) |

On the seeded plan it also found a flaw nobody planted: middleware that runs before the route cannot see whether the login
succeeded, so as written it could never count failures. On the fixed plan it raised no blocker, so the gate passes; its
two medium findings were real gaps (how `handle` captures the route's status, and calling `now()` through the module so a
test's patch applies).

### The builder (Haiku, given only the task block, as a Build task agent is)

Two builders got the seeded Task 2, two got the fixed Task 1. A hidden acceptance test written from intent.md alone drives
the app through its entry point, `src.app.handle`.

| Builder | Its own tests | Limit, window, refusal it chose | AC-01 (423 after 3 failures) | Wired into POST /login |
|---|---|---|---|---|
| seeded 1 | pass | 5, 900 s, 429 | FAIL (401) | no |
| seeded 2 | pass | 5, 900 s, 429 | FAIL (401) | no |
| fixed 1 | pass | 3, 600 s, 423 + Retry-After | PASS (423, Retry-After 570) | yes |
| fixed 2 | pass | 3, 600 s, 423 + Retry-After | PASS (423, Retry-After 570) | yes |

Both seeded builders passed their own tests and would have passed their task gate: the defect is invisible to TDD, because
the test encodes the same guess as the code. Both said so in their reports: `src/app.py` was outside their `**File:**` line,
so they left the feature unwired. (The seeded builds pass AC-02 only because nothing is wired, so every attempt is a plain
401.)

## 3. What it costs

**The model.** `TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh cost 3` runs the same headless session three times without
the review (`plan.fresh-review: off`) and three times with it (`always`): a scratch Python project with an accepted medium
intent, from the Plan agent to the plan question. Wall time is what the shell measured; the Plan agent's and the reviewer's
times come from the run's usage rows; the cost is Claude Code's own figure for the session at API prices.

| Mode | Runs | Wall time (mean) | Plan agent (mean) | Reviewer (mean) | Cost (mean, API prices) |
|---|---|---|---|---|---|
| off | 3 | 170 s | 145 s | none | $1.01 |
| always | 3 | 207 s | 144 s | 26 s | $1.18 |

The review added about 26 seconds of reviewer time, about 37 seconds of wall time (it also adds a turn of the orchestrator),
and about $0.17 per plan, roughly 17% of the Plan stage. The runs vary (one session with the review cost $1.40, another $1.04),
so read these as an order of size from three runs each, not a rate. A risk H plan runs two reviewers. On a subscription the
cost is usage, not a bill. In the earlier evidence run, one reviewer used about 61,000 tokens and 30 to 34 seconds.

**The CLI.** The median of 20 calls on the same medium plan, two rounds each, 9.7.5 against 9.7.6: `temper gate plan` 900 ms
against 970 ms (the fresh review rows add about 70 ms), `temper next --json` about 130 ms in both.

## What this does not show

- Two builders per variant and one reviewer run per plan: enough to show the mechanism, not a rate. A reviewer can miss a
  defect or raise a false one; the gate counts what it records, and the person decides each finding.
- The fixture was written for this test. Real plans differ; the deterministic table above is the part that holds for every
  plan.
- The fresh review runs when the person asks for it at the plan question (`plan.fresh-review: ask`, the default); `auto` runs
  it by itself for medium and complex plans, and `off` never.
