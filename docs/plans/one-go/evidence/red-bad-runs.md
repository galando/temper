# Red team: the bad runs and the ordinary runs, replayed through draft v1

Subject: `scratchpad/plan-draft-v1.md`, read against `10e965a`. Read only in `/home/user/temper`; nothing run there.
Sources: the draft, `_crosscheck.md`, `changelog-recent.md` section 3, `flow-loops.md`, `pr-env.md`, four verifier
reports, ADR 0017 and 0018, CHANGELOG 9.8.4 and 9.8.5, `ab-replay-9.8.5.md`, `bench-2026-11.md`. Code read to settle a
point: `scripts/check_run.py:42-43, 76-145, 358-398, 678-750`, `scripts/temper:2441, 3321, 3408, 3862-3931`,
`scripts/flow.py:813-885, 1463-1475, 1960-2046`, `agents/intent.md:17-20`, `commands/temper.md:176-179`.

"The planned run" below is the run of section 2 of the draft with every stage done, unless a stage is named.

## 0. Verdict

The draft would have stopped both failed real runs, but mostly through what 9.8.4 and PR #115 already ship plus the
dialog and budget work of stage 2. Its own headline item for late faults, the baseline of 4b, does not catch the Java
run's faults as that run was shaped (the build file one folder down, integration tests behind `verify`, a JDBC
message no pattern names), and on a project with a slow suite three items stall or fail the run as worded. The largest
gap is order: the run becomes unattended in stage 2 while the checks that fail correct work on ordinary projects are
repaired only in stage 4.

Four blockers, sixteen majors. Each has the exact text change in section 7.

## 1. Run A: the complex feature (9.8.4)

Recorded: 8 criteria, about 30 files, risk H, a request that was already a spec; 5 Plan passes, 6 fresh reviewers in
3 rounds, 5 Build attempts of one group of 12 tasks, about 30 questions, nothing on the branch.

| # | Fault, in order | Where the planned run meets it | By which item | What the person sees | Mark |
|---|---|---|---|---|---|
| A8 | The request was a spec; Intent, Plan, Design and three review rounds derived it again | At the front | 3c (no Design), 3f (one front launch), "one fresh review round" | Nothing, if 3f applies. **Not settled:** the run is clear and risk H at once, and the table of section 2 has one column for each. 3f is also conditional on 3e | partly |
| A4 | Each fresh review round was a new full review; medium and low findings sent the plan back | Plan, before the approval | shipped in 9.8.4 (recheck rounds, only high blocks); 3d (narrow revision on Sonnet) | One dialog "Revise the plan" per high finding round, **unless the draft makes that revision the CLI's own action; it does not say** | before Build |
| A1 | G1's Validate ran test files a G2 task edits: the group could never pass | Inside Plan's own turn, at its `gate plan` | the 9.8.4 row `group validate order` (shipped), 4i's extension for new files | Nothing | before Build |
| A1' | The same fault with a Validate that names no path (`pytest -q`, `mvn verify`, a whole selftest) | At G1's group gate, after G1's 12 tasks are built once | not static (v-failure-budget 5.2); 4g, then the group fix agent, then 4h | One stop. If the fix agent changed something and the check still fails, the recommended step is the loop to Plan, and 4h names no author for an amendment that needs judgment | **Build, bounded only by 2h; can still end in a full replan** |
| A2 | A failed group check recommended a blind rerun, five times; reason cut to 200 characters | First failed group gate | shipped in 9.8.4; stage 0 (fix agent launched in an armed run, no replan by rule); 2h | At most one stop with the failure text | Build, bounded |
| A3a, A3c | A step back lost the findings and the failed group check | Any step back | shipped in 9.8.4; 4g keeps the record outside `groups.json` | Nothing | n/a |
| A3b | The review round limit dead ended after a loop back | Plan | 9.8.4 made the earned rounds unlimited (8 ran with the limit at 3); 2h bounds them only through the loops it counts | A budget question. **2h states no number and no way to grant more** | bounded, if 2h is completed |
| A5 | Haiku on a complex, risk H plan; three tasks on one production file | Plan gate; launch | shipped in 9.8.4 | Nothing | before Build |
| A6a | The CLI's credential filter broke every git call under the CLI in cloud sessions | Baseline, if the project's tests call git | 4b | "Baseline red" with the output tail. **When** is not defined: Intent takes 30 to 45 s, a real suite longer | before Build, if 4b says what happens when the baseline turns red after Plan started |
| A7 | Small frictions | | shipped | | n/a |

