# Verification: checks once, and early (draft items 3a, 3b, 3d)

Base: `/home/user/temper` at `10e965a` (PR #115, 9.8.5). All line numbers are of that head. Nothing was written or run
in that folder. One experiment ran in a clone: `.../scratchpad/work-v-checks-once-early/exp.py` (toy project in
`.../work-v-checks-once-early/toy`, the PR's `run_env.py` and `check_run.py` imported from the clone).

Marks: **[code]** read at the cited line. **[run]** the experiment. **[inf]** inferred, not run. **[reader]** a
reader's measurement I did not repeat.

**Verdict: feasible with changes.** The three mechanisms can be built on what exists, but three things in the draft
do not hold as worded: (1) neither of the two existing tree digests survives a test byproduct, so "one digest" is new
code, not a choice between the two; (2) "once per tree" saves almost no suite runs unless the suite command has one
owner (today the plan writes one text and Check runs another); (3) a baseline of the project's own command does not
replace the preflight for commands the plan invents, and needs three results, not two.

---

## 1. Every call site that runs a project command

One runner already exists: all 14 sites go through `run_env.run_cmd` (`scripts/run_env.py:183-205`); two of them
through `run_cached` (`:149-180`). [code: `grep run_cmd( scripts/*.py`]

| # | Where | What runs | On which tree, in which place | Cached? | Evidence |
|---|---|---|---|---|---|
| 1 | Plan gate, `preflight.py row` | every distinct Validate, task Test, Integration and scenario Test command | HEAD, a detached worktree under the system temp folder | stored whole in `.temper/preflight.json` under (HEAD commit, command texts, setup, limit); not per command | `scripts/temper:3600`; `scripts/preflight.py:44-61, 143-147, 189-202` |
| 2 | `acceptance lock` (`cannot_run`) | the acceptance command, expected to fail | base plus the spec folder, project folder | no | `scripts/check_run.py:471-483, 509` |
| 3 | `task test` RED and GREEN | the task's Test (Maven through `maven_loop`) | task worktree, uncommitted | no | `scripts/temper:3053`; `scripts/task_ops.py:433, 435`; `scripts/maven_loop.py:105` |
| 4 | `task gate` verdict | each scenario Test the task owes | task worktree, uncommitted, under the run lock | no, no row | `scripts/task_ops.py:706-708`; `scripts/scenario_ops.py:124-130` |
| 5 | `group gate` | the group's Validate | group worktree, tracked files clean | **yes** (pass only, clean tree only) | `scripts/temper:2496`; `scripts/task_ops.py:464` |
| 6 | `group gate` | each scenario Test owned in the group (those of row 4 again) | group worktree | no, no row | `scripts/temper:2505`; `scripts/scenario_ops.py:107-112, 162-164` |
| 7 | `integrate` | the plan's Integration command | merged tree, project folder | **yes**, same rule | `scripts/temper:3408`; `scripts/task_ops.py:488` |
| 8 | `integrate` | every scenario Test | merged tree, project folder | no; one row each | `scripts/temper:3422`; `scripts/scenario_ops.py:133-155` |
| 9 | `integrate` when already PASS | Integration again if HEAD moved; **every scenario Test again, always** | project folder | suite: yes; scenarios: no | `scripts/temper:3316-3331` |
| 10 | `check ahead` / `check run` | the suite in its coverage form, then the coverage report | project folder | no; the ahead run is "adopted" by a second digest | `scripts/check_run.py:691-697, 780-829`; `scripts/flow.py:1375-1378` |
| 11 | same | every scenario Test | project folder | no | `scripts/check_run.py:715-722` |
| 12 | same | the locked acceptance tests | project folder | no | `scripts/check_run.py:656-674, 725` |
| 13 | same | the test command once per mutant, up to 40, budget 300 s | a copy in the temp folder | no | `scripts/check_run.py:358-398` |
| 14 | same, fix runs | the test command on the code before the fix | temp worktree of `base_sha` | no | `scripts/check_run.py:402-427` |

Also: `detect` probes `pytest --version` and `coverage --version` on each call (`scripts/check_run.py:46-50, 87, 99`),
and `flow.cli_check` calls `detect` (`scripts/flow.py:1551-1556`). Tool probes, not project commands.

### Count for a clean two group run today

Shape: G = 2 with G2 depending on G1, one task a group, S scenarios each owed by one task, the same text for both
Validate lines and for Integration, the project ignores its byproducts.

| | Runs today | Trees they ran on |
|---|---|---|
| Suite (no mutants) | **4 to 5**: preflight 1, G1 gate 1, G2 gate 1, integrate 0 (reused: G2's tree is the merged tree) or 1, Check 1 | base, G1, G2 = merged |
| Suite, when the project does not ignore a byproduct | **6**: integrate is not reused (row A below) and the ahead run is thrown away, so Check runs twice (row B) | |
| Each scenario Test | **5**: preflight (base), task gate, group gate, integrate, Check. S × 5 in all | base, task = group, merged |
| Acceptance tests | 2: at the lock (cannot pass yet), at Check | |
| Mutants | up to 40 suite runs (a reader: 13 changed lines gave 20) | merged, copied |
| Task tests | 3 a task by the brief (RED, GREEN twice) plus the preflight's run of each on the base | |

On **one** tree the repeats are: the suite at integrate and at Check on the merged tree (2, or 3 when the ahead run is
discarded), and each scenario Test at integrate and at Check (2), plus task gate and group gate when the task is the
group's last change (2 more). The draft's "4 to 8 times on one tree" counts runs across three or four different trees.

### Three facts from the experiment [run]

- **A.** `run_cached` on a project that does not ignore `__pycache__`: first call ran, key before the run
  `f87f234bda…`; second call: key `None`, ran again. Confirms the reader's result (`scripts/run_env.py:135-138`).
- **B. New.** `check ahead` discards its own run whenever the suite leaves an untracked, not ignored file that is not
  named `__pycache__`. `check_run.ahead` compares `tree_digest` before and after its own run (`scripts/check_run.py:788,
  797`), and the digest includes untracked files (`:764-771`). With a test command that leaves a `.coverage` file:
  `ahead.json` was not written on the first run, nor on a second run with the file already there (its content changes).
  With a command that leaves only `__pycache__`: written. The Python default is `python3 -m coverage run`
  (`scripts/check_run.py:99-108`), which writes `.coverage` in the project folder; coverage.py is not installed here, so
  that its file content differs between runs is [inf]. Effect: on such a project Check's whole run (suite, scenarios,
  acceptance, up to 40 mutants) happens twice, once in the background and once at `check run`.
- **C.** `tree_digest` hashes the HEAD **commit** (`scripts/check_run.py:763`): a group worktree and the merged project
  folder with the same `HEAD^{tree}` gave different digests. `result_key` uses `HEAD^{tree}` and matched, but returned
  `None` for the project folder because of byproducts.

---

## 2. One definition of "same tree"

**Definition.** The git tree object of: the work tree as it is (tracked files with their current content, plus every
untracked file git does not ignore), minus `.temper/`, `.claude/` and the paths recorded as byproducts of the runner's
own runs.

**How.** Copy the worktree's index to a temp file, `GIT_INDEX_FILE=<copy> git add -A -- . ':(exclude,top).temper'
':(exclude,top).claude' <byproduct excludes>`, then `git write-tree`. The real index is not touched.

**What the experiment showed [run]:**

| Check | Result |
|---|---|
| Clean tree, byproducts left out: equals `HEAD^{tree}` | yes |
| Byproducts kept in | differs (this is today's failure) |
| Group worktree against merged project folder (different commits, same content) | equal |
| An uncommitted edit of a tracked file | differs |
| A new untracked test file | differs |
| Real index after the call | unchanged |
| Cost on this repository (575 files) | 0.011 s |

**Byproducts.** The notion exists: `task_ops.py testrun` records "untracked paths that first appear during this CLI
run" on the row (`scripts/task_ops.py:428, 436-438, 453`) and the task verdict leaves them out (`:735-737`). The runner
does the same for every run and keeps the set in the store. An untracked path that a task declares is committed by the
task gate (`scripts/temper:3205-3206`) and is then tracked, so it counts again.

**Where the store lives.** Where it is now: `temper-results.json` in the git common folder
(`scripts/run_env.py:124, 144-146`). That is right: one file for every worktree of the clone, outside every work
tree (it can never dirty one), and `state clear` does not remove it. It has no lock (read, change, `os.replace`): two
group gates at once can lose an entry, which costs one rerun.

**What must be in the key** (today: tree, command list, setup block, `scripts/run_env.py:141`):

| Input | Today | Needed |
|---|---|---|
| Tree | `HEAD^{tree}`, clean only | the digest above |
| Command text | yes | yes |
| Setup block (`run`, `env`, `services`, `tools`) | yes | yes |
| Folder inside the repository (`git rev-parse --show-prefix`) | no; a monorepo prefix is added to the path (`scripts/temper:2256`) | yes |
| Tool versions | no | the first version line of each program the command starts and each `setup.tools` entry (`doctor.version`, `scripts/doctor.py:37-49`) |
| Inputs outside the digest | no | for the acceptance command: the lock's file digests (`scripts/check_run.py:666-667`), since the tests live under `.temper/` |
| Time limit | no | no: a pass is a pass |
| The rest of the environment, services, the clock, ignored folders (`node_modules`, `target/`) | no | not knowable; say so in the row (`reused` and its time are already recorded, `scripts/task_ops.py:470, 493`) |

Not handled by this digest: a dirty submodule, a sparse checkout, and `git add` writing a blob for each changed file
into the object store (fix: a temp `GIT_OBJECT_DIRECTORY` with the real one as alternate). [inf]

---

## 3. The baseline

**Where it starts.** As a `before` call of the Intent agent, the pattern `check ahead` uses for Review
(`scripts/flow.py:1375-1378`) and `acceptance start` uses (`:1417`). `agent()` gives Intent no `before` today
(`:1119-1136`). The driver runs every `before` call before it starts an agent, and hands the run back when one fails
(`hooks/temper-mod/core/driver.ts:401-412`); the page does the same (`commands/temper.md:81`). So the call must start
a background process and exit 0 whatever happens, as `check ahead` does (`scripts/temper:4955`). Not `state init`: it
runs before the slug's spec folder and the setup offer exist, and a door or a fix run has no Intent launch, so the plan
gate row must also start it when no result is stored (as `preflight.py row` computes on a miss, `scripts/preflight.py:167-174`).

**Where it runs.** A detached worktree of HEAD under `.claude/worktrees/`, beside the group and task worktrees
(`scripts/temper:2380, 2957`). The preflight runs under the system temp folder (`scripts/preflight.py:191-193`), where
a lookup that walks up to the project folder (a `node_modules`, a `conftest.py`) finds nothing; Build's worktrees are
inside the project. Through `run_env.run_cmd`, so the setup block applies.

**What it runs.** The command the later gates run, in its coverage form when there is one
(`check_run.detect`, `scripts/check_run.py:76-145`). Two corrections to "the project's own test command":
- For Maven `detect` gives `mvn -q test` (`:141`) while the plan gate forces each Maven group's Validate to be
  `mvn verify` with JaCoCo on (`scripts/gate_rows.py:149-155`). A green `mvn test` proves less than the gates ask.
- The coverage form gives the base coverage that "no drop" needs (section 5), and the suite's seconds, which today's
  fixed limits lack: the group gate allows 600 s (`scripts/temper:2441`) and offers "twice the time" after a time-out
  (`scripts/flow.py:1995`).

**Is a binary rule enough? No: three results, and the reason as text.**

| Result | When | What the run does |
|---|---|---|
| green | exit 0 | goes on; later failures of this command are the change's. Its pass is the store's entry for the base tree |
| red | any other exit | one question before Plan is launched (Plan is the $0.75 to $1.13 step). The reason shown is `preflight.env_fault`'s text when it finds one (`scripts/preflight.py:73-96`), else the output tail. Options: repair the environment (the existing setup offer, `scripts/flow.py:1184-1220`), go on with the suite as information only for this run, or stop |
| unknown | no test command, still running, timed out, skipped with a reason | never blocks. Shown in the plan approval. Today's behaviour applies |

A red base cannot be "go on and judge new failures only": that needs the set of failing tests per stack, which nothing
parses. The honest option is "the suite does not gate this run"; task tests, scenario tests and acceptance tests still do.

**A suite of 20 minutes.** Intent plus Plan take about 3 to 5 minutes (budget rows 2 and 8), so the baseline is not
done at the plan gate. The plan gate must not wait (it would hold an Opus turn open, the fault of budget row 9). The
approval shows "baseline: running"; the first group gate, which runs a suite of the same length anyway, reads the
result. Today the same project fails the preflight at 300 s as an environment fault (`scripts/preflight.py:31, 80-81`)
until the person writes `plan.preflight-skip` (`:152-157`), then times out at the group gate at 600 s.

**No test command.** `detect` returns `{}` (`scripts/check_run.py:97, 118, 145`): nothing to run at run start. After
Plan, the plan's `**Integration:**` line is the full suite by contract (`reference/plan.md:313`): run that once on the
base at the plan gate. That is the one part of the per command preflight that stays.

**What of `preflight.py` stays, and what goes.**

| Part | Stays? | Why |
|---|---|---|
| `env_fault` (`:73-96`) | stays | three callers: `classify`, Check's `setup_fault` (`scripts/check_run.py:186`), the task verdict's ENV (`scripts/task_ops.py:764`) |
| `programs` (`:64-70`) | stays, and gets a new use | "the program resolves" is **not** a row today; `programs` is used only to name a `command not found` at exit 127 (`:90-93`). The draft's "keep" is new code |
| The store and its key (`:143-182`) | goes into the runner's store | one store |
| `verify` for a candidate setup block (`:227-243`) | stays, reading the baseline's fault | `doctor` and the setup offer use it (`scripts/flow.py:1189, 1211`) |
| Running each task Test and scenario Test on the base | goes | they fail there by design; the last line of `classify` passes every such failure (`:115`) |
| The four classes and `CMD_PATTERNS` (`:33, 36-37, 99-115`) | go, except as reason text | |
| Running a plan-written Validate or Integration on the base | **stays for a command whose text is not the baseline's** | see below |
| The static Maven row (`scripts/gate_rows.py:149-155`) | stays | it is what catches the measured fault |

**What the baseline does not catch.** ADR 0018 names three faults of the measured run
(`docs/decisions/0018-one-declared-environment-and-a-preflight.md:9-12`): the JDK (a baseline catches it), a Maven
check that skipped `cd backend && mvn` lines (static), and "a filtered `mvn verify` that could never meet a JaCoCo
bundle rule". The third is a command the plan wrote. The project's own command passes on the base; only the static
Maven row, or a run of that command, finds it. So: a plan command that is the baseline command needs no run; any other
Validate or Integration command gets one run on the base in the baseline worktree, judged only for an environment
fault, and after the approval rather than inside the Plan agent's gate call. A wrong flag in a task Test is found at
the first RED instead ("the RED run did not run the tests", `scripts/task_ops.py:697-701`), which costs a task attempt.

---

## 4. Coverage and the acceptance tests inside `integrate`

**The precondition the draft leaves out: one owner of the suite command.** `integrate` runs the plan's
`**Integration:**` text (`scripts/temper:3355, 3408`); Check runs `detect`'s command in its coverage form
(`scripts/check_run.py:691`). Different texts are different keys, so "Check reuses the pass" never fires. Either the
CLI's command replaces the plan's Integration line whenever `detect` finds one, or `integrate` runs both. Only the
first saves a run.

**`integrate` after the change** (`scripts/temper:3405-3423`), in this order, through the runner, rows into the Build
ledger: the suite with coverage; every scenario Test; the locked acceptance tests. A failing suite fails the
integration as today (`:3413-3417`). A failing scenario or acceptance test records a row and leaves the verdict PASS,
as scenario tests do today (`:3419-3420`), so the Build gate fails on the row.

**What the Build gate then reads** (`gate_build`, `scripts/temper:3613-3716`): as today RED then GREEN, the task
rows, the criteria rows, feedback, the integration verdict; and new, the acceptance row (the logic of
`:3932-3945`, read from the Build ledger) and a coverage row. Both belong in `gate_rows.py build-rows`
(called at `scripts/temper:3651`), not in the bash file: `scripts/temper` is 260,504 bytes against a cap of 262,144.

**What moves with it.** The acceptance failure path lives at Check: `acc_failure` reads Check's failed rows
(`scripts/flow.py:1445-1457`), then a triage agent and the "Correct the acceptance test" option (`:1459-1485`). All of
it must read Build's rows and hang on the Build question. With it, a failing acceptance test reaches the Build fix
pass (`scripts/flow.py:1655-1672`) before Review, which is the point of the move; the builders are already told the
tests "must pass at integration" (`:1436-1441`) although nothing runs them there.

**What Check still does.**
- For a grouped run whose tree did not change after `integrate`: records the suite, coverage, scenario and
  acceptance rows from the store, marked reused, so `gate_check`'s rows keep their evidence
  (`scripts/temper:3869-3945`). No command runs.
- The mutation score (`scripts/check_run.py:732-740`); draft item 3h decides its fate.
- Everything, for real, in a run with no `integrate`: a `/temper:fix` run has no tasks.md
  (`scripts/temper:3692`), and a door's run on earlier built code skips it (`:3618-3631, 3704`).
- Everything, for real, on any tree that changed after `integrate` (a repair at Review).
- The regression proof of a fix; `code` and `metric` criteria through the Check agent
  (`scripts/flow.py:1361-1373`); the criteria evidence row (`scripts/temper:3958-3964`).

**`check ahead`** shrinks to the mutation run and a warm store. `adopt`, `ahead_paths` and `tree_digest`
(`scripts/check_run.py:757-829`) go; the wait for a run in flight (`:810-815`) moves into the runner.

---

## 5. Coverage on changed lines: is the data there?

`changed_lines` exists and is used for the mutants (`scripts/check_run.py:216-238`): added or changed lines of
non-test files with a `.py` or C-style extension, against `base_sha`.

| Stack or kind (`detect`) | What the run leaves today | Per line data? |
|---|---|---|
| python, coverage.py | `coverage json` (`:107`) with executed and missing lines per file | **yes, as recorded** |
| go | `-coverprofile` (`:135-136`), blocks with line ranges | derivable; the paths are import paths and need go.mod's module name |
| node, jest | `json-summary` (`:122-123`): totals per file | **no**; one more reporter (`lcov` or `json`) gives it |
| node, vitest | `json-summary` (`:125-126`) | no; same |
| node, c8 | `json-summary` (`:128-129`) | no; same |
| node, `node --test` | a printed table, no file (`:130-131`) | no |
| configured (`check.commands.coverage`) | a printed total line (`:79-83, 166`) | no; needs a second key naming a report file |
| rust | no coverage command (`:139`) | no |
| maven | none (`:141`) | no (a JaCoCo XML has it when the pom makes one) |
| gradle | none (`:144`) | no |

So changed line coverage is ready for one kind of nine, close for four, and absent for four. "No drop" needs a base
value: a total exists for the first seven rows, and only if the baseline runs the coverage form. For rust, maven and
gradle there is nothing to compare, and today that fails the gate (`scripts/check_run.py:712`;
`scripts/temper:3909-3913`); "information" is the only rule that fits.

A caution on "no drop": on a project at 92%, new code covered at 85% lowers the total, so "no drop" fails what an 80%
rule on the changed lines passes. Order the rules: changed lines against the threshold where line data exists; else
the total not below the base by more than a set tolerance; else information.

---

## 6. Flaky tests: what one cached pass hides

Today the suite runs 4 to 5 times in a clean two group run, plus once per mutant. A test that passes 4 times in 5
gets through four runs 41% of the time; the other 59% it stops a correct run, and in a mutant run its failure counts
as a caught bug (`scripts/check_run.py:389-390`).

With one run per tree a cached pass hides:

1. **A test that does not always pass** (order, time, randomness, network). A one group run would see it once.
2. **Retry until green, then frozen.** Only a pass is kept and a failure always runs again
   (`scripts/run_env.py:164, 168`). "Run again" on an unchanged tree turns a flaky failure into a pass that every
   later call reuses.
3. **State outside the tree**: a database or service, the date, tool versions, and every ignored folder
   (`node_modules`, a stale `target/classes`). None is in the key.
4. **The place.** A pass in a group worktree is reused for the project folder (already so in the PR:
   `scripts/task_ops.py:464` to `:488`). A test that depends on an absolute path or on what sits above the worktree
   is not run where the code will live.
5. **Order between commands.** A scenario test that passes only after the suite left a file is no longer run after it.

What to do, cheaply: keep the last failure per key beside the pass (not reusable); a failure followed by a pass on the
same key marks the entry `flaky`, and the commit question and the report say so. Every reused row already carries
`reused` and its time. This is the same guarantee one CI run gives; it is weaker than today's accidental repeats and
should be said in `docs/trust.md`.

---

## 7. Patch outline, tests, expected saved runs

### The patch, in order

1. **`scripts/run_env.py`**: `tree_key(wt)` (section 2) replaces the clean tree rule of `result_key` (`:133-141`);
   the byproduct set, taken from the `untracked` before and after logic of `scripts/task_ops.py:428, 438`; the key
   gains the folder prefix, tool versions and caller inputs; the entry gains seconds, an `extra` dict (the coverage
   value) and the last failure; one run in flight per key. `run_cached` keeps its name and return shape.
2. **Call sites**: `scripts/scenario_ops.py:127, 145`; `scripts/check_run.py:671` (inputs: the lock's digests),
   `:693-696`, `:720`. Left uncached on purpose: task RED and GREEN (`scripts/task_ops.py:433, 435`), `cannot_run`
   (`scripts/check_run.py:475`), mutants (`:386`), the regression proof (`:421`).
3. **`scripts/check_run.py`**: delete `tree_digest`, `ahead_paths`, `adopt` (`:757-829`) and the `adopt` call in
   `main` (`:857-858`); `ahead` becomes `run` into a throwaway ledger; a new entry `build-checks` that runs the suite
   with coverage and the acceptance tests for `integrate`; the coverage rule and one more reporter for jest, vitest and
   c8 (`:122-129`); a reader of coverage.py's and go's line data.
4. **`scripts/temper`**, byte neutral: `cmd_integrate` (`:3405-3423` and `:3316-3331`) calls `build-checks` in place
   of the `integrun` and `scenario_ops.py integrate` lines; `gate_check`'s coverage row (`:3904-3914`) takes the new
   rule; the preflight line (`:3600`) calls the baseline row; `_RUN_FILES` (`:632-634`) gains the baseline's file.
5. **`scripts/gate_rows.py`** `build-rows`: the acceptance row and the coverage row for the Build gate.
6. **Baseline**: grow `scripts/preflight.py` (`start`, `row`, `wait`; the worktree under `.claude/worktrees/`);
   `scripts/flow.py`: a `before` call on the Intent agent (`:1119-1136`), the red base question before Plan (reusing
   `setup_offer`, `:1184-1220`), the plan approval shows the baseline line.
7. **`scripts/flow.py`**: `acc_failure`, the triage and its question read Build's rows (`:1445-1485`); the Build
   question gains "Correct the acceptance test".
8. **The suite's owner**: `integrate` and the group gate run the CLI's command when `detect` finds one;
   `reference/plan.md:313-333` and `scripts/tasks_md.py:28-64` keep `**Integration:**` for a stack the CLI cannot read.

### Tests

- **New selftest case file** for the runner. None exists: `grep -l 'run_cached\|temper-results'` over
  `scripts/selftest/` and `scripts/e2e/` finds nothing [run], and the `reused` hits there are about worktrees. Cases: same tree in a worktree and in the project
  folder is one run; `__pycache__` and `.coverage` do not defeat reuse; a tracked edit and a new untracked file do;
  setup, command text, tool version and lock digest each invalidate; a failure is never reused; fail then pass marks
  flaky. Count runs with a counter file the test command appends to.
- `temper-cases-15.sh` (5 `check ahead` and adopt assertions, 11 on acceptance, 9 on coverage): rewrite.
- `temper-cases-22.sh` (24 preflight lines), `-23`, `-24`, `-27`: the baseline's three results, a red base asked
  before Plan, the skip reason, a slow suite still running at the plan gate.
- `temper-cases-11.sh`, `-16.sh`, `-5.sh` (scenario runs), `-25.sh` (the Integration suite): run counts.
- `temper-cases-1`, `-8`, `-9`, `-13`, `-28`, `test-temper.sh`: the coverage row's new rule.
- `temper-cases-8.sh` and both view fixtures (`make-view-fixtures.sh`): the Intent action carries a `before` call,
  the Build gate has two more rows.
- e2e: `scripts/e2e/scenarios.ts`, `pyjokes.ts`, `replay.ts`, `ab-replay.sh`: a run count assertion, and the Maven
  scenario's preflight steps. The mod's tests change only if a row is renamed (the driver runs `before` calls
  generically).

### Expected saved runs, clean run

| | Today | After, plan keeps its own Integration text | After, one owner of the suite command |
|---|---|---|---|
| Suite, two groups in a line | 4 to 5 (6 when a byproduct is not ignored) | 4 | **3** (base, G1, G2 = merged) |
| Suite, one group | 3 to 4 | 3 | **2** |
| Each scenario Test | 5 | 1 to 2 | 1 to 2 |
| S = 2 in the two group shape | 10 | **3** | 3 |
| Task Test runs on the base | T | 0 | 0 |
| Acceptance tests on built code | 1, after Review | 1, before Review | same |
| Mutants | up to 40 | up to 40 | up to 40 |

Two readings of the table. The saving in suite runs on a clean run is one or two, not "4 to 8 down to 1": each
group's tree is a different tree and must be run. And the mutation step (3h) is still the largest part of Check's
time; 3a does nothing for it.

What the three items buy beyond counts: an environment fault found before Plan is paid for; a failing acceptance test
repaired inside Build instead of after Review; no second Check on projects where the ahead run is discarded today.

---

## 8. Not determined

- Whether coverage.py's `.coverage` content differs between two runs on one tree (coverage.py is not installed here).
  The first run's discard does not depend on it.
- How long the digest takes on a large repository; 0.011 s is this one, with 575 files.
- How often real plans write a Validate or Integration text that differs from the project's own command. It decides
  how much of the per command run on the base remains.
- Whether the plugin directory's 256 KiB rule counts `scripts/temper` alone; I took the draft's figure and the file's
  size (260,504 bytes).
- Seconds saved on a real project: no document times a suite, a scenario test or a Check run outside the toy projects.
