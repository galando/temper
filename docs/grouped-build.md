# Grouped Build (experimental, 9.7.0)

Grouped Build is an opt-in way to run the Build stage. It is **experimental in 9.7.0**:
it ships off by default, and nobody has yet measured whether it saves money or time on a
real feature. The numbers a comparison needs are recorded for you (see
[Measuring it](#measuring-it-against-the-per-task-build)); the comparison itself is a
follow-up after 9.7.0.

## What it changes

Per-task Build (the default) runs one task at a time, each on the session model with the
full build brief, and a human gate after every task. Grouped Build changes three things:

- **Plan writes groups.** `tasks.md` has three levels: the feature, **groups** (related work
  in one area, the human review unit) and small **tasks** in each group. Every task declares
  its files, its dependencies and its own scoped `**Test:**` command. Plan writes one
  `**Context:**` block per group (shared files, interfaces, conventions, and the pack rules
  that apply, security rules always).
- **Each task is one launch of a slim Haiku agent** (`claude-haiku-5-5` by default). The
  agent reads only its task and its group's Context (a launch carries at most about 11.5 KB
  instead of about 64 KB), writes a RED then a GREEN test run, and stops. It does not commit.
- **One human gate per group** (Continue / Change / Stop) replaces the per-task gate.

The `temper` CLI, not a prompt, decides what is ready, what passes and what merges.
The orchestrator launches every task agent itself, so grouped Build works when subagents
cannot launch subagents (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`).

## Switching it on

In `.claude/temper.config`:

```yaml
build:
  mode: grouped          # absent, per-task or anything else = the ordinary per-task Build
  grouped:
    task-model: claude-haiku-5-5     # default shown
    escalation-model: sonnet         # default shown
    max-parallel: 4                  # default shown; tasks running at once
```

With `build.mode` absent or not `grouped`, nothing changes: `temper model --all` prints the
same eight stage lines, `temper gate plan` applies no grouped check, and the grouped
commands below exit 1 with "grouped mode is off (build.mode)".

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

## Measuring it against the per-task Build

Goal: the same feature built twice, once per-task and once grouped, then compared on tokens
per model, wall time and Review findings.

1. Pick one feature of medium size. Start from the same commit on two branches.
2. **Branch A (per-task):** leave `build.mode` unset. Run `/temper` through Check. When it
   finishes, save `temper report --json` (whole-flow usage, with `usage.by_stage`,
   `usage.by_model` and `usage.total`, plus the gate verdicts) and the Review findings.
3. **Branch B (grouped):** set `build.mode: grouped`. Run `/temper` through Check. Save
   `temper group report --json` (`tokens_by_model`, `attempts`, `escalations`, `parked`,
   `wall_ms_by_group`, `build_wall_ms`, `review_findings_open`) and `temper report --json`.
4. Compare per model: tokens multiplied by that model's current price, summed. Compare the
   Build stage's wall time (`usage.by_stage.build.ms` against `build_wall_ms`), plus
   retries, escalations and parked groups from the group report, and the number of Review findings.
5. Repeat on a second feature before drawing a conclusion; one run is an anecdote.

`temper report --json` also covers the per-task baseline, because every stage launch in
both Build modes is recorded with `temper usage add --stage S --model M --tokens T --ms D`
(optionally `--task N --group G`). The orchestrator makes that call after each launch.
