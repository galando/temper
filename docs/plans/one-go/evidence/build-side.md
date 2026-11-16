# Temper Build subsystem: how it works, what it costs, where it wastes

Reader: build-side (one of 17). Tree read: `/home/user/temper` at PR #115 head `9a01eff` (branch `pr115`, version
9.8.5, `.claude-plugin/plugin.json:5`); `origin/main` is `7c7a1c1` (9.8.4). All paths are relative to the repository
root; line numbers are those of the PR head.

How each claim is labelled:

- **[code]** read in the code at the line given.
- **[run]** measured by me with the PR head's CLI (a clone at
  `/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-build-side/repo`) on throwaway
  Python projects (5 files, a suite that takes 0.1 s). Transcripts are summarised in the appendix. CLI times are for
  that tiny project on this Linux container; they show the CLI's own overhead, not a real project's test time.
- **[doc]** a claim in a document of the repository that I did not check against a run.
- **[inferred]** my reasoning from the code; not run.

I did not launch any model agent. Agent times and costs are quoted from the repository's own measurements.

---

## 1. Main findings

1. **Build has no light path.** Every `/temper` feature run builds through groups, one git worktree per group and one
   per task, a task gate, a group gate, a merge and a Build gate, even for one task in one group. The only places one
   agent edits in place are the fix pass, `/temper:fix`, the "Make a small change" window and Intent's TRIVIAL exit
   (section 7). **[code]**
2. **Parallelism was hardly used in the measured runs.** In 11 of the 18 runs of the Haiku against Sonnet benchmark
   the whole Build was one task agent doing a chain of 3 to 6 tasks one after another
   (`docs/evidence/haiku-sonnet-task-agents.md:30-47`, column "task launches"). Each of those tasks still paid its own
   worktree, gate, commit and merge. **[doc]**
3. **The same tests run several times on the same code.** In a one task walk-through the task's test command ran 5
   times inside Build (RED, GREEN, task gate, group gate, integrate) and once more in the plan gate's preflight; Check
   runs it again. Scenario tests are never cached (section 4). **[run]**
4. **Failure discards work.** A failed task gate throws the attempt's worktree away and a new agent starts from
   nothing; "Run the group's tasks again" reverts every task; a loop back to Plan archives the whole grouped run and
   every task is built again (section 5). **[code]**
5. **One failure path has no question and no bound.** When `temper integrate` fails on its suite, `temper next`
   launches the Sonnet fix pass again each time, and the Build gate that would ask the person never runs. Three
   consecutive `temper next` calls gave the same launch (section 5, row 14). **[run]** on the PR head; main has the
   same branch of `build_work` (`git show origin/main:scripts/flow.py`, lines 1471-1482) **[code]**
6. **The task gate holds the run lock while it runs tests.** A sibling task's `task start` waited 6.2 s behind a 6 s
   scenario test, and with the lock limit shortened to 3 s a sibling's RED row was dropped with exit 75. The documents
   say the lock is never held while a test runs (section 8). PR #115 turns the old "write past the lock" into a
   failed call. **[run]**
7. **Tests that exist before Build are not run by Build.** The acceptance writer is the first agent of Build, but its
   locked tests run only at Check (`scripts/check_run.py:723-725`). A failure there is a loop back from Check to
   Build. The benchmark shows 12 and 16 Build fix passes after a step back in 9 runs per arm
   (`docs/evidence/haiku-sonnet-task-agents.md:79`). **[code] [doc]**
8. **Nothing shares dependencies or build output between worktrees.** A worktree holds tracked files only. The only
   things shared are git's object store, a pass cache for group and integration checks added by PR #115
   (`scripts/run_env.py:121-180`) and whatever the tool keeps outside the tree (`~/.m2`) (section 6). **[code]**

---

## 2. The life of one Build task and one group

Who decides: `temper next --json` (`scripts/flow.py:1635-1770`, `build_work`) computes each step; `temper go`
(`scripts/go.py:1-21`) runs the CLI's own calls and stops where an agent or the person is needed. "Orchestrator" below
is the main session following `commands/temper.md:64-132`, or the mod's run driver
(`hooks/temper-mod/core/driver.ts`). **[code]**

