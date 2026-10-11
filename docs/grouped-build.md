# Grouped Build (9.7.0)

Build runs in groups of small tasks, each handed to a slim Haiku agent, with one human gate
per group. It is the default Build since 9.7.0. See
[Why it is the default](#why-it-is-the-default) for the run that decided it, and
[Going back to the previous Build](#going-back-to-the-previous-build) for the one line that
turns it off.

## What it does

- **Plan writes groups.** `tasks.md` has three levels: the feature, **groups** (related work
  in one area, the human review unit) and small **tasks** in each group. Every task declares
  its files, its dependencies and its own scoped `**Test:**` command. Plan writes one
  `**Context:**` block per group (shared files, interfaces, conventions, and the pack rules
  that apply, security rules always).
- **Each task is one launch of a slim Haiku agent** (`claude-haiku-5-5` by default). The
  agent reads only its task and its group's Context (a launch carries at most about 11.5 KB),
  writes a RED then a GREEN test run, and stops. It does not commit.
- **One human gate per group** (Continue / Change / Stop).

The `temper` CLI, not a prompt, decides what is ready, what passes and what merges.
The orchestrator launches every task agent itself, so grouped Build works when subagents
cannot launch subagents (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`). The loop it runs is
`reference/build-groups.md`. When Review or Check loops back to Build, the groups are not
re-run: the Build brief (`agents/build.md`) runs once on the feature branch as a fix pass.

## Tuning it

In `.claude/temper.config` (all optional; the defaults are shown):

```yaml
build:
  grouped:
    task-model: claude-haiku-5-5     # the task agents
    escalation-model: sonnet         # the third attempt after two failed ones
    max-parallel: 4                  # tasks running at once
```

`temper model --all` prints the stage lines plus `task=` and `task-escalation=`.

To keep groups but run the tasks on another model (no Haiku), set `task-model: sonnet`.

## Going back to the previous Build

One line in `.claude/temper.config` brings back the Build Temper ran before 9.7.0:

```yaml
build:
  mode: per-task
```

With it, Plan writes the flat `tasks.md` layout, Build runs one task per launch on the build
model (`temper model build`, Sonnet by default) with a human gate after every task, nothing runs
on Haiku, the grouped plan, build and commit-gate rows do not apply, and the grouped commands
(`schedule`, `group`, `task`, `integrate`) exit 1 saying the mode is per-task. Remove the line
to return to grouped Build. Switch between runs, not in the middle of one: a plan written for
one mode does not pass the other mode's plan gate.

## What a run looks like

1. **Plan** (Opus) writes the grouped `tasks.md`. `temper gate plan` checks it: every task
   has files, dependencies and a test; each group has a Context; the size budgets hold
   (task brief 6144 bytes, group Context 4096, task block 1536); declared files do not
   overlap between tasks or groups that can run at the same time; no single group declares
   more files than `autonomy.max-blast-radius`.
2. **Start a group.** `temper group start G1` creates one git worktree,
   `.claude/worktrees/temper-{slug}-G1`, on branch `temper/{slug}/G1`, based on the feature
   branch.
3. **Schedule.** `temper schedule` (add `--json` for the machine form) prints the launchable tasks,
   one JSON line each, with the model to use: dependencies met, group not parked, declared
   files disjoint from running tasks, `max-parallel` respected. The orchestrator launches all
   of them in one turn.
4. **The orchestrator** runs `temper task start N` and launches the agent. **The task agent** runs `temper task show N`, edits only its
   declared files, then `temper task test N --phase red` and `temper task test N --phase green`.
   The CLI runs the task's own declared test command and records the output.
5. **Task gate.** `temper task gate N --model M --tokens T --ms D` passes only with RED then
   GREEN evidence for that task and only declared files changed. On PASS the CLI makes a
   local commit of the declared files on the group branch. On FAIL the task is retried once on
   Haiku, then escalated once to Sonnet. If that also fails, the group stops and the run parks
   for a human; independent groups finish first. Every attempt, its model and outcome are recorded.

   **A park after a commit the CLI did not make.** Task agents must not run `git commit`. If one
   does, the task gate FAILs naming the commit and its files and the group parks at once, with no
   retry. The CLI changes nothing on the branch or in the working tree, and the group's other
   tasks refuse `task gate` and `task test` (no verdict, no row), so tasks still running keep
   their work. You have two ways out:
   - (a) once no task of the group runs, take the commits off the branch yourself (the park
     prints `git -C <worktree> rebase --onto <sha>~1 <sha>`, newest first; a reset works too),
     then `temper group reopen G1 --task N`. Reopen is refused while a parked commit is still
     on the branch.
   - (b) keep them knowingly: `temper group reopen G1 --task N --accept-foreign <sha>[,<sha>]
     --reason "<why>"`. The acceptance is recorded like an override and `temper report` lists it.
   Known limits: detection is by sha, so rewritten history can hide a commit (the group gate
   still checks that each passed task's commit is on the branch); a rebase that drops a commit
   also rewrites the CLI commits after it, and the group gate then asks you to reopen those tasks.
6. **Group gate.** `temper group gate G1` passes when every task passed and the group's
   tests pass. You choose Continue, Change or Stop. **Change** records your feedback and
   runs `temper group reopen G1 --task N [--task M] [--feedback ID]`, which re-runs only the
   tasks it concerns; re-planning is the separate "Loop back to Plan" choice.
   `group reopen` is an orchestrator-only command: a task agent must not run it (its revert is excused
   in a sibling's verdict only while the files still hold the revert's exact content; the mod cannot
   tell a task agent's Bash from the orchestrator's, so this is a rule, not a hook).
   The group gate also fails while the group is parked and when a passed task's commit is no
   longer on the group branch.
7. **Integrate.** `temper integrate` merges the passed group branches into the feature branch
   (`--no-ff`), removes the worktrees, runs the full suite and checks the declared
   interfaces. A conflict or failure stops the run before Review with the cause recorded.
   Review and Check then run as today, and the final feature commit still goes through
   `temper gate commit` and a human.

Nothing is ever pushed. Autonomy may let the CLI make the local task commits and the local
integrate merge; it never pushes, never merges to a remote, never re-plans and never makes
the final feature commit.

## Limits to know about

- **Parallel tasks in a group share one worktree.** One task's test run can see a sibling's
  unfinished edit. Each task's own scoped test limits this, but a failure can still be
  attributed to the wrong task. Order tasks with `**Depends:**` when they touch related code.
- **Pack rules reach task agents only as distilled text** in the group Context. Review
  still checks the full packs.
- **Merge commits run no pre-commit hook.** The CLI checks the upstream-gate condition
  (ADR 0009) itself before each commit and merge.
- **Usage numbers are rough.** They are the per-agent totals that Claude Code returns for
  each launch, not split into input, output and cache tokens. The orchestrator session's own
  usage is not visible and is not recorded.

## Run files

The CLI owns these `.temper/` runtime files. Do not hand-write them and do not commit them
(this repository's `.gitignore` lists them; add the lines to a project's `.gitignore`):

- `.temper/groups.json` - per-group worktree, status and gate verdict; per-task status,
  attempts and commit; the integration verdict.
- `.temper/usage.json` - one row per agent launch: stage, model, tokens, milliseconds, task and group.
- `.temper/.lock/` - the short-lived lock directory that serializes writes to the files above
  (stale after 30 s, never held while a test runs).

## Why it is the default

One feature, built twice from the same commit of [pyjokes](https://github.com/pyjokes/pyjokes)
with this release's Temper: "list N jokes that contain a substring", from the Python API and the
CLI. Both runs had the same accepted intent, the same config (autonomy armed at the plan gate)
and the same gates; only Build differed.

| | Per-task Build (removed) | Grouped Build |
|---|---|---|
| Plan | 4 sequential tasks | 2 groups, 1 task each (G2 depends on G1) |
| Build launches | 4 on Sonnet | 2 on Haiku, both passed on attempt 1, 0 escalations |
| Build tokens | 257,674 | 134,363 |
| Build at list input price | about $0.52 | about $0.013 |
| Plan to Check, at list input prices | about $1.48 | about $0.97 |
| Tests at the end | 21 pass, coverage 94% | 25 pass, coverage 97% |
| Review findings | none | 1 medium (CLI tests mock the API), 1 low |
| Run state | the build agent rewrote `build-state.json` and dropped `spec_path`, so the Check gate skipped its scenario rows | intact |

Token counts are the per-agent totals Claude Code reports (mostly cached input), priced at the
input rate per million tokens: Opus 5.5 $4, Sonnet 5.5 $2, Haiku 5.5 $0.10. They show the ratio,
not the bill. One run is an anecdote: keep measuring.

## Measuring a run

Every stage launch is recorded with `temper usage add --stage S --model M --tokens T --ms D`
(the orchestrator makes that call after each launch; task agents are recorded by
`temper task gate --tokens --ms`). After a run, save:

- `temper report --json`: whole-flow usage (`usage.by_stage`, `usage.by_model`, `usage.total`)
  and the gate verdicts;
- `temper group report --json`: `tokens_by_model`, `attempts`, `escalations`, `parked`,
  `wall_ms_by_group`, `build_wall_ms`, `review_findings_open`.

To compare two runs (two models for the task agents, two plans, two versions of Temper), build
the same feature from the same commit on two branches and compare tokens per model times that
model's price, Build wall time, retries, escalations, parked groups and Review findings.