Count for the planned run, explicit path form: 1 front launch or Intent plus Plan, 2 reviewers (2 more on a recheck),
0 or 1 narrow revision, the acceptance writer, the task agents once, one Review. Dialogs: 0 or 1 Blocking, 0 or 1
"Revise", the approval, the commit: 2 to 4, against about 30.

## 2. Run B: the Java 24 Maven project (9.8.5)

Recorded: 12 tasks, 3.2 hours of agent time, most of 2.8 hours of Build lost to faults that existed before any code.
Per launch on that project: Plan 12 minutes, a Build task 25, a fix pass 40 (`ab-replay-9.8.5.md:21-22`).

| # | Fault, in order | Where the planned run meets it | By which item | What the person sees | Mark |
|---|---|---|---|---|---|
| B1 | JDK 21 in every shell, the project needs `[24,)` | **As drafted: at the plan gate, after Plan is paid for.** The baseline uses `check_run.detect`, which looks for `pom.xml` in the project root only (`scripts/check_run.py:140`); this project's pom is in `backend/`. Result "unknown", which never blocks. The plan's own `cd backend && mvn verify` then fails on the base at the plan gate (pattern 4) | stage 0 (the PR's preflight and setup offer), not 4b | One dialog: add the proposed setup block | before Build, **not before Plan** |
| B2 | Plan wrote `cd backend && mvn verify -Dtest=...` under a JaCoCo bundle rule | Inside Plan's own turn | stage 0: the row `maven filtered verify`, Maven found after `cd backend &&` | Nothing | before Build |
| B3 | The Maven check skipped `cd backend && mvn` lines | Rows: fixed by the PR. **The same blindness is still in `detect`**, so the baseline is unknown and Check has no test command (`UNKNOWN: no test command`, `scripts/check_run.py:681`) | none; 4c names "one owner of the suite command" but not who owns it when `detect` finds nothing | At Check: "Run Check again (Recommended)", the same again, then "Save for later" | **not caught early** |
| B4 | Postgres down; the integration tests need it | **Not by the baseline:** for Maven it would run `mvn -q test` (`check_run.py:141`), which runs no integration test. **Not by the plan command on the base:** the draft keeps "the pattern classes" for it, and the JDBC message is `Connection to localhost:5432 refused`, which the pattern `Connection refused` does not match (pr-env 2.1). The replay's fake Postgres prints a text that matches. First seen at a task's GREEN or at G1's group gate | 4g could class it as environment because the same command failed on the base, but only if the base failure is kept, which the draft does not say | A task agent spends its attempts (4a: two), then a stop | **not caught early**; Build, bounded |
| B5 | An environment failure at a task gate spent the attempt and reset the worktree | Before Build for the JDK | stage 0 (ENV verdict, with the "it is the code" way out) | Nothing once the setup block is in | before Build |
| B6 | The failure text was a passing test's log line | | stage 0 (S4), 4g | The build tool's own summary | n/a |
| B7 | Fix passes with no fault in the prompt; fix agents that changed nothing, then the same check | | stage 0 (S7, S8), 4c, 2h | At most one fix agent, then a stop | bounded |
| B8 | One wrong command line needed Plan, Design and every task again | | stage 0 (`plan patch`), 4h, 3c | One typed answer; tasks kept | bounded |
| B9 | A Design answer did not reach `tasks.md` | Before the approval | 3c | The design questions, then the approval. **Who applies an answer that is not the first choice is not said** | before Build |
| B10 | A High finding did not block | Review | stage 0 (High blocks), 4f | Nothing: a fix agent and a narrow recheck | bounded, 0 dialogs |
| B13 | Check recommended a loop back for an environment fault | **With 4d the suite runs at `integrate`, and the SETUP path stays at Check.** An environment fault at `integrate` is a failed Build gate, whose step is a fix pass | 4d moves the acceptance path only | A fix agent launched on an environment fault: fault B7 again at a new site | **reopened by 4d** |
| B17 | Review and Check always asked | | 2a | Nothing | n/a |
| B' | The second run: a plan line that could never finish in its time limit; three fix agents that changed nothing | Plan gate, on the base | 4b's second half. The preflight limit is 300 s, the group limit 600 s, and a time-out there is an "environment fault" whose remedy is the environment agent (pr-env 5.4, severity A). **5.4 is not in the draft's stage 0 list** | "Let an agent find the setup (Recommended)" for a slow command | before Build, with the wrong class and remedy |

Planned run on this project, with the fixes of section 7: one setup click, the approval, the commit; Plan once.

## 3. The rough benchmark runs

| Run | Fault | Where the planned run meets it | Item | Dialogs and launches left | Mark |
|---|---|---|---|---|---|
| Loop at Check, $23 to $38 (three runs) | A wrong locked acceptance test, first run after Review; the fix pass got only the name; a builder edited the locked test | At `integrate`, when Build ends | 4d | **The order is not stated.** The triage is skipped in an armed run today (`scripts/flow.py:1471`), and the planned default run is armed. If the fix pass goes first, an agent bends correct code to a wrong test (one of the three tests assumed customer ids are global). With the triage first: 1 triage launch, 1 dialog ("Correct the acceptance test" is the person's), 1 writer launch | Build, bounded, **if the order is written** |
| login-lockout | The same, two loops, three small change hand backs, an override | As above | 4d, 2g | 1 dialog. The override stays the person's | Build, bounded |
| tenant-leak (fix run) | The suite failed at Check after Fix; the locked regression test asserted a field the API never returns; on the third pass the agent listed files outside the plan; hand back | **At Check, after Review, as today.** A fix run has no `integrate` (v-checks section 4), and 4d names only `integrate`. 4f repairs the red suite once. Nothing names the wrong regression test | 4f only | 0 dialogs for the first repair; then a stop with no option that corrects the test; the hand back stays | **not caught early** |
| vague-late-fees, loop to Plan | The plan's Cases contradicted each other; the task agent stopped before its gate; the failed verdict was read as a broken call | Not knowable by a row. First task agent | 2g (the verdict), 4a | Two attempts, a parked group, one dialog, then **a full replan**: 4h covers File, Depends and Validate lines, not a task's Cases. Cases are not in the plan digest (`scripts/temper:2163-2174`), so a narrow revision of that task block would need no replan and no reset | **not caught early; still a loop to Plan** |
| partial-payments, hand back | `integrate` found an interface the plan named and no task built | **Still at `integrate`.** 4i's row checks that the interface's file is declared by a task; here the file was declared and the function was not written | 2g (no hand back), then a fix pass | 0 dialogs only if a failed `integrate` launches one fix pass by itself in an armed run. Today an armed run parks at a failed Build gate (flow-loops 5.1), and the draft does not say | Build, late; bounded |

## 4. Three ordinary cases

### 4.1 A one line typo

Steps: `state init`; the baseline starts (4b); the front agent says TRIVIAL after 30 to 45 s; 2c "ends the run".

- **What happens next is not written.** Today the conversation clears the run, makes the change, runs the tests and
  commits in the same turn (`commands/temper.md:176-179`). "A CLI verdict that ends the run" leaves the person with a
  message and a second request to type. That is one more exchange than today.
- The baseline keeps running after the run ended. On the project of 4.3 that is 15 minutes of machine time for a typo.
- If 3f puts the front launch on Plan's model, the triage of a typo is paid on Opus.
- If the run is not triaged as trivial (a typo inside a function): 4d judges coverage on changed lines. One changed
  line is 0% or 100%. An uncovered line fails the row and 4f launches a fix agent to write a test for code the
  request did not touch.

### 4.2 A clear two file change in a Python project

Steps: baseline (seconds); one front launch; the approval; one builder; `integrate` with the suite, coverage and the
acceptance tests; one reviewer; Check reuses; mutation; the commit question. Dialogs: 2. Launches: 3, plus the
acceptance writer until 3g decides.

- **Mutation can take the whole time budget.** Up to 40 runs of the suite within 300 s
  (`scripts/check_run.py:42, 369-381`). The pass line for a clear feature is 3 times vanilla, about 270 to 300 s for
  the whole run. 4e says "sound and bounded, or information only" and gives no bound; information only still runs it.
- A project whose dependencies live in a virtual environment the shell has not activated gives a red base on the
  first run: one new question. It is a true fault, but the draft does not say the answer is kept, so it is asked on
  every run.
- Changed line coverage with a small denominator: 4 changed lines with one defensive line uncovered is 75%.
- Two hidden launches are not in the target of "one front agent, one builder, one reviewer": the record pass and
  the Check agent, whenever the intent holds a criterion validated by `code` or `metric` (crosscheck section 4,
  item 2). The draft has no item for them.

### 4.3 The first run on an existing Java or Node project: a 15 minute suite, 55% coverage, no coverage tool

| Step | What the draft does | Result |
|---|---|---|
| Baseline at the start | The suite on HEAD in a new worktree under `.claude/worktrees/`: a cold compile plus 15 minutes. No limit is stated (Check's is 1,800 s, the preflight's 300 s) | Still running when Plan returns and usually when the person approves. "One question before Plan is launched" cannot hold: Intent is 30 to 45 s |
| Plan gate | "A command the plan itself wrote still runs once on the base at the plan gate." The brief makes every Maven group validate with a full `mvn verify` (`agents/plan.md:95`), so this is the whole suite again, under another text than the baseline's `mvn -q test` | **Fails or hangs.** Inside the Plan agent's own gate call a Bash call ends at 120 to 600 s and leaves the command running (pr-env 5.11); at 300 s the preflight calls it an environment fault and offers an agent (5.4). Two 15 minute runs on the base where one would do. On Maven the Plan agent has no command that passes: a filtered `verify` fails the row `maven filtered verify`, a bare `test` fails `maven group verify`, and the unfiltered `verify` runs past the 300 s the brief tells it to stay under (`agents/plan.md:95-104`). The person must write `plan.preflight-skip` to get past the plan gate. This holds from the day stage 0 merges |
| Each group gate | Limit 600 s (`scripts/temper:2441`) | **A time-out at every group.** 10 minutes lost, then "twice the time". In the planned run that is a stop per group, or a counted repeat per group against 2h's one budget. The baseline measured the suite's seconds and the draft does not use them |
| Suite runs | 4c: base, G1, G2 | 45 minutes of suite for two groups, 60 for three, before mutation |
| A red or flaky test on HEAD | "Go on with the suite as information" at the red base question | **Not wired.** 4d says `integrate` runs the suite and a failing suite fails it; the fix pass is then launched on failures that were there before. 4c forbids a second run of a failed check unless its class is environment or measurement, so a flaky test also goes to a fix agent |
| Coverage | 4d: information when no tool; else the total against the base | Passes, **once stage 4 has landed.** Until then: Maven, Gradle and Rust fail Check on `coverage tool missing` and recommend "Run Check again" twice, then "Save for later" (`scripts/flow.py:852-863`); Node with jest or Python with coverage.py at 55% fail on the 80% rule and recommend a loop back to Build (`:874-875`). With 2a the run is unattended when it gets there. If the baseline is unknown there is no base value, and the draft does not say what the rule is then |
| Mutation | 4e | One mutant is one suite run of 15 minutes; the budget check is between mutants, so one runs, the score needs three, the result is "not measured" (`check_run.py:381, 395-397`), and `check run` waits for it. 15 minutes for no number |
| Time limits | none in the draft | See the group gate row |

Dialogs with the fixes of section 7: one setup click on a wrong environment, the approval, the commit. As drafted:
those, plus a failed plan gate, plus one stop per group, plus a fix agent on old failures.

## 5. Where the planned run still goes backward, asks again, or waits without need

Backward steps that remain:

1. Build to Plan, in full, for a task whose Cases contradict (late-fees) and for a group check that still fails after
   a fix (A1'). 4h covers neither. A full replan still resets every built task; the draft keeps the record (4g) but
   not the tasks.
2. Approval to Intent ("Loop back to Intent", 2d): Intent, Plan and the approval again. The draft names this risk.
3. Check to Fix in a fix run when the suite is red after Fix: Review is spent first.
4. After the second repair of 4f: the old loop back, as the only way out.
5. From the commit question, when the person wants a Medium finding repaired: no option is named, so it is a loop.

Questions asked again or asked without need:

6. "Revise the plan" after a fresh review finding (one recommended answer after a failed check).
7. The design concerns as a dialog of their own between Plan and the approval. The table of section 2 says they are
   "among" the product questions, but they come from Plan, after Intent's dialog is closed.
8. The red base question, then the setup offer, then possibly the environment agent offer: up to three dialogs for
   one fault. And the same red base question on every later run.
9. The red base question in every `/temper:fix` run that starts from a failing test. There a red base is the bug.
10. One stop per group for a time-out on a slow suite.
11. A criterion confirmed by hand at Check, then the commit question: two dialogs at one stop.
12. A TRIVIAL request: a second request typed by the person.

Waits without need:

13. Mutation at Check on any suite longer than a few seconds.
14. The plan command's run on the base, when it is the suite under another text than the baseline's.
15. The baseline on a run that ends as TRIVIAL.
16. Per task cold compiles on a compiled stack (6d is in stage 6 and conditional). Not worse than today.
17. A stop of an armed run that nobody is told about: the ENV question at a task gate waits with no report
    (flow-loops E9). With two approvals the person has left.
18. After any hand back with the mod, a model in the main session for the rest of the run.

Fault classes the draft still finds late:

| Class | Found | Why not earlier |
|---|---|---|
| An environment fault that exits 1 with a text no pattern names (JDBC, asyncpg, `ECONNREFUSED`, a missing module) in a command the plan wrote | first task gate or group gate | 4b keeps the pattern classes for plan commands |
| Any environment fault when the build file is one folder down, or `detect` picks the wrong stack | plan gate at best | the baseline is "unknown" |
| A fault that needs integration tests (a service) on Maven | first group gate | the baseline runs `mvn -q test` |
| A group whose whole suite Validate breaks on tests a later group updates | first group gate | not static; the Maven row forces this shape |
| An interface whose file is declared and whose function nobody writes | `integrate`, after every group | 4i checks the file only |
| A wrong locked acceptance test | `integrate`, after every group | cannot be known before code; could be known per group |
| A wrong locked regression test, a red suite after Fix (fix runs) | Check, after Review | 4d names `integrate` only |
| Contradicting Cases in a task | first task agent | not static; no record kind; no narrow repair |
| A flaky test | any of G + 1 suite runs | no flaky rule; 4c forbids the second run |
| A suite slower than the fixed limits | each group gate | the baseline's seconds are not used |
| Coverage and missing tool faults of correct work | Check, until stage 4 | order of stages |

## 6. Do stage 0 and stage 2 alone prevent the two failed real runs?

**Yes, for the two runs as they happened. Stage 4 is needed for their neighbours on other stacks, not for them.**

- **Run A.** The root cause (a Validate that names test files a later group edits) is caught by the row
  `group validate order`, shipped in 9.8.4, inside Plan's own turn. The five Build attempts are stopped by the 9.8.4
  ladder and stage 0's two policy fixes (launch the group fix agent in an armed run; never take a move back to
  Plan). The 30 questions fall with 2a, 2b, 2d and 2f. The repeats nothing counted fall with 2h. Items that carry
  most: the shipped row, 2h, 2a.
- **Run B.** The PR's own replay shows it: 191 agent minutes to 92, 10 launches to 7, no hand repair of the shell
  (`ab-replay-9.8.5.md:26-35`). The carriers are all in stage 0: the row `maven filtered verify` with Maven found
  after `cd backend &&`; the preflight's JDK class with the one click setup block; "no fix pass without a fault" and
  "a fix that changed nothing keeps the check failed"; `plan patch`. Stage 2 takes the questions from 8 to about 3.
  Stage 4's baseline would move the JDK fault from after Plan (12 minutes of Opus on that project) to before it,
  and as drafted it does not even do that for this project (section 2, B1).
- **What this says about the order.** The plan's stage 4 holds the cheap, general versions of what prevented both
  runs (a binary baseline, three static rows of half a day, a coverage rule that does not fail correct work), behind
  28 to 39 days of stages 1 to 3. Stage 2 makes the run unattended first. A person who approves and leaves is told
  later, not sooner, about every fault the run finds late.

## 7. Findings, each with the change to the plan text

### Blockers

**BL1. Stage order: 2a ships an unattended run before Check stops failing correct work (draft 2a, 4d, pass line of
stage 2).** On Maven, Gradle and Rust every run fails Check on a missing coverage tool; on a project at 55% every run
fails the 80% rule and is told to loop back. The bench cannot see it: its projects are Python above 80%.
Change: move the last two sentences of 4d into stage 1 as item **1h**: "Coverage never fails correct work: judged on
changed lines where the data exists and at least 10 executable lines changed; else the total not below the base by
more than 1 point; else, and whenever there is no tool or no base value, a line of information at the commit
question. The 80% rule on the whole project applies only when the project's config sets `check.coverage-threshold`
itself." Add to stage 2's pass line: "and a first run on the slow fixture (1c) ends at the commit question with no
stop at Check".

**BL2. 4b, second half: a plan command "still runs once on the base at the plan gate" (draft 4b).** On a slow suite
this is the whole suite inside the Plan agent's gate call: a killed Bash call, or a 300 s time-out classed as an
environment fault with an agent as the remedy. Change the sentence to: "A Validate or Integration command whose text
is not the suite owner's runs once on the base, started by the CLI in the baseline's worktree after the Plan agent
has returned, never inside an agent's turn and never waited for by the plan gate; its limit is Build's own limit for
that command; a time-out is its own class (slow), whose remedies are a longer limit, another command, or a skip with
a reason." Add to stage 0's list: "A slow command is called an environment fault and the environment agent is offered
(pr-env 5.4); a gate call that is ended leaves its command running (5.11)."

**BL3. 4b does not catch the Java run's faults earlier than the PR does (draft 4b, 4c, pass line of stage 4).**
`detect` reads the project root only; for Maven it runs `mvn -q test`; plan commands stay judged by patterns.
Change 4b to: "Before the first agent is launched, in under 5 seconds: the tool versions the project's own files ask
for against the shell (the facts `doctor --propose` already reads, root and one folder down) and each declared
service; a mismatch is the red base question at once. The baseline then runs the suite owner's command: the
config's `check.commands.test`, else what `detect` finds in the root or one folder down (for Maven `verify`, the
form the plan gate demands of a group), else, after Plan, the plan's Integration line. A plan command that names no
file a task creates must exit 0 on the base: a binary rule, no pattern. The pattern classes stay only for a command
that names a new file." Change 4c to: "One owner of the suite command, in that order; the baseline, the group gate's
suite, `integrate` and Check run its text. A run never ends at Check for want of a test command when the plan has an
Integration line."

**BL4. 4d moves every mechanical failure to the end of Build and does not say what an armed run does there (draft
4d, 4f, decision 2, pass line "a repaired finding costs no dialog").** Today an armed run parks at a failed Build
gate, stage 0 calls the unasked fix pass after a failed `integrate` a defect, the SETUP path stays at Check, and the
acceptance triage is skipped in an armed run (`scripts/flow.py:1471`). Add to 4d: "At a failed `integrate` or Build
gate the next step is read from the failure record: class environment, the SETUP question (it moves here with the
acceptance path) and no fix pass; a failed locked acceptance test, the triage first, in every mode, and code changes
by rule only when the triage blames the code; class code, one fix pass as the CLI's own action, counted in 2h; then
the run asks." Add to 4f's "never by rule" list: "an acceptance or regression test the triage does not blame on the
code". Reword decision 2: "It may repair once per stage, by rule: a failed mechanical check of class code at the end
of Build, and a critical or high finding at Review or Check."

### Majors

**M1. "Go on with the suite as information" is not carried through (4b, 4d).** Add to 4d: "When the person chose it
at the red base question, a red suite at a group gate, at `integrate` and at Check is a line of information for this
run and launches no fix pass; task tests, scenario tests and acceptance tests still gate; the commit question shows
the failures before and after."

**M2. Fix runs are left out (4b, 4d, 4f; the tenant-leak run).** Add to 4b: "In a `/temper:fix` run a red base is
recorded and not asked, unless the fault is the environment's by structure (the setup line failed, a program is
missing, a declared service does not answer)." Add to 4d: "A fix run has the same step: when the Fix agent returns,
the CLI runs Check's suite and the regression proof before Review; a red result goes to the Fix stage as a repair. A
locked regression test the triage calls wrong asks 'Correct the regression test', one dialog."

