# The Temper benchmark

The question this answers: given the same task, does Temper produce code that is more correct, better scoped and
better wired than plain Claude Code, and at what cost? It is graded by tests no arm ever sees, never by a model's
opinion of itself.

## The arms

The task text is the same, word for word, in every arm.

| Arm | What runs |
|---|---|
| `vanilla` | Claude Code with the task as the prompt |
| `careful` | The strong baseline: the task plus the words a careful developer would add (read the code, plan, tests first, run the suite, wire it in, add nothing extra) |
| `temper` | `/temper:temper <task>` with this repository loaded as a plugin |

Every arm runs through the Agent SDK with no user or project settings, in a fresh git repository built from the
task's `repo/` folder, with the same model. One simulated person (`person.mjs`) answers every question in every
arm from the options alone: it approves and continues, fixes rather than skips, never overrides a failed gate, and
knows nothing beyond the task text. Every question and answer is logged to `person.jsonl` for audit.

## A task

```
tasks/<id>/
  task.md      the request, as a person would write it
  meta.json    size, language, expected_paths (where a change belongs)
  repo/        the project at the start, with its own suite in repo/unit
  hidden/      acceptance tests written from task.md alone; copied in only at grading
```

## What is measured

`grade.py` copies the result, then:

1. **Hidden tests:** each test passes, fails or errors. The headline number is how many runs pass every hidden
   test.
2. **The original suite**, taken from the task as it was before the run, so deleting or weakening a test gains
   nothing: did the change break what worked?
3. **The diff:** files and lines changed against the base commit (Temper's own `.temper/` and `.claude/` folders
   counted apart), and every changed file outside `expected_paths`.
4. **Cost and time**, from the SDK's own result messages (`run.json`). That is the one source of cost: the
   scorecard and `report.py` read `cost_usd` of `run.json`. `loop.py` prices the same requests from Claude Code's
   logs, and `loop.py --check` compares the two; its figure is for a reader, never a second number in a table.

`report.py` prints one table per task and one overall, with the median, the minimum and the maximum beside each mean.
Arm names are free: an arm that is not one of the five known ones gets its own row.

## The scorecard

`run.mjs` also writes, on each line of `person.jsonl`, the dialog it was asked in (four Blocking questions in one
dialog share the index), the question's id, the move of the answer and, for a step back, the stage it goes to, and in
`run.json` which code ran: the plugin's version and commit, the Claude Code version and whether the mod was loaded.
`agentlog.py` reads the agents of a run from Claude Code's own logs (the type matched whole).

```bash
python3 scorecard.py ~/results-before ~/results-after          # scorecard.json in each folder, and one table
python3 scorecard.py ~/results-before ~/results-after --gate ../docs/evidence/scorecard-9.8.5.json
```

A block is one arm of one results folder, named `<folder>/<arm>`, so the round before and the round after, both run as
the arm `temper`, stay apart, and a third arm (the model test) lives in a folder of its own. `--gate` holds one block
against the pass lines of part H of `docs/plans/one-go/done.md` (`bug`, `clear`, `vague`, `hidden`, `rules_met`,
`reviews`, `steps_back`): `--arm NAME` names it, by default the `temper` block of the last folder; `--before` and
`--plain` name the round before and plain Claude Code. `steps_back` holds the steps back to Plan and the blocked tasks
(each `temper task blocked N` the CLI took, read from the agents' logs) against the round before; only a vague task has
one more dialog for every four Blocking answers. A line with no data says so and is not a pass. A missed line is
reported with its numbers; it is never tuned.

Two figures the plan names per run (`docs/plans/two-approval-run.md`, item 1b) are left out of the scorecard.
Seconds to the first decision: `run.mjs` writes the milliseconds since the start (`t`) on every line of
`person.jsonl`, and `scorecard.py` does not read it. Permission prompts: `run.mjs` runs with permissions bypassed, so
a run raises none and there is nothing to count. The rounds of 9.8.5 are in the tree as `run.json` and `grade.json`
only (`docs/evidence/bench-9.8.5/`), without their person lines, so neither figure can be worked out for them now.

Two figures show a weak plan before it fails hard. `amendments` counts the entries of the run's amendments record
(`.temper/evidence/amendments.json`), and apart those made by rule (`amendments_by_rule`, `temper plan amend`) and
those the person made (`amendments_by_person`, `temper plan patch`). `first_review_high` counts the findings of level
high or critical that the first Review of the run recorded in its ledger, up to that Review's `review completed` row.
`temper state clear` deletes both records when a run ends, so `run.mjs` keeps every entry it sees while the run goes
on, in the run's folder under `records/`. A run with no such record gives `null`, never 0: plain Claude Code, and a
CLI that writes no amendments record, as the round before on the base (`10e965a`). Both are in each run and, as a
spread with the number of runs that had the record, in each cell, and the printed table shows their means.

The model test (the build of 9.8.5, WP32) runs the same tasks once more on the result with the planner on Sonnet below
risk H, in a results folder of its own (round (c)), against the round on the default config (round (b)). Its rule was
fixed before round (c) ran: the default table changes to Sonnet below risk H only if, against round (b), the hidden
tests are equal, the rules met stay at least 95%, the blocked tasks and the steps back to Plan do not rise, and the
means of `amendments` and of `first_review_high` are not above those of round (b). Else Opus stays. Round (a) has
neither record, so the two figures compare round (c) with round (b) only; with three runs a cell one finding moves a
mean, so the number of runs stands beside each figure.

## Running it

It costs real model calls and is never part of CI. It runs the arms unattended with permissions bypassed inside a
scratch folder under `~/temper-bench-results/` (or `$TEMPER_BENCH_RESULTS`), outside the plugin folder, since Temper refuses to run a project inside its own plugin, so run it on a machine or container you are happy to give that access.

```bash
cd bench && npm install
node run.mjs --task login-lockout --arm temper --rep 1     # one run
python3 grade.py ~/temper-bench-results/login-lockout__temper__1           # grade it
bash run-all.sh 3                                           # every task x every arm x 3 reps, graded
BENCH_CONFIG_YAML='models:\n  plan: sonnet' bash run-all.sh 3 temper   # the same, with more config lines each run
python3 report.py                                           # the tables, also in ~/temper-bench-results/report.md
```

To compare models of the Build task agents, run the `temper` arm with `--task-model haiku` and `--task-model sonnet`
into folders named `<task>__temper-<model>__<rep>` (`--out`), grade each, then `python3 compare_models.py <results folder>`.
The last comparison is in `docs/evidence/haiku-sonnet-task-agents.md`.

`run.mjs` also takes `--config-yaml 'plan:\n  fresh-review: always'` (more lines for the project's config) and
`--task-dir DIR` (a task folder outside `tasks/`; `grade.py` reads it from `run.json`). A bug task (`kind: bug` in its
`meta.json`) starts with `/temper:fix`, every other task with `/temper:temper`, so a run starts at Intent.

## Rules that keep it honest

- Write the hidden tests before any arm runs, from `task.md` alone, and check that a reference solution passes
  them and the untouched repo fails them.
- Run at least 3 repetitions per task per arm; single runs are noise.
- Publish every run, including the tasks Temper loses (the small ones are expected to cost more with no gain).
- The pilot tasks here were written by the Temper author. A claim to the world needs tasks from outside: real
  issues from other repositories, with acceptance tests written by someone who has not seen any arm's output.
