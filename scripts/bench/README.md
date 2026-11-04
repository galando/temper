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
4. **Cost and time**, from the SDK's own result messages (`run.json`).

`report.py` prints one table per task and one overall.

## Running it

It costs real model calls and is never part of CI. It runs the arms unattended with permissions bypassed inside a
scratch folder under `~/temper-bench-results/` (or `$TEMPER_BENCH_RESULTS`), outside the plugin folder, since Temper refuses to run a project inside its own plugin, so run it on a machine or container you are happy to give that access.

```bash
cd scripts/bench && npm install
node run.mjs --task login-lockout --arm temper --rep 1     # one run
python3 grade.py ~/temper-bench-results/login-lockout__temper__1           # grade it
bash run-all.sh 3                                           # every task x every arm x 3 reps, graded
python3 report.py                                           # the tables, also in ~/temper-bench-results/report.md
```

## Rules that keep it honest

- Write the hidden tests before any arm runs, from `task.md` alone, and check that a reference solution passes
  them and the untouched repo fails them.
- Run at least 3 repetitions per task per arm; single runs are noise.
- Publish every run, including the tasks Temper loses (the small ones are expected to cost more with no gain).
- The pilot tasks here were written by the Temper author. A claim to the world needs tasks from outside: real
  issues from other repositories, with acceptance tests written by someone who has not seen any arm's output.
