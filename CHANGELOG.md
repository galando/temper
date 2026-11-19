# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v9.8.5: a run that asks twice

- M2 (WP08): a passed Review with an open finding keeps every way on in reach, and no More holds a More.
- F1 (WP08): a Medium finding goes on to Check and is listed where you commit; only High or above loops back.
- M3 (WP08): under the policy, a failed group check whose fix you asked for launches the group fix agent.
- M4 (WP08): the policy never takes a step back to Plan; the armed run parks and the step back is yours.
- M5 (WP08): a step back to Intent, Plan or Design turns the run back to asking at every stage.
- M6 (WP08): under the policy, a criterion only you can confirm parks the run; the next question is the confirmation.
- M7 (WP08): the Check brief records the test run with evidence run, and the CLI checks a small change at Check.
- M10 (WP08): the same environment fault at Check after a run again recommends Save for later, not the repair.
- M11 (WP08): when only the commit gate's own row fails, the first option, Check again, runs the gate again.
- M13 (WP08): the environment agent is no longer offered; the question shows the proposed setup block whole.
- F2 (WP08): a Design answer newer than the tasks passes its row with a note and goes to every Build task.
- WP09: a failed group check or a failed integrate is a verdict for every carrier and reaches its question with no
  hand back. `temper gate`, `task gate`, `group gate` and `integrate` print `VERDICT: <scope> <verdict>` once they
  recorded one; `temper go` (its new key `verdicts`), the mod's run driver and the scripted loop read that line only.
- WP10: one budget in the CLI (ADR 0019 decision 1). Every repeat that follows a failed check spends one entry of
  `.temper/budget.json` (`scripts/budget.py`): 2 for one failure and 6 for one run (`budget.per-failure`,
  `budget.per-run`). A call past a limit prints `BLOCKED: ...`, exits 1 and writes nothing; no flag and no variable
  exempts it. `temper next` never offers such a call: it asks `run.budget` (Save for later, or `Allow two more`, which
  only the person answers with `temper budget grant`), and an armed run parks there. `temper budget` prints the record.
  The keys `fix.max-loops`, `feedback.enabled`, `loops.max-per-type` and `autonomy.budget` are read by nothing; the
  rule "Build to Plan once per run" is gone, and the budget bounds that step back.
- WP18: `temper evidence resolve --fixed-by` takes only a commit the CLI recorded (`cli_commits`) after the reviewed
  HEAD, on this branch; a note is refused. Until a later release records a repair commit, a finding ends by your
  accept, or by a loop back and a second Review. Review's completion row names the files it read
  (`evidence add --read FILE`), and the row `review completed` fails while a file of `temper review files` is not
  named; `Run Review again` is recommended, and its launch names the unread files. A run saved before 9.8.5 after its
  Review has a completion row with no read list: it fails once, and Review runs again. With the mod, `evidence
  resolve` is refused as a tool call in a /temper or /temper:fix run; with no run, the CLI refuses it, as it has no
  commits of its own to resolve a finding with.
- WP14: Design runs only when you ask for it (ADR 0019 decision 2). A default run launches no Design agent at any
  tier or risk; the plan approval offers `Run Design first` in its More list, in the place of Teach Me, and
  `/temper:design` asks for it too. What Design asked is now a Blocking question Plan writes, its first choice the
  answer the tasks assume, and you answer it before the approval: `state advance plan_complete` is refused while one
  is open. The row `tasks agree with decisions` moves to the plan gate: the first choice passes it with a note,
  another answer fails it until `tasks.md` changes, the first time Plan runs again by itself and the second time you
  are asked, with `Revise the plan` recommended. A plan of risk H gets the fresh review with no request, and the
  unattended run is offered at risk H only after a complete round with no open High finding. `phases.design` and the
  state key `intent_asked` are gone; the Architecture Depth pack also reads the plan.
- WP11: the approval runs to the commit by default (ADR 0019 decision 3). Its first option, Approve and build, lets the
  run go on by itself: a passed check moves on, a failed check gets one counted repair by rule (a loop back to Build for
  a finding at a level of `review.block-on` or a failed Check, the recommended fix of a failed group), and every other
  case is a recorded stop that asks you, after which the run goes on by itself. The commit question always asks, with
  commit, a pull request, or a loop back to Build. Ask me at every stage keeps every gate's question. `run.default`
  (`to-commit`, `ask`, `never-unattended`) orders the two; `autonomy.enabled: false` reads as `ask`. A skip, an
  accepted finding and a step back to Plan end it. A plan that declares a sensitive path is rated H and repaired by
  nothing; a changed sensitive file outside the plan is confirmed at the failed commit question. `temper go
  --taken-up` asks a run taken up again once. What a rule decided is in `.temper/rule-log.json` and the view's
  `rule_log`. A run armed by 9.8.4 asks at every stage. `autonomy.policy` and the labels Stage by stage and
  Autonomous Build are gone.
- WP12: the approval is bound to what was shown (ADR 0019 decision 4). The approving options carry the digests of
  `intent.md` and `tasks.md` as the question showed them (`--shown intent.md=<H1> --shown tasks.md=<H2>`, made by the
  new `scripts/approval.py`), and the CLI refuses the advance when a file changed since; `plan_complete` is refused
  while the intent is a draft, and `intent accept --digest` refuses the same way. The advance records `intent_hash`
  beside `plan_hash`; a later change to either file fails the new row `intent unchanged since the approval` of the
  Build, Check and commit gates until you approve again, and stops a run that goes on by itself. Before the approval a
  run makes no branch and no commit: leaving Intent accepts the intent and moves on, and the approval makes the branch
  and one commit of the spec folder. A branch an earlier run left is named by the approval, which continues on it, and
  its More list offers a new branch; the Intent branch question is gone. With the mod a write of `intent.md` is refused
  from Build on. With the mod off the commit hook gates the branch the run stands on before the approval, and a new
  classic hook, `scripts/guards/hold_before_approval.py`, refuses a project file write by the tools that write a file
  at Intent, Plan and Design of a feature run. The plan digest has one home, `scripts/approval.py`.
- WP13: the run leaves Intent by rule; the approval accepts the intent (ADR 0019 decision 5). You approve the intent
  and the plan in one question before any code is written, and you approve the commit. A passed Intent check with an
  `intent.md` and nothing open (no Blocking question, no step back into Intent, no note of yours, no door) moves on to
  Plan as the CLI's own action; the approval's first options run `intent accept --digest` before their one commit
  (`docs(plan): accept the intent and approve the plan of <slug>`), and `Accepted-by` reads `the person, at the plan
  approval`. A skip of a failed plan gate never accepts a draft intent: its own question at Plan does. The approval's
  More list offers `Loop back to Intent`, and the Plan agent gets the request. The Context check asks nothing for a map
  with no `ignore` or `gap` line, and a flagged map whose lines the approval shows whole is answered there; the Plan
  brief no longer adds the `Blocking: Context check` line. A draft beside `tasks.md` passes `no scenarios in draft`.
  The fresh review's digest leaves out the CLI's own lines of `intent.md`, so the accept at the approval keeps a
  review current. A clean scripted run asks two dialogs; the new scenario `context-fold` shows the fold.
- WP15: the cards of the approval, the commit and a stop. Each question that decides carries one card the CLI computes
  from files and ledgers (`scripts/card.py`): the field `card` of `temper next --json` and of `.temper/view.json`, the
  rows `temper card` prints (76 columns) and `temper go` gives, and a drawing above the dialog the mod's run driver
  raises. The approval card shows the request as typed, what Intent assumed, the criteria one a row, the out of scope
  bullet, your answers, the files by group (a sensitive path on its own row), the gate commands word for word, every
  flagged Context Map line whole, the launches, the risk, and what the run does by itself after the click. The commit
  card shows the criteria met, the suite, the coverage, the open findings, the files, what a rule decided since the
  approval, the skips, the tree, the time and the message the click uses; at `commit.confirm` the click commits the
  uncommitted change with that message, and the record of the run follows. A stop card shows what fails, what was
  tried with the budget used, what still passes and the time spent. No card holds dollars; a time is in minutes, and
  the approval's estimate is the median of the finished runs this project kept. A flagged map is now folded into the
  approval whenever the card shows its lines, of any length. A sensitive path of the plan is named on the card, no
  longer in the question's text. The Plan panel and `temper panel plan` are gone.
