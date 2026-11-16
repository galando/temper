# Verification: Build in one tree (draft items 5a, 5b, 5c, 5d)

Tree read: `/home/user/temper` at `10e965a` (PR #115 head, 9.8.5). All line numbers are of that commit. Nothing was
written or run in that folder. Experiments ran in a clone:
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-v-build-one-tree/repo`
(patch kept as `.../work-v-build-one-tree/one-tree-experiment.patch`; driver `chain.sh`, project maker `mkproj.sh`).

Marks: **[code]** read at the line. **[ran]** I ran it in the clone. **[reader]** measured by a reader, not repeated.
**[inferred]** reasoning, not run.

## Verdict

**Feasible with changes.** One tree per chain works with a small change when the tree is the group's worktree: a
21 line experimental patch built a three task chain in one worktree with the same commits, records and gate verdicts
[ran]. Four things in the draft need changing: "on the run's branch" is a different and much larger change than "in
one worktree"; "the setup line once per worktree" cannot work as worded; "two attempts, the second on the stronger
model" has no stronger model on risky plans; and the expected saving on the benchmark's small Python tasks is about
zero seconds, so the gain is on compiled stacks, where nothing is measured.

---

## 1. How a chain works today

- One agent already builds several tasks. `chain_of` puts into one agent every pending task of the group that waits
  only on the chain (depends on it, or shares a file with it) and clashes with no other ready or running task
  (`scripts/flow.py:1558-1588`). The launch carries `Tasks: N, M, K`, one `before` call `task start <first>`, and one
  `task gate N --if-running` after call per task (`scripts/flow.py:1706-1721`). The agent starts and gates each later
  task itself (`agents/build-task.md:12-15`). [code]
- Worktrees: **one per group plus one per task, T + 1 for a chain of T tasks in one group**, the task ones one after
  another. `task start` makes `.claude/worktrees/temper-{slug}-T{n}` on a new branch from the group branch
  (`scripts/temper:2955-2972`); a PASS commits there, merges the task branch into the group branch and removes the
  worktree and branch (`scripts/temper:3196-3261`); a FAIL removes them (`scripts/temper:3150-3153`, `:2997-3005`).
  The comment in the flow says so: "Each task keeps its worktree, its RED run, its CLI gate and its retry"
  (`scripts/flow.py:1703-1704`). [code]
- [ran] Baseline, three tasks 1 → 2 → 3 in one group: worktrees `temper-demo-T1`, `-T2`, `-T3` in turn beside
  `-G1`; history is three task commits fast-forwarded onto the group branch and one `--no-ff` group merge (no merge
  commit per task: the merge is a fast-forward while the group branch has not moved, `scripts/temper:3212-3213`).
  CLI time per task on the toy project: `task start` 0.67 to 0.76 s, `task gate` 0.89 to 0.96 s.

## 2. What each step assumes about a private worktree

| Step | Assumption | Where |
|---|---|---|
| `task start` | A new worktree and branch per task, from the group branch | `scripts/temper:2955-2972` |
| `task start` | The start snapshot is empty (`snap='{}'`): "the worktree is this task's alone, every dirty file in it is this task's change" | `scripts/temper:2952-2954, 2973` |
| `task start` | `start_sha` is the worktree's HEAD; `start_hashes` are the declared code files "as this attempt found" them | `scripts/temper:2974, 2984, 2990-2991`; `scripts/task_ops.py:419-423` |
| `task start` | Ready check, `git worktree add` and the record all under the run lock | `scripts/temper:2918-2925, 2937-2946, 2963-2972` |
| `task test` | Byproducts are the untracked paths that first appear during this run | `scripts/task_ops.py:428, 436-438` |
| verdict | Only rows of this task and this attempt since `started_at` count | `scripts/task_ops.py:676-679` |
| verdict | RED on code as found: `red_hashes` against the final files and `start_hashes` | `scripts/task_ops.py:176-192, 689-694` |
| verdict | Changed paths are the worktree's `git status` against the start snapshot | `scripts/task_ops.py:712-714` |
| verdict | Any commit in `start_sha..HEAD` the CLI did not record is this task's agent's | `scripts/task_ops.py:716-725` |
| verdict | "the worktree is this task's alone: every other changed path is an undeclared change of this task"; only this attempt's own byproducts are excused | `scripts/task_ops.py:733-737` |
| gate FAIL | The reset is "remove the worktree and the branch" | `scripts/temper:3150-3153, 2997-3005` |
| gate, kept cases | A foreign commit, COVERED, ENV, AWAIT and a failed merge keep the worktree | `scripts/temper:3122-3137, 3142-3146, 3229` |
| gate PASS | Pathspec commit of the declared changed paths in the task worktree, merge into the group branch, tick, remove | `scripts/temper:3196-3261` |
| group gate | Every passed task's `commit` is an ancestor of the group HEAD; no uncommitted tracked change in the group worktree; Validate runs there | `scripts/task_ops.py:535-541`; `scripts/temper:2485-2496` |
| group worktree | It "only takes merges and the group Validate" | `scripts/task_ops.py:212-213` |
| pass cache | A tree with any untracked, not ignored file is never stored or reused | `scripts/run_env.py:133-141` |

Why the private worktree exists: ADR 0011's amendment lists the defects of **parallel** tasks in one tree (start
snapshot of dirty paths, a sibling's files in a verdict, restoring undeclared paths on FAIL, innocent siblings failed
on a foreign commit) (`docs/decisions/0011-grouped-build.md:152-165`). A chain is serial: at most one task of it is
running, and each earlier one is committed. None of the listed defects needs a sibling-free tree to be private per
task; they need it to have one writer at a time. [code, inferred]

Precedent in the shipped code: the group fix agent already edits in the group worktree and the CLI commits its
change on the group branch (`scripts/flow.py:2048-2066`; `scripts/group_fix.py:71-94`). [code]

## 3. The narrowest change

### 3.1 One worktree per chain: build the chain in the group's worktree

Condition: the chain is alone in its group (no other ready or running task of that group). Then no task worktree, no
task branch and no merge exist for it; the group branch isolation, `integrate` and the foreign commit rules are
untouched.

What I ran (`one-tree-experiment.patch`, behind an environment switch; clone only):

| Run | Result |
|---|---|
| E1 baseline | 4 worktrees over the run; all gates PASS; Integration reused from the group's Validate |
| E2 patch, 21 lines in `scripts/temper` (start in the group worktree with a real start snapshot; PASS records the commit and skips the merge and removal; FAIL resets to `start_sha`) | All three tasks built in `temper-demo-G1`; same three commits and the same `--no-ff` group merge; `tasks.N.commit` set; task gates, group gate, `integrate`, `gate build` all PASS. `task start` 0.73 to 0.79 s, `task gate` 1.03 to 1.06 s: no faster on a toy |
| E3 same, project that does not ignore `__pycache__` | Task 2 FAILs: `undeclared change: src/__pycache__/calc.cpython-313.pyc`. Task 1's run left it, Task 2's run rewrote it. Baseline on the same project passes |
| E4 plus 4 lines in `task_ops.py` (byproducts of the group's earlier CLI runs count) | All PASS. But Integration **ran again** (baseline reused it): the group worktree now holds untracked byproducts, so the pass cache had no key for Validate |

The change, in order:

1. `scripts/flow.py` `build_work` (`:1698-1723`): when a chain is alone in its group, the `before` call is
   `task start N --chain N,M,K`. A bare `task start N` keeps today's private worktree, so every existing selftest
   case stays valid.
2. `scripts/temper` `_task_start_body` (`:2927-2993`): with `--chain`, or for a task recorded in the group's chain
   and no other task of the group running: use the group worktree and branch, take a real start snapshot
   (`_task_py snap`), `start_sha` = HEAD. Otherwise as today (the fallback).
3. `scripts/tasks_md.py` `_why_waiting` (`:149-165`): a task of a group whose tree a chain task is running in waits
   ("group G builds in one tree"). Without this rule the amendment's defects come back when `max-parallel` frees a
   slot mid chain.
4. `scripts/temper` `_task_gate_body`: FAIL resets the tree (`git reset --hard <start_sha>`, `git clean -fd`; ignored
   build output stays) in place of `_task_wt_discard` (`:3149, 3153`); PASS skips the merge (`:3214-3247`) and the
   removal (`:3261`) and records the commit as the task's.
5. `scripts/temper` `cmd_task_cover` retry (`:3458-3466`): reset the tree; today it removes the task worktree.
6. `scripts/task_ops.py` verdict (`:733-737`): a path an earlier CLI run in the same tree left untracked is a
   byproduct (E3, E4).
7. `scripts/run_env.py` `result_key` (`:133-141`): do not count CLI-recorded byproducts as dirty (E4), or the PR's
   reuse of Validate at `integrate` is lost for every project that does not ignore its test byproducts.
8. `agents/build-task.md:3, 12-15`: "each inside its own task worktree" becomes "in the folder `task show` names".
   The agent already works from the `WORKTREE:` line (`agents/build-task.md:27`), and the end to end helpers read
   the same line (`scripts/e2e/scenarios.ts:38, 46-68`), so neither needs new logic.

Proof kept: per task CLI-run RED and GREEN rows, the RED-before-code check, the declared files check, the owed
scenario tests, one CLI commit per task recorded in `cli_commits`, the foreign commit check, the group gate, the
`--no-ff` group merge, the Integration row, the scenario rows, the Interfaces check. Lost: the task branch and the
"merge(slug): Task N into G" commit that appears only when a sibling moved the group branch.

Size limit: `scripts/temper` is 260,504 bytes against a cap of 262,144 (`scripts/quality-check.sh:21-24`). My 21
lines took 1,004 of the 1,640 spare bytes [ran]. The real change must put its logic in `scripts/task_ops.py`
(44,468 bytes) and take as many bytes out of `scripts/temper` as it adds.

### 3.2 "On the run's branch" for a one chain plan: a different change

It removes the last worktree and gives the build the project's own installed dependencies and build output, which is
the strongest answer to cold builds. It also removes what the group branch gives today:

- A failed Build leaves the feature branch untouched; task commits on the feature branch would have to be undone at
  a loop back to Plan (`_groups_reset` archives and moves branches aside, `scripts/temper:1297-1329`; it has no code
  to take commits off the person's branch).
- The reset on a failed attempt would run `git reset --hard` in the person's checkout; with uncommitted work of the
  person there it must be a path restore (`scripts/task_ops.py:623-667`) and a refusal on a dirty tree.
- The CLI's task commit would go through the native pre-commit hook with run state present. It passes only through
  ADR 0009's build checkpoint carve out (`scripts/temper:4066-4110`; conditions in
  `docs/decisions/0009-build-checkpoint-commit-carve-out.md:17-25`). **Draft item 6d deletes that carve out as
  dormant.** In a worktree the hook finds no run and passes (`scripts/temper:2904-2906, 4059-4063`).
- `integrate` and the group gate would need a no-merge form; the foreign commit check reads `base..branch`
  (`scripts/task_ops.py:292-303`) and `spec commit` shas are not in `cli_commits` (`scripts/flow.py:525, 2205`).

Recommendation: ship 3.1 first. Decide 3.2 only after the scorecard shows what a cold group worktree costs on a
compiled project; if it is done, keep the carve out.

### 3.3 One group plan: group gate and integrate as one check

Today, one group: `group gate` runs Validate and the group's scenario tests in the group worktree
(`scripts/temper:2496, 2504-2508`), the flow continues by itself (`scripts/flow.py:1763-1765`), `integrate` merges,
runs Integration through the pass cache, runs every scenario test again and checks Interfaces
(`scripts/temper:3387-3429`). Integration is already reused when its text equals Validate's and both trees are
clean: seen in E1 and E2 [ran]. The merge commit has the same tree as the group tip when the feature branch did not
move, which is why the key matches.

Narrowest change: do not merge the two commands (each holds a record another row reads: `groups.G.gate` and
`integration`, `scripts/temper:3356-3360, 3692-3713`). Make the second a reuse: scenario tests go through
`run_cached` and write a row at the group gate (`scripts/scenario_ops.py:124-155`), and the key ignores recorded
byproducts (step 7 above). Then for one group `integrate` is a merge, three reused rows and the Interfaces check.
Proof kept: the group row, the Integration row marked `reused` with the time of the real run, one scenario row per
scenario, the Interfaces check, the merge commit, the integration verdict with its head. When Validate and
Integration are different commands both still run; that is not a duplicate.

## 4. The mod's write rules

None needed for 3.1. A write under `.claude/worktrees/temper-{slug}-G{n}/` or `-T{n}/` is already judged by its
worktree relative path (`hooks/temper-mod/core/rules.ts:206-218`, pattern `[GT] followed by (\d+)` at `:211`), and in Build that
rule allows the spec folder, test files and any file of the plan, not a task's own list
(`hooks/temper-mod/core/rules.ts:292-293`). The per task declared files check is the CLI's alone
(`scripts/task_ops.py:736-742`). For 3.2 the same Build rule already allows plan files in the project folder (the fix
pass relies on it). A new worktree name that is not `G<n>` or `T<n>` would need `rules.ts:211` and its tests changed:
avoid one. The driver reads a failed `task gate` after call as a verdict by its `NEXT:` line
(`hooks/temper-mod/core/driver.ts:77-81`); keep that line.

## 5. Keeping work on failure

What the next attempt gets today: `task show` prints `PREVIOUS ATTEMPT` with the reason and the first 20 lines of
the last recorded output (`scripts/task_ops.py:407-416, 753-756`). So the reason is already handed over; what is
missing is the tree. Two defects in what is handed over [code]:

- For a failed owed scenario test the output is dropped: `run_owed` returns only name, command and exit
  (`scripts/scenario_ops.py:115-130`), and the 20 lines shown are those of the last task test row, which is the
  passing GREEN.
- It is the first 20 lines of the output, where a test runner prints its failures last; `fail_lines` exists and is
  used only for groups (`scripts/task_ops.py:130-143, 471-472`).

What a kept tree needs:

1. The verdict's row window: today a RED of attempt 1 does not count for attempt 2 (`scripts/task_ops.py:676-679`).
   Record the first attempt of the kept tree and count CLI rows from it.
2. A kept start must not overwrite `snapshot`, `start_sha`, `start_hashes` (`scripts/temper:2984-2990`): a new
   snapshot would hold the kept work as "already there" and the commit would leave it out.
3. Hand over `fail_lines` of the failing run, and the failed scenario test's own output.

Which failures can be repaired in the kept tree (reasons of `scripts/task_ops.py:686-752`): no green run, final run
not green, an owed scenario test failed, an undeclared change. Which cannot: a RED that never ran the tests or was
made on the finished code (`:689-701`), because the code exists and no failing-first run can be made; these reset. A
foreign commit and `task blocked` park as today.

Reset of a broken tree: `git reset --hard <start_sha>` and `git clean -fd` in the chain's tree; `start_sha` is the
previous task's commit, so earlier tasks stay. Triggers: a failure class that cannot be repaired, the repair attempt
failing, `task retry`, the person's "Run the task again" (`group reopen` already restores to `start_sha` with revert
commits, `scripts/temper:2732-2779`).

Who repairs: the chain agent runs the gate itself (`agents/build-task.md:13-15`), so the reason is in its context
when the gate fails. The cheapest repair is the same agent in the same turn (`task start N` again on the kept tree,
fix, GREEN, gate), with no launch. Nothing in the driver continues a finished agent (cross check section 4, item 3),
so a repair after the agent returned is a new agent with `task show` as its only memory.

## 6. Warm worktrees

Today a worktree gets nothing: `git worktree add` only (`scripts/temper:2401, 2968`; preflight
`scripts/preflight.py:189-193`). The one link in the code base is Check's mutation copy, which links `node_modules`
(`scripts/check_run.py:377-379`). `PYTHONPATH` puts the folder the command runs in first
(`scripts/run_env.py:50-52`). [code]

The setup line cannot run once per worktree. `setup.run` runs in the same shell as each command so that its exports
reach it (`scripts/run_env.py:18-21, 102-118, 183-189`); the template's own example is
`eval "$(scripts/ensure-jdk24.sh --export)" && ...` (`templates/temper.config.default:163-166`). Run once, the
exports are gone. A once per worktree step needs its own key (for example `setup.worktree:`), run after
`git worktree add`, outside the lock, with a stamp.

Per stack [inferred unless marked]:

| Stack | Already shared | Safe to add | Not safe |
|---|---|---|---|
| Node | Module lookup walks up from `.claude/worktrees/...` to the project's `node_modules` | Nothing needed for plain projects | Workspaces: links in `node_modules` point at the main checkout's packages, so a task's change to a sibling package is not what its test loads. A `node_modules` link when the task changes the lockfile |
| Maven | `~/.m2` (outside the tree); `mvnd` when on PATH (`scripts/maven_loop.py:5-7`) | Nothing | Sharing or copying `target/` (stale classes; a fresh checkout's newer source times force a full compile anyway) |
| Gradle | `~/.gradle` dependency cache and daemon | The build cache (`org.gradle.caching`), content addressed and made for this; the project's choice, in its setup | Sharing `build/` or `.gradle/` |
| Python | An activated venv or interpreter on PATH | `uv sync` or similar in `setup.worktree` | A link to a `.venv` that holds an editable install of the project: with a `src/` layout the tests import the main checkout, since only the worktree root is put on `PYTHONPATH` |
| Rust | `~/.cargo` registry | A shared `CARGO_TARGET_DIR`: dependencies compile once; members rebuild per path | It serializes parallel builds on cargo's lock; can hit the 600 s task limit |
| Go | Build and module caches are global and content addressed | Nothing | |

The largest warm lever is 5a itself: tasks 2 to T of a chain compile incrementally in the tree task 1 warmed, with
no sharing between trees and so no leak. Any link the CLI or a setup step makes is an untracked path: the verdict
calls it an undeclared change (`scripts/task_ops.py:736-737`) and the pass cache refuses the tree
(`scripts/run_env.py:135-138`) unless the name is added to `info/exclude`, as the CLI does for the worktrees folder
(`scripts/temper:2388-2391`). A `node_modules/` line in `.gitignore` does not match a symlink of that name.

## 7. The lock

`cmd_task_gate` takes the lock around the whole body (`scripts/temper:3073-3080`); the body calls the verdict
(`:3115`), and the verdict runs the owed scenario tests with a 600 s limit (`scripts/task_ops.py:706-708`;
`scripts/scenario_ops.py:124-130`). A waiting call fails with exit 75 after 120 s and writes nothing
(`scripts/temper:421-441`), so a sibling's `task test` whose test already ran loses its row (the row is appended
under the lock at `:3057`). [code] Measured by a reader: a sibling's `task start` waited 6.2 s behind a 6 s scenario
test, and a RED row was lost with the limits shortened. [reader] `task start` also holds the lock across
`git worktree add` (`scripts/temper:2918-2925, 2963-2972`). The comments and two documents say the lock is never held
while a test runs (`scripts/temper:329-330, 3070-3072`; `docs/grouped-build.md:154-155`;
`docs/decisions/0011-grouped-build.md:34-37`).

Narrowest fix: before the lock, compute the verdict without the owed tests; when it would pass and tests are owed,
run them and keep the result with a fingerprint of the tree; then take the lock and run today's body with that
result passed in. The verdict under the lock stays the one that counts and is refused when the fingerprint moved.

## 8. Effort, tests, records, seconds

Effort (working days, one person, including CI waits of 30 to 60 minutes a round):

| Item | Size | Days | Files |
|---|---|---|---|
| 5a in the group worktree (3.1) | M | 3 to 4 | `scripts/temper`, `task_ops.py`, `tasks_md.py`, `flow.py`, `run_env.py`, `agents/build-task.md`, 2 docs, 1 new case file, `temper-cases-8.sh` |
| 5a on the run's branch (3.2) | L | 4 to 6 more | plus `integrate`, `_groups_reset`, the commit gate, ADR 0009 |
| 5b keep work, repair | M | 3 | `scripts/temper`, `task_ops.py`, `scenario_ops.py`, `tasks_md.py`, `flow.py`, `agents/build-task.md` |
| 5c `setup.worktree` key and `info/exclude` for links | S | 1 to 2 | `run_env.py`, `scripts/temper`, template, ADR 0018 |
| 5d tests outside the lock | S | 1 | `scripts/temper`, `task_ops.py`, comments, 2 docs |
| Total without 3.2 | M | 8 to 10 | about 14 files |

Seconds saved, with the basis:

- 5a on the benchmark's small Python projects: about 0. `task start` and `task gate` take the same time in one
  tree as in three (E1 against E2), and `git worktree add` takes 0.05 s on a 575 file repository [ran].
- 5a on a compiled project: (T - 1) cold builds per chain, and the agent no longer reads its files again under a
  new path for each task. **Not determined**: no document splits the Java run's 25 minutes a Build task (cross
  check section 4, item 7).
- 5b: one task agent per repairable failed gate (122 s an agent on 9.8.0; 32 to 54 s a task on Haiku by the
  build-side reader's division), less the repair. On the 18 run benchmark this is 0: no retry was caused by the
  model, and the 11 extra task runs came from a plan no model could build
  (`docs/evidence/haiku-sonnet-task-agents.md:76-78, 92-97`). Frequency on real runs: not determined.
- 5d: 0 with one agent (11 of 18 benchmark runs). With siblings, up to one scenario test duration per gate, and no
  lost row when a scenario test takes over 120 s.
- One group, one check: Integration is already reused; what remains is each scenario test running three times in
  Build. Saving: twice the scenario tests' duration per run.

So WP5 will not move the draft's pass lines on the current benchmark. Its case rests on a compiled stack fixture
that WP1's scorecard does not yet name.

Decision records and documents to change:

- `docs/decisions/0011-grouped-build.md`: a third amendment (one tree per chain; a private worktree only for tasks
  that run at once in a group); D-03 (`:57-59`) if the ladder changes; `:134-135, 163-164` (setup paid per task).
- `docs/decisions/0013-...md:130` ("there is no lighter path").
- `docs/decisions/0018-...md` if `setup.worktree` is added.
- `docs/decisions/0009-...md` only for 3.2.
- `docs/grouped-build.md:76-84, 129-132, 154-155`; `agents/build-task.md:3, 12-15`; `CHANGELOG.md`; the comments at
  `scripts/temper:326-330, 3070-3072`; `scripts/task_ops.py:212-213`.