| # | Step | Who runs it | What it does | Time | What it records |
|---|---|---|---|---|---|
| 0 | Acceptance writer | Orchestrator launches `temper:temper-acceptance` (Sonnet, `agents/acceptance.md:4`); before call `temper acceptance start` | Before any group starts, for every `/temper` run that has an `intent.md`, whatever the tier (`scripts/flow.py:1394-1420`). Writes tests under `{spec}/acceptance/` and locks them. At most 2 launches (`scripts/check_run.py:625`), then a recorded skip. | 30 to 45 s **[doc]** `docs/evidence/bench-2026-11.md:457-459`. I saw it launch for a plan rated `simple` **[run]** | `.temper/evidence/acceptance-lock.json`; a usage row |
| 1 | `temper state set base_sha`, `temper group start G1` | CLI (`temper go`) | Refuses a protected branch (`scripts/temper:2344-2358`); `git worktree add -b temper/{slug}/G1 .claude/worktrees/temper-{slug}-G1 HEAD` (`:2380-2404`); merges each group it depends on (`:2406-2416`). At most `build.grouped.max-groups` (2) groups open at once (`scripts/flow.py:1677-1687`). | 0.41 s **[run]** plus one checkout of the repository | `groups.json`: `plan_hash`, `groups.G1.{status, worktree, branch, base_sha, started_at}` (`scripts/temper:2420-2434`). No ledger row |
| 2 | `temper schedule` (inside `next`) | CLI | The ready set: dependencies passed, group started and not parked, files disjoint from running tasks, `max-parallel` (4) (`scripts/tasks_md.py:149-229`). Tasks that would run one after another anyway go to one agent as a chain (`scripts/flow.py:1558-1588`, `:1706-1721`). | 0.15 to 0.18 s per `next` **[run]** | Nothing (read only, `scripts/temper:2198-2210`) |
| 3 | `temper task start N` | Orchestrator, as the agent's `before` call (`scripts/flow.py:1713`); the chain agent itself for the 2nd and later tasks (`agents/build-task.md:12-14`) | Under the lock: checks the task is ready, `git worktree add -b temper/{slug}/TN .claude/worktrees/temper-{slug}-TN <group branch>` (`scripts/temper:2955-2972`) | 0.77 s **[run]** plus a checkout | `groups.json` `tasks.N.{status: running, attempt, start_sha, started_at, worktree, branch, model, start_hashes}` (`scripts/temper:2975-2991`) |
| 4 | Launch | Orchestrator launches `temper:temper-build-task` with a 4 line prompt (384 bytes **[run]**) | The agent reads `agents/build-task.md` (6,043 bytes) and runs `temper task show N`: task block, declared files, scenario tests owed, group Context, a pattern test, feedback, the previous attempt; capped at 8,600 bytes (`scripts/temper:2848`, `scripts/task_ops.py:377-417`) | `task show` 0.25 s **[run]**. The agent as a whole: 122 s on average after the 9.8.x panel fix, 193 s before (`docs/evidence/bench-2026-11.md:457-476`) **[doc]** | Nothing |
| 5 | RED: `temper task test N --phase red` | Task agent | The CLI runs only the task's declared `**Test:**` command in the task worktree (`scripts/temper:3040-3054`; a Maven command through `maven_loop.py`, `scripts/task_ops.py:429-433`); limit 600 s (`TEMPER_TASK_TEST_TIMEOUT_S`) | CLI 0.55 s **[run]** plus the test | Build ledger row: `claim "Task N unit test red"`, cmd, exit, phase, task, group, attempt, `executed_by: cli`, last 4,096 bytes of output, byproducts, `red_hashes` (`scripts/task_ops.py:449-456`) |
| 6 | GREEN: `temper task test N --phase green`, then once more after REFACTOR (`agents/build-task.md:38-40`) | Task agent | Same command, same worktree | 0.55 s each **[run]** plus the test; at least 2 runs by the brief | Same row shape, phase `green` |
| 7 | `temper task gate N --model M` | The chain agent (`agents/build-task.md:13-14`); the orchestrator's after call `task gate N --model M --if-running` only gates a task the agent left running (`scripts/flow.py:1716-1718`, `scripts/temper:3103-3108`) | Whole gate under the lock (`scripts/temper:3073-3080`). Verdict (`scripts/task_ops.py:669-775`): a valid RED before a passing GREEN, the last run green, the RED not made on finished code (PR, `:176-192`), then **runs the scenario tests the task owes** in the worktree (`:706-708`), no undeclared change, no commit the CLI did not make. On PASS: commit the declared paths (`scripts/temper:3196-3211`), merge the task branch into the group branch (`:3214-3247`), tick the box (`:3248`), remove the worktree and branch (`:3261`) | 1.08 to 1.25 s **[run]** plus the owed scenario tests | `usage.json` row (`:3121`); `tasks.N.attempts[]` `{n, model, outcome, reason, ms, ts}`, `status`, `commit`, `passed_at`; `cli_commits[]` (`:3249-3260`). **No ledger row for the scenario runs** (`scripts/scenario_ops.py:124-130`: "Records nothing") |
| 8 | `temper usage add`, `temper panel task N` | Orchestrator (after calls, `scripts/flow.py:1717-1720`) | Records the agent's time; the CLI draws the task panel | 0.18 s **[run]** | `usage.json` row, stage `build` |
| 9 | `temper group gate G1` | CLI (`temper go`), when every task of the group is done (`scripts/flow.py:1750-1753`) | Refuses when parked, a task not passed, a passed task's commit off the branch, no Validate, uncommitted tracked changes (`scripts/temper:2474-2492`). Runs the group's `**Validate:**` in the group worktree, with the pass cache (`:2496`, `scripts/task_ops.py:459-474`), then **the scenario tests of the group again** on the merged group branch (`scripts/temper:2504-2508`). Limit 600 s; not under the lock | 0.72 s **[run]** plus Validate plus the scenario tests | Ledger row phase `group` (with `reused`, and `fail_lines` on failure); `groups.G1.gate {verdict, ts, reason, timeout_s, ran, fail_lines}`, `fails`, `status`, `finished_at` (`scripts/temper:2518-2535`) |
| 10 | Group question, or `temper group continue G1` | The person; automatic when the plan has one group (`scripts/flow.py:1761-1765`) or the run is armed (`:1759-1760`) | "Group G1 (Core) passed its check. Continue?" Continue / Change / Stop (`scripts/flow.py:1942-1947`). A group that depends on G1 cannot start before this answer (`scripts/temper:2370-2377`; I saw the refusal **[run]**) | 0.21 s **[run]** plus the person | `groups.G1.confirmed` (`scripts/temper:2824-2827`) |
| 11 | `temper integrate` | CLI (`temper go`), when every group passed and was continued (`scripts/flow.py:1767-1769`) | Refuses unknown commits (`scripts/temper:3361-3378`); merges each group branch into the feature branch with `--no-ff` (`:3387-3398`); removes the group worktrees (`:3399-3404`); runs `**Integration:**` in the project folder, with the pass cache, limit 3,600 s (`:3405-3418`); **runs every scenario's `Test:` command** (`:3419-3423`); checks the `**Interfaces:**` literals (`:3424-3429`); deletes the group branches (`:3430`) | 0.95 to 1.08 s **[run]** plus the suite plus every scenario test | Merge commits; ledger row phase `integration`; one row per scenario, phase `scenario`; `groups.json` `integration {verdict, reason, head}` (`:3292-3299`) |
| 12 | `temper gate build` | CLI (`temper go`) | Runs no test. Rows: `RED then GREEN` (CLI-run rows only, `scripts/temper:3633-3645`), `all tasks complete` (`scripts/task_rows.py:23-41`), `criteria validated` (each scenario criterion needs a CLI-run passing row, `scripts/acceptance.py:259-291`), `checkpoint feedback answered` (`scripts/temper:3654-3691`), `integration` (`:3692-3713`) | 0.68 s **[run]** | `gates.json` `build` |
| 13 | Build question | The person; an armed run advances by itself (`scripts/flow.py:2454-2463`) | "Build: the check passed. Continue to Review?" Continue / Change something / Teach Me / More options (Loop back to Plan, Make a small change, Save for later) (`scripts/flow.py:743-752`; seen **[run]**) | the person | `state advance build_complete review` |

Totals for one task in one group **[run]**: 11 Build commands of the CLI (rows 1 to 12, without `usage add` and
`state set base_sha`) and 7 `next` computations, about 7.5 s in all with a 0.1 s suite; 2 worktrees and 2 branches
made and removed; 1 task commit and 1 `--no-ff` merge commit on the feature branch; 2 agent launches (acceptance
writer and task agent); 1 question.

With 4 tasks in 2 groups (G2 depends on G1) **[run]**: tasks 1 and 2 came out as one chain agent, task 3 as a second
agent launched with it; after G1's gate the group question was asked; G2 started only after `group continue G1`; its
worktree was G1's branch merged into a new branch (`merge(demo): G1 into G2 base`); a second group question followed
G2's gate.

Git history Build leaves on the feature branch: one commit per task (`feat({slug}): Task N title [G]`,
`scripts/temper:3202`), a merge commit per task when the group branch moved meanwhile (`:3225`), one `--no-ff` merge
per group (`:3390`), and the fix pass's own commits (`agents/build.md:72-76`). **[code]**

---

## 3. Models and parallelism

### Which model builds a task

| Rule | Where | Label |
|---|---|---|
| `build.grouped.task-model` in `.claude/temper.config` wins | `scripts/temper:573-575`, `scripts/cli_ctx.py:69` | [code] |
| else `sonnet` when the run's `complexity` is `complex` or its `risk` is `H` | `scripts/temper:576-577`, `scripts/cli_ctx.py:24,46-73` | [code] |
| else the frontmatter of `agents/build-task.md` (`claude-haiku-5-5`), else that constant | `scripts/temper:578-583`, `agents/build-task.md:4` | [code]; I saw `haiku` for a `simple` plan [run] |
| Attempts 1 and 2 run on the task model, attempt 3 on `build.grouped.escalation-model` (default `sonnet`) | `scripts/tasks_md.py:209-210`, `scripts/temper:586-589,2989` | [code]; seen [run] |
| When the task model is already `sonnet` (complex or risk H), attempt 3 is `sonnet` again: no escalation happens | follows from the two rules above; no code raises it | [inferred] |
| A chain runs every one of its tasks on the first task's model | `scripts/flow.py:1712-1718` | [code] |
| The fix pass and the group fix agent: `agents/build.md`, `sonnet` | `agents/build.md:4`, `scripts/flow.py:1119-1136` | [code]; seen [run] |
| The acceptance writer: `sonnet` | `agents/acceptance.md:4` | [code] |

### Retry and escalation

A failed gate on attempt 1 prints `NEXT: retry Task N on <task model>`, on attempt 2 `NEXT: escalate Task N on
<escalation model>`, on attempt 3 `NEXT: park group G` (`scripts/temper:3151-3185`). Each failed attempt's worktree is
discarded first (`:3153`, `:2997-3005`); the next agent gets only the last attempt's reason and 20 lines of output
(`scripts/task_ops.py:407-416,753-756`). I ran all three: the three `next` actions and then the parked question
(appendix A3). **[run]**

