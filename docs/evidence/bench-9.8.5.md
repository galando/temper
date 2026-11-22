# Bench of 9.8.5: cost, time and correctness against plain Claude Code

Three rounds of the bench of `bench/`, run on 2026-11-21 with the model access of the build session, one run at a
time, three runs a task. The six tasks are those of `docs/plans/one-go/done.md`, note 1: two bugs (`cent-mismatch`,
`tenant-leak`), two clear features (`partial-payments`, `ts-seat-holds`) and two vague ones (`vague-refunds`,
`vague-late-fees`). Every run is graded by tests no arm ever sees. The scorecard is
`docs/evidence/scorecard-9.8.5.json`; each graded run's `run.json` and `grade.json` are under
`docs/evidence/bench-9.8.5/` (folder `a`, `b` or `c`, one folder a run).

## The rounds

- **(a), before:** the code this release started from (`10e965a`), as the arm `temper`, with plain Claude Code beside
  it (the arm `vanilla`). 36 runs. The harness is this release's `bench/` folder; only the plugin differs.
- **(b), after:** this release (`a47cdcb`) with its default config: the planner on Opus. 18 runs.
- **(c), the model test:** this release with the planner on Sonnet below risk H (`models.plan: sonnet` and
  `models.high.plan: opus`, which the CLI resolves as `plan=sonnet (config)`). 18 runs.

Rounds (b) and (c) ran on `a47cdcb`, the code after the first round of the adversarial review of this release. The
second round's fixes came after it; they refuse calls on paths a plain run does not take (a typed skip, a cleared
ledger, a moved branch) and change no step of a run that goes its plain way.

## The scorecard

| Block | Runs | Cost, mean (median, min to max) | Seconds, mean (median) | Dialogs, median | Hidden tests | Rules met |
|---|---|---|---|---|---|---|
| (a) plain Claude Code | 18 | 0.39 (0.40, 0.22 to 0.56) | 71 (74) | 0 | 0.948 | 0.758 |
| (a) the base | 18 | 2.44 (2.72, 0.41 to 4.73) | 545 (596) | 13 | 0.906 | 1.0 |
| (b) this release, planner on Opus | 18 | 1.30 (1.50, 0.37 to 2.30) | 358 (434) | 5 | 1.0 | 1.0 |
| (c) this release, planner on Sonnet below risk H | 18 | 0.82 (0.84, 0.39 to 1.41) | 262 (287) | 5 | 0.901 | 0.970 |

Hidden tests is the share of hidden tests passed; rules met is the share of the vague tasks' rules a run kept. Against
the base, this release halves the cost (1.30 against 2.44 dollars a run), takes a third less time (358 against 545
seconds) and asks fewer dialogs (a median of 5 against 13; the base looped at Check on its coverage row in one bug run
and asked 60). Every hidden test of every run of (b) passed, against 0.906 for the base and 0.948 for plain Claude
Code. All 18 runs of (b) ended done, at the commit, with no step back to Plan and no task blocked.

## Part H of the definition of done (rows D90 to D96), read from round (b)

| Line | Measured | The line | Result |
|---|---|---|---|
| A bug: cost, time and dialogs against plain Claude Code | 1.68 times, 3.23 times, 2 dialogs | 1.5 times, 2.5 times, 2 | miss |
| A clear feature | 4.01 times, 5.92 times, a median of 5 dialogs | 2 times, 4.5 times, 2 | miss |
| A vague feature | 3.63 times, 5.01 times, a median of 6.5 dialogs | 3 times, 4.5 times, 2 and one for every four Blocking answers | miss |
| Hidden tests at least as the base | 1.0 against 0.906 | not below | pass |
| Rules met | 1.0 | at least 0.95 | pass |
| Runs with two or more Reviews | 0.22 of runs against 0.44 for the base | at most half of the base | pass |
| Steps back to Plan and blocked tasks | 0 and 0 | not above the base | pass |

The cost, time and dialog lines miss for every kind of task. `done.md` note 2 expected the misses of the clear and the
vague lines with the planner on Opus (about 2.7 times the cost for a clear feature); the measure is higher still.
Where the time goes: the fresh review of the plan launched 52 times in 18 runs (2.9 a run), and the narrow revise
agent 13 times. These misses are reported as measured, and nothing was tuned to reach the lines.

## The model test (rule d)

The rule, fixed before round (c): the default planner becomes Sonnet below risk H only if, against (b), the hidden
tests are equal, the rules met stay at 0.95 or more, blocked tasks and steps back to Plan do not rise, and the means of
the amendments and of the first Review's High findings are not above those of (b). Round (c) passed 0.901 of the
hidden tests against 1.0 for (b): the hidden tests are not equal, so **the planner stays on Opus**. Round (c) cost 0.82
dollars and 262 seconds a run; the cheaper planner wrote plans whose code missed hidden tests.

The two plan figures: no run of (b) or (c) wrote an amendments record, so no approved plan was changed during a run
(the scorecard shows this as not measured, since a run with no record gives no number). The first Review recorded
0.17 High findings a run on average in (b), and none in the 17 runs of (c) that reached a Review.

## What the bench does not show

Three runs a task are few: a difference of one run moves a mean, and a line that sits near its value misses about one
round in two. The tasks are small Python and TypeScript projects with a fast suite; a slow build (row D97) was not
measured. The scripted person answers every question with the recommended option and does not read the plan.

Two figures the plan names per run are not in the scorecard: the seconds to the first decision (the bench writes the
time of each answer and the scorecard does not read it; the answers of these rounds were not kept in the tree) and
the permission prompts (the bench runs with permissions bypassed, so none is raised).
