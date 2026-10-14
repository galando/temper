# Grouped Build (9.7.0)

Build runs in groups of small tasks, each handed to a slim Haiku agent, with one human gate
per group. It is the one Build since 9.7.0: in the baseline measurement (galando/temper#97) the
Haiku task agents cost about a fourteenth of a Sonnet build agent ([ADR 0013](decisions/0013-the-cli-says-what-next-the-mod-only-draws.md)).

## What it does

- **Plan writes groups.** `tasks.md` has three levels: the feature, **groups** (related work
  in one area, the human review unit) and small **tasks** in each group. Every task declares
  its files, its dependencies and its own scoped `**Test:**` command. Plan writes one
  `**Context:**` block per group (shared files, interfaces, conventions, and the pack rules
  that apply, security rules always).
- **Each task is one launch of a slim Haiku agent** (`claude-haiku-5-5` by default). The
  agent reads only its task (with the test cases Plan wrote for it), its group's Context and one
  existing test of the project as a pattern (a launch carries at most about 14 KB), writes a RED
  then a GREEN test run, and stops. It does not commit.
- **One human gate per group** (Continue / Change / Stop).

The `temper` CLI, not a prompt, decides what is ready, what passes and what merges.
The orchestrator launches every task agent itself, so grouped Build works when subagents
cannot launch subagents (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`). `temper next --json` gives it
each step of the loop ([the flow](flow.md)). When Review or Check loops back to Build, the groups are not
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

## What a run looks like

1. **Plan** (Opus) writes the grouped `tasks.md`. `temper gate plan` checks it: every task
   has files, dependencies, a test and at least 2 concrete test cases under `**Cases:**`; each
   group has a Context; the size budgets hold (group Context 4096 bytes, task block 2048; the
   self test holds the task brief to 6144); declared files do not overlap between tasks or
   groups that can run at the same time; no single group declares more files than
   `autonomy.max-blast-radius`.
2. **Start a group.** `temper group start G1` creates the group's git worktree,
   `.claude/worktrees/temper-{slug}-G1`, on branch `temper/{slug}/G1`, based on the feature
   branch. It only takes the merges of its passed tasks and runs the group's Validate.
   A worktree is a checkout of the whole repository: for a project below the top of its
   repository (a package of a monorepo) the task works in the project's folder inside it, and
   the CLI reads every path from the project folder, as the plan writes them.
3. **Schedule.** `temper schedule` prints the launchable tasks,
   one JSON line each, with the model to use: dependencies met, group not parked, declared
   files disjoint from running tasks, `max-parallel` respected. The orchestrator launches all
   of them in one turn.
4. **The orchestrator** runs `temper task start N`, which gives the task **its own worktree**
   (`.claude/worktrees/temper-{slug}-T{N}`, branch `temper/{slug}/T{N}`, from the group branch),
   and launches the agent. **The task agent** runs `temper task show N`, edits only its declared
   files in that worktree, then `temper task test N --phase red` and `temper task test N --phase green`.
   The CLI runs the task's own declared test command there and records the output. Tasks that run
   at the same time never see each other's unfinished edits.
5. **Task gate.** `temper task gate N --model M --tokens T --ms D` runs once the task's agent
   has returned, never before: the CLI refuses a task gate with no `--model`, and the schedule
   lists a task whose agent still works as `running on {model}: wait for its agent to return`. It
   passes only with RED then GREEN evidence for that task and only declared files changed in its worktree. On PASS the CLI
   commits the declared files on the task branch, merges it into the group branch (a fast-forward
   when it can) and removes the task's worktree. On FAIL the task's worktree is discarded and the
   task is retried once on Haiku in a fresh one, then escalated once to Sonnet. If that also fails, the group stops and the run parks
   for a human; independent groups finish first. Every attempt, its model and outcome are recorded.

   **A park after a commit the CLI did not make.** Task agents must not run `git commit`. If one
   does, the task gate FAILs naming the commit and its files and the group parks at once, with no
   retry. The commit can only be that task's, since the worktree is its own. The CLI changes
   nothing in that worktree and keeps it, and the group's other tasks refuse `task gate` and
   `task test` until the reopen (no verdict, no row), so they keep their work. You have two ways out,
   and the orchestrator asks you which one with a question (you click, Claude runs the lines):
   - (a) take the commits off the task's branch (the park prints
     `git -C <task worktree> rebase --autostash --onto <sha>~1 <sha>`, newest first), then
     `temper group reopen G1 --task N`; the next `task start` reuses that worktree with the
     agent's uncommitted work. Reopen is refused while a parked commit is still on the branch.
   - (b) keep them knowingly: `temper group reopen G1 --task N --accept-foreign <sha>[,<sha>]
     --reason '<why>'`. The acceptance is recorded like an override and `temper report` lists it.
   Known limits: detection is by sha, so rewritten history can hide a commit (the group gate
   still checks that each passed task's commit is on the branch); a rebase that drops a commit
   also rewrites the CLI commits after it, and the group gate then asks you to reopen those tasks.
6. **Group gate.** `temper group gate G1` passes when every task passed and the group's
   tests pass. You choose Continue, Change or Stop. **Change** records your feedback and
   runs `temper group reopen G1 --task N [--task M] [--feedback ID]`, which re-runs only the
   tasks it concerns; re-planning is the separate "Loop back to Plan" choice.
   `group reopen` is an orchestrator-only command: a task agent must not run it (the mod cannot
   tell a task agent's Bash from the orchestrator's, so this is a rule, not a hook).
   The group gate also fails while the group is parked and when a passed task's commit is no
   longer on the group branch.
7. **Integrate.** `temper integrate` merges the passed group branches into the feature branch
   (`--no-ff`), removes the worktrees, runs the full suite and checks the declared
   interfaces. A conflict or failure stops the run before Review with the cause recorded.
   Before any merge it checks that every commit on each group's branch is the CLI's or one you
   kept. When one is not, the orchestrator asks you: take the commits out of the group's branch
   (newest first; the groups are merged again), or keep them with your reason
   (`temper group reopen G1 --accept-foreign <sha> --reason '<why>'`, with no task: nothing runs
   again). Take them out is offered only when they are the newest commits of the branch (a rebase
   would write the CLI's own commits above them again, as commits it did not make); below those,
   keep them or save the run and take them out by hand. Once every one is kept or gone, the next
   step merges the groups again.
   Review and Check then run as today, and the final feature commit still goes through
   `temper gate commit` and a human.

Nothing is ever pushed. Autonomy may let the CLI make the local task commits and the local
integrate merge; it never pushes, never merges to a remote, never re-plans and never makes
the final feature commit.

## Limits to know about

- **One worktree per task costs a checkout each.** A task's worktree is a fresh checkout of
  the group branch: a project whose tests need an install step or a build cache pays it once per
  task. A task that needs another task's code must `**Depends:**` on it, so it starts after that
  task merged.
- **Pack rules reach task agents only as distilled text** in the group Context. Review
  still checks the full packs.
- **Merge commits run no pre-commit hook.** The CLI checks the upstream-gate condition
  (ADR 0009) itself before each commit and merge.
- **The cost is an estimate.** Input and cache tokens come exact from each agent's transcript;
  a subagent's transcript records a reply before it streams, so its output is taken from the
  reply's text, and its thinking (billed as output) is not counted. The cost is at the API list
  prices `scripts/usage_cost.py` holds (with their date); a Claude plan is not billed per token.

## Run files

The CLI owns these `.temper/` runtime files. Do not hand-write them and do not commit them
(`temper init` lists them in the clone's `.git/info/exclude`, so a project needs no `.gitignore` lines):

- `.temper/groups.json`: per-group worktree, status and gate verdict; per-task status,
  attempts and commit; the integration verdict.
- `.temper/usage.json`: one row per agent launch: stage, model, tokens, milliseconds, task and group,
  and, when the agent's transcript was found, its cost, calls, the models that served it and its session.
- `.temper/view.json`: the run as the mod draws it, written after every change (docs/flow.md).
- `.temper/.lock/`: the short-lived lock directory that serializes writes to the files above
  (stale after 30 s, never held while a test runs).

## Measuring a run

Every stage launch is recorded with `temper usage add --stage S --model M --agent ID --tokens T --ms D`
(the orchestrator makes that call after each launch; task agents are recorded by
`temper task gate --agent --tokens --ms`). After a run, save:

- `temper report --json`: whole-flow usage (`usage.by_stage`, `usage.by_model`, `usage.total`)
  and the gate verdicts;
- `temper group report --json`: `tokens_by_model`, `attempts`, `escalations`, `parked`,
  `wall_ms_by_group`, `build_wall_ms`, `review_findings_open`.

The tokens are what each agent was billed for, read by its id from its own transcript
(`<config>/projects/<project>/<session>/subagents/agent-<id>.jsonl`, `CLAUDE_CONFIG_DIR` or
`~/.claude`): every call's input, cache writes, cache reads and output, the model that served it,
its speed and its inference geography, priced at list prices. The total the Agent tool returns
(`subagent_tokens`) is the agent's context at its last call, not what it was billed for: one
Haiku task of 19 calls returned 114K and was billed for 1.65M, mostly cache reads. When the
transcript is not found, the row takes that total (and the time) from the Agent result or, for an
agent run in the background, its completion notice, and has no cost; an agent named with no
transcript and no total is refused (its report came before its notice). `temper report` adds the
main conversation since the run started, from the session transcript the agents sit below. Claude
Code's transcript layout is not a documented interface: what the CLI cannot read is left out, and
the report says how many launches have no cost.

To compare two runs (two models for the task agents, two plans, two versions of Temper), build
the same feature from the same commit on two branches and compare tokens per model times that
model's price, Build wall time, retries, escalations, parked groups and Review findings.