Exceptions that skip the ladder: a commit the CLI did not make parks at once and keeps the worktree
(`scripts/temper:3142-3146`); `task blocked` parks at once (`:3147-3149`); COVERED, ENV and AWAIT spend no attempt
(`:3122-3137`).

### Parallelism

- `build.grouped.max-parallel` (default 4): tasks running at once (`scripts/temper:2207`, `scripts/tasks_md.py:196-197`).
- `build.grouped.max-groups` (default 2): groups started and not yet continued (`scripts/flow.py:1677-1687`).
- The orchestrator launches every ready agent in one message (`commands/temper.md:77-84`); no agent launches another
  (`docs/decisions/0011-grouped-build.md:21-25`).
- A group that depends on another starts only after that group's gate passed **and** the person answered Continue
  (`scripts/flow.py:1683-1685`, `scripts/temper:2360-2378`). Dependent groups are therefore serial with a question
  between them, unless the run is armed.
- A parked group stops every other task of that group, independent ones included (`scripts/tasks_md.py:158`); I saw the
  parked question replace the launch of the chain for tasks 1 and 2 when task 3 parked. **[run]**
- All task gates serialize on one lock, and that lock is held during the gate's scenario tests (section 8).

### What the Haiku against Sonnet evidence concluded

`docs/evidence/haiku-sonnet-task-agents.md` (18 runs, 3 feature tasks, 3 runs per arm) **[doc]**:

| | Haiku | Sonnet | Line |
|---|---|---|---|
| Runs that pass every hidden test | 9 of 9 | 9 of 9 | :70 |
| Cost of a run, mean | $2.58 | $2.83 | :72 |
| Cost of the task agents in a run | $0.07 | $0.33 | :73 |
| Wall time of a run | 890 s | 790 s | :74 |
| Time of the task agents in a run | 259 s | 134 s | :75 |
| Extra task runs the model caused | 0 | 0 | :77 |
| Build fix passes after a step back, 9 runs | 12 | 16 | :79 |
| Review rounds, 9 runs | 13 | 13 | :80 |

Its conclusions (`:84-99`): no difference in what was built; Haiku is cheaper by about $0.25 a run (9%), inside the
spread between runs; Haiku is slower (the task agents take about twice as long, a run about 100 s longer); all 11
extra task runs and both escalations came from one plan defect no model could build; the 9.8.4 rule (Sonnet for
complex or risk H) "is not a quality fix on this evidence" and "buys speed and fewer retries for about $0.25 a run".
Decision (`:109-112`): keep Haiku for simple and medium plans, Sonnet for complex or risk H. Limits (`:103-105`): 5 to
7 tasks per plan, a simulated person, no vague task.

Two things the table shows that the document does not draw out:

- The task agents are 3% to 12% of a run's cost (`:87-88`), so the task model is not where the money is.
- "task launches" is 1 in 11 of the 18 runs for 3 to 6 tasks (`:30-47`): the plan was one chain and one agent built
  it. Per task that is roughly 32 to 54 s on Haiku and 20 to 35 s on Sonnet (the "Build task s" column divided by the
  "tasks" column; my division, not a figure in the document).

`docs/grouped-build.md:6-7` still says the Haiku task agents "cost about a fourteenth of a Sonnet build agent"; that
compares with the removed per task Build, and the newer document measures about a fifth against Sonnet task agents
(`docs/evidence/haiku-sonnet-task-agents.md:87`).

---

## 4. Every test or suite run from the first task to the Build gate

Five kinds of command exist in a plan: a task's `**Test:**`, a group's `**Validate:**`, the plan's
`**Integration:**`, a scenario's `Test:` in `intent.md`, and the acceptance lock's command. Check adds its own suite
and coverage commands.

