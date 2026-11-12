# Build task agents: Haiku against Sonnet (2026-11-12)

The question: should Temper's Build task agents run on Haiku 5.5 or on Sonnet 5.5? The model guide lists Haiku for
"the lowest latency and price" and for "subagent tasks", and says "Having a good evaluation set is the most important step".
This is that evaluation on Temper's own benchmark.

## Setup

- **Code:** Temper 9.8.4 (branch `claude/magical-rubin-ux5vjn`), loaded as a plugin by `bench/run.mjs` through the Agent SDK.
- **Arms:** the same `temper` arm twice. `run.mjs --task-model haiku | sonnet` commits a `.claude/temper.config` whose
  `build.grouped.task-model` is that model into the base, and an explicit task model wins over every default. Nothing
  else differs: Plan, Design and the root cause agent on Opus, the other agents on Sonnet, the same simulated person.
- **Tasks:** the three large feature tasks that are not vague: `partial-payments` and `subscriptions` (Python) and
  `ts-seat-holds` (TypeScript). Bug tasks go through `/temper:fix`, which runs no task agents; the vague ones add a
  simulated product owner, which is noise here. Plan rated 14 of the 18 runs complex and every run had Design, so most
  plans were of the kind 9.8.4 now builds on Sonnet by default.
- **Runs:** 3 per task per arm, 18 in all, the two arms of a task alternating rep by rep, three tasks in parallel.
- **Graded** by `grade.py` on hidden tests no arm sees, the task's original suite, and the files changed outside the
  expected paths. Cost is the SDK's own; the task agents' cost is priced from their own logs with `loop.py`'s prices
  (Haiku $0.10/$0.50, Sonnet $2/$10 per million tokens in and out), which matched the SDK to the cent.
- **Two runs repeated.** The first Haiku runs of `partial-payments` and `subscriptions` started before coverage.py was
  installed in the container, so Check failed on a missing measurement and looped for reasons that have nothing to do
  with the model (that loop is fixed in 9.8.4: commit d65802c). Both were run again with coverage.py; the tables use the
  repeated runs. The first ones are kept apart and not counted.

## Every run

| task | arm | rep | hidden | suite | outside | cost $ | task agents $ | wall s | Build task s | tasks | task launches | task runs | escalated | stopped: file outside the task | fix passes | reviews | questions | coverage missing |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| partial-payments | haiku | 1 | 26/26 | ok | 0 | 2.72 | 0.056 | 883 | 261 | 6 | 1 | 6 | 0 | 0 | 1 | 2 | 14 |  |
| partial-payments | haiku | 2 | 26/26 | ok | 0 | 1.99 | 0.055 | 679 | 191 | 6 | 1 | 6 | 0 | 0 | 0 | 1 | 10 |  |
| partial-payments | haiku | 3 | 26/26 | ok | 0 | 3.19 | 0.199 | 1109 | 484 | 6 | 7 | 17 | 2 | 3 | 0 | 1 | 16 |  |
| partial-payments | sonnet | 1 | 26/26 | ok | 0 | 2.42 | 0.325 | 657 | 129 | 6 | 2 | 6 | 0 | 0 | 1 | 1 | 11 |  |
| partial-payments | sonnet | 2 | 26/26 | ok | 0 | 2.98 | 0.326 | 831 | 133 | 5 | 1 | 5 | 0 | 0 | 3 | 2 | 14 |  |
| partial-payments | sonnet | 3 | 26/26 | ok | 0 | 2.55 | 0.258 | 661 | 103 | 5 | 1 | 5 | 0 | 0 | 1 | 2 | 14 |  |
| subscriptions | haiku | 1 | 25/25 | ok | 0 | 3.60 | 0.062 | 1283 | 322 | 6 | 4 | 6 | 0 | 0 | 3 | 2 | 18 |  |
| subscriptions | haiku | 2 | 25/25 | ok | 0 | 2.75 | 0.075 | 1062 | 296 | 6 | 3 | 6 | 0 | 0 | 1 | 1 | 13 |  |
| subscriptions | haiku | 3 | 25/25 | ok | 0 | 3.48 | 0.106 | 1196 | 310 | 6 | 3 | 6 | 0 | 0 | 3 | 2 | 14 |  |
| subscriptions | sonnet | 1 | 25/25 | ok | 0 | 3.32 | 0.444 | 923 | 177 | 7 | 4 | 7 | 0 | 0 | 1 | 1 | 13 |  |
| subscriptions | sonnet | 2 | 25/25 | ok | 0 | 5.43 | 0.437 | 1534 | 183 | 7 | 4 | 7 | 0 | 0 | 6 | 3 | 26 |  |
| subscriptions | sonnet | 3 | 25/25 | ok | 0 | 2.96 | 0.519 | 874 | 211 | 6 | 4 | 6 | 0 | 0 | 1 | 1 | 12 |  |
| ts-seat-holds | haiku | 1 | 11/11 | ok | 0 | 1.85 | 0.036 | 619 | 180 | 5 | 1 | 5 | 0 | 0 | 1 | 1 | 9 |  |
| ts-seat-holds | haiku | 2 | 11/11 | ok | 0 | 2.09 | 0.030 | 713 | 173 | 5 | 1 | 5 | 0 | 0 | 2 | 2 | 14 |  |
| ts-seat-holds | haiku | 3 | 11/11 | ok | 0 | 1.58 | 0.022 | 469 | 110 | 3 | 1 | 3 | 0 | 0 | 1 | 1 | 8 |  |
| ts-seat-holds | sonnet | 1 | 11/11 | ok | 0 | 1.74 | 0.157 | 466 | 66 | 3 | 1 | 3 | 0 | 0 | 1 | 1 | 9 |  |
| ts-seat-holds | sonnet | 2 | 11/11 | ok | 0 | 2.30 | 0.297 | 674 | 124 | 4 | 1 | 4 | 0 | 0 | 1 | 1 | 11 |  |
| ts-seat-holds | sonnet | 3 | 11/11 | ok | 0 | 1.73 | 0.170 | 488 | 82 | 4 | 1 | 4 | 0 | 0 | 1 | 1 | 9 |  |