**M3. Time limits are never set from the baseline (4b, 4c).** Add to 4c: "The limit of a run is three times the
seconds that command took on the base, never under today's default; a command with no measured time gets the default,
and after its first time-out the doubled limit holds for every later run of it in this run. A time-out with a
measured base time is not counted in 2h."

**M4. Mutation has no bound in the draft and wastes a suite run on a slow suite (4e).** Replace 4e with: "Mutation
is information, never a gate row, until one bench round shows a stable score. It runs beside Review, only when three
mutants fit in its budget (suite seconds times three under the budget), stops when Review returns plus 60 seconds,
and never delays the commit question; what it found is shown there."

**M5. No rule for a flaky test, and 4c forbids the rerun (4c).** Add: "A check that passed on the base and fails
with fail lines that name no file of the plan is run once more before any agent is launched; fail then pass is
recorded as flaky and shown at the commit question."

**M6. 4h names no author and no case beyond File, Depends and Validate (4h; Run A's neighbour; late-fees).** Add:
"Who writes it: the CLI when the record names the file and its owner; else the narrow revision agent of 3d, given
the failure record and the task blocks it names, limited to the approved files. A task agent that cannot build its
task as written records why (`task blocked --reason`, kind contradiction) and spends no second attempt; the first
step is the narrow revision of that task block, which is outside the plan digest, so no task is reset. A full replan
keeps every built task whose approved fields did not change."

**M7. The interface check stays at `integrate` (4i, 4a; partial-payments).** Add to 4i: "The group gate runs the
Interfaces check for the group's own entries, and the read only verdict of 4a tells the task that declares an
interface's file that the interface is owed."

**M8. Every Maven group validates with the whole suite (4c; case 4.3; Run A's neighbour).** New decision 7 for the
owner: "A group gate runs the tests the group's tasks name and the scenario tests it owns; the whole suite runs
twice a run, on the base and on the merged tree. The row `maven group verify` moves to the Integration line."
Recommended: yes. Without it a 15 minute suite costs 15 minutes per group, and on Maven no Validate can pass the
plan gate of the PR when the suite takes over 300 s (the three rules of `agents/plan.md:95-104` exclude each other).
Until the decision is taken, add to stage 0: "The limit of a plan command on the base is Build's limit for it, not
300 s."

**M9. Two hidden launches have no item (section 2's Agents row).** Add to stage 3: "**3i.** A criterion validated by
`code` or `metric` is recorded by the CLI, which runs the criterion's command through the runner: no record pass and
no Check agent in a default run."

**M10. Nothing in the scorecard is an ordinary existing project (1c, 6d, section 7 of the draft).** Add to 1c: "A
scripted fixture with no model cost, built as `scripts/e2e/replay.ts` builds its mock: a build file one folder down,
a fake build tool that takes a set time, 55% coverage, no coverage tool, one test red on HEAD, one flaky. Each stage's
pass line includes it: no time-out, no stop beyond the setup click, the approval and the commit, at most G + 1 suite
runs." Move the compiled fixture of 6d here.

**M11. A baseline that turns red after Plan has started, or after the approval (4b).** Add: "Red before the
approval: the approval shows it and its options are the three of the red base question. Red after the approval: no
new task agent is launched, the work in flight is kept, and the run asks."

**M12. Changed line coverage on a tiny change (4d; cases 4.1, 4.2).** Covered by the "at least 10 executable lines"
clause of BL1; say so in 4d.

**M13. Stops before the approval that have one recommended answer (3c, 3d, section 2).** Add to 3d: "After a fresh
review finding at high, and after a design answer that is not the first choice, the CLI launches the narrow revision
and the recheck as its own action, once; then it asks." Change 3c: "The design questions are questions of the
approval dialog (a dialog holds four); the first option approves the plan as written under the first choices." Add
a row to the table of section 2: "Clear and risky: one front launch, one fresh review round, the approval."

**M14. 2h has no number, no rule for what it does not count, and no way out (2h).** Add: "Default: two per failure
key, six per run. Not counted: the person's own changes, a task's first two attempts, a rerun after a measured
time-out. At the limit: one question that names the failure record, 'Save for later' first, and one option only the
person can take that grants two more."

**M15. An armed run that stops must say so (2a).** Add: "Every stop of an armed run is a park with a report line
and the host's notice; no question waits without one (the ENV question at a task gate does today)."

**M16. The red base question can be three dialogs and is asked again on every run (4b).** Add: "The question shows
the proposed setup block; its first option adds it and runs the baseline again. The answer is stored under the
baseline's key (tree, setup, tool versions) and not asked again while the key holds."

### Minor

- **2c.** Say what follows TRIVIAL: "the run ends and the request goes to the conversation as the named hand back
  kind `trivial`: the change, the project's tests, the ordinary commit; the person types nothing more. The triage
  runs on the cheapest front model. A baseline in flight finishes and is stored under its key."
- **2f.** A criterion confirmed by hand is a question of the commit dialog, not a dialog before it.
- **4f.** The commit question offers "Repair these first" for carried Medium findings: one repair of 4f, not a loop.
- **2g.** Say whether a hand back returns: "the conversation does the one step and tells the person the command
  that gives the run back to the driver".
- **4b.** State the baseline's own limit (Check's 1,800 s) and that a baseline over it is "unknown", shown as such.