| When | Command | Tree | Times | Cached | Where |
|---|---|---|---|---|---|
| Plan gate preflight (PR #115, before Build) | each distinct Validate, task Test, Integration and scenario Test | a throwaway worktree of HEAD under the temp folder | once per plan; again whenever HEAD, any command, the setup block or the limit changes (the key covers all commands together) | stored result, `.temper/preflight.json` | `scripts/preflight.py:44-61,143-210` |
| Acceptance writer | the acceptance command | project folder | once by the agent, once by `acceptance lock` to see that it can run | no | `agents/acceptance.md` step 4, `scripts/check_run.py:471-483,509` |
| Task RED | the task's Test | task worktree | 1 or more | no (`run_cmd`) | `scripts/task_ops.py:425-457` |
| Task GREEN | the task's Test | task worktree | 2 by the brief (GREEN, then again after REFACTOR) | no | `agents/build-task.md:38-40` |
| Task agent's own look at a failure | a file, class or keyword | task worktree | any | no | `agents/build-task.md:46` |
| Task gate | each scenario Test the task owes | task worktree, under the lock | 1 each | no (`run_cmd`), no row | `scripts/task_ops.py:706-708`, `scripts/scenario_ops.py:101-130` |
| Group gate | Validate | group worktree | 1 per gate run | yes when the same command passed on the same clean tree (PR #115) | `scripts/temper:2496`, `scripts/run_env.py:149-180` |
| Group gate | each scenario Test whose owner is in the group, the ones the task gates ran included | group worktree | 1 each | no, no row | `scripts/temper:2504-2508`, `scripts/scenario_ops.py:107-112` |
| Integrate | Integration | project folder, merged tree | 1 | yes, same rule | `scripts/temper:3405-3418` |
| Integrate | every scenario Test | project folder | 1 each | no | `scripts/temper:3419-3423`, `scripts/scenario_ops.py:133-155` |
| Build gate | none | | 0 | | `scripts/temper:3613-3716` |
| After Build (not Build's, for the total) | Check's suite with coverage, every scenario Test, the locked acceptance tests, mutation runs; started while Review reads (`check ahead`) | project folder | 1 each when the tree is unchanged | adopted, not cached | `scripts/flow.py:1375-1378`, `scripts/check_run.py:678-725,805-828` |
| After a step back to Build | Integration again when HEAD moved, and every scenario Test again | project folder | once per fix pass | Integration only on an unchanged tree | `scripts/temper:3316-3331` |

### Where the same thing runs more than once on the same code

1. **A scenario test owed by a task: task gate, group gate, integrate, Check.** None of the three Build runs is cached.
   The integrate run and the Check run are on the same merged tree when Review changed nothing. In my one task
   walk-through the scenario's command was also the task's Test, so the same command ran on the same task worktree
   twice back to back (GREEN, then the gate), and 5 times in Build in all; the ledger holds 5 rows because the task
   gate and group gate runs record none (appendix A1). **[run]**
2. **The full suite: the last group's Validate and Integration.** For one group, or a linear chain of groups, the
   merged tree is the last group's tree. On main both ran (`git show origin/main:scripts/task_ops.py`, `grouprun` and
   `integrun` call `run_cmd`). With PR #115 the second is reused only when the two command texts are identical and
   the tree has no untracked, not ignored file (`scripts/run_env.py:133-141`). I saw the reuse in both walk-throughs
   (`[temper: the same command passed on this same tree ...; reused, not run again]`). **[run]**
3. **The full suite again at Check**, with coverage, on the tree Integration just passed
   (`scripts/check_run.py:693`, `run_cmd`, no reuse). For a Maven project the plan gate forces each group's Validate
   to be `mvn verify` with JaCoCo on (`scripts/gate_rows.py:136-155`), so suite plus coverage runs once per group,
   then the suite at integrate, then suite plus coverage at Check. **[code]**
4. **Each group's Validate when groups depend on each other.** G2's tree contains G1; with the usual "whole suite"
   Validate (`reference/plan.md:331-333`) G1's tests run at G1's gate and again at G2's. In my two group run the
   suite ran at G1, at G2, and was reused at integrate. **[run]**
5. **The preflight runs every command on the base** before Build, where the suite passes by definition and the new
   tests fail by definition. Its use is to catch environment and command faults (`docs/decisions/0018`), at the price
   of one more suite run per plan revision that changes any command.

The repository's own note on this: "a measured run ran the same 11,600 tests about eight times"
(`scripts/run_env.py:121-123`, CHANGELOG 9.8.5 package 4). **[doc]**

---

## 5. Every way a task or a group fails, and what happens next

"Q" is the question text the person sees, as the CLI writes it. Rows marked [run] I produced with the CLI.

| # | Failure | What the CLI does | Next | Q the person sees | Where |
|---|---|---|---|---|---|
| 1 | Task gate FAIL, attempt 1 (no green run, last run not green, RED invalid, undeclared change, owed scenario test failed) | Worktree and branch discarded; attempt recorded | Retry on the task model in a fresh worktree; no question | none | `scripts/temper:3139-3186` [run] |
| 2 | Task gate FAIL, attempt 2 | Same | Escalate to `sonnet`; no question | none | same [run] |
| 3 | Task gate FAIL, attempt 3 | Group parked; the group's other tasks stop | Question | "Group G1 is parked (Task 3 failed 3 attempts). Run the task again?" Run the task again (Recommended) / Loop back to Plan / Save for later | `scripts/flow.py:2113-2129` [run] |
| 4 | The same group parks again after "Run the task again" | Reopen had reset the attempts to 1, so three more agents ran | Question | "Group G is parked again after a rerun (...). Loop back to Plan?" Loop back to Plan (Recommended) / Run the task again / Save for later | `scripts/flow.py:2114-2128`, `scripts/temper:2761-2779` [code] |
| 5 | RED invalid: exit 126, 127, a timeout, a signal, pytest exit other than 1 | Counts as a failed attempt | Row 1 | none | `scripts/task_ops.py:158-166,697-701` [code] |
| 6 | RED made on finished code (PR #115); stricter with `build.red-before-code: true` | Counts as a failed attempt; the finished work is discarded | Row 1 | none | `scripts/task_ops.py:176-192,689-694` [code] |
| 7 | COVERED: the RED run passed before any change | No attempt spent; worktree kept | Question; an armed run accepts it | "Task N (title): its tests already pass before any change, so an earlier task built it. ... Accept it as done?" Accept it as done (Recommended) / Run it again / Loop back to Plan / Save for later | `scripts/temper:3122-3127`, `scripts/flow.py:1832-1855` [code] |
| 8 | ENV (PR #115): the last GREEN failed with an environment pattern (wrong JDK, connection refused, `temper-setup: FAIL`, offline dependency) | No attempt spent; worktree kept | Question in every mode | "Task N (title) failed on the environment, not on its code: ... Repair the environment ..., then check it again?" Check it again (Recommended) / Save for later | `scripts/task_ops.py:758-767`, `scripts/preflight.py:73-96`, `scripts/flow.py:1857-1870` [code] |
| 9 | `temper task blocked N --needs PATH` (the test needs a file the task does not declare) | Gate fails once, group parks, no retry | Question | "Group G is parked: Task N needs X, which Task M declares (...). No attempt can build it as planned. Loop back to Plan?" | `scripts/task_blocked.py`, `scripts/temper:3147-3149`, `scripts/flow.py:2094-2112` [code] |
| 10 | A commit the CLI did not make in the task's range | Group parks at once; worktree kept; siblings' `task test` and `task gate` refused | Question | "Group G is parked: a task agent made commits the CLI did not (shas). Take them out, or keep them?" | `scripts/temper:3142-3146,3062-3068`, `scripts/flow.py:2078-2093` [code] |
| 11 | The task passed but its merge into the group branch conflicts | Group parks; worktree kept | Row 3's question with the merge reason | as row 3 | `scripts/temper:3225-3243` [code] |
| 12 | Manual task (`**Test:** manual`) | AWAIT | Question; an armed run parks | "Task N (title) is a manual task. Confirm by hand that each Case holds: ..." then a name question | `scripts/flow.py:1872-1899` [code] |
| 13 | Group gate FAIL after every task passed (Validate failed, or a group scenario test failed) | Gate records the reason, FAIL lines, count | Question; first time the fix is recommended | "Group G1 failed its check (...). What failed: .... Fix its merged work?" Fix the group's merged work (Recommended) / Run the group's tasks again / Loop back to Plan / More options (Change the group's command, Save for later) | `scripts/flow.py:1957-2046` [run] |
| 13a | The fix agent changed nothing (PR #115) | Check stays failed, `fix_empty` counted | Question | "... A fix agent changed nothing, so the cause is not in the group's code: the plan's command or the environment is .... Change the group's command?" Change the group's command (Recommended) / Loop back to Plan / Fix the group's merged work / More options | `scripts/group_fix.py:79-86`, `scripts/flow.py:2021-2045` [run] |
| 13b | Group gate timed out | `timeout_s` recorded | Question | "Run the gate again with twice the time (Recommended)" first | `scripts/flow.py:1990-1995` [code] |
| 13c | Group gate fails a second time, or a fix did not help | | Question | Loop back to Plan (Recommended), or Save for later when the one loop is spent | `scripts/flow.py:1996-2018` [code] |
| 13d | "Run the group's tasks again" | Every task's files reverted (one revert commit each), attempts reset | Every task of the group is built again | (the person chose it) | `scripts/flow.py:1987,2002`, `scripts/temper:2732-2779` [code] |
| 14 | `temper integrate` fails on the Integration suite, an Interfaces literal, or a merge conflict | Verdict recorded in `groups.json`; **`gate build` does not run** because a failed call stops its action (`scripts/go.py`, `commands/temper.md:128-132`) | `temper next` launches the Sonnet fix pass with "What failed: integrate: <reason>" (no FAIL lines of the suite); its after calls are `integrate`, `gate build`; when `integrate` fails again the same launch comes again. **No question, no bound.** The mod's driver hands the run back to the conversation on the failed call (`hooks/temper-mod/core/driver.ts:352,432`) | none | `scripts/flow.py:1655-1672`, `:1236-1246`. [run] for a failing suite: 3 of 3 consecutive `next` calls gave the same launch. [code] for the other two: the same branch of `build_work` |
| 15 | Integrate finds commits the CLI did not make on a group branch | Verdict FAIL with the shas | Question; an armed run parks | "Group G's branch holds commits the CLI did not make (...). Take them out, or keep them?" | `scripts/temper:3361-3378`, `scripts/flow.py:1772-1830` [code] |
| 16 | Build gate FAIL (a row fails after integrate passed) | Verdict FAIL | Question | "Build: the check failed (...). Run Build again?" Run Build again (Recommended) / Loop back to Plan / Override and continue / Save for later. After the same failure twice: "It failed the same way after it ran again. Save the run for later?" | `scripts/flow.py:753-765` [code] |
| 17 | Build gate fails only for rows nobody recorded | A "record pass" of the Build agent, once per round | no question | none | `scripts/flow.py:2415-2423` [code] |
| 18 | tasks.md has tasks and no groups | Build stops | Question | "Build stopped: tasks.md has tasks but no groups ..." Run Plan again (Recommended) / Save for later | `scripts/flow.py:1621-1633` [code] |
| 19 | Loop back to Plan (from any row above) | `groups.json` archived; every clean group and task worktree removed; branches moved to `refs/temper/kept/` | Plan, the plan gate (and its preflight), then **every** group and task again. Once per run (`scripts/loop_step.py:24-25`) | (the person chose it) | `scripts/temper:1276-1279,1297-1329` [code] |
| 20 | "Change" at a group question | Feedback rows; `group reopen G --task N` reverts the task's files and runs the whole task again with the feedback | A full task agent per changed task | "Which task changes?" | `scripts/flow.py:1928-1949`, `scripts/temper:2585-2796` [code] |
| 21 | "Change something" at the Build question, or a step back from Review or Check | Build's ledger is emptied on a step back (`scripts/temper:1876-1896`) | The fix pass (Sonnet, in place on the feature branch), then `integrate` (suite when HEAD moved, every scenario test) and `gate build` | (the person chose it) | `scripts/flow.py:1655-1672`, `scripts/temper:3316-3331` [code] |

What an armed run does: a failed or parked group parks the run (`scripts/flow.py:1973-1977,2074-2077`); under
`autonomy.policy: decide` (PR #115) it takes the recommended option of a failed group check when no typed answer is
needed (`:1963-1972`). Row 14 has no armed branch. **[code]**

Worst case for one task no model can build and whose agent does not record `task blocked`: 3 agents, a question,
3 more agents, a question, then the loop back to Plan and a rebuild of everything. The benchmark's case took two
Haiku and two Sonnet attempts before the loop back (`docs/evidence/haiku-sonnet-task-agents.md:92-97`). **[doc]**

---

## 6. What makes Build slow on a real project

| Cause | What the code does about it | What it does not do |
|---|---|---|
| **A slow suite** | Pass cache for Validate and Integration on the same clean tree (PR #115, `scripts/run_env.py:121-180`). The preflight fails a command over 300 s at the plan gate (`scripts/preflight.py:31,80-81`). Group gate limit 600 s with a "twice the time" option (`scripts/temper:2441`, `scripts/flow.py:1990-1995`). `temper plan patch` changes one command without a loop (PR #115, `scripts/plan_patch.py:1-12`). Agents are told never to run the full suite (`agents/build-task.md:46`). A passing run prints only its last 12 lines (`scripts/task_ops.py:113-121`). | No cache for scenario tests. No reuse between Integration and Check. No selection of the tests a change can affect. A Validate per dependent group. The timeouts are environment variables, not config keys (`scripts/temper:2441,3053,3408`). |
| **A JVM start per task** | A Maven task test runs only the declared test classes, offline, with the check plugins skipped, on `mvnd` when it is on PATH (`scripts/maven_loop.py:20-22,63-80`). | At least three Maven invocations per task (RED, GREEN, GREEN). The scenario tests at the task gate, group gate and integrate run the raw command, not through `maven_loop` (`scripts/scenario_ops.py:124-130`). Nothing installs or asks for `mvnd`. |
| **Worktrees without dependencies or build output** | Nothing in Build. `PYTHONPATH` puts the worktree first so an installed package resolves to the worktree's copy (`scripts/run_env.py:50-52`). The documents name the cost: "a project whose tests need an install step or a build cache pays it once per task" (`docs/grouped-build.md:129-132`, `docs/decisions/0011-grouped-build.md:134-135,163-164`). | A worktree is `git worktree add`: tracked files only (`scripts/temper:2401,2968`). `target/`, `build/`, `node_modules`, `.venv`, `.gradle` and untracked local config are absent in every task worktree, every group worktree and the preflight worktree. The first compile in each is cold. |
| **The `setup.run` line** (PR #115) | It runs in the same shell before the command (`scripts/run_env.py:102-118`). | It runs before **every** command the CLI runs (each task test, scenario test, Validate, Integration, preflight command), not once per worktree (`scripts/run_env.py:183-189`). |
| **Serial groups** | Independent groups run two at a time (`max-groups`). One group goes on without a question (`scripts/flow.py:1761-1765`). | A dependent group waits for the gate of the one before it and for the person's Continue (`scripts/temper:2370-2377`). |
| **Lock contention** | Calls nest; a stale lock is broken (`scripts/temper:315-330`). | The task gate holds the lock through its scenario tests (section 8). |
| **Retries and reruns** | `task blocked`, COVERED and ENV avoid some (section 5). | A failed attempt is rebuilt from nothing. |

### Is there any dependency or cache sharing between worktrees?

No. I searched `scripts/` for `node_modules`, `symlink`, `ln -s`, `.venv`, `.m2`, `CARGO_TARGET`, `GRADLE_USER_HOME`,
`copytree`: the only hit that shares anything is Check's mutation step, which links `node_modules` into its own copy
(`scripts/check_run.py:377-379`). What is shared in Build:

- git's object store (inherent to `git worktree`);
- `temper-results.json` in the git common folder, the pass cache of Validate and Integration
  (`scripts/run_env.py:144-146`);
- whatever a tool keeps outside the tree: the Maven local repository, a Python environment on PATH, Go's build cache.
  **[inferred]**
- Node: worktrees live under the project (`.claude/worktrees/`), so Node's upward lookup finds the project's
  `node_modules`. Nothing in the code arranges this. **[inferred]**

How much of the Java run's 3.2 hours was cold worktrees I could not determine: ADR 0018 says "most of 2.8 hours of
Build went to faults that existed before any agent wrote code" (`docs/decisions/0018-one-declared-environment-and-a-preflight.md:9-12`)
and gives no split.

### A squeeze the PR creates for a slow Maven project

- The plan gate row `maven group verify` requires every Maven group's Validate to be `mvn verify` with JaCoCo on
  (`scripts/gate_rows.py:136-155`, `agents/plan.md:95`).
- The row `maven filtered verify` fails a `verify` with `-Dtest=` under a JaCoCo BUNDLE rule
  (`scripts/gate_rows.py:158-191`).
- The preflight fails a command that takes over 300 s as an environment fault (`scripts/preflight.py:80-81`), and
  the Plan brief says to "pick commands that end within" it: "a group's Validate runs the tests that group can break,
  not a suite that takes longer" (`agents/plan.md:103-104`).

For a project whose full `mvn verify` takes over 300 s these three cannot all hold; the person has to raise
`plan.preflight-timeout` or record `plan.preflight-skip`, and over 600 s the group gate times out as well.
**[inferred from the three rules; not run]**

---

## 7. A small change: grouped Build against one agent editing in place

For a plan of one task in one group, after the plan is approved **[run]** unless marked:

| | Grouped Build | One agent in place (what the fix pass or vanilla does) |
|---|---|---|
| Agent launches | 2: the acceptance writer (Sonnet, 30 to 45 s [doc]) and the task agent | 1 |
| What the builder reads first | `agents/build-task.md` 6,043 bytes and `task show` up to 8,600 bytes | the files |
| Worktrees and branches | 2 made, 2 removed | 0 |
| Commits on the feature branch | 1 task commit and 1 `--no-ff` merge | 1 |
| CLI commands | 11, plus 7 `next` computations: about 7.5 s with a 0.1 s suite | 2 or 3 (`evidence run` red and green, a gate) |
| Runs of the task's own test | 5 in Build (RED, GREEN, task gate, group gate, integrate); the brief asks for a second GREEN | 2 (RED, GREEN) |
| Runs of the suite | Validate once; Integration reused when its text equals Validate's and the tree is clean, else a second run | 1 |
| Questions in Build | 1 (the Build question; the group question is skipped for one group) | 0 or 1 |
| On a failed gate | the worktree is discarded and a second agent starts over | the same agent goes on |

With a fast suite the grouping itself costs seconds, not minutes; what a small change pays is the extra agent, the
repeated test runs when the suite is slow or the build is cold, and a full restart on any gate failure.

### Is there a non grouped path left in the code?

Not for Build in a `/temper` feature run. `build.mode: per-task` and `reference/build-per-task.md` were removed
(`docs/decisions/0011-grouped-build.md:172-180`). A `tasks.md` with tasks and no groups stops Build with a question
(`scripts/flow.py:1621-1633`); with no tasks at all, `build_work` falls through to `gate build`, which fails
(`:1770`). One agent editing in place exists in four places:

1. **The fix pass** (`agents/build.md`, Sonnet): only after the groups are integrated, or when an earlier run built
   the code (`scripts/flow.py:1655-1672`).
2. **`/temper:fix`**: its Fix stage is one agent, and `gate build` has no integration row for a run without
   `tasks.md` (`scripts/temper:3692-3693`).
3. **"Make a small change"** at the Build, Review, Check and Commit questions: the conversation model edits, then only
   the touched checks run (`scripts/flow.py:900-974`).
4. **Intent returns TRIVIAL**: no run at all (`commands/temper.md:176-179`).

ADR-0017 (`docs/decisions/0017-a-request-that-arrives-as-a-spec.md`, a draft, nothing built) proposes a lighter route
in front of Build and says "Build, Review, Check and the commit are unchanged" (`:46-47`).

---

## 8. Where a document and the code disagree

| Document says | Code does | Label |
|---|---|---|
| The lock is "never held while a test runs" (`docs/grouped-build.md:154-155`, `scripts/temper:329-330`); "A held lock is only ever waited on for a git commit and a few small file writes" (`scripts/temper:3070-3072`) | `cmd_task_gate` takes the lock (`scripts/temper:3073-3080`), and the verdict it calls runs the owed scenario tests with a 600 s limit (`scripts/task_ops.py:706-708`). A sibling's `task start` waited 6.2 s behind a 6 s scenario test | [run] |
| A lock held past the limit "is written past with a WARN (fail open)" at `TEMPER_LOCK_MAX_S (60)` (`scripts/temper:326-327`) | PR #115: the call fails with exit 75 after 120 s and writes nothing (`scripts/temper:421-441`). With limits of 1 s and 3 s a sibling's `task test` ran its test and lost its row | [run] |
| "One human gate per group" (`docs/grouped-build.md:20`) | A plan with one group has no group question (`scripts/flow.py:1761-1765`) | [run] |
| "task agents are recorded by `temper task gate --ms`" (`docs/grouped-build.md:159-161`) | The chain agent gates its own tasks without `--ms` (`agents/build-task.md:13-14`), so `attempts[].ms` is empty and `temper group report`'s agent time, which sums it (`scripts/group_report.py:27-29`), misses them; the time goes into one `usage add --stage build` row for the first task of the chain (`scripts/flow.py:1717`) | [code] |
| The fix pass: "Run the full suite and return the summary panel" (`reference/build.md:153`) | Its own brief: "never the full suite; Check runs it once" (`agents/build.md:96`) | [code], two documents the same agent reads |
| "the tool's absence never fails a gate, a missing record does" about `code_search` in `build-context.json` (`agents/build.md:44-50`, `reference/build.md:29-35`) | No script reads `code_search`; only `deviations` is read (`scripts/spec_ops.py:71-77`); `gate_build` has no such row (`scripts/temper:3613-3716`) | [code] |
| `reference/build.md:27-63` describes "For each task in tasks.md" steps a to f | The fix pass never runs tasks (`agents/build.md:21-25`) | [code] |
| "task block 1536" bytes (`docs/decisions/0011-grouped-build.md:64-65`) | 2,048 (`scripts/temper:108`) | [code] |
| Task prompts say the acceptance tests "must ... pass at integration" (`scripts/flow.py:1436-1441`) | Integrate does not run them; only Check does (`scripts/check_run.py:723-725`) | [code] |
| The pattern test gives the agent "an existing test of the project as a pattern" (`docs/grouped-build.md:17-18`) | None is found for a JUnit name (`FooTest.java`), a `python -m unittest pkg.module` command or a Go package path (`scripts/task_ops.py:223,231-245`). `task show` printed no PATTERN TEST for `python3 -m unittest tests.test_mul` although `tests/test_calc.py` exists | [run] |

---

## 9. What a user or a planner has to hold in mind

- **Config keys of Build:** `build.grouped.task-model`, `.escalation-model`, `.max-parallel`, `.max-groups`,
  `.keep-days`, `build.red-before-code`, `models.build`, `models.acceptance`, `autonomy.max-blast-radius` (per
  group), `evidence.claimed-runs`, `plan.preflight-timeout`, `plan.preflight-skip`, the `setup:` block.
- **Environment variables:** `TEMPER_TASK_TEST_TIMEOUT_S` (600), `TEMPER_INTEGRATION_TIMEOUT_S` (3600),
  `TEMPER_LOCK_WAIT_S` (10), `TEMPER_LOCK_MAX_S` (120).
- **CLI commands:** `schedule`; `group start | gate | reopen | continue | report | fix`; `task start | show | test |
  gate | confirm | accept | retry | blocked`; `integrate`; `plan patch`; `acceptance ...`; `panel task`; `usage add`.
- **States:** a task is pending, running, passed, failed or covered, with the marks awaiting, env_fault and blocked
  (`scripts/task_cover.py:20-26`); a group is running, passed or parked, with gate, confirmed, fix, fix_tries,
  fix_empty, fails, parked_foreign.
- **Six kinds of test command** (section 4) and about a dozen kinds of question (section 5).
- **Size of the mechanism:** `scripts/temper:2201-3486` (about 1,290 lines of bash), `scripts/flow.py:1558-2129`
  (about 570 lines), and `task_ops.py` 775, `tasks_md.py` 249, `run_env.py` 205, `scenario_ops.py` 175,
  `maven_loop.py` 125, `task_cover.py` 104, `group_fix.py` 101, `group_report.py` 93, `task_blocked.py` 69,
  `task_rows.py` 60 lines.

---

## 10. What PR #115 changes in Build

From `git diff origin/main...HEAD` on the Build files:

- ENV verdict at a task gate (`scripts/task_ops.py:758-767`, `scripts/temper:3128-3132`, `scripts/flow.py:1857-1870`).
- Pass cache for Validate and Integration (`scripts/run_env.py:121-180`, `scripts/task_ops.py:464,488`).
- A RED made on finished code does not count; `build.red-before-code` (`scripts/task_ops.py:168-192,689-694`).
- A fix agent that changed nothing keeps the group's check failed (`scripts/group_fix.py:79-86`).
- `temper plan patch` and the "Change the group's command" option (`scripts/plan_patch.py`, `scripts/flow.py:2021-2034`).
- Interfaces match by shape (`scripts/task_ops.py:145-156,520`).
- FAIL lines prefer the build tool's summary (`scripts/task_ops.py:123-143`).
- The `setup:` block applied to every command and shown in every agent prompt (`scripts/run_env.py:76-118`,
  `scripts/flow.py:448-456`).
- The preflight at the plan gate (`scripts/preflight.py`).
- The lock fails a call instead of writing past it (`scripts/temper:421-441`).
- `autonomy.policy: decide` at a failed group check (`scripts/flow.py:1963-1972`).
- `temper integrate` runs Integration again when HEAD moved (`scripts/temper:3316-3327`).

It leaves untouched: one worktree per task, discard on failure, the three scenario runs, the group question, the
loop back that rebuilds everything, row 14 of section 5, and the lock held through the task gate's tests.

---

## 11. Waste, in the owner's terms

| # | What | Where | Kind | Size and its basis | Idea |
|---|---|---|---|---|---|
| W1 | A scenario test runs at the task gate, the group gate and integrate, uncached | `scripts/task_ops.py:706-708`, `scripts/temper:2504-2508,3419-3423` | time | 3 runs per scenario in Build on code that did not change, plus preflight and Check; 5 runs of one command in a one task Build [run] | Cache by tree and command as Validate is; run each once per tree |
| W2 | Validate per group, Integration, then Check's suite | `scripts/temper:2496,3405-3418`, `scripts/check_run.py:693` | time | at least 2 full suite runs on the finished code even with the PR's cache (the group's Validate, then Check), 3 on main or when the two command texts differ; one more per dependent group; "11,600 tests about eight times" in one run (`scripts/run_env.py:121-123`) [doc] | One run after the merge, with coverage, that integrate and Check both read |
| W3 | A cold worktree per task, group and preflight | `scripts/temper:2401,2968`, `scripts/preflight.py:189-210` | time | one checkout and one cold build each; not measured here; named in `docs/grouped-build.md:129-132` | One worktree per agent or per run; share build output |
| W4 | A failed task gate discards the work | `scripts/temper:3151-3153`, `scripts/task_ops.py:407-416` | time, tokens | one full task agent (122 to 193 s [doc]) per failed attempt, up to 3, and 3 more after "Run the task again"; 11 extra task runs and 2 escalations from one plan defect in one benchmark run (`docs/evidence/haiku-sonnet-task-agents.md:76-78`) | Keep the worktree and repair, as ENV already does |
| W5 | A loop back to Plan rebuilds every task | `scripts/temper:1276-1279,1297-1329` | time, tokens, loops | all tasks; a 12 task group was built 5 times in the failed run (CHANGELOG 9.8.4, `CHANGELOG.md:72-74`) [doc] | Keep the passed tasks whose block did not change |
| W6 | Integrate failure relaunches the fix pass with no question and no bound | `scripts/flow.py:1655-1672`, `commands/temper.md:128-132` | loops, reliability | one Sonnet agent per round, unbounded; 3 of 3 `next` calls [run] | Record the Build gate's FAIL after a failed integrate so the question and its "same failure" rule apply |
| W7 | The lock is held through the task gate's scenario tests | `scripts/temper:3073-3080`, `scripts/task_ops.py:706-708` | time, reliability | a sibling waits as long as the tests take (6.2 s behind 6 s [run]); past 120 s its call fails and its row is lost (shown with a 3 s limit [run]) | Run the tests outside the lock; lock only the commit and the record |
| W8 | A question per group, and a dependent group waits for it | `scripts/flow.py:1758-1766`, `scripts/temper:2370-2377` | questions, time | one question per group in a plan of 2 or more groups; idle time until the answer | Continue by itself on PASS, as one group and armed runs already do |
| W9 | Acceptance tests are written in Build and first run at Check | `scripts/flow.py:1394-1420`, `scripts/check_run.py:723-725` | loops | a Check to Build loop per failure: fix agent, integrate, Build gate, Check again; 12 and 16 fix passes after a step back in 9 runs per arm [doc]; three runs failed a locked acceptance test at Check (`docs/evidence/bench-2026-11.md:165`) [doc] | Run the locked command at integrate |
| W10 | Three attempts, and attempt 3 on the same model when the task model is Sonnet | `scripts/temper:573-589`, `scripts/tasks_md.py:209-210` | time, tokens | one or two agents per stuck task that the evidence says cannot help ("extra task runs the model caused: 0") [doc] | Two attempts; the second a repair on the kept worktree |
| W11 | The fix pass reads 21,968 bytes of brief and reference, part of it about a Build it does not do, with a record no gate reads | `agents/build.md:15-16,44-50`, `reference/build.md:27-63,153` | tokens, complexity | per fix pass launch; 1.3 to 1.8 launches a benchmark run [doc] | One short fix brief |
| W12 | "Change" at a group question reruns the whole task | `scripts/temper:2732-2779` | time | a full task agent per changed task and each task that shares its files | Send it to the fix agent on the group's tree |
| W13 | No pattern test for JUnit names, `-m unittest` modules, Go packages | `scripts/task_ops.py:223,231-245` | tokens, loops | every task of such a project explores the test conventions itself [run for unittest; regex checked for the others] | Use the `TEST_FILE` pattern of line 168 |
| W14 | The Maven rules and the preflight limit cannot all hold for a suite over 300 s | `scripts/gate_rows.py:136-191`, `scripts/preflight.py:80-81`, `agents/plan.md:95-104` | loops, questions | a failed plan gate until the person sets a key [inferred] | One rule: what Validate must cover, and one place that runs the full check |
| W15 | `setup.run` before every command | `scripts/run_env.py:102-118,183-189` | time | its duration times every CLI-run command; not measured | Once per worktree |
| W16 | Per task agent time is not recorded when the agent gates itself | `agents/build-task.md:13-14`, `scripts/group_report.py:27-29` | complexity | `temper group report` shows no agent time for those tasks [code] | Record the time at the after call |
| W17 | Per task worktrees and merges when one agent builds a chain | `scripts/flow.py:1558-1588`, `scripts/temper:2955-2972` | time, complexity | 11 of 18 benchmark runs were one agent, 3 to 6 tasks [doc] | A worktree per agent |

---

## 12. Changes I would make here, most valuable first

| # | Change | Effect | Risk | Effort |
|---|---|---|---|---|
| 1 | **Build in one tree when one agent builds.** One worktree per agent (a chain), or the feature branch itself when the plan is one chain; keep the per task RED, GREEN, gate and CLI commit; a worktree per task only when two or more agents really run at once. | Removes a checkout, a cold build, a merge and a worktree removal per task in the common case (11 of 18 benchmark runs were one agent); for one group the group gate and integrate become one check. Fewer states to explain. | A task's verdict today is "its own worktree's diff" (ADR 0011 amendment); in a shared tree the declared-file check must diff against the previous task's commit. A failed task can no longer be thrown away by deleting a folder. | M |
| 2 | **Run at the end of Build what Check runs.** After the merge: one suite run with coverage plus the locked acceptance tests; integrate and Check read that result while the tree is unchanged. | Acceptance and coverage failures are repaired inside Build instead of a Check to Build loop (1.3 to 1.8 fix passes after a step back per benchmark run); the suite runs once on the finished code instead of 2 or 3 times. | Build's gate gets as slow as Check's suite. A wrong acceptance test still needs the person; that question would move into Build. | M |
| 3 | **Each check once per tree.** Scenario tests through the pass cache; no group gate rerun of what a task gate passed on the same tree; no Validate for a plan of one group. | A scenario test drops from 3 Build runs to 1 per tree; a one group plan runs its suite once. | The cache key has no state outside the tree (a database, a clock); a flaky pass would be reused. | S to M |
| 4 | **Keep work on failure.** A failed task gate keeps the worktree and sends the gate's reason to a repair attempt; a loop back to Plan keeps passed tasks whose block (files, test, dependencies) did not change. | A retry becomes a short repair instead of a full agent; a re-plan rebuilds only what changed (the failed run rebuilt a 12 task group 5 times). | Kept work can be wrong for the new plan; needs a digest per task and a rule for tasks that depend on a changed one. A repair on bad work can go on longer than a fresh start. | M to L |
| 5 | **Close the two reliability holes.** A failed integrate records the Build gate's FAIL (with the suite's FAIL lines), so the person is asked and the "same failure twice" rule applies; the task gate runs its tests outside the lock. | Ends an unbounded series of Sonnet launches; parallel tasks no longer wait on, or lose rows to, a sibling's tests. | Low. The verdict must be read again under the lock before the commit. | S |
| 6 | **No question inside Build.** A passed group continues by itself, as one group and armed runs do today; the Build question stays the one place to ask for a change. | One question less per group in plans of two or more groups; a dependent group starts at once. | The person loses the point to stop before a dependent group builds on a wrong one. I found no count of how often "Change" is picked. | S |
| 7 | **Warm worktrees.** Share dependency and build output folders between worktrees, or keep one long lived build tree; run `setup.run` once per worktree. | Removes a cold build per task, per group and per preflight on compiled stacks. | Shared build output can leak one task's classes into another's test run; the declared-file check must not see linked folders as changes. | M |
| 8 | **Two attempts, one short fix brief, a pattern test for every stack.** Attempt 2 is the repair of change 4 on the stronger model; `agents/build.md` stops reading `reference/build.md`; `TEST_NAME` learns JUnit, RSpec and module names. | One agent less per stuck task; about 11 KB less per fix pass; fewer exploring turns in Java and unittest projects. | A task that would pass on a third attempt parks earlier; the evidence has no such case. | S |

---

## 13. Invariants a redesign must keep

1. The CLI computes every verdict from the evidence ledger; no model asserts one (`.claude/CLAUDE.md`, "The
   deterministic spine"; `scripts/temper:3613-3716`).
2. Only a test run the CLI made counts (`scripts/task_ops.py:678`, `scripts/temper:3633-3634`, CHANGELOG 9.8.5 Q3).
3. RED before GREEN for each task (`scripts/task_ops.py:680-703`) and at the Build gate (`scripts/temper:3637-3645`).
4. Task agents never commit; the CLI commits the declared files after its own verdict
   (`docs/decisions/0011-grouped-build.md:41-43`, `agents/build-task.md:47-48`).
5. A commit the CLI did not make is detected and stopped, never repaired (`docs/decisions/0011-grouped-build.md:70-82`).
6. A task changes only its declared files (`scripts/task_ops.py:736-742`); a file outside the plan needs the person's
   Drift decision (`agents/build.md:78-88`).
7. Build refuses a plan that changed after the person approved it, except the person's own `plan patch`
   (`scripts/temper:2163-2196`, `scripts/plan_patch.py:8-11`).
8. The CLI commits and merges only when the plan, intent and design gates are satisfied (ADR 0009,
   `scripts/temper:2907-2915`).
9. Never on a protected branch (`scripts/temper:2344-2358,3335-3349`); nothing is pushed; autonomy never re-plans and
   never makes the final commit (`docs/grouped-build.md:123-125`).
10. The orchestrator launches every agent; no agent launches another (`docs/decisions/0011-grouped-build.md:21-25,62-63`).
11. The person decides only in a question the CLI wrote; what comes next is `scripts/flow.py`, gate mechanics are
    `scripts/temper`, stage logic is the stage's brief (`.claude/CLAUDE.md`, "Known mistakes").
12. A test gets no credential-named variable (`scripts/run_env.py:33-53`).
13. Every write of a `.temper/` JSON file goes through the lock and an atomic replace
    (`docs/decisions/0011-grouped-build.md:34-37`, `scripts/temper:2216-2247`).
14. Uncommitted work is never removed (`scripts/temper:2283-2286,1306-1308`).
15. No file of the plugin over 256 KiB (`scripts/task_ops.py:9-10`).

---

## 14. What I could not determine

- How often a person picks "Change" at a group question. No document I read counts it.
- How much time a cold worktree costs on a JVM project; no measurement in the repository splits it out, and I ran no
  Maven build.
- The fix pass's own duration and cost; the benchmark reports it only as a count.
- Whether real plans, unlike the benchmark's, have tasks that run in parallel often enough to pay for a worktree per
  task.
- Whether the pass cache is safe for a suite whose result depends on something outside the tree; its key is the
  tree, the command and the setup block only (`scripts/run_env.py:133-141`).
- Whether Node projects really resolve `node_modules` from a worktree by the upward lookup; I reasoned it, and the
  TypeScript benchmark task passing is consistent with it.

---

## Appendix: what I ran

All with `<scratch>/repo/scripts/temper` (PR head), in projects under
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-build-side/`. The intent and
plan gates were run for real (fresh review and context check turned off in the throwaway config); the acceptance
writer was skipped with `temper acceptance skip`; I played the task agent by hand.

**A1. One task, one group (`proj`).** `gate plan` PASS, 25 rows, preflight "2 command(s): 1 passes, 1 needs new
code", 1.2 s. Then, with `time`: `next` 0.15 to 0.18 s (7 calls); `group start` 0.41; `task start` 0.77; `task show`
0.25 (845 bytes, no PATTERN TEST section); `task test` red 0.55 (exit 1); green 0.55; `task gate` 1.08; `panel task`
0.18; `group gate` 0.72; `group continue` 0.21; `integrate` 0.95 with "[temper: the same command passed on this same
tree at ...; reused, not run again]" and "scenario 'mul works': exit 0"; `gate build` 0.68, PASS with 5 rows. Ledger:
red, green, group, integration (reused), scenario. History: `feat(demo): Task 1 mul [G1]`, `merge(demo): group G1`.

**A2. Four tasks, two groups (`proj2`).** First action: "Build: Tasks 1, 2 on haiku, Task 3 on haiku" (two agents).
After G1's gate: "Group G1 (Core) passed its check. Continue?". `group start G2` before the answer: "FAIL: G2 depends
on G1, which the person has not continued yet". After G2: a second group question; `integrate` reused G2's Validate;
`gate build` PASS, "4 failing-first run(s), 4 passing run(s)".

**A3. Three failed attempts (`proj2`, Task 3 gated with no green run).** "NEXT: retry Task 3 on claude-haiku-5-5";
"NEXT: escalate Task 3 on sonnet" and the next action names `sonnet`, attempt 3; "NEXT: park group G1" and the
question "Group G1 is parked (Task 3 failed 3 attempts). Run the task again?". After `group reopen G1 --task 3` the
attempt counter is 1 again.

**A4. A failed group check (`proj3`, Validate that prints `FAIL: test_other broke`).** The question and options of
section 5 row 13; `group fix G1`; the next action is one `temper:temper-build` agent on sonnet with after calls
`usage add`, `group fix G1 --commit`; `group fix G1 --commit` with no change: "the fix agent changed nothing ... its
check stays failed", and the question of row 13a.

**A5. A failing Integration (`proj5`).** `temper go`: `action: error`, "the call temper integrate failed (exit 1)",
`ran: ['temper integrate']`. `next`: "Build: the fix pass is working on sonnet", prompt line "What failed: integrate:
integration suite failed (exit 1): ...", after calls `usage add`, `integrate`, `gate build`. Repeating the after
calls three times (`integrate` fails each time) gave the same action three times; `gates.json` held only `intent`
and `plan`.

**A6. The lock (`proj4`, `proj6`, scenario Test `sleep 6 && ...`).** `task gate 1` in the background took 7.1 s; a
concurrent `task start 3` took 6.2 s (0.77 s alone). With `TEMPER_LOCK_WAIT_S=1 TEMPER_LOCK_MAX_S=3`, a concurrent
`task test 3 --phase red` ran its test, then printed "FAIL: .temper/.lock is held (owner ...) past 3s; nothing was
written. Run the call again"; the ledger held no row of Task 3.