- WP16: with the mod, a run leaves the run driver only for one step on a closed list of seven kinds, each one you chose
  by an option: talk (Grill Me, Teach Me, the Design walk through), the HTML review, the depth review, the config
  suggestions, a small change, the pull request and the CI fix (`NEEDS` of `scripts/flow_base.py`, the cap
  `handback_kinds`). The note after the command ends `step <kind> <option id>`; the conversation does that step and ends
  its turn, and your next `/temper:temper` (or `/temper:fix` with no words, which now takes an active fix run up) goes
  on in the driver. A failed check, a failed call, a typed answer, a scope drift and a question nobody answered no
  longer hand a run over: an answer you type at a gate runs the question's `typed` calls (a note for the next agent, and
  at Intent, Plan, Design, Build and Fix the stage run again with it while the budget has room); a failed call, a bound
  or a defect is a saved stop that starts with what stopped and shows the CLI's FAIL line; a run whose state cannot be
  read asks the restart question. Scope drift is the CLI's question: an agent records a file outside the plan with
  `temper drift ask`, and `next` asks `scope.drift` before anything else of the stage, in an unattended run too, then
  launches the agent again with one `Drift decision:` line a file. The calls of the flow are all CLI calls: `temper spec
  branch --carry NAME` (the branch clash switch), `temper spec branch --if-protected` (a fix run's branch), `temper
  group take-out G SHA...` (commits the CLI did not make), `temper group feedback G --text T` (Change at a passed group,
  typed in its own question). The record commit with no file list is `temper spec commit` too. A typed Context check
  answer counts with the mod (its view held the question as an object), up to 2,000 characters. A group that continues
  by rule is in the record of the commit card. The hand back words `next`, `discuss` and `chose` are gone.
- WP17: `/temper:fix` asks twice. The root cause question is the approval: its card shows the bug as typed, the cause,
  the fix, the regression test, the files, the test command and the risk from `rca.md`, and `Approve and fix` binds
  `rca.md` as shown (`--shown rca.md=<H>`), makes the fix branch off main or master only (`spec branch --if-protected`)
  and lets the run go on by itself; `Ask me at every stage` keeps the four questions, and `run.default` orders the two
  as at the plan question. A passed Fix, Review and Check then move on by rule, Check's run starts beside Review, and
  the commit question offers Commit, Loop back to Fix and Save for later, never a pull request. A change typed at the
  root cause question runs the root cause agent again with it. The fix run starts with `--feature`; neither the page
  nor the driver prints the RCA panel or makes a branch. A trivial request is a verdict the CLI records: the Intent
  agent calls `temper intent trivial --why TEXT` (`scripts/trivial.py`), makes its one change and returns; the flow
  closes the run with `intent trivial --close`, which writes `.temper/trivial.json` and a run summary line of kind
  `trivial`. The change is yours to commit, and with no run the commit hook holds it to one production file and 10
  lines (the row `trivial exit`) until HEAD moves or a run starts. The mod lets no `state clear` through at Intent,
  and writes the one change only while the verdict is recorded; the return word `TRIVIAL` is gone.

- WP19: checks judged against the project. A gate row is passed, failed or not measured: `pass` null with `state:
  not measured`, printed `[?]`, drawn `?` by the mod, named on the commit card, and never read as passed or failed.
  Coverage is one row, `coverage`, judged by one rule (`scripts/check_run.py coverage-verdict`): the key
  `check.coverage-threshold` only when the project's config holds it (its failed row names the key and how to remove
  it); no coverage command or a coverage program that could not start (exit 127) is not measured, as is no base
  value; with line data and ten or more changed executable lines, their share that ran reaches the base total (at
  most 80); else the total may be at most 1 point below the base total. Line data comes from coverage.py's JSON, Go's
  profile and `lcov.info` (jest, vitest and c8 now write it). A coverage not measured fails nothing, and the run moves
  on; a measured drop takes the one repair, then asks. The planted bug score is no row of Check: `temper check ahead`
  plants bugs beside Review only when three runs of the suite fit the budget, writes `.temper/evidence/mutation.json`,
  and stops 60 s after `check run` starts (`.temper/check/mutation.stop`); `check run` plants none and never waits.
  The commit card and the Check marker `mutation` show the score as information. The template's
  `coverage-threshold: 80`, the default 80 in code, the key `check.mutation-threshold`, the row
  `mutation score >= threshold`, the ledger row of a missing coverage tool and stop 21 (`check.mutation-only`, ADR
  0019 decision 3) are gone.
- WP20: the environment check, the baseline and the limits. A run's first step is the CLI's own `temper baseline
  start` (`scripts/baseline.py`), which always exits 0: the tools and services the project's files and the config name,
  checked in under 5 s with no suite (`doctor.needs`), then the project's own suite once on the current code, in the
  detached worktree `.claude/worktrees/temper-baseline`, in its own process. Who owns the suite command is one rule
  (`python3 scripts/check_run.py owner`): the config, the root, the one folder one level down (`cd <folder> && `), the
  plan's Integration line; Maven's detected command is `mvn -q verify`. `.temper/evidence/baseline.json` says green
  (its seconds and coverage, WP19's floor), red (its kind and fail lines) or unknown (the reason); the approval card
  shows it in one of four forms. A fault or a red base is the one question `base.red` before any agent, and after the
  approval Build launches no new task agent on it (a run that goes on by itself stops there): Add this setup block and
  run it again (`temper doctor --propose --write --expect <hash>` writes the block shown), Run it again, Go on anyway
  (`temper baseline accept-red`, the person's: a recorded skip, the override `base-suite`; at Check only the base's
  fail lines are skipped, one new line fails `tests pass`; a later run on the same key asks nothing) and Save for
  later. A fix run records a red base and asks nothing. Every limit is the larger of its default and three times the
  base's time of the same suite (`baseline.limit_for`); a first time out of a group's check runs again with twice the
  limit as the CLI's own call. Gone: the option "Run the gate again with twice the time", and the setup block's offer
  at a failed plan gate (it is the red base question's now). `temper baseline clean` removes the worktree; `state
  clear` and `state init` call it.
- WP21: a plan command runs once on the base; the preflight goes (ADR 0020, which amends ADR 0018). `temper gate plan`
  runs no project command. The planner's last calls are `temper baseline plan`, then `gate plan`: each group's
  Validate and the Integration line run once on the current code, in the baseline's worktree, in a process of their own
  (a fresh reviewer, a revision and a changed command end the same way, and Build's first step runs it when a result is
  missing), each under Build's own limit. Left out: the suite the baseline ran, a command that names a file a task
  creates, every task and scenario Test. The exit code alone decides (`plan` of `.temper/evidence/baseline.json`): pass,
  fail, `timeout`, or `fails like the base` on a red base; exit 125 and a program that does not resolve are class
  `environment`, and a program of the plan that does not resolve turns the base red. A failure or a time out is the
  question `plan.command` (one site with `base.red`): Allow it more time (`more-time`, a longer limit kept in `limits`)
  or Run it again, Change the command (`temper plan patch`, now also before the approval), Revise the plan (Loop back to
  Plan after the approval), Go on anyway (`temper baseline skip`, the person's, the override `plan-command`), Save for
  later; a run that goes on by itself stops there. At a task gate only three sure signs give ENV (`run_env.env_fault`):
  the setup line failed, exit 127 for a program the command starts, a declared service that does not answer; a code bug
  that prints `Connection refused` spends its attempt. `temper doctor --propose --write` writes only with `--expect` the
  hash of the block the question showed. Gone: `scripts/preflight.py` with its classes and text patterns, the plan
  gate row of that name, `temper plan` of that name, `.temper/` files of that name and `setup-tried.json`, the keys
  `plan.preflight-timeout` and `plan.preflight-skip`, the environment agent (`agents/env.md`, its type and model name)
  and `temper doctor` with an agent's draft file. The stops `base.red`, `plan.command` and `person.baseline` join
  `scripts/stops.json`. The mod's run driver takes the person's note on an option that needs a reason as that reason
  (as its guard already did) and asks no second dialog for it.
- WP22: one digest, the reuse store and the flaky recheck. The same command on the same tree runs once: the digest
  (`run_env.tree_key`) is the work tree as it is, tracked and untracked files alike, without `.temper/`, `.claude/` and
  the byproducts a run left (never a tracked, declared, source or test file); the key adds the command, the setup block,
  the folder and the first version line of each program. Every group check, `integrate`, Check (its suite, scenario
  tests and acceptance tests), a task's scenario tests and the baseline go through the store, `temper-results.json` in
  the git folder, now changed under a lock with one run in flight a key. A failure is kept beside the pass and not run
  again on the same key; a failure whose command passed on the base runs once more at once, and fail then pass is
  `flaky`, shown on the commit card. Each row names `tree`, `key`, `seconds` and `reused`, and each verdict its `tree`;
  the commit gate fails (`checked tree`) when the project changed after Check. Run it anyway (`--fresh` on `check run`,
  `group gate` and `integrate`, the option `run-anyway`) runs whatever the store holds, spends one repeat and marks the
  row `forced`. `check ahead` warms the store: gone are its adopt step, `tree_digest` and `.temper/check/ahead.json`.
- WP23: the checks run when Build ends; one failure record. `temper integrate` runs, in one call (`temper check
  build-checks`), the suite in the owner's run text with its coverage, each scenario test and the locked acceptance
  tests into the Build ledger; the Build gate gains the rows `acceptance tests written before Build` and `coverage`, and
  Check on the tree integrate left runs no command (its rows are reused). A failing locked test gets the triage first,
  in every mode: `code` is one fix pass as the CLI's own action, `test` is the question, whose `Correct the acceptance
  test` is yours. A fault of the environment is the setup question at Build, with no fix agent (`check-again`,
  `it-is-the-code`, `save`). A fix run runs the suite and the regression proof when the Fix agent returns, and only a
  proof the CLI ran counts. Every failure is one typed record in `.temper/evidence/failures.json`
  (`scripts/failure.py`), of one of five classes; a class picks the next step and never a verdict; a step back keeps
  it, and `state archive` copies it into `gate-ledger.json`.
- Phase 5, the parts WP22 and WP23 left out. The questions read the reuse store before they compare failure texts: a
  failure the store kept and gave back on the same tree is the same failure (after a fix pass by rule too), and a
  group's check asked again on the same tree counts as a fix that changed nothing. A fix run's regression proof that
  fails twice with the same text offers `Correct the regression test` (`correct-test`), whose reason the Fix agent
  gets as your note. `check ahead` of a feature run plants bugs only, timed by the store's entry of the tree, and says
  why when there is none; a fix run's stays the warm run. A group's Validate in the owner's test text runs in the
  owner's run text, so `integrate` reuses the last group's run on the merged tree.

**The floor, the caps and the run summary (WP05).** `scripts/e2e/floor.json` holds, for each scripted scenario and
mode, what a run with no model call did: the dialogs (by stage and by kind), the launches by agent type, the steps the
CLI took by itself, the steps back, the hand backs of the run driver and the runs of the whole suite.
`bun scripts/e2e/run.ts <mode> <name> --floor scripts/e2e/floor.json` compares them exactly, `--write-floor` writes
them, and `scripts/check_floor.py` refuses a `final` above its first committed value; the entry `replay` holds the
replay of the measured run and `replay_base` the numbers of the base (`10e965a`) on it, which
`bash scripts/e2e/ab-replay.sh 10e965a` checks. A new scenario, `default-run`, is the run the floor counts.
`scripts/caps.json` holds the growth caps (question and option sites, option labels, question ids, gate rows, briefs,
listed commands and skills, config lines, prompt bytes, `cli_bytes` and README lines), each with `now` equal to the
measure and a `final` nobody raises, checked by `scripts/check_caps.py` in `scripts/quality-check.sh`; the room case of
`temper-cases-32.sh` is now the cap `cli_bytes`. `scripts/stops.json` lists the stops an unattended run must keep. The
fixtures write `- reviewed: pending` and the Context check line, as a real planner does, so every scenario meets the
Context check; the plain loop asks Blocking questions four to a dialog, as the driver does; a fixture's whole suite
runs behind one script that counts its runs (`TEMPER_E2E_COUNT`). `temper state clear` appends one line a run to
`.temper/runs.jsonl` (`scripts/run_summary.py`: the CLI's questions once each, by stage and kind, the steps back, the
launches, the time, the skips), which keeps 200 lines and survives `state init`. The bench writes the question id, the
move and a dialog index on each line of `person.jsonl` and which code ran into `run.json`; `bench/agentlog.py` and
`bench/scorecard.py` make the scorecard and hold one arm against the pass lines of part H (`--gate`). CI runs the job
Floor and caps. Its cases are in `temper-cases-41.sh`.

**Ids in the protocol (WP04).** Every question that `temper next --json`, `temper go` and `.temper/view.json` carry has
an `id` from one registry (`QUESTIONS` in `scripts/flow_base.py`, which also says what decision the question asks for)
and a `kind`; every option has an `id` from a closed list (`OPTION_IDS`), a `kind` where a reader acts on it (`more`,
`accept`, `cancel`, `carry`, `type`) and `recommended: true` on the recommended one. The run policy, `temper go`, the
mod's run driver and the scripted persons select by these fields and never by label text; only `opt()` and `set_rec()`
read the `(Recommended)` suffix. No label changed, the view stays version 1, and the mod still reads a view with no ids.
An id is a lookup: an answer still counts only on the exact header, question, label, run and step. No question that
goes to the dialog holds a new key, since the question tool refuses one: the ids of a reason, name or Blocking question
sit beside it (`reason_ids`, `answer_ids`, `question_ids`), and the ids of the Scope drift options beside its list of
labels (`drift_ids`). Its cases are in `temper-cases-40.sh` and `tests/mod/ids.test.ts`.

- **M12 (WP08).** The backup push of the mod is removed: during a run every push is refused, to a `temper-backup/`
  branch too.
- **M13 (WP08).** With the mod on, `temper doctor` with `--write` is the person's call: a setup block reaches the
  config only as the call of the option the person picked; `doctor` and `doctor --propose` still only read.
- **M14 (WP08).** The mod guards the files that turn a gate row as it guards the verdicts: the store of reused passes
  (`.git/temper-results.json`), `.temper/preflight.json`, `.temper/decisions.json`, `.temper/setup-tried.json` and
  the rows of the Check run made ahead (`.temper/check/ahead.json`), which Check adopts.

One real run on a Java 24 Maven project (3.2 hours of agent time, 12 tasks) lost most of its time to faults that existed
before any code was written, and a Temper run on this very change (a plan line that could never finish in its time
limit, three fix agents that changed nothing) showed most of them again. Each change below has its cases in
`temper-cases-21.sh` to `temper-cases-30.sh`.

**Before Build (package 1: S1, S2, S3, U3)**
- **Preflight.** The plan gate runs every Validate, task Test, Integration and scenario command once on HEAD, in a
  throwaway worktree, and sorts each into passes, needs new code, environment fault or command fault; the two faults
  fail the gate with the real error. Once per plan: the result is stored and read while HEAD, the commands and the
  setup block hold (`temper plan preflight` runs it again). `plan.preflight-timeout` (300 s); only the person skips it,
  with `plan.preflight-skip: "<reason>"`.
- **Maven rows.** Maven is found after `cd backend &&`, `./mvnw` or `mvnd`. New row `maven filtered verify`: a `verify`
  with `-Dtest=`/`-Dit.test=` under a JaCoCo BUNDLE rule fails (use `test`, or `-Djacoco.skip=true`).
- **The environment contract.** `setup:` in `.claude/temper.config` (`run`, `env`, `services`, `tools`) applies to every
  command the CLI runs and is in every agent prompt; credential names are never set or shown. `temper doctor` shows the
  toolchain, the block and the services, and changes nothing. `temper doctor --propose` writes the block from the
  project's own files, and a failed preflight or Check offers it as one click.
- **ENV at a task gate.** A GREEN that failed on the environment keeps its attempt and worktree; "Check it again".

**Decisions and findings (package 2: Q1, Q2, Q7)**
- A Design answer given after the plan holds Build until `tasks.md` changes (Loop back to Plan is recommended), and
  Build task prompts carry those decisions.
- `review.block-on` defaults to `[critical, high]`; open findings at medium or above recommend the repair, and the
  question counts them per level.
- `temper integrate` runs the Integration command again when HEAD moved since its last pass.

**Fewer wrong clicks (package 3: S4, S7, S8, Q6, Q8)**
- The failure text is the build tool's summary (Maven's failed goal, `Rule violated`, failed tests), never a passing
  test's log line; a time-out says so.
- No fix pass without a fault in its prompt. A fix agent that changed nothing keeps the check failed, with no rerun on
  the same tree, and the question points at the plan or the environment.
- Check says `SETUP` for an environment fault and recommends repairing it, never a loop back.
- "Override and commit" is offered only where it can clear the row.
- Every question has four options at most; the Context answer takes up to 2000 characters (the "Include what is left
  out" option was always refused at 100).

**Less back and forth (package 4: S5, S6, U1, U2, U4, Q4, Q5, Q9, U5)**
- `autonomy.policy: decide`: an armed run goes on through Review and Check by fixed rules (loop back within the budget,
  repair medium and above, never override); anything else and the commit park for the person.
- `temper plan patch`: change one command line of the approved plan, keep the passed tasks, spend no loop.
- A passing check on the same clean tree is reused. The lock never lets a write through without it. A RED made on the
  final code does not count (judged on a task's first attempt). Interfaces match by shape. A person's note is labelled `PERSON`. The mod allows a push to a
  `temper-backup/` branch. The orchestrator can add a marked note to a question.

**The gaps, closed**
- **Q3.** The Build gate's RED then GREEN and Check's tests pass count a run only when the CLI ran it (`temper evidence
  run`, a task test, a group check, integrate, Check) or the person confirmed it; a run an agent recorded with
  `evidence add --exit` is a claim and counts nowhere (`evidence.claimed-runs: count` keeps the old rule). The build and
  fix briefs record RED and GREEN with `evidence run`. `temper evidence void` marks a false pass void: the row stays,
  is shown as void, and counts no more; only a pass can be voided.
- **Q4.** `task start` records the code files as the attempt finds them, so retries and reopens are judged too: a RED
  made on code this attempt had already finished does not count. `build.red-before-code: true` allows no stub either.
- **The policy** also takes the recommended option at a failed group check when no person is needed for it.
- **`doctor --propose`** reads Gradle toolchains, `.java-version`, `.tool-versions`, Docker Compose services (Postgres,
  MySQL, MariaDB, Redis; only when a Docker daemon answers) and Python virtual environments too.
- **A setup for any project.** Three sources: the rules above, the project's CI and devcontainer files (the JDK and
  Node versions, the database services and the variables that point at them), and an environment agent
  (`agents/env.md`) when neither describes the project. One check: a block is written only after the CLI reran the
  commands that failed on the environment with it, and they passed. The person still makes one click.
- **The selftest.** Case file 6 runs on its own (`case-helpers-5.sh`, made by `make-helpers-5.sh`), so the parallel
  runner no longer runs 5 and 6 as one pair.
- **F4 (wp08).** The plan gate's preflight runs each group's Validate and the Integration line only, never a task Test
  or a scenario Test (they need code not written yet), all under one total `plan.preflight-timeout`.
- **M15 (wp08).** A preflight command over its limit is `not checked`, never an environment fault: the row passes and
  names a longer `plan.preflight-timeout`, another command (`temper plan patch`) and `plan.preflight-skip`.
- **M16 (wp08).** A failed preflight is never read back from `.temper/preflight.json`: the next gate runs it again, and
  the failed plan question offers `Check again` (`plan preflight`, then `gate plan`) first.
- **M1 (WP08).** A suite broken after a pass is recorded at Build and asked; integrate passes again once repaired.
- **M8 (WP08).** The config reader merges a key written twice; the template has no empty `build:` or `evidence:` key.
- **M9 (WP08).** A task held on an environment fault offers It is the code; the same fault twice recommends Save.
- **U19 (WP08).** `preflight.json`, `setup-tried.json` and `decisions.json` are run files: excluded, and cleared.

## v9.8.4: the faults one failed run exposed

A `/temper:temper` run of a complex feature (8 criteria, about 30 files, risk H) used 5 Plan passes, 6 fresh reviewers over
3 rounds and 5 Build attempts of a group of 12 tasks, asked about 30 questions and put nothing on the branch. Every task
passed its own gate each time; the group check failed each time. Each fault is fixed with a failing test first, mostly in
`temper-cases-20.sh` (CLI) and `temper-cases-8.sh` (flow).

- **1. A group must be able to pass its own Validate.** New plan gate row `group validate order`: it fails when an existing
  test file a group's Validate runs (named in the command as a path or a dotted Python module, inside a folder it names,
  or named by a script it runs) is
  edited by a task of a group that is not on that group's worktree, and names the file and both groups. G1's Validate
  ran selftest cases 8 and 9 while the task that updated them was in G2.
- **2. A failed group check stops recommending a blind retry.** The group gate keeps the FAIL lines of its Validate output
  (read from the whole output) and counts the group's failed checks; the question shows the first three lines and the
  count, and the reason is no longer cut to 200 characters. When every task passed and the group check fails, the first
  and recommended option is one Build fix agent on the group's merged tree (`temper group fix G<n>`, then
  `group fix G<n> --commit`, which commits the agent's work on the group branch as the CLI's own commit and clears the
  group's gate, so the next action checks the group again as an ordinary call). From the second failure on, "Run the
  group's tasks again" is never recommended, and once a fix of the merged tree did not make the group pass, the fix is
  not recommended again either: the loop back to Plan is, or, with that step spent, Save for later (an end to end run
  on a mock project looped on the recommended fix 131 times before this). A FAIL line is what failed (FAIL, ERROR, an `...Error:` line), not a
  traceback's header.
- **3. Loop backs carry what was learned.** a: a step back from Plan keeps Plan's open fresh review findings, and the reason
  and findings of a step back reach every stage the run comes through again (the Plan agent after a loop to Intent); the
  Intent brief revises an accepted intent on a loop back instead of changing nothing. b: the fresh review round limit no
  longer dead ends after a loop back: a loop back to Intent, Plan or Design, or a replan, earns one more round once
  `plan.md` or `tasks.md` changes (the choice is stated in `docs/flow.md`). c: a step back from Build carries each failed
  group check first, with its reason, count and FAIL lines, and no task's RED run.
- **4. The fresh review converges.** The first round runs a fourth lens, `tests` (which existing tests the change breaks,
  and which task updates them). Each later round is a `recheck`: it gets the earlier findings and the changed task blocks,
  checks only whether each finding is fixed, and keeps the earlier paraphrase. Only high findings block; medium and low
  ones are no longer a recommended revision and reach the builder of the task they name as a `Plan review note`.
- **5. Build model by risk.** With no `build.grouped.task-model`, a plan whose complexity is complex or whose risk is H
  builds its tasks on sonnet (`temper model --all --source` says `task=sonnet (risk)`); an explicit task model still wins.
  New plan gate row `shared production files`: it fails when more than two tasks of one group declare the same production
  file, and says to merge them.
- **6. Selftest isolation.** a: `run_env.py` keeps git's `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_n`, `GIT_CONFIG_VALUE_n`
  family together (`_KEY_` read as a credential stripped the keys and kept the count, so every git call under the CLI's
  runs failed with "unable to parse command-line config" in Claude Code cloud sessions); a family with a credential key
  (an extra header, a helper) is left out whole. b: each case file of `test-temper.sh` starts from an emptied work folder
  (files 3, 6 and 9 still go on from 2, 5 and 8).
- **7. Small frictions.** a: "Include what is left out" passes the whole text to Plan (it was cut to 100 characters, and
  Plan was told "already co"). b: `.temper/brief.md` is in the run files `temper init` lists in the clone's
  `info/exclude`. c: `temper output <stage>|G<n>` prints the last output of a gate or a group gate, read only (with the mod
  on, the session cannot run `printenv` or a test runner). d: `temper usage add ... --fill` puts a background agent's time,
  from its completion notice, into the row recorded without one (the report showed "-" for Design and Build).
- **Found by the full SDLC run** (a mock pyjokes project through Intent, Plan with two fresh reviewers and a recheck,
  Design, grouped Build, a Review finding sent back to Build, Check, the commit, then a `/temper:fix` run; plain, with the
  mod and with its driver). After a step back to Build, the fix pass now ends with `temper integrate`, which on a run
  integrated already reruns the scenario tests on the fixed tree: the step back had cleared Build's scenario rows, and a
  model's record pass was asked to record rows the CLI can run. And Build failing the same way after "Run Build again"
  no longer recommends running it again: Save for later is recommended, and the question says so (following the
  recommendation had relaunched the fix pass forty times on one failure). The same holds at Check for a measurement the
  run still cannot take after "Run Check again" (a benchmark run without coverage.py ran Check again 52 times).
- **Haiku or Sonnet for the Build task agents, measured** (`docs/evidence/haiku-sonnet-task-agents.md`, 18 benchmark runs):
  the same quality (every run passed every hidden test), Haiku about 9% cheaper a run and 13% slower; its one run with
  retries was a plan defect no model could build.
  The default stays as above: Haiku for simple and medium plans, Sonnet for complex or risk H. `bench/run.mjs
  --task-model` and `bench/compare_models.py` run and tabulate such a comparison.
- **A task its plan cannot build is not retried.** When a Build task's test needs a change in a file the task does not
  declare, its agent records `temper task blocked N --needs <path> --reason '<why>'` (the CLI checks the path is outside
  the task and names the tasks that declare it). The task's gate then fails once and parks the group, with no retry and
  no escalation, and the question recommends the loop back to Plan, naming the file and its task. In the benchmark one
  such task took two Haiku and two Sonnet attempts, each stopping for the same reason, before the loop back.
- **Live checks of the new brief instructions** (`docs/evidence/live-brief-checks.md`): real Sonnet reviewers ran the
  `tests` lens and the recheck rounds as written, a real Haiku task agent recorded `temper task blocked`, and the group fix
  agent fixed a failed group. They found one waste, now fixed: the person's Context check answer, written into plan.md's
  Context Map, made the fresh review stale and launched a recheck round with nothing to check; the review's digest now
  leaves the Context Map out. A second pass reached the rest: a Haiku agent that could not dodge its block recorded it in
  both runs, and the live Intent agent revised an accepted intent on a loop back by setting it back to draft and
  leaving the scenarios to Plan, which the Intent brief now asks for (the person accepts the revision at the Intent
  question).
- **8. A request that arrives as a spec.** A proposal only: `docs/decisions/0017-a-request-that-arrives-as-a-spec.md`
  drafts a lighter route for a request that already states its rules, files, tests and done condition. Nothing of it is
  built.
- **The lock is never seen without its owner** (galando/temper#114, merged with this release). The lock folder was made
  first and its owner line written after, so a waiter past its wait could find it with no owner, take it for a foreign
  lock and write past a live holder: a ledger row was lost now and then on CI (L1, M4). The lock is now made under another
  name with its owner inside and renamed into place. A foreign lock with no owner line is still written past after the
  wait with a WARN (fail open). Case A16 in `temper-cases-17.sh` stalls mkdir to show the race.
- **The pyjokes runs in CI.** `scripts/e2e/pyjokes.ts` adds three end to end scenarios on a mock pyjokes project, run in
  every mode by `bun scripts/e2e/run.ts all`: `pyjokes` (faults 1, 2, 3a, 4, 5, 7c and 7d in one run), `pyjokes-full`
  (risk H with two fresh reviewers and a recheck, Design, a Review finding sent back to Build, then `/temper:fix`) and
  `pyjokes-blocked` (`temper task blocked` parks a task at once and the loop back to Plan is recommended). The e2e job's
  time limit goes from 45 to 60 minutes.
- **Housekeeping.** The embedded Python of `_earlier_build`, of the usage summary and of the grouped Build report moved to
  `scripts/earlier_build.py`, `scripts/usage_ops.py` and `scripts/group_report.py`, and `group fix` and `output` live in
  `scripts/group_fix.py` and `scripts/output_ops.py`, keeping the CLI under the plugin directory's 256 KiB limit for a
  file with the lock fix of galando/temper#114 merged as well (the two together were 172 bytes over it).
- **The mod's tests type check on Claude Code 2.1.323.** That release (out the day of this one) has no MultiEdit tool in
  its types and adds `isCollapsed` to the band's props, so `claude plugin validate --strict`, which CI runs on the latest
  Claude Code, failed on three test files, on main as well. The tests now type check on 2.1.287, 2.1.322 and 2.1.323; the
  guard still refuses a MultiEdit from an older host.

## v9.8.3: the run's state machines made explicit

Each piece of run state that several writers moved (the run's stage, a group, a task, the small change window, the
end report, a finding, the stop marker, the mod's pane and held run) now has one table of allowed moves or one
function every writer goes through; the moves that were possible but wrong are refused. Tests: `temper-cases-17.sh`
(CLI), `temper-cases-18.sh` (flow), `temper-cases-19.sh` (guards), `tests/mod/state-machines.test.ts` (mod).

- **CLI.** `state loop` takes only stages of the run, backward from the stage it is at; a backward `state set
  next_stage` goes back the same way (one `_go_back`). `override` takes only a gate of the run, and a skip covers the
  verdict it was given for, not a newer one. Task status moves through one table (`task_cover.py` `TASK_MOVES`); a
  group's status follows its gate, and a reopen drops its Continue and its integration. The small change window opens
  only at the run's stage and closes on any move. `end_report`, the bookkeeping `stage` and the evidence of Commit and
  Pipeline follow a step back. `intent complete` refuses a draft. `state set` refuses the CLI's own keys and checks
  `run_mode`, `pipeline_round` and `regression_test`. Build to Plan is once per run in the CLI as in the flow
  (`loop_step.budget`).
- **Flow.** A RED that passed beside an undeclared change or a foreign commit stays FAIL (not COVERED); a covered task
  shows as covered. Task readiness, task done, intent status and Blocking questions each have one definition; finding
  state is `findings.finding_state`. The acceptance writer's launches and corrections are bounded. An earlier stage
  with no verdict shows todo, not passed. The agents a stage named are kept in `.temper/agents-named.json`.
- **Lock.** A row is no longer lost when writers queue under load. The lock is freed in one rename, so it is never
  seen without its owner; a waiter goes on waiting for a holder that is alive (up to `TEMPER_LOCK_MAX_S`, 60 s) or
  that is between its mkdir and its owner line; a lock freed while a waiter looks at it is taken, not written past;
  and a lock is broken as stale only when its owner's process is gone. (L1, L2 and F6 lost a row now and then on CI.)
- **Guards.** The stop marker names its session and keeps its refusal count; a marker of another session, or older
  than a day, no longer blocks. The fallback commit guard accepts `commit_complete`.
- **Mod.** The run is held when view.json is lost at any stage, Commit included; an interrupt ends the driver as
  stopped; an answer is recorded once; an Allow once is spent after the call ran; the skill window and the kept
  request end with their step and run; `regression_test` is lifted only by the person during a fix run.

## v9.8.2: plan.context-check off finally means nobody is asked

- **`off` passes a pending review.** *Before:* the Plan agent always writes `- reviewed: pending`, and `plan_ops.py` failed
  that row in every mode, so `plan.context-check: off` had no effect and unattended runs parked at the Plan gate. *Now:*
  in `off` mode a pending review passes the row (`scripts/plan_ops.py`), and `temper next` does not ask the Context check
  question (`scripts/flow.py`). A missing `- reviewed:` line still fails in every mode, and `auto`/`always` are unchanged.

## v9.8.1: what the plugin directory asks of a plugin

The plugin directory refused 9.8.0. These changes answer its findings that apply to every publisher; the rest
(hooks, mods and scripts) it accepts only from Verified organizations.

- **The mod runs one program, the plugin's own CLI, with no shell.** *Before:* the run driver ran each call the CLI
  wrote through `bash -c`. *Now:* it runs `scripts/temper` by its path with the call's words as plain arguments
  (`hooks/temper-mod/core/argv.ts`); a call that needs a shell goes to the conversation. The CLI's setup calls are its
  own subcommands for this: `temper config init` (in place of `mkdir -p .claude && cp ...`) and `temper guards install`
  (in place of `bash .../install.sh`).
- **`/temper:temper` and `/temper:fix` pass on unchanged.** *Before:* when the run driver handed a run to the
  conversation, it replaced the command's arguments with `next`, `discuss <text>` or `chose <label>`. *Now:* the
  command goes on as typed, and those words come as one note the model reads after it (`commands/temper.md` says so).
- **The PreToolUse hook only denies.** `scripts/guards/block-stdin-wait.sh` is now `scripts/guards/block_stdin_wait.py`:
  on a hit it prints one JSON answer, `permissionDecision: deny`, and prints nothing otherwise.
- **An icon** (`.claude-plugin/icon.png`), and the README says what the hooks and the mod run, start, read and change,
  and where `gh` uses your GitHub login.

## v9.8.0: proof the CLI computes, questions the person clicks, and fewer steps

Built from what a benchmark showed (`docs/evidence/bench-2026-11.md`): on complete specs, plain Claude Code was as
correct as Temper at a tenth of the cost; on vague requests, asking before building mattered, and a one line prompt
asked as well as Temper. 9.8.0 keeps what only Temper does (a gate the model cannot talk past, the person's decisions
on record), proves more of it with the CLI instead of an agent, asks better questions, and takes out steps.

**Check, run by the CLI**
- **The CLI runs Check itself (`temper check run`, new `scripts/check_run.py`).** *Before:* a Sonnet agent ran the suite
  and typed the results into the ledger; a row it forgot (coverage recorded as "none") failed the gate for no fault of
  the code. *Now:* the CLI runs the suite with coverage, each scenario's `Test:` command and the new gates below, and
  records each as a real run. It detects Python (pytest, unittest, coverage.py), Node (npm test; jest, vitest, c8 or
  `node --test --experimental-test-coverage`), Go, Rust, Maven and Gradle; `check.commands.test` and
  `check.commands.coverage` name the commands for any other stack. The Check agent runs only for a stack the CLI cannot
  read, and for criteria validated by code or a metric.
- **When no coverage tool is there,** the coverage row says what to install, and Check runs again once it is.

**New gates, computed by the CLI**
- **Mutation score (`mutation score >= threshold`, `check.mutation-threshold`, default 70).** Coverage says a line ran;
  this says a test would notice it break. One small bug at a time is planted in the lines the run changed (a comparison
  flipped, + and - swapped, a constant moved by one, `and`/`or` or `&&`/`||` swapped, `true`/`false` swapped, a `not`
  dropped, a call deleted), and the suite must catch it. Python is read as a syntax tree; JavaScript, TypeScript, Java,
  Kotlin, Go, C#, Rust, Swift, Scala, C, C++, PHP and Ruby as text, never inside a string or a comment. At most 40
  mutants and a time budget (`TEMPER_MUTATION_BUDGET_S`, default 300 s).
- **Regression proof for a fix (`regression proof`).** The tests a fix added or changed must fail on the code before the
  fix and pass with it; the CLI checks out the old code and runs them.
- **Acceptance tests written before Build (`acceptance tests written before Build`, new `agents/acceptance.md`).** Before
  the first task, an agent that writes no code writes tests from the approved intent into the spec's `acceptance/` folder
  and locks them (`temper acceptance lock`). Check runs them as locked; a change after the lock fails the gate. A builder
  can no longer encode the same wrong guess in its code and its tests.
- **Scope in every run.** The commit gate's declared-files row applied to unattended runs only; now every run with a plan
  has it. Test files, the spec folder and files the person allowed at a Scope drift question count as in scope.
- **A criterion validated by hand is confirmed by the person** at the Check question ("Confirmed"), never claimed by an
  agent. A deferred optional criterion needs no evidence (as in the Build report).

**Better questions**
- **Intent drafts the rules, the person clicks.** It works through a checklist (who may do it, time limits, amounts,
  states, where it shows, exceptions) and writes each open rule as a Blocking question with ready answers
  (`choices: A | B | C`, the recommended first); what it does not ask goes under `### Assumptions`, for the person to scan.
  Where a house rule gives a default, it asks whether the rule holds. It runs on Sonnet. It no longer asks for a reviewer
  (the header is optional: the person who accepts at the gate is the approver).
- **Carry forward works.** Carry forward on a Blocking question used to record nothing, leaving the Intent gate red with
  no way out; `temper intent carry` now marks it Deferred.
- **The Context check names what the plan leaves out.** "Is this the right context for the plan?" became a concrete
  question from the map's `ignore` and `gap` lines ("The plan leaves out: refunds in the export. Is that right?"). Any
  answer but "As planned" sends Plan back to revise with it (`temper plan review --redo`); before, the answer was only
  written down.
- **Design runs on risk:** for a complex plan, and for a medium one only at risk H (Plan raises it for a data model,
  money, permissions or an integration). `risk` is kept by the CLI (`temper risk`), so it cannot be lowered to skip
  Design. A concern the person must decide becomes a Blocking question with ready answers, asked before the Design
  question. ADRs only in a project that keeps them (a `docs/decisions/` folder with one in it).

**Fewer steps**
- **Unattended, with no setting.** "Autonomous: run the rest unattended" is offered at the last question before Build
  (the plan question, or the Design question when Design runs). `autonomy.enabled` is no longer read; it was `false` in
  the shipped config, so most runs never saw the option. An unattended run takes a Build task an earlier task already
  built as done, instead of parking; `auth/`, `payment/` and `billing/` changes park it only when they are outside the plan.
- **A plan with one group goes on to the merge by itself;** the Build question gains "Change something".
- **The report page is written without a question.**

**A lighter orchestrator (measured: 127 main session turns, 87k tokens read each, for one feature)**
- **`temper go` (new `scripts/go.py`).** The CLI runs its own steps (gates, group starts, merges, Check's run, an armed
  run's moves) and hands the session one compact object at the next agent launch, question or steps. In the measured run
  59 of 88 tool calls were such steps, each a turn re-reading the whole conversation. `temper next --json` stays the full
  view; the loop in `commands/temper.md` uses `temper go`. It never runs a call only the person may cause.
- **The loop runs on Sonnet** (`model: sonnet` on `/temper:temper` and `/temper:fix`): it relays the CLI's decisions and
  the person's answers, and decides nothing, so it need not run on the session's model. (Ignored where the model is
  restricted, or in auto mode for a model it does not support.) With the mod loaded, the mod carries the run itself
  (round 5, below), and the loop runs only what is handed back to it.
- **One build agent per chain.** Tasks that run one after another anyway (a dependency, a shared file) go to one agent,
  which starts, builds and gates each in order (`task gate --if-running` covers a task it left running); independent
  tasks keep agents of their own, launched together. In the measured runs every task ran alone.
- **The commit message is drafted by the CLI:** `feat(<slug>): <the intent's title>`, and for a fix the RCA's title,
  root cause and regression tests.
- **"Accept it as done" records its reason itself** (an earlier task built it), with no second question.

**No more loops at Check (measured: two runs at $26.91 and $38.24, against about $3 for the others)**
- **A step back from Check carries what failed.** Build's fix pass got only the name of the failed run ("acceptance
  (written before Build)"), passed its own tests, and Check failed again on the same test. The step back now keeps the
  tail of each failed run's output (the failing test and its assertion) and, for a low mutation score, the surviving
  mutants, which the mutation row also names.
- **A wrong locked acceptance test has a way out.** In one run the test assumed customer ids were global, and the code
  numbers them per tenant: no change to the code could pass it. Check now offers "Correct the acceptance test" with the
  person's reason (`temper acceptance reopen`, only the person's); the writer corrects only the failing test against the
  intent and locks it again, and the gate row shows the reason. It is the recommended option once a step back to Build
  left the same failure.
- **A lock is taken once.** A builder in one run edited a locked test; it could have locked it again. `acceptance lock`
  now refuses a second lock unless the person reopened it, the lock keeps a copy, and "Restore the locked tests"
  (`temper acceptance restore`) puts a changed test back.
- **Design may change the tasks.** A Design answer (a fee floor) changed tasks.md, and Build refused to start ("the
  approved plan changed"). The Design question now says what Design changed ("Task 1 gains src/floor.sh", "new Task
  7", from a copy of the tasks the CLI keeps at the plan gate), and Continue approves them with the design; an
  unattended run parks for the person instead. A Build agent that edits tasks.md is still refused.
- **Files outside the plan at the commit gate:** "Add to plan" is the first option (the same record as at a Scope drift
  question), next to Override and commit.

**Shorter runs, and rules that cannot be skipped**
- **Check runs while Review reads.** Review writes no code, so the CLI starts Check's suite, coverage and mutation score
  in the background when the Review agent starts (`temper check ahead`); `check run` adopts that run when the tree is
  unchanged since, and runs again otherwise. On a project with a slow suite this takes the whole Check run off the
  clock.
- **Design on a fully specified request is skipped.** A complex plan runs Design when Intent had to ask the person
  something or when the risk is H; when the request settled every rule and the risk is below H, the plan goes on to
  Build.
- **A failing locked test is triaged before a Build round.** An agent that changes nothing reads the failing test, the
  intent and the code, and records which looks wrong (`temper acceptance triage`); the Check question recommends
  correcting the test or stepping back to Build from that, and says why. Before, a wrong test cost a Build and a Review
  round first.
- **The rules checklist is recorded.** A draft intent lists each checklist item (who, when, how much, states, where it
  shows, exceptions) as asked, assumed or not applicable under `### Rules covered`, and the Intent gate fails one that
  leaves an item out. Exceptions name six kinds: excluded or exempt, twice, at the edge, gone, someone else's, halfway.
- **House rules first.** A Blocking choice marked `(house rule)` (what CONVENTIONS.md, CLAUDE.md, AGENTS.md or the code
  already does) is listed first by the CLI, as the recommended answer, whatever order the model wrote.
- **Every state is tested.** When intent.md lists `**States:**`, the acceptance writer brings a record into each and
  reads it back, and tries each action in each state; `acceptance lock` refuses tests that never name a listed state.
- **`scripts/temper` is under 256 KiB again** (it had grown past the plugin directory's limit): three Python blocks
  moved to their own files, and `quality-check.sh` now fails any file over 256 KiB.

**Fixes**
- **"Accept it as done" looped.** A covered Build task's option shared the move `accept` with accepting a review
  finding; it is now `covered`.
- **The CLI called from a subfolder** (after writing a file in `docs/`) started a second `.temper` there; it now finds
  the project's `.temper` above it (never from the home folder or inside the plugin folder).

**Not done, on purpose:** small plans still build in worktrees. The benchmark showed the time in Build goes to model
turns, not to worktrees; the one problem worktrees caused (the loop above) is fixed.

**The benchmark** moved to `bench/` (no part of the CLI) and gained a TypeScript task, a mutation scorer for C-style
languages and a Node grader. The 9.8.0 numbers are in `docs/evidence/bench-2026-11.md`.

### Round 5, in the same version: a main session that only relays, and fewer turns for it

Built from round 5 of the benchmark (`docs/evidence/bench-2026-11.md`), which priced every request from Claude Code's
own logs. The main session cost $0.30 to $0.82 a run, about evenly reading the cache, writing it and writing output;
Opus (Plan and Design) was about half of every run. A Haiku 5.5 main session is nearly free while its context stays
under 100,000 tokens and five times dearer above it, and in round 4 it left the script. Round 5 makes the session unable
to leave the script, and takes out the turns and the context it did not need.

**The main session relays, and the mod holds it to that (`hooks/temper-mod/core/session.ts`)**
- During a `/temper` run the conversation itself writes no file with the editing tools, runs only the temper CLI and
  commands that only read (no redirect into a file, no interpreter, no `git add`, `git commit` or `git checkout`),
  launches only an agent the CLI named at the run's stage with its type, its model and its prompt as given, and asks
  only a question the CLI gives at the step (header, question and option labels) or a Scope drift question. The agents
  keep their stage rules. A small change window the person opens, and a skill they choose (Grill Me, Teach Me), are the
  two openings; a command the CLI wrote whole passes as written. Round 4's Haiku session edited the spec files and the
  locked acceptance tests and asked a question of its own; a Sonnet session once launched the root cause agent on a
  cheaper model. Each is now refused, with what to do next.
- The CLI set in a variable in the same command (`T=/path/scripts/temper; $T go`) is read as the CLI; a program in a
  variable set anywhere else is refused.
- A run starts from the person's request, word for word: the mod keeps what they typed after `/temper:temper` and
  refuses a `temper state init` whose `--feature` differs from it, in the conversation that typed it (a Haiku session
  started a run of a dozen rules with a one line summary, and every agent planned from that line).
- The Intent agent's prompt carries the request with one period after it (a request that ended with a period got two;
  a Haiku session tidied them, and the guard refused the launch as another prompt).
- A typed change request goes to the stage's agent (`temper state redo <stage> --reason`), never to the session.
- The view carries what the guard needs: `next.agents` (every agent named at the run's stage, the current action's
  first: a task's `task start` turns the next action into `wait` before its agent is launched), `blocking_asks` and an
  option's `skill`. The mod keeps no memory of its own; the engine loads it again between turns.

**The plan keeps the request's routes**
- The plan gate's new row `request routes kept`: every `METHOD /path` the request names is in plan.md or tasks.md,
  method and shape unchanged (a parameter may be renamed). A Plan once built the request's `POST /invoices/{id}/refunds`
  as another path, and Design, the acceptance tests and Build followed it. A request that names no route passes, and so
  does a route the person changed in the intent's Decisions.

**Fewer turns, and less for each to read again**
- **`temper intent answer '<question>' '<answer>'`** writes the person's answer to a Blocking question into Decisions
  (and a `Design:` question's concern in design.md). The session no longer reads intent.md and edits it with a script
  (two to four turns a stage that asks, and where a cheaper session began editing spec files). `temper go` hands each
  Blocking question ready to ask, with its answer call; one call takes every answer of a dialog.
- **`temper spec branch` and `temper spec commit '<message>' [-- FILE...]`**: leaving Intent, Plan or Design, and the
  record commit, are temper calls (before: `git checkout`, `git add` and a `git commit` that had to go in a call of its
  own). **`temper spec deviations`** writes plan.md's Deviations from build-context.json (an instruction to the session
  before).
- **An agent's gate call prints its failed rows only** (`temper gate <stage> --brief`): the passed rows were the
  largest single source of the session's context (22,000 to 28,000 characters a run).
- **`temper go`'s question is slimmer**: the question as it is asked, and per option only what the answer runs.
- **A fix pass's findings are short** in the agent's prompt (200 characters each, with the file that holds them whole):
  a raw traceback in a prompt was copied wrong by a cheaper session, and its launch was refused.
- **The fix run's lesson is written by the Fix agent**, which has the root cause in hand, not by the session at the
  commit.
- **Every view is written by one path** (`cli_ctx.py view`), with the models `temper next` resolves: a view written by
  `group start` once named an agent with another model than `next` did, and the guard refused the launch.

**Agents**
- Plan and Design are told never to read the plugin's scripts to learn a format (a measured Plan spent three turns in
  the CLI's Python on the `Test:` line).

**The benchmark**
- A resumed session's result carries the session's cumulative cost; `run.mjs` added the results up, so a resumed run
  was counted two or more times. It now takes the last result when the costs only grow.
- The SDK stream records each message's output count at its first block, so a price from `transcript.jsonl`
  understates output. `run.mjs` copies Claude Code's own session logs into the run folder, and the new
  `bench/loop.py` prices every request from them (Opus $4/$20, Sonnet $2/$10, Haiku $0.10/$0.50; cache reads $0.20,
  $0.10 and $0.01; a 5 minute write 1.25 times the input rate, a 1 hour write 2 times; a Haiku request over 100,000
  tokens 5 times), matching the SDK's cost to the cent, and shows the main session turn by turn.

**Measured** (round 5 in `docs/evidence/bench-2026-11.md`, 27 counted runs of four tasks): with the loop on Haiku 5.5
and these guards, the main session cost $0.03 to $0.09 a run (the Sonnet loop: $0.27 to $0.85), and every run met
every hidden test, every fact of the brief and the plan's scope (partial-payments only once the request checks were
in: before them, 14/26 twice). A whole run was about 30% cheaper on a bug and 23% to 27% cheaper on a feature. The
Sonnet loop on the same code was only a little cheaper. Opus (Plan, Design, the root cause agent) is now two thirds to
four fifths of a run.

**The loop stays on Sonnet** (`model: sonnet` in `commands/temper.md` and `commands/fix.md`). A guarded Haiku loop
met every hidden test in 7 of 8 runs of a confirming pass (the eighth stopped at Build on three CLI defects, fixed
below). Without the mod nothing guards it, and in 8 runs with no mod it left the script twice: it edited and committed
the project's `CONVENTIONS.md`, and it started a run from a one line summary of the request (17/26). With the mod the
mod carries the run and the loop's model matters only for what is handed back, the steps that need judgment; without
it Sonnet is the loop that was measured safe. Against vanilla Claude Code on the same tasks the same day, Temper met
every hidden test where vanilla did and more on the vague task (11/11 against 8/11).

**Work the CLI does instead of a model**
- **The CLI draws the Plan, Design and RCA panels** (`temper panel plan | design | rca <rca.md>`) from the files those
  stages wrote; it counts the criteria, the scenarios and the files to create or modify itself. Each Opus agent drew
  its own 76 column box (a Python script to pad it, then the box again as its last message: 2,000 to 3,000 output
  tokens and 30 to 40 seconds a stage) and now returns one line. Plan writes the terminal drawing of its diagram into
  plan.md's Diagram section; RCA writes `rca.md` as plain fields, which Fix and the fix commit message read.
- **The project brief** (`temper brief`, `.temper/brief.md`): from the request's own words (file paths, backticked
  names, routes, nouns) the CLI ranks the files the request reaches, lists their tests, copies the conventions and the
  best ranked files whole, and lists the project's files. The Plan and Design actions make it; RCA makes it from the
  bug text. They read one file first, instead of `cat` of the whole project and a second turn to read the saved output.
  A word counts by how rare it is in the project, a file with no extension (a script) is read, and every part is
  bounded: on a 529 file repository the brief is 57 KB in 0.3 s; on 7,810 files, 42 KB in 7 s.
- **Intent asks Who, When and How much first.** Two measured runs skipped a refund window: one wrote "When: not
  applicable (no time window in the request)", the other assumed "no time limit" while it asked where refunds show.
  The Intent gate fails both: the request's silence is the reason to ask, and within its six questions the first three
  items of the checklist come first.

**The mod carries the run (the run driver, `hooks/temper-mod/core/driver.ts`)**
- With the mod loaded, `/temper:temper <request>` (no run active) and `/temper:temper` (a run active) are carried by
  the mod itself, with no model in the main session: it runs `temper go` and the calls the CLI gives, launches each
  agent the CLI names with its type, model and prompt as given and waits for it, prints the panels and the report,
  asks each question the CLI gives (its Blocking questions too) and runs the calls of the answer the person picks.
  The guard checks its questions and agents as it checks the session's.
- It hands the run to the conversation for what needs a model or the person's words: a typed answer (as `discuss`),
  a skill, the HTML plan review, a small change window, a pull request step, an agent's DRIFT rows, a name question,
  a failed call. The CLI holds the run, so the conversation goes on from the same state. Without the mod, a
  `/temper:fix` run, a run word or a second request, the conversation carries the run as before.
- An option the conversation must carry out (a skill, the HTML plan review, a small change, a name to type) is handed
  over as `chose <label>` before any of its calls runs, and the conversation carries it out as the answer given, with
  no second question; a list of steps with one only the conversation can do (a pull request) is handed over whole, so
  none is left half done. Found by the e2e driver below: a skill chosen in the dialog was asked about again, never run.
- `/temper:fix <bug>` with no run active is carried too: the CLI's setup, the root cause agent with the prompt of
  `commands/fix.md`, the panel from `rca.md`, the run's state, the fix branch, then the same loop.
- The e2e driver gains a third mode, `driver` (`bun scripts/e2e/run.ts all`): the same 20 scenarios carried by the run
  driver's core, the real CLI's setup included. It found the half done steps above, and a scenario that wrote the pull
  request body into the project (`reference/pr.md` says `mktemp`), which the commit hook the setup installs refuses.
- The driver's question dialog shows each option's description and its preview (the Context check's table): `$.ui.ask`
  takes labels alone, and the mod's own tool call hook gives the AskUserQuestion it raises the CLI's descriptions and
  previews back (a live probe confirmed the dialog receives them). An interrupt stops the driver between steps and
  while it waits on an agent, with no model turn after it; a CLI call streams, so a long Check inside `temper go` has
  no time cap.
- **Checked in an interactive terminal** (Claude Code 2.1.318, tmux): `/temper:fix` held the command while the root
  cause agent worked, the agent's permission prompts reached the person, and the gate dialog showed each option's
  description. Two defects showed there and nowhere headless, both fixed: a panel logged in one call was drawn as one
  row with marks for its line breaks and cut at 2000 characters (now logged a row at a time), and at Esc the read of
  the aborted child threw, which the driver took for a failure and handed to the conversation (now it is the stop, with
  no model turn after it). Probes in the same terminal confirmed both fixes and a hand back (`next` with new words).
  The rest of that run was not taken further: answering a permission prompt is the person's.
- The mod's reviewed calls gain `agent.spawn`, `ui.ask`, `ui.log`, `clock.now` and `process.spawn` (the one process
  call, for the CLI's calls): `scripts/check-mod-calls.sh`, `docs/mod.md`, `docs/trust.md`.
- Measured on vague-refunds (2 live runs, `docs/evidence/bench-2026-11.md`): the run the driver carried to the
  commit cost $0.00 in the main session, with no main session turn, $1.69 and 678 s in all (the Haiku loop on the
  same task: $2.00 to $2.31, 689 to 1,010 s). The other run handed back at the Intent gate on a driver defect, fixed
  (the action's `gate` call after the Blocking answers), and the conversation finished it: 11/11.
- **The final pass** (the four tasks twice on the final code, `docs/evidence/bench-2026-11.md`): against 9.8.0 before
  round 5 a run costs 28% to 54% less and takes 15% to 45% less time, with 7 of 8 runs meeting every hidden test.
  Against vanilla Claude Code it costs 1.3 to 1.4 times as much on a bug and 4 to 5 times on a feature.
- **The shipped code, measured** (16 runs, the Sonnet loop, with the mod and without, `docs/evidence/bench-2026-11.md`):
  every run met every hidden test, and every vague-refunds run met all 5 facts, its Intent agent asking the time limit
  each time. With the mod the driver carried 7 of 8 runs with no main session turn: a bug run it carried whole cost
  $0.45 to $0.50 in 88 to 110 s, a feature $1.93 to $2.28 in 11 to 14 minutes (means), 31% to 55% less than before
  round 5 on three tasks. Without the mod the Sonnet loop stayed on the script in all 8 runs, at $0.28 to $0.97 of main
  session a run.

**Build: faster, from where the measured time went**
- **The CLI draws each Build task's panel** (`temper panel task N...`, after the task gates) from what it recorded:
  the attempt, the RED and GREEN runs of `task test`, the gate's verdict and reason, the files of the task's commit and
  the scenarios the task owes. A Build task agent drew the 76 column box itself, with a Python script to pad it: about
  a minute of each Haiku Build agent's three, in the 16 runs of the shipped code, and the driver never showed that box.
  The agent now returns one line a task (`TASK N: done`, or `TASK N: stopped: why`), and the driver shows a stopped
  line, the one thing the CLI cannot know.
- **A command that would wait for input until the Bash timeout is refused** (`scripts/guards/block-stdin-wait.sh`, a
  `PreToolUse` hook on Bash in the plugin's hooks, with the mod or without it). Claude Code runs a command that holds a
  heredoc with its input left open, so a `cat > file` with no input in it waits two minutes, and the agent gets
  nothing back. In the 16 runs, 4 commands of Build agents did this: 480 seconds, 14% to 24% of each of the 3 feature
  runs it hit. Replayed through the guard, the 902 Bash commands of those runs had exactly those 4 refused. It acts
  only in a folder with a `.temper` folder at or above it, and fails open.
- **Measured** (`docs/evidence/bench-2026-11.md`, 10 runs): no command hung, and a Build task agent took 122 s on
  average against 193 s. A whole run moved less than its run to run noise (6% to 10% faster with the mod on the two
  feature tasks). Every hidden test passed. The same page has the seven other benchmark tasks on this code against
  vanilla Claude Code: vanilla met all 84 hidden tests, Temper 82, at 3 to 13 times the cost.

**From the first hands-on run in a terminal**
- **Autonomous is Build alone** ("Autonomous Build: run Build unattended"): Build runs every group and task by itself
  and parks if it stops; when its gate passes, the run goes on to Review and turns back to interactive, so Review,
  Check and the commit ask the person as in every run. An armed Review or Check no longer loops back by itself. The CLI
  records that Build ran unattended (`ran_unattended`, set when the person arms the run, refused to `state set`), and
  the commit gate still holds such a run to the plan's files and to `autonomy.park-on-touch`.
- **One answer is one decision.** With the mod carrying the run, the answer in the dialog reached both the guard's
  hook and the driver's own record, and the pane's "Your decisions" listed it twice. The book keeps an answer once per
  run, step and stage.
- **A stage that waits for the person is not red.** The bar drew Intent red before its first question: its check
  "failed" only because the Blocking questions were open. The view now marks such rows (`waits`): open Blocking
  questions at any stage, the Context check and a fresh review at Plan, a criterion only the person confirms at Check,
  and a criterion record the CLI writes itself at Build. The mod draws the stage as current; a real failure stays red.
- **Panels in the mod's output are a few rows.** A panel logged a row a call read as forty rows of "temper:", and a
  dialog's preview cannot hold one ("cannot be shown in full", seen in a terminal). The driver shows each CLI panel as
  its title, a row a fact and a row a section, and says where the Plan's diagram is; without the mod the conversation
  prints the whole box, which draws in markdown.
- **A Temper agent's message is drawn in full**, where the engine folds a message from another agent into one line
  ("Message from @temper-temper-plan (ctrl+o to expand)"). Other senders, the ctrl+o view and the mod's off mode keep
  the engine's drawing. Written against the documented message row; not yet seen live.
- **The Blocking questions come in one dialog**, four at most (the rest in the next), as the conversation already asked
  them without the mod: the driver asked six in six dialogs. `$.ui.ask` raises the first question, and the mod's tool
  call hook puts every one in and reads back each answer (checked in a terminal: one dialog, a tab a question, a review
  before Submit, every answer returned). When the engine keeps only the first, the rest are asked one at a time.
- **The fresh review's findings below high are the person's call at the plan question.** Only a critical or high
  finding failed the plan gate; medium and low ones passed it, and the question offered Stage by stage as if nothing
  were found (a person who asked for the review saw two medium findings, one a real gap, go on unseen). The question
  now names the open findings and offers Revise the plan (the Plan agent fixes or contests each, then the plan is
  checked again): first and recommended when one is medium, after the ways on when all are low.
- **A manual task's name question can be shown.** It held one option (Cancel), and the question tool refuses a dialog
  with fewer than two, so a run with a manual task stopped there, with the mod and without it (seen in a terminal: the
  guard rightly refused the confirm call that no answer allowed). It now offers "Type it below" (it records nothing; the
  question is asked again) and Cancel; the typed name is the answer, and the guard counts no option of the question
  as a name. With the mod, the driver asks it itself and runs the confirm calls with the name.
- **"Make a small change" says who makes it:** Claude makes one small change in the conversation, with no loop back to
  Build, and asks the person what to change when the fix is theirs ("Change the work yourself" read as the person's
  own edit).
- **An earlier attempt of the same run name no longer blocks Build** (`scripts/temper`, group start and task start).
  Two runs on a person's machine stopped at `task start`: an earlier attempt had left its group and task branches, and
  git records of worktrees whose folders were gone. Group start then took such a record for this run's worktree and
  went on with no folder, and task start failed on it, or refused the leftover branch and
  told the person to run git. Now a record whose folder is gone is cleared, a clean leftover worktree is removed, and a
  branch this run did not make is moved aside to `refs/temper/kept/{slug}/earlier-{time}/{G or Tn}` with its commits
  kept, all said on one NOTE line; a leftover worktree with uncommitted work is never removed (exit 3, naming it). This run's own
  group worktree whose folder went comes back on its branch at the next task start or task gate. Claude Code 2.1.318
  deletes nothing under `.claude/worktrees/` when a session starts or ends (checked in a sandbox), so the folders went
  by another hand.
- **The driver starts every task before it launches any agent.** With two tasks ready, it launched Task 1's agent and
  then handed the run back when `task start 2` failed, with Task 1's agent running and no one to follow it ("a before
  call failed"). Now every agent's before calls run first; when one fails, the agents whose tasks started are launched
  and followed to their gates, and the hand back names the CLI's FAIL line.
- **Earlier attempts' branches leave `git branch`** (`scripts/task_ops.py`, `keep` and `tidy`). A re-plan renamed each
  group and task branch to `temper/{slug}/replan-{time}/{G}`, and nothing ever deleted them, so repeated attempts piled up
  in `git branch`. That work now goes to `refs/temper/kept/` with its commits, and `temper state clear` (the end of a
  run, and Start over) moves the branches older versions left there too, and drops what was kept longer than
  `build.grouped.keep-days` (30 days; 0 keeps everything). A branch checked out in a worktree is left where it is.
- **Room in the CLI:** the grouped plan gate's rows and the quality bands moved from `scripts/temper` into
  `scripts/plan_rows.py` and `scripts/bands.py`, as they ran; the CLI had 886 bytes left under the directory's
  256 KiB limit for a file, and has 11 KiB now.
- **The words of a question match the run** (`scripts/flow.py`), found when every question was read for the flow
  explainer: More options named what used to be behind it once Make a small change went in or Teach Me went out
  (it lists what is there now); in a `/temper:fix` run, a failed Review asked "Loop back to Build?" over a Loop back
  to Fix option, Change something and Make a small change spoke of Build, Save for later named `/temper:temper`, and a
  small change whose review failed offered no way back to Fix. The page question at Commit, asked nowhere since the
  page is written without one, is gone, and `docs/flow.md` no longer describes it.

**Three gaps of the last measured pass**
- **Exempt is an item of the rules checklist, asked with Who, When and How much** (`scripts/gate_rows.py`,
  `agents/intent.md`): what never gets the action (below an amount, a kind of record, a state), asked as one open
  question that names every kind of exclusion. A vague-late-fees run spent its last questions on narrow exceptions
  (once ever, fees on fees), never asked which invoices are exempt, and missed "invoices under 20.00 are never charged".
  The Intent gate fails a draft with no Exempt line, or with Exempt assumed while a later item was asked.
- **A rule the request states decides its edges** (`agents/intent.md`): an orders-pagination run asked whether a last
  page of exactly `limit` items gets a cursor, though the request said `next_cursor` is null on the last page; the
  click put a cursor there, and a hidden test failed.
- **A corrected acceptance test that fails again keeps the acceptance path** (`scripts/temper`, the Check gate): the
  "tests pass" row read the acceptance run as a suite run once a correction named it ("corrected after the lock: ..."),
  so two rows failed, the triage and "Correct the acceptance test" were no longer offered, and a login-lockout run went
  back to Build twice for a test that was wrong (it counted a failure 601 s old), then ended in an override. The
  acceptance run is judged by its own row only.
- **A Build task agent that stops before its own gate no longer hands the run back** (`core/driver.ts`,
  `scripts/temper`): the after call `task gate N --if-running` then gates the task, and a failed verdict exits 1 with
  its next step (a retry, a stronger model, the group parked), which the driver took for a broken call; and once a
  sibling's third failure parked the group, `--if-running` on a task never started was refused. Both are the CLI's
  verdict now, and `temper go` asks the person what comes next. Two measured runs handed back this way ($0.36 and
  $0.91 of Sonnet each, both finished right).
- **Measured** (`docs/evidence/bench-2026-11.md`, 7 runs on the three tasks and vague-refunds): every hidden test
  passed; vague-late-fees 13/13 twice, asking "What never gets a late fee?"; orders-pagination 9/9 twice.
- **Not done, measured:** running the acceptance writer beside Design. Design edits intent.md and plan.md in all 20
  measured runs, so tests written beside it would miss what Design decided.

**Build: three defects of a measured run**
- **A scenario is owed by the task that writes its test file.** Plan traced API scenarios to the task that built the
  domain module, while their test file came with the route's later task: that task's gate could never pass, and the
  group parked again and again. A task that writes a file a scenario's `Test:` command runs is now traced too, and the
  latest of them owes it.
- **A group parked again after a rerun recommends Loop back to Plan** (the rerun is still offered): the same gate had
  failed six times on every model, and the question kept recommending another rerun.
- **`acceptance lock` runs the command once** and refuses one that cannot run here (a test runner that is not
  installed, a program not found, no test collected). A run locked `python3 -m pytest` with pytest not installed.

## v9.7.6: a fresh reader checks the plan, contests cite evidence, a reviewer that stopped is not a clean review, spec drift

Five ideas from Google's Elephant Goldfish Model (a reviewer with no context reads a design before any code), built on
Temper's own spine: every verdict is still a CLI row from recorded evidence, and the person still decides each gate.

**The fresh review of the plan**
- **A plan could leave a decision to the builder (new `agents/plan-review.md`, `scripts/fresh_review.py`).** *What broke:* each
  Build task runs on a small model that sees only its own task block, and nothing checked that the block was enough. A task
  that said "rejects too many attempts" was built with whatever limit, window and status the model guessed. *Fix:* a reviewer
  with no context reads intent.md, plan.md and tasks.md through three lenses: readiness (can each task be built from its own
  block), zoom-out (work nobody asked for, a helper the code already has, found by searching the code) and comprehension (a
  newcomer's paraphrase, and project terms used without a definition). Three plan gate rows read what it records:
  `fresh review ran`, `fresh reader's paraphrase` and `no open plan blockers`. A `high` finding fails the gate.
- **The person chooses it** (`plan.fresh-review: ask`, the default): the plan question offers **Fresh review first**, at every
  tier, and the review applies once chosen (`temper plan fresh request`). `auto` runs it by itself for `medium` and `complex`
  plans, `always` for every plan, `off` never.
- **The paraphrase is in the plan question** ("A reader with no context took it as: ..."), also when the plan failed on another
  row, for the person to compare with the intent.
- **The CLI marks each launch** (`temper plan fresh start`, after Plan returned): the digest of intent.md, plan.md and tasks.md,
  and how many rows the plan ledger held. Only rows appended after the mark count, so rows the Plan agent writes itself never
  pass the gate. An edit of any of the three files makes the review stale; it runs again on the new text, and findings against
  the old text no longer count. `fresh` in the run state is the CLI's; `state set fresh...` is refused.
- **A lazy review does not pass:** the readiness row names how many tasks it checked (`--value N`), which must be the number of
  tasks in tasks.md, and each part of the paraphrase needs 6 words or more.
- **A round limit:** `plan.fresh-review-rounds` (default 3) caps the launches of one run. At the cap the plan question offers no
  more revisions: accept a finding, skip the check or step back.
- **Revise the plan** (`state redo plan`) runs the Plan agent again with each open finding. It fixes it, contests it or escalates
  it (`reference/plan.md`, "Answering the fresh review").
- **A risk `H` plan gets two independent reviewers** (A and B; `plan.fresh-review-twice: false` turns it off).
- **A plan entered through a stage command** (checked, not run again) gets the fresh review too.

**Contests that can be checked**
- **`temper evidence contest --stage S --id N --cite <file>[:<line>|:<symbol>] --quote Q --reason R`** (`scripts/findings.py`).
  The CLI checks the file is inside the project, holds the line or symbol, and holds the quote (at least 12 characters, within 3
  lines of a cited line); "it was intentional" is refused, and the refusal names escalate.
- **`temper evidence escalate --stage S --id N --reason R`** for evidence outside every file (a team rule, a spoken decision).
- **A comprehension finding is never contested or escalated:** a reader with no context could not follow the plan, so the plan
  is missing context.
- Both leave the finding open: the person decides. The accept question lists escalated and contested findings first, and
  offers the checked citation and the quote as reasons. Review findings work the same way: the Review gate names a contest,
  the Review accept question orders them the same, and `reference/review.md` and `agents/build.md` say how the fix pass uses it.

**A reviewer that stopped is not run**
- Each lens of each reviewer records its own completion row. A lens with none is `not run` (the row names it), never a lens
  with no findings. A launched reviewer that stopped is not launched again by itself: the plan question offers **Run the fresh
  review again** (`temper plan fresh again`).

**Spec drift**
- **`temper drift [--run] [--json]`** (`scripts/drift.py`, read only, never a gate): for each finished spec (a committed
  gate-ledger.json), a planned file that is gone, a scenario test file that is gone, and a planned file changed since the spec.
  `--run` also runs each scenario's `Test:` command (from the project folder, at most 300 seconds, without credential-named
  variables) and names each that fails now. `/temper:status` shows it as SPEC DRIFT.

**The evidence** ([docs/evidence/fresh-review.md](docs/evidence/fresh-review.md))
- The 9.7.5 and 9.7.6 CLIs on the same plan states (`scripts/e2e/ab-plan-gate.sh`): 9.7.5 passes a plan with a reader's
  blocker, a review that stopped after two lenses and a review of an older tasks.md; 9.7.6 fails each, and both pass a good plan.
- What it costs (`live-smoke.sh cost 3`, the same session three times each): about 26 s of reviewer time, 37 s of wall time and
  $0.17 at API prices per plan, about 17% of the Plan stage; `temper gate plan` is about 70 ms slower, `temper next` the same.
- A live run: the fresh reviewer found all 5 defects planted in a plan, and no blocker in its fixed twin. Two Haiku builders
  given the defective task passed their own tests and failed the intent (5 failures, 15 minutes, status 429, nothing wired into
  `/login`); two given the fixed task passed every criterion.

**The mod**
- **The pane shows the fresh review at Plan and Design**: the reader's summary, a lens that did not run (or that tasks.md changed
  after the review), and each finding with its lens and state, a contest with its checked citation. The count of open blockers
  includes contested and escalated ones: they wait for the person. No button, as before. The view carries it as `fresh`
  (`docs/flow.md`), `null` when the fresh review does not apply.
- **`reviewerModel` also sets the fresh plan reviewer's model** (`temper:temper-plan-review`); `models.plan-review` in the config
  still sets it without the mod.

**A live check, off by default**
- `scripts/e2e/live-smoke.sh` gains a fresh review check (`TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh fresh`, on a
  machine where Claude Code is signed in): a scratch Python project with an accepted medium intent at Plan, taken up headless by
  `claude -p "/temper:temper"`, once with the mod and once with `disableAllHooks`. It checks each lens ran on the tasks.md as it
  is, the paraphrase, the plan question that carries it and `fresh` in view.json, and that both legs end the same. Never in CI.
- Found while writing it: a plan question that failed on another row did not carry the reader's paraphrase. It does now.

**Also**
- The README is short: what Temper is, install, how it works, the commands. The mod's details live in [docs/mod.md](docs/mod.md).
- The website: each video has a second source and a link to the file; the Pages workflow fails when a restored video is missing
  or not an MP4, and checks after the deploy that the live site serves each one as a playable file.
- Tests: case file 14 (63 checks); three earlier cases with a medium plan record its fresh review (`fresh_reviewed` in
  case-helpers.sh); the view fixtures carry `fresh` (a new fixture, `plan-fresh-blocker`, holds an open blocker and a contest). The self test: 2074 pass, 0 fail (9.7.5:
  2010). The e2e driver: 20 scenarios, each passing with the mod and without it, the flow identical (new: `fresh-review`,
  `fresh-not-run`, `fresh-contest`, `fresh-ask`). Mod tests: 1620 pass, 0 fail (new: tests/mod/v976.test.tsx).
## v9.7.5: the Context Map, scenario tests that run, small changes, draft pull requests and the Pipeline stage

A private fork of 9.7.0 grew a set of behaviours in its own "9.7.1". This release rebuilds them on 9.7.4, with every hold of the
plugin directory kept: `validate-directory.sh` passes, usage stays time only, no script opens a Claude Code settings file or reads a
git identity, the mod runs nothing and sets nothing, and `userConfig.enforcement` stays a `/config` option.

**Gates and Plan**
- **A scenario criterion passed on a `Traced to:` line (F7, F8, F9).** *What broke:* a criterion with `Validate: scenario` passed
  Build with no test run for its scenario. *Cause:* the Build gate counted tasks and RED then GREEN runs, never the scenarios.
  *Why nothing failed:* the tests existed; nothing tied them to the scenario. *Fix:* every scenario carries a `Test:` command
  (the plan gate row `scenario test commands` names each one without it). `temper task show` lists the ones a task owes, with their
  exact names; the task gate and the group gate run them; `temper integrate` runs each on the merged tree and records a CLI run
  row, and the Build gate row `criteria validated` passes a scenario criterion only from such a row. A pytest exit 4 or 5 says to
  write the test under that exact name. A gate that fails only for rows nobody recorded sends a record pass, once per round.
- **The Intent gate passed over an open Blocking question (F10).** It fails now while a draft holds one.
- **The Context Map (F6).** Plan writes `## Context Map` at the top of `plan.md`; `plan.context-check` (auto, always, off) says when
  the person is asked. The question is the CLI's own (`context_map` and `context_check` in `temper next` and `view.json`), the answer
  runs `temper plan review --answer`, and nothing edits the `reviewed:` line by hand, which auto mode can refuse
  (`docs/auto-mode.md`).
- **Risk was Plan's estimate (F11).** `temper risk` computes it from the blast radius: the same blast radius, the same rating.
- **tasks.md (F12).** Bullet file lists and the `**Files:**` alias parse; a task with `**Test:** manual` needs no RED or GREEN and the
  person confirms it (`temper task confirm N --by '<name>'`, the name the person gives, never read from git). The all-tasks check
  counts every task, also one with no checkbox (it passed with one of eight done).

**Build**
- **Change reopened every task (F13).** It asks which task changes and reopens that task and the tasks that must reopen with it.
- **A small change needed a loop back (F14).** `temper adhoc open --stage S --reason R` and `adhoc close` at Build, Review, Check and
  Commit; the change re-runs only what it touches; the mod lets a code write through in the open window at its stage only.
- **Build stopped when the mod was off (F15).** It runs the same groups; nothing in the CLI reads `TEMPER_MOD`.
- **Groups (F16, F17).** `build.grouped.max-groups` (default 2); a plan with tasks and no groups stops before any agent; a group gate
  records a timeout, takes `--timeout-s`, and offers a rerun at double the limit.
- **Tests imported the wrong copy (F18).** The folder a command runs in is first on `PYTHONPATH`.
- **A task an earlier task built (F19).** Its RED run passed, so it was retried and parked. The person decides now:
  `temper task accept` or `temper task retry`.
- **Scoped tests, one suite run (F20).** Task agents and the fix pass run scoped tests; Check runs the suite once with coverage in
  the same run, under `.temper/check/`. Briefs tell agents to wait for runs in the foreground (`validate-panels.py` checks it).
- **Blast radius counted Temper's own files (F21).** Temper's files and test output no longer count.
- **Maven (F22).** `scripts/maven_loop.py` runs the declared test classes offline and needs a new surefire report per class; the plan
  gate row `maven group verify` names a Maven group that does not verify with JaCoCo.

**Check**
- **A missing tool sent the run back to Build (found by running Temper on pyjokes).** *What broke:* with no coverage tool installed the Check
  gate failed on `coverage >= threshold`, and its question offered Loop back to Build (recommended), Override, a small change or Save.
  *Cause:* the gate asks for a recorded coverage value and the question had no way to measure again. *Why nothing failed:* every
  option worked; none fitted a failure that is not in the code. *Fix:* when the only failed rows are a measurement nobody took (no
  passing test run, no coverage value), the question is **Run Check again?** with **Run Check again (Recommended)** first
  (`state redo check`); a failing test keeps Loop back to Build first. The Check brief now tells the person to install the tool and choose
  that option, never to record a number by hand, and `reference/check.md` says the gate fails without a coverage value, as it
  always did (its table said the level was skipped). `.temper/check/`, where the coverage output goes, is excluded from git like the other run files.
- **Pipeline could not read the checks in a Claude Code cloud session.** `gh pr checks` uses GraphQL, which those sessions refuse with
  HTTP 403, and the Pipeline brief had no other way. It now falls back to `gh api repos/{owner}/{repo}/commits/{head sha}/check-runs` (REST, tried
  from this session). `gh pr create` uses GraphQL too: there the pull request step falls back to the commands it prints, as it does for any other failure.
- **A CI fix sent Review, Check and the commit gate again, before CI was read (found by running the fix loop as printed).** *What broke:*
  after "Apply the fix and push" the next action was the Review agent over the pushed fix, not the Pipeline read. *Cause:* `adhoc close`
  treated a change made at Pipeline like one made at Check or Commit. *Why nothing failed:* the end to end driver's scripted Review and Check
  agents accepted the extra launches. *Fix:* a change made at Pipeline re-runs nothing (`state redo pipeline`, the last step of the fix,
  reads CI again), and the scenario now counts the Review and Check launches.
- **The Pipeline agent guessed a fix path and a round limit.** The launch line is now `Round: N of M.` (M is `loops.max-per-type`), so the
  panel's "ROUND n of max" is no longer made up, and each `fix` entry starts with a path that exists in the project or with `no file:`;
  the gate row `fix paths` fails any other entry, and the red question shows why.

**After Commit**
- **The Pipeline stage (F26, ADR 0014)**, draft pull requests and stacked parts by branch pointers (F23, F24, ADR 0015).
  Every pull request is a draft; Temper never marks one ready; the agent never pushes.
- **Record commit and loop reasons (F27).** No record commit when there is nothing to stage; a fix pass reads the latest loop reason.

**Sessions and hooks**
- **Branch clash (F28)**, **the commit hook gates the run's branch only (F29)**, **`temper guards uninstall` (F30)** and the stage
  refusals that name the run and point at a worktree, and **the band (F31)**: no failed rows while an answer is carried out.
- **Notes and typed answers (F1)** reach the next agent; the wait text and every `say` are sentences for the person (F3); a failed
  call stops its action (F4); `temper next` starts one Python process (F5); the models and their sources are shown (F2).

**What broke in the short entries (cause, why nothing failed, fix)**
- *F1, F3, F4.* A note or a typed answer only edited files, so no agent read it; a `say` could hold an instruction for Claude; a failed call
  let the action go on. The loop had no rule for any of the three, and every step still ran, so no test failed. Notes are ledger rows the next
  agent prompt carries, every `say` is a sentence, and `commands/temper.md` states that a failed call stops its action (the stage agent's
  gate call named `gate` is the one exception).
- *F2, F5.* The model a stage ran on was invisible, and `temper next` started several Python processes (2.2 s). Nothing measured either. The
  model rules and the setup facts moved into `scripts/cli_ctx.py`, one process computes the answer and the view, and the output is byte for
  byte the same (the view fixtures are regenerated and compared).
- *F13, F16, F17.* Change reopened the whole group, a plan with tasks and no groups reached a Build with nothing to run, and a slow group gate
  was cut at the task limit. Each was a missing rule in a path the happy run never took. Each now has its own question or limit.
- *F18, F20, F21.* A test imported the project copy instead of the worktree copy, agents ran the full suite twice, and Temper's own files
  counted as outside the declared files. All three passed locally because the copies were equal. The folder first on `PYTHONPATH`, scoped
  tests and one suite run, and a skip list in `scripts/blast_filter.py` fix them.
- *F27.* A run with nothing to stage still printed `git add` and `git commit`, and the commit hook refused the empty commit. The record
  steps now say there is no record commit when no code is uncommitted, no lesson file exists, and the spec folder is git ignored or unchanged.
- *F28, F29, F30, F31.* A new branch took the spec files of an earlier run with it, the commit hook gated every branch, a disabled plugin
  left its hook behind, and the band showed failed rows while an answer was carried out. Each hid behind a single-run test setup.
- *The readiness skill (F25) is not part of this release.* The optional `review-readiness` skill was taken out: the Check question offers
  Temper's own draft pull request steps (`reference/pr.md`) and nothing else, and `temper next` takes no `--skill`.

**Tests.** The self test refuses a CLI call outside its own folder (`TEMPER_SELFTEST_ROOT`) and leaves the real `.temper` as it was.
`scripts/selftest/run-selftest.sh` runs the case files in parallel (`--jobs`, `TEMPER_SELFTEST_JOBS`, at most 12) with tiers
(`--fast`, `--slow`, `--changed [REV]`); the helpers the case files share are in `case-helpers.sh`. `bun scripts/e2e/run.ts both`
plays the orchestrator with scripted agents and a scripted person through the real CLI, with the mod's rule engine and without it, over
16 scenarios, and checks the flow is identical (`scripts/e2e/live-smoke.sh` is a live model smoke, off by default and never in CI).
The mod answer audit answers every option of every question of the view fixtures and judges each person only call by the mod's rule.
The e2e carry scenario found one real fault: the mod refused the command the CLI wrote to carry the spec files across a branch switch;
it now passes character for character when the person chose it and the only Temper path it writes is the spec folder.

**Migration.** An old flat `tasks.md` is counted by its boxes as before. Rows in `.temper/usage.json` are read as they were. A run
started on 9.7.4 carries on: its running tasks take their model from the attempt number. A hook an older version left runs the gate
on every branch until `bash scripts/guards/install.sh` writes the 9.7.5 hook; remove it with `temper guards uninstall`.

**Suite counts.** The full self test went from 1761 passing, 0 failing (9.7.4, 22 minutes 37 seconds in series) to 1988 passing, 0 failing
(`run-selftest.sh`, 4 at a time, about 17 minutes; the serial run in CI takes about 26 minutes). `claude plugin test .` runs 1610
tests across 34 files; `bun scripts/e2e/run.ts both` plays 16 scenarios with the mod and without it and finds the flow identical in
each (48 lines, 0 failures). `claude plugin validate --strict .`, `validate-directory.sh`, `validate-docs.sh`, `validate-readme.sh`,
`validate-plugin.sh`, `validate-panels.py`, `check-mod-calls.sh` (13 calls, unchanged) and `check-known-limits.sh` pass, and the largest
file, `scripts/temper`, is 254,333 bytes.

## v9.7.4: no key in CI, no token count, no credential handed to a test

The directory's report on 9.7.3 (b1d1c18) cleared three holds: the mod staying the same, the mod running slash commands
and the mod setting configuration. Two remain: "This plugin includes a mod", which always goes to a reviewer, and
"Update adds credential forward" ("Uses a credential from the user's machine"), whose note now says what it looks for: a
part that reads a credential and a part that sends data. This release removes the three parts left that a reader could
take for either.

**No key in CI.** The Mod job made Claude Code write the mod's type declarations by running
`claude -p "hi" --plugin-dir .` with an invalid `ANTHROPIC_API_KEY` set: a key and a request in one line. It runs with
no key or login now (Claude Code says it is not logged in, and has written the declarations by then), and fails when
they are missing.

**No token count.** 9.7.0 had the orchestrator take each agent's token count from Claude Code (the Agent result, or
`subagent_tokens` in a completion notice) and pass it to the CLI, which kept it in `.temper/usage.json`, the report and
the bar. Temper records the time only now.
- `temper usage add` and `temper task gate` take `--ms`; a token count an older after call passes is accepted and read
  by nothing. A usage row is `{stage, model, ms, task, group, ts}`.
- `temper report`, `temper report --html`, `/temper:temper report` and the bar show launches and time, and no token
  count. `temper group report` gives `ms_by_model` in place of `tokens_by_model`.
- `/temper:temper` and `/temper:fix` fill `{ms}` only.
- The view the mod puts in `$.state` (`types/index.d.ts`, `TemperView`) has a clock of minutes only.

**No credential handed to a test.** The commands the CLI runs in a grouped Build (a task's test, a group's Validate
command, the integration suite) get the environment without the variables whose names say they hold a credential: a
key, a token, a secret, a password or passphrase, credentials, an auth socket or helper. Every other variable passes as
it is. A test checks both.

The trust page, Grouped Build, the flow page, the orchestrator patterns and the manual test checklist say the same.

**Migration.** A `.temper/usage.json` row with a token count still counts, its count unread. A test that needs a key is
not a task's unit test: run it in Check.

## v9.7.3: no hook written through a split name, no settings file or git identity read, the mod sets nothing and runs nothing

The directory's report on 9.7.2 (59576ee) held it for the same five reasons as 9.7.1. "This plugin includes a mod"
always goes to a reviewer. This release answers the other four in code.

**The mod stays the same (`temper-cases-5.sh`, named again).** The cause was two test helpers that 9.7.0 added to that
file. They wrote a git pre-commit hook into git's own hook folder of the test repository, with that folder's name written
as two quoted halves, which the shell joins back into `hooks`, the name of the folder that holds the mod.
`validate-directory.sh` rules 9 and 10 never saw the name. 9.6.6 was held for exactly such a write, and only this file
had one, which is why the report named it twice. The helpers now write the case's hook into a folder of its own in
the git folder, `case-gate`, and point `core.hooksPath` at it by its absolute path, as Temper's installer does. Each
case's fresh repository removes it. The slow hook cases still see a commit in flight, so the hook runs. A new
rule 13 in `validate-directory.sh` fails on a word joined from quoted pieces with nothing between them (a quote mark
doubled between two letters). On 9.7.2 it fails on exactly those two lines, and on nothing else in the tree.

**The CLI edits no Claude Code settings file.** "Update adds credential forward" held 9.7.2 too, after the transcript
reads were gone. 9.7.0 had also added `temper init --foreground-agents`, which read the project's
`.claude/settings.json` whole (people keep keys and tokens in its `env` block) and wrote it back with
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` added, and read that variable from the environment. It is removed.
`/temper:init` now says in one line how the person sets the variable themselves, and Getting Started shows where. An
old `temper init --foreground-agents` call runs the plain init and writes no settings file. A test checks that init
leaves a settings file as it is and that the CLI names no settings file.

**No Claude Code settings file is opened, and no name or email is read from git.** The report names a credential "from
the user's machine" without saying which, so this release removes the two other reads of that kind.
- `scripts/guard-entries.py`, which read the project's `.claude/settings.json` and `.claude/settings.local.json` to list
  Temper guard entries, is removed, with every flow that read or merged those files: the stale guard check of
  `/temper:pack` and `/temper:init`, and the merges of `/temper:pack enable guardrails` and `disable guardrails`.
  `enable guardrails` now prints the entries through `scripts/guardrails-snippet.py`, which reads only the plugin's own
  `packs/guardrails/settings-guardrails.json`, for the person to add to a project settings file. `disable guardrails`
  removes the `packs:` entry and says which entries to remove. A test runs the snippet script under an audit hook and
  checks that it opens that one file, and that no shipped script or mod file names a project settings file to open.
- The CLI no longer runs `git config user.name` or `user.email`, and no longer reads `$USER`. An override, an accepted
  finding and an accepted intent record that the person decided it at the gate (`the person`, and `the person at the
  Intent gate`). Before a commit of its own, the CLI asks git only whether an identity is set (the exit status of
  `git var` with `user.useConfigOnly`, so git guesses none from the system account; its output is thrown away),
  and passes a fixed one when none is. The intent briefs write a name the person typed, never one from git. Tests
  check that no shipped script makes such a read.
- The orchestrator passes each agent's token count to the CLI as `--token-count` (it was `--tokens`): a count of
  model tokens, a whole number, which a reader could take for a credential under the old name.
- The new tests write no stand-in settings file and name no plugin root variable (9.6.7 removed those names from
  the tests). The pages that still said an override records your git name say what it records now.

**The mod runs no command and sets no setting.** Every report from 9.6.4 to 9.7.2 held the plugin for these two, with
the README text the directory asks for.
- The bar's Go on button, the mod's one `$.command.run` (it ran `/temper:temper`), is gone. The bar has no button; you
  type `/temper:temper` to take a run up again.
- `/temper:temper mode` and `/temper:temper enforcement` no longer change the two settings (`$.config.set`, after a
  `$.config.list` read for a locked row). They say what is set and where to change it: `/config`, Temper UI mode and
  Temper enforcement, the plugin's own options. The first run mode question (`$.ui.ask`) and its store key are gone.
- The mod's reviewed calls go from 18 to 13 (`scripts/check-mod-calls.sh`): no `command.run`, `config.list`,
  `config.set`, `ui.ask` or `ui.invalidate`. The mod tests check that no command runs, no setting changes and the bar
  has no button.

The README, `docs/mod.md`, `docs/commands.md`, `docs/trust.md`, the privacy page, Getting Started, the pack pages
and the manual test checklist say the same. The mod's drawing kit no longer offers a button at all.

**Migration.** A mode or enforcement you set with the old commands stays set; change it in `/config` from now on.
Guard entries you added to a settings file stay as they are; after a plugin upgrade, run
`/temper:pack enable guardrails` to print the current ones and put them in place of the old. Overrides and accepted
intents recorded before keep the name they hold.

## v9.7.2: the directory's holds on 9.7.1, answered in code and in the README

The directory's report on 9.7.1 (f33d200) held it for five reasons. "This plugin includes a mod" always goes to a
reviewer. This release answers the other four.

**No script names a path with a folder named like one of the mod's.** The report could not confirm that the mod stays
the same after it is checked, and named `scripts/selftest/temper-cases-5.sh`. 9.7.0 added shell cases whose throwaway
projects keep their tests in a `tests` folder: 65 lines in five files (27 in the named one), where 9.6.7 and 9.6.8 had
none. `tests` is the name of the folder that holds the mod's tests, and 9.6.4 was held for the same name. Those
projects use `unit` now, and so do the grouped example in `templates/tasks.md` and two doc examples; the view
fixtures are generated again. The named file also made a folder through a variable followed by `..`; it names the
folder directly now. A comment named a file of the mod's tests, and two decision records and the 9.7.0 entry named
files of the mod; they name them by role.
- Rule 10 of `scripts/validate-directory.sh` now fails on a path with a folder named like any folder of the mod or of
  its tests (`hooks`, `tests`, `mod`, `core`, `ui`, fixed text in the script), and a new rule 12 fails on a step up a
  folder right after a variable or a `$( )` span. Run on 9.7.1, they fail on those 65 lines and on that path. The
  validator's comments describe the forms in words, and its tests give each rule its own stand-in (another folder
  name, another wildcard character), as rule 10's tests always did, so neither file spells a form it refuses.
- Other names a reader could take for the mod's: the Pages workflow restored the videos by a loop over the mod
  folder's own name; it now restores each video and poster by its blob id in the pinned media commit, under
  neutral names. The grouped example's `src/cli.sh` and `src/report.sh` are `src/main.sh` and `src/printer.sh`. The
  init command and the guardrails pack name the hook file as the `pre-commit` file in the folder git names, and the
  TDD and Rust packs and the Check brief say "the `tests` folder" in words.

**The CLI reads no Claude Code file.** The report held 9.7.1 for "Update adds credential forward". 9.7.0 read each
agent's transcript in Claude Code's own folder in your home folder for the tokens it was billed and a cost at list
prices, and the report the run commits carried what it read, while the privacy page and
`docs/trust.md` said Temper opens no file there but its own pack folder. `scripts/usage_cost.py` is deleted. A usage
row is the totals Claude Code gives for an agent (the Agent result, or the completion notice of an agent run in the
background), and `temper report`, `report.html` and the view give time and tokens by stage and by model, with no
cost. The `after` calls `temper next` gives no longer name an agent id; `--agent` is accepted and ignored, so a run
started on 9.7.0 or 9.7.1 still records. An agent with no total given is recorded with empty values instead of being
refused. A test checks that a row holds exactly the totals given, and that no file of the CLI expands a home folder
or reads a transcript.

**The secret guard no longer repeats a secret.** `block-secrets.sh` printed the whole match in its refusal, which
Claude and the session transcript see when a commit is refused. It now shows the first 4 characters and the length.

**The README says what the mod sets, runs and hooks.** The report asked, at the lines that make them, for the README to
say which settings the mod sets, which command it runs and when, and what its `classic.SessionStart` and `command.run`
hooks do. 9.6.8 had cut that section to a link. It now says each, checked line by line against the code: the mode
question a bare `mode` asks, `/temper` as well as `/temper:temper`, what the session hooks change in the mod's own
state (the pane, a toast, the kept report) and which hooks cause them, the refusals of `tool.call` and when each applies,
what the system prompt section holds, the line above the question dialog, and the toasts. It says what Temper reads outside the project (the pack folder, the folders above the session folder where the
mod looks for the project, and through git your name, email and hooks folder), and what setting up a project changes;
`docs/trust.md` says the same. The Install section also gives the one line install `claude plugin validate` suggests.

Notes the directory listed that need no change: `types` (Claude Code's own validator needs it for the mod's `$.state`
keys), no icon (a bundled image holds a plugin for review, and an icon added now would not become the listing icon),
and the download-and-run notes, which sit in docs, history, test inputs and the guard's patterns.

**Migration.** Usage rows a 9.7.0 or 9.7.1 run wrote keep their extra fields; the CLI reads only their tokens and time.

## v9.7.1: the plugin directory can fetch Temper again, and no file is over 256 KiB

The Claude plugin directory could not fetch 9.7.0 (a17c0e7 and e7a49e8): "Something in the repository the
scanner won't accept", and nothing was scanned. No behaviour change.

**A line-ending rule the scanner accepts.** The directory names a line-ending rule in `.gitattributes` without
`eol=lf` as the most common cause. The repository's one rule was `* text=auto`; it is now `* text=auto eol=lf`, so
every text file is stored and checked out with LF on every platform. `git add --renormalize .` changed no file: each
was already stored with LF.

**No file over 256 KiB.** `scripts/temper` had grown to 281,652 bytes, and the directory holds a version for a
reviewer when a file that is not an image is over 256 KiB. The Build task operations (the CLI's `_task_py`: a task's
brief and context, its test runs, the group checks, restore and the task verdict) move unchanged from a heredoc in
`scripts/temper` to `scripts/task_ops.py`, and `_task_py` runs that file with standard input closed, as the heredoc
left it. `scripts/temper` is now 249,734 bytes. The three tests that read the CLI's own text (no folder listed by a
wildcard and no folder put on `sys.path`, no lock test seam, no variable for the overrides file) read
`scripts/task_ops.py` too.

## v9.7.0: the CLI says what comes next, the mod only draws, Build runs in groups of Haiku agents

**The CLI says what comes next (ADR 0013).** `temper next --json` prints the one next action of a run:
work (CLI calls, a stage brief to launch, the commit steps), a question with its exact header, question
and options (each with the CLI calls it maps to), a wait, an armed run's own move, or a broken run.
`commands/temper.md` is a loop over it (6,870 words to 2,117), and `commands/fix.md` follows the
same loop (2,057 to 676). The CLI writes `.temper/view.json` after every change. `state advance` refuses
to leave a failed stage nobody skipped, a stage with no verdict, or a stage out of order, and leaving
Plan records the approved files and `base_sha`.

**One flow (ADR 0012, amended by ADR 0013).** The CLI is the only run state. The person decides every
gate in the `Temper gate` question, with the mod or without it, in every mode. The mod counts an answer
only when its header, question and label are exactly what the CLI wrote for that run and step; a typed
message is never a move. The stage commands are doors into `/temper` (`state init <slug> --enter <stage>`).

**The guard claims only what it can enforce.** A call only the person may cause (leaving Intent or Plan,
a skip, a step back, an accepted finding, arming autonomy, kept agent commits, the commit override,
starting over) passes only as one of the calls of the person's answer, word for word. The file rules hold
each stage to its writes and Build to the approved files. Through Bash the mod refuses `--no-verify`, a
changed `core.hooksPath` and a write onto a protected file. The mod's shell parser and its lists
are deleted. Temper is not a sandbox: `docs/trust.md` lists what the guard does not see.

**The mod draws the run from view.json, and reads nothing else of the CLI's.** The band: the stage
timeline, time and tokens, the loops with their reasons, and one button, Go on. The pane, read only: plan
files by group, the Build grid (state, model and retries per task), the Review findings with confidence
and file:line, the Check markers with their failing lines, the criteria with their evidence. At the
commit, `temper report --html` writes `report.html` in the spec folder. The game is removed. The mod
went from 6,092 lines to 3,224, its tests from 8,755 to 5,235.

**Build runs in groups of small Haiku task agents (ADR 0011, amended).** Plan writes `tasks.md` as groups
of tasks, each with its files, dependencies and at least two test cases (an input and its exact result).
Each task runs on Haiku in its own worktree, with a slim brief and a pattern test; a failed task is
retried, then escalated, then parks its group, and a person reviews each group once. The CLI makes the
task commits and the merges, and parks a group on a commit it did not record. Per task Build and
`build.mode` are removed; `agents/build.md` is the fix pass of a loop back to Build. Every stage records
its usage (`temper usage add`), and a fix run's commit adds its lesson to `.temper/lessons.md`.

**Release audit fixes.** A verdict of the active run is computed from its own spec folder and the project's config:
`gate --spec-path` of another folder prints the rows and records nothing, and `TEMPER_CONFIG` is not followed while a
run is active. The plan gate records the digest of the approved `tasks.md`, so a Test, Validate or Integration command
changed after it stops the grouped Build, and from Design on no agent writes `tasks.md`. A project below the top of its
git repository (a package of a monorepo) builds in its own folder inside each worktree, and the native hook gates every
project a commit touches. The guard reads `$'...'` and `$"..."` quotes, expands every word's brace lists (a quoted one
not), finds a program through a glob or in another case and a call at every word that names the script, and refuses a
config handed to git that can switch the hook off (`-c include.path`, `--config-env`, an alias whose body skips the hook,
`GIT_CONFIG_GLOBAL`); a copy into the spec folder is no longer refused. At Commit only the spec folder is written.
`base_sha` is recorded once. A door's walked approvals commit the spec only when it changed, and a walked stage whose
check fails offers to run it. A commit the CLI did not make on a group's branch is a question (take it out or keep it).
The commit step skips a file deleted in a commit. `gate build` wants the passing run after the failing one; a Review that
did not finish offers to run again; `config get fix.max-loops` prints the limit the loop keeps. The plan gate has no
"Walk through step by step" option.

**Second audit fixes.** The guard judges a copy's target on its own, so a copy into `.temper/` no longer lets an
`rm -rf .temper/` in the same command through; a brace list gives each word as many times as bash does (`-m {-n,-n}`);
a glob with a class names a program (`/usr/bin/[[:alpha:]]it`); a command that runs git and sets `HOME` or
`XDG_CONFIG_HOME` is refused, and so is a temper call with an unquoted glob in its words. A config suggestion may go
into `.claude/AGENTS.md`. The native hook and the commit gate read a rename by both its names, so a file moved out of a
project below the top, or a code file moved into the spec folder, is gated. A project folder whose name holds a glob
character keeps its run files out of `git status`. After Keep the commits, the next step merges the groups again, and
Take the commits out is offered only for the newest commits of the branch.

**Live run fixes.** A live run of the release candidate found that the accepted intent was committed on the branch the
person was on (often main): leaving Intent now switches to the run's branch, or makes it, before that commit. A group
that builds on another starts only after the person's Continue of it (`temper group start` refuses before that). A
passed Review with open findings below the blocking severity offers Loop back to Build and Accept a finding. The end of
the run prints the report before it clears the run state, and clearing it leaves an unchanged gate ledger as it is, so
the commit leaves the spec folder clean. The Check marker of the tests reads no scenario row. When Build committed the
code itself, the last commit's message names the run's record instead of a feature. A background agent's tokens and time
come from its completion notice. A second narrow review closed more ways around the guard: a glob as a copy target
(`cp f .temper/[Eg][Va]*`), `NAME+=value`, a program named by bracket sets alone (`/usr/bin/[g][i][t]`), `cp --parents`
and `rsync -R` landings, `rsync --remove-source-files`, and a glob after a call's reason; a glob in a call is refused only
when it could spell a word the person decides (`--model sonnet[1m]` passes). After Keep the commits the person is asked
before the groups are merged again, so a merge that stops early does not go round unasked.

**Two more live runs.** A `/temper:fix` run in a fresh project now runs the setup calls, so its commit hook is
installed. A loop back to Build keeps what Review (or Check) left open, and the fix pass prompt names it, since the
loop clears that stage's ledger. The last commit's message names the run's record when the code it lists is already
committed. `state clear` keeps the ledger `state archive` wrote for the commit, so the commit's own hook (which records
the spec only commit's verdict) no longer changes the committed record. Check's `.temper/coverage/` folder is kept out
of git status.
The line `temper next` gives before each launch names the model the agent runs on ("Plan runs on opus.",
"Build hands out 2 tasks on haiku."), and the report's stage table names the model each stage was launched on (in the
terminal, in `report.html` and in the view's `usage.by_stage`). Both name the model Temper asked for; the session
transcript holds the model that served each turn.
A passed Design offers Loop back to Plan (a concern can need a missing case, and the plan is closed from Design on),
and a loop back to Intent, Plan or Design gives that stage's agent the person's reason, as Build and Fix already had.

**Targeted live runs.** A door into Review or Check reads the run's diff from where the feature started (before the
commit that added the spec's `intent.md`, else where the branch left main or master), so committed work is
reviewed; before, its base was HEAD and Review read an empty diff. `state init --enter` takes the tier from the
Complexity line of `plan.md` (else of `intent.md`, which holds Intent's first guess), so a Design door no longer
skips Design on a first guess of simple. The last commit of a run whose code is all committed says the code is in the
commits before it. Such a door's walked Build passes on the newest Build PASS the spec folder's committed
`gate-ledger.json` records (looking back past a later door that skipped Build), while no file of the plan changed
since that commit (before, it always failed: the door's run holds no evidence of the run that built the code, and Run
Build built the whole plan again). When a file of the plan changed since, the check fails and names it, and Run Build
is the fix pass on that code, not the plan built again. A loop back from a door's run runs the stage it goes back
to, and Build's fix pass mends the code the earlier run built (before, Build was only checked again, so a door's run
could never fix what Review found). `enter` and `built_before` are the CLI's keys. Check's tests row reads the latest
run of each test command, so a failing integration run beside a passing unit run fails it, and a passed Check offers
Loop back to Build, for what Check passed with a warning (a lint run, by the methodology a warning).
Review writes no code: the CLI records the project's tracked files as Review starts, and the Review check fails, naming
the file, when a Review agent left a change in them or made a commit (a probe it restores leaves none); a live Review
had fixed a critical finding itself and resolved it, so no loop back ran and no test came first. A loop names only the
feedback file of the stage it came back from, and Check's `test-gap-report.json` is kept out of git status.
The orchestrator launches a stage agent with `run_in_background: false`, and when the tool runs it in the background
anyway, its completion notice is the agent's return and the turn it starts runs the `after` calls: a run once sat
idle after its Plan agent finished in the background until the person wrote. Getting Started says what to do
when a run waits after an agent finished, and names `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, which keeps agents in
the foreground. A plugin cannot set that variable, so `/temper:init` asks whether to add it to the project's
`.claude/settings.json` (`temper init --foreground-agents`, which merges the one `env` key, keeps every other key,
and writes nothing into a file it cannot read as JSON or through a symlink); the line said when an agent goes to the
background names `/temper:init` too. A parked commit question says the armed run parked there and where its report is.

**The lows of the live runs.** The Design question names each open area of concern (`design.md` gives each its own
heading or list item); leaving Design records the ones the person accepted as written (`resolved: accepted as written
at the Design question`) and commits `design.md`, which was left for the last commit; an armed run parks at a Design
with open concerns, since a person decides them before Build. `temper next` no longer lists `temper init` after every
finished run (a run's end removes `gates.json`, which the setup check read); it lists it when `.temper` is missing or
the clone's exclude list lacks a run file, so a project set up before a newer run file (`security-map.json`) gets it.
A task agent's box gives its test runs' exit codes as `red exit 1, green exit 0`, and the RCA box wraps a long fact
row instead of cutting it (the box is saved as `rca.md`). The CLI, the guard scripts and the commit hook run their
inline Python isolated (`python3 -I`): before, a file in the project named like a standard module (`json.py`) ran on
every `temper` call; a hook installed before this is listed for `install.sh` again.

**The lows of the Design run.** Three lows of a run through Design, armed at the plan gate, are fixed. The
`resolved:` line leaving Design adds is a paragraph of its own (Markdown joined it to the concern's last list item
or paragraph); under a list item concern it is indented to the item's text. A passing group Validate or integration suite prints
only its last 12 lines into the main conversation (a suite of 60 tests printed about 250); a failing one prints all
of its output, and the ledger row keeps the last 4 KB as before. `temper state set complexity` also writes the tier
into the `**Complexity:**` line of `intent.md` (and of `plan.md`, when it has one): a tier the person changed at the
plan gate stayed only in the run's state, `plan.md` names no tier, so a later door took Intent's first guess. The
plan gate's new `tier recorded` row fails when such a line names another tier than the run.

**Usage, cost, and the report at the end.** A run's report showed zero tokens and zero time for every stage:
its agents ran in the background, each one's report came before its completion notice, and the orchestrator
recorded the stage when the report came. `temper usage add` and `temper task gate` now take the agent's id
(`--agent`), and the CLI reads what the agent was billed for from its own transcript: each call's input, cache
writes, cache reads and output, with the model that served it, so the numbers no longer depend on when the call
runs. The total Claude Code returns (`subagent_tokens`) is the agent's context at its last call, not its usage:
one Haiku task returned 114K and was billed for 1.65M tokens, mostly cache reads. An agent named with no
transcript and no total is refused, and nothing is recorded. The report gives an estimated cost at API list
prices (`scripts/usage_cost.py`, with their date), by stage and by model, and the main conversation's since the
run started, from the session transcript. A subagent's transcript records each reply before it streams, so its
output is taken from the reply's text and its thinking is not counted: the cost of the agents can be low. At the
end of a run the report prints in the terminal before the commit, the orchestrator shows it, and a question
offers the HTML page; before, `report.html` was always written, and the terminal report came after the commit.
The orchestrator records an agent and goes on at its report, the first of its report and its notice to arrive:
the agent has finished by then, and its numbers come from its transcript. Claude Code started a turn for the
report but none for the notice, so a run that waited for the notice waited until the person wrote.
The first run with this showed no cost at all: its Claude Code named each model with a gateway prefix
(`ml-asset:static-model/...`), and the price table matched only bare ids. The CLI now takes the last
`claude-<family>` id in the name, whatever comes before or after it. That run also skipped the HTML question
and did not show the report: both were instructions in a list of commit steps. The question is now one
`temper next` asks, after `temper report --end` has printed the report; the page says to copy the report into
the reply. The next run priced only its Sonnet stages: one call on a model the price table does not know
dropped the cost of its whole agent, the report did not say which model, and its run total added only what
had a cost. A row now keeps the cost of the agent's other calls; that cost, and every total it is in, is
marked `+`; a launch none of whose calls has a price still has none; and the report names the models with no
price, so a missing one can be added to `scripts/usage_cost.py`. Its note "no transcript was found, or a model
they ran on has no price" now gives the two causes apart: the launches with no transcript, with the agent ids
they were given, and the launches that ran only on models with no price.

**The pane opens for a run started in the session.** In full mode the mod opened the pane by itself only
when a session started during a run, so a run started with `/temper:temper` in the session showed no pane
until the person typed `/temper:temper pane`. Now the person's own `/temper:temper` with a feature
description (or any word that goes on to the run) opens it, which Claude Code places at any width, and so
does the first read that finds a run started later in the session (a door, or a run Claude started), which
Claude Code places only on a wide terminal. A pane the person closed by hand is not opened again by itself
in that session. The empty pane now says that a run shows there once it starts.

**The two videos show 9.7.0.** The workflow video (43 seconds) takes one run through each stage and
shows how each stage hands work to the next: Intent writes the criteria with an ID, Plan turns each
criterion into a scenario (`Covers: AC-01`) and a task (`Traced to:`) and names every file, Build gives each
task to a Haiku agent that writes a failing test first, Review reads the change against the plan and the
intent and sends a real bug back, Check traces every criterion to evidence (the real `temper gate check`
output), and only then the commit and the report. The mod video (36 seconds) shows the bar, a gate
question, a tour of the pane section by section, and the Scope drift question. Neither video has a
refusal scene. One commit holds the two videos, and the website links pin that commit.

**Migration.** A run planned before 9.7.0 has a flat `tasks.md`, which fails the plan gate (`grouped
plan`): loop back to Plan to write it as groups. A `build.mode` left in a config changes nothing.

The entries before 9.7.0, from v9.6.8 back to v5.0.1, are in `docs/history/changelog-before-9.7.md`.