"task runs" counts each task an agent reported as done or stopped (`TASK N: done | stopped`), retries included; a chain the
agent stopped part way does not count the tasks it never reached. "escalated" counts task agents launched on Sonnet in the
Haiku arm (the third attempt of a task that failed twice on Haiku). "stopped: file outside the task" counts attempts that
stopped because the task's test needs a change in a file the task does not declare. "fix passes" are Build fix agents
after a step back.

## Per task (means)

| task | arm | runs | all hidden | hidden pass rate | cost $ | task agents $ | wall s | Build task s | task runs per task | fix passes | reviews |
|---|---|---|---|---|---|---|---|---|---|---|---|
| partial-payments | haiku | 3 | 3/3 | 100% | 2.63 | 0.104 | 890 | 312 | 1.61 | 0.3 | 1.3 |
| partial-payments | sonnet | 3 | 3/3 | 100% | 2.65 | 0.303 | 716 | 122 | 1.00 | 1.7 | 1.7 |
| subscriptions | haiku | 3 | 3/3 | 100% | 3.28 | 0.081 | 1180 | 309 | 1.00 | 2.3 | 1.7 |
| subscriptions | sonnet | 3 | 3/3 | 100% | 3.90 | 0.467 | 1110 | 190 | 1.00 | 2.7 | 1.7 |
| ts-seat-holds | haiku | 3 | 3/3 | 100% | 1.84 | 0.029 | 600 | 154 | 1.00 | 1.3 | 1.3 |
| ts-seat-holds | sonnet | 3 | 3/3 | 100% | 1.92 | 0.208 | 543 | 91 | 1.00 | 1.0 | 1.0 |

## In all (9 runs an arm)

| | Haiku | Sonnet |
|---|---|---|
| runs that pass every hidden test | 9 of 9 | 9 of 9 |
| original suite broken, files outside the expected paths | none | none |
| cost of a run, mean | $2.58 | $2.83 |
| cost of the task agents in a run, mean | $0.07 | $0.33 |
| wall time of a run, mean | 890 s | 790 s |
| time of the task agents in a run, mean | 259 s | 134 s |
| extra task runs in 9 runs | 11, all in one run, from one plan defect | 0 |
| extra task runs the model caused | 0 | 0 |
| escalations to Sonnet in 9 runs | 2, the same plan defect | 0 |
| Build fix passes after a step back, in 9 runs | 12 | 16 |
| Review rounds in 9 runs | 13 | 13 |

## What it shows

1. **No difference in what was built.** Both arms passed every hidden test in every run, broke no original test and
   changed no file outside the expected paths. Haiku code did not need more fixing later: fix passes and Review rounds are
   no higher in the Haiku arm.
2. **Haiku is cheaper, by little.** The task agents cost about a fifth on Haiku ($0.07 against $0.33), but they are 3% to
   12% of a run; Opus planning dominates. A run was about $0.25 cheaper on Haiku (9%), well within the spread between
   runs of the same arm ($1.99 to $3.19 for one task).
3. **Haiku is slower.** The task agents took about twice as long (259 s against 134 s; 230 s without the run below) and a
   run about 100 s longer (13%).
4. **The retries were a plan defect, not Haiku.** All 11 extra task runs and both escalations are one run
   (`partial-payments`, Haiku, run 3) and one task: Task 6's test needed `payment_id` in an audit event written in
   `ledger/payments.py`, a file Task 3 declares and Task 6 does not. Every attempt stopped and said so, the two Haiku
   attempts and the two Sonnet ones alike; then the run looped back to Plan, the chain was rebuilt, and Task 6's tests
   passed. No model could have built that task as planned. (An earlier count said 11 against 1: it counted every task
   of a chain the agent stopped part way. The Sonnet arm has no retry.)
5. **The 9.8.4 rule (Sonnet for complex or risk H plans) is not a quality fix on this evidence.** Most of these plans
   were complex, and Haiku built them as well as Sonnet. The rule buys speed and fewer retries for about $0.25 a run.

## Limits

Three tasks, three runs each: enough to see a large quality gap, not a small one. The tasks are well specified and have
5 to 7 tasks each; the run that motivated 9.8.4 had 12 tasks in one group and about 30 files. The person is simulated
and always takes the recommended option. No vague task was run.

## Decision

Keep the 9.8.4 default: Build task agents run on Haiku for simple and medium plans, and on Sonnet for complex or risk H
plans, unless `build.grouped.task-model` names a model. The rule costs about $0.25 on those runs and halves the time of
the task agents; the plans it covers can be larger than any measured here.
To revisit with more data: the vague tasks and a plan with 10 or more tasks, 3 runs per arm (`bench/compare_models.py`).
