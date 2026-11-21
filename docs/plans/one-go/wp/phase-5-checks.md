# Phase 5, checks: the specs of WP19, WP20, WP21, WP22 and WP23

This file holds WP19 (checks judged against the project), WP20 (environment check and baseline), WP21 (plan
commands on the base, the preflight removed), WP22 (one digest and the reuse store) and WP23 (checks in `integrate`).

The brief is `docs/plans/one-go/README.md`, and every shared name below is the one `docs/plans/one-go/contracts.md`
fixes. Every `file:line` is of the head `10e965a`. WP02 and WP03 land before these packages and move code: find each
function by its name ("the flow modules" are `scripts/flow.py` and the seven modules WP03 made of it). The five
packages are built in the order of this file, after WP17. Each ends as the brief's section 4 says:
`bash scripts/verify.sh quick` green, then the package commit, then the small progress commit, in one push;
`bash scripts/verify.sh full` after WP23 ends phase 5.

Names this file uses, from `docs/plans/one-go/contracts.md`: the new case files are
`scripts/selftest/temper-cases-60.sh` to `temper-cases-64.sh`, one a package in this order, and a new file needs no
`source` line because the runner of WP01 finds it by its name. The scripted projects of WP06 are the scenarios
`slow-first-run` and `slow-at55` of `scripts/e2e/slow.ts` and `broken-first-run` and `broken-flaky` of
`scripts/e2e/broken.ts`. The caps file is `scripts/caps.json`, the floor file `scripts/e2e/floor.json`, and the
cards are built in `scripts/card.py`. A package that rewrites an assertion of the base lists it in
`docs/plans/one-go/changed-tests.md`, takes each check it makes pass off `scripts/selftest/expected-fail.txt`, and
writes its lines into `CHANGELOG.md` under the one heading of the result, `## v9.8.5: a run that asks twice` (no
package adds a version heading). A check that passed earlier is simply not on the list
(`docs/plans/one-go/done.md`, note 7). If one still fails for a reason that belongs to a later package, do not
weaken it: name that package on its line of the list and in `docs/plans/one-go/PROGRESS.md`.

## WP19 Checks judged against the project

- **Goal:** Check never fails correct work on a number the project never had, and never passes what nobody measured.
  Coverage is judged by one rule in a fixed order, a measurement that was not taken is a third state in every gate,
  question, view and report, and the planted bug score is information beside Review.
- **Depends on:** WP02, WP03, WP04, WP06, WP08, WP11, WP15.
- **Lane:** `flow core`.
- **Touches:** `scripts/check_run.py`, `scripts/gate_rows.py`, `scripts/temper` (`_req`, `gate_check`, the row printer
  of `cmd_gate`), the flow modules that hold `Run.failed_rows`, `ask`, `measurement_gap` and `check_markers`,
  `scripts/card.py` (the commit card of WP15), `scripts/output_ops.py`, `scripts/run_report.py`,
  `hooks/temper-mod/core/runview.ts`, `hooks/temper-mod/core/view.ts`, the mod's drawing of the checks,
  `tests/mod/drawings.test.tsx`, `tests/mod/hardening.test.ts`, `templates/temper.config.default`,
  `.claude/temper.config`, `agents/check.md`, `reference/check.md`, `docs/flow.md`, `docs/trust.md`, `README.md`,
  `scripts/selftest/` (`temper-cases-60.sh`, new; cases 1, 8, 9, 13, 15, 26, 28 and 52; `test-temper.sh`), both view
  fixture files, `scripts/e2e/scenarios.ts`, `scripts/e2e/slow.ts`, `scripts/e2e/pyjokes.ts`, `scripts/e2e/replay.ts`,
  `scripts/caps.json`, `scripts/stops.json` and `docs/decisions/0019-a-run-that-asks-twice.md` (trap 7),
  `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-60.sh` (new; the hand list of `scripts/selftest/test-temper.sh:235-244`
     went with WP01, so no `source` line is added). Case `w19 rule table`: feed
     `python3 scripts/check_run.py coverage-verdict` one JSON object per row and compare the printed verdict. Rows: 12
     changed lines of which 10 ran, base 71: pass, rule `changed lines`, floor 71. Base 92, changed lines at 85%:
     pass, floor 80. 12 changed lines of which 6 ran, base 71: fail. 9 changed lines, total 70.4, base 71: pass, rule
     `total`. Total 69.9, base 71: fail. Line data and no base value: `not measured`. No coverage command:
     `not measured` with the hint. Key set to 80 and total 55: fail, rule `threshold`. Key set and no coverage
     command: `not measured`.
  2. Same file, case `w19 no tool is the third state`: a project with only a `Cargo.toml` and a fake `cargo` on PATH
     that exits 0. `temper check run` then `temper gate check` gives PASS; the row `coverage` has `"pass": null` and
     `"state": "not measured"`; its printed line starts with `[?]`.
  3. Same file, case `w19 no printer says pass`: with that ledger, the output of `temper gate check`,
     `temper gate check --brief`, `temper report`, the `checks` and `check_markers` of `.temper/view.json`, and the
     commit question of `temper next --json` each name the row with the words `not measured` and none marks it passed.
  4. Same file, case `w19 the old key`: a config with `check: coverage-threshold: 80` and a recorded total of 55 fails
     the gate with a detail that names the key and how to remove it; the same ledger with no key in the config and a
     base value of 55 passes.
  5. Same file, case `w19 mutation is no row`: a Check ledger that holds `mutation score` with value 40 gives a gate
     with no row whose name holds `mutation`, and the verdict is PASS.
  6. Same file, case `w19 check run plants no bug`: the test command appends one line to a counter file on each run;
     after `temper check run` on a green suite with changed lines the file holds one line.
  7. Same file, case `w19 three must fit`: with `TEMPER_MUTATION_BUDGET_S=2` and a suite that sleeps 1 s,
     `temper check ahead` writes `.temper/evidence/mutation.json` with `"state": "not run"` and a reason, and the
     counter file shows no run for a planted bug. The call returns at once; wait for the file as the helper
     `_ahead_done` waits today (`scripts/selftest/temper-cases-15.sh:451`).
  8. `scripts/e2e/slow.ts`, the scenario `slow-first-run` that WP06 wrote on its slow project (55% coverage, no
     coverage tool): a default run ends at the commit question with exactly the approval and the commit as
     dialogs, no stop at Check, and the commit card text holds `coverage: not measured`. Plain and driver mode, the
     two modes WP06 registers for the scripted projects. These
     assertions pass here; the scenario stays on the expected to fail list until WP23 (row `D11`).
  9. `scripts/e2e/scenarios.ts`, a new scenario `coverage-drop` (the function `coverageDrop`): the scripted builder
     leaves 12 new lines of which 4 run; the unattended run makes its one counted repair and, when the scripted
     repair changes nothing, stops with one question that names the row. It never passes on and never takes a
     second repair by itself.
  10. `tests/mod/drawings.test.tsx`: a `checks` entry with `state: 'not measured'` is drawn with its own mark, and a
      `check_markers` entry `mutation` with state `info` is drawn as information.
  11. Rewrite, in the same change, every test that states the old behaviour on purpose. They match on
      `coverage >= threshold`, `coverage tool missing`, `recorded coverage 'none'` or `mutation score >= threshold`:
      `scripts/selftest/temper-cases-15.sh` (the most), `-1`, `-8`, `-9`, `-13`, `-26`, `-28`, `test-temper.sh`,
      `scripts/e2e/pyjokes.ts`, `scripts/e2e/replay.ts`, `scripts/e2e/scenarios.ts`, `tests/mod/hardening.test.ts`.
      List each one that is of the base in `docs/plans/one-go/changed-tests.md`. The case of WP11
      `run: a failed Check whose only failed row is the mutation row stops` (`scripts/selftest/temper-cases-52.sh`)
      goes with the row; trap 7 says what becomes of its stop.
  12. From `scripts/selftest/expected-fail.txt`: `D35b`, `D35c` and `D35d` of `scripts/selftest/temper-cases-44.sh`
      pass and leave the list here. `slow-at55` (row `D12`) stays listed with WP20 named: its base value comes from
      the baseline (`docs/plans/one-go/contracts.md` section 13).
- **Mechanism:**
  1. **The third state of a gate row.** A row is `{name, pass, detail}` today, written by `_req`
     (`scripts/temper:2004-2010`) and by `gate_rows.row` (`scripts/gate_rows.py:23-24`). Add the form
     `{"name": N, "pass": null, "state": "not measured", "detail": "not measured: <why>"}`. `_req` takes `na` as its
     second word for it. A gate function never sets `all_pass=0` for such a row, so the verdict is unchanged by it.
     `pass` is `null` on purpose: a reader that was not updated shows the row as failed, never as passed.
  2. **Every reader of `pass`, each changed in this package.** `Run.failed_rows` (`scripts/flow.py:283-284`) keeps
     only rows whose `pass` is `False`, and a new `Run.unmeasured(stage)` returns the third state rows. The printer
     at the end of `cmd_gate` (`scripts/temper:4328-4332`) and its twin in the report (`scripts/temper:4730`) print
     `[?]`. `scripts/output_ops.py:67` and `scripts/gate_rows.py:241` test `is False`.
     `hooks/temper-mod/core/runview.ts:273` carries `state` beside `pass`. The shell tests
     `grep -q '"pass": false'` (`scripts/temper:3592, 3598, 3601`) need no change.
  3. **The coverage rule, one pure function.** Add `coverage_verdict(measure, base, changed, threshold)` to
     `scripts/check_run.py`, with a command entry `coverage-verdict` for the tests. It returns
     `{"state": "pass" | "fail" | "not measured", "rule", "value", "floor", "why"}`. In this order:
     1. The project's config holds `check.coverage-threshold`: the old rule. The total must reach the key's value;
        with no total the state is `not measured`. Rule name `threshold`.
     2. No coverage command for the stack, or the coverage program could not start (exit 127): `not measured`, with
        the hint `detect` gives (`scripts/check_run.py:110, 133, 139, 141, 144`). This is decided by the CLI's own
        probe and exit code, never by output text.
     3. No base value: `not measured: no base value` plus the baseline's result in words.
     4. Line data exists and at least 10 changed executable lines: the share of those lines that ran must reach the
        floor. The floor is the base total, and never more than 80. Rule name `changed lines`.
     5. Else the total must not be below the base total by more than 1 point. Rule name `total`.
     6. Else `not measured`.
  4. **Choice, floor for changed lines.** The plan's card shows the base total as the floor ("coverage may not drop
     below 71%"); the cap of 80 keeps a base at 92% from failing new code covered at 85%
     (`docs/plans/one-go/evidence/v-checks-once-early.md`, section 5).
  5. **Line data.** `changed_lines` exists (`scripts/check_run.py:216-238`). A changed line is executable when the
     report lists it as run or as missed. Readers to add: coverage.py's JSON (`executed_lines` and `missing_lines`
     per file, the file of `scripts/check_run.py:107-108`); Go's profile (`scripts/check_run.py:135-136`; its paths
     start with the module name of `go.mod`); and `lcov.info` for jest, vitest and c8, by adding the `lcovonly`
     reporter to the three commands at `scripts/check_run.py:122-129`. `node --test`, a configured command, Rust,
     Maven and Gradle give no line data and fall to step 5 or 6 of the rule.
  6. **The base value.** The function takes it as an argument. The caller reads the field `coverage` of
     `.temper/evidence/baseline.json`, which WP20 writes. Until WP20 the file is absent and the state is
     `not measured: no base value`; the tests of this package write the file by hand.
  7. **Where the row is made.** `check_run.run` records one coverage row with the verdict's fields: `value`, `rule`,
     `floor`, `state`, and `exit_code` 0 for pass, 1 for fail, `null` for not measured. It replaces the row
     `coverage tool missing: ...` with exit 1 (`scripts/check_run.py:704-713`). `gate_check` loses its coverage
     block (`scripts/temper:3904-3914`) and calls a new entry `check-rows` of `scripts/gate_rows.py`, which prints
     the row from the ledger's latest coverage row. The row's name becomes `coverage`.
  8. **The old key.** `gate_check` reads `check.coverage-threshold` with the default 80 (`scripts/temper:3864`).
     The default becomes empty: the key counts only when the project's config holds it. Delete the line from
     `templates/temper.config.default:34` and from `.claude/temper.config:34`. A config that still carries the
     template's old copy keeps the 80 rule until the person removes the line. The failed row's detail names the
     value, the key `check.coverage-threshold` as the source of the 80, and the way out: remove the line and
     coverage is judged against the project. The one time config question of WP29 offers that removal.
  9. **Mutation leaves the gate.** Delete the row `mutation score >= threshold` and its key read
     (`scripts/temper:3915-3931`). `check_run.run` no longer calls `mutation` (`scripts/check_run.py:732-740`).
  10. **Mutation beside Review.** `check ahead` is already a `before` call of the Review agent
      (`scripts/flow.py:1375-1378`; `scripts/temper:4948-4956`). It becomes the one place that plants bugs. It runs
      them only when three fit: three times the suite's measured seconds must be under `MUTATION_BUDGET_S`
      (`scripts/check_run.py:42`); until WP23 `ahead` times the suite itself (`scripts/check_run.py:692-694`). It
      writes `.temper/evidence/mutation.json`:
      `{"state": "measured" | "not run" | "running", "why", "ran", "caught", "survivors", "tree", "ts"}`. `check run`
      never waits for it and writes `.temper/check/mutation.stop` with the time 60 s from then; the loop of
      `mutation` tests that file beside its budget before each planted bug (`scripts/check_run.py:380-382`).
  11. **Who shows it.** `check_markers` (`scripts/flow.py:2597-2616`) gives the coverage marker the state `info`
      and the detail `not measured: <why>` for the third state, and gains a marker `mutation` with state `info`.
      The commit card of WP15 lists coverage as value, rule and floor, or as `coverage: not measured: <why>`, and
      the planted bug line (`7 of 9 planted bugs caught`, or why none ran). A `mutation.json` whose `tree` is not
      the current tree is not shown.
  12. **The questions.** `measurement_gap` (`scripts/flow.py:880-885`) loses the alternative
      `recorded coverage 'none'`: a coverage that was not measured is no failed row, so "Run Check again" is no
      longer offered for it (`scripts/flow.py:852-863`). The branch stays for a run with no test evidence.
  13. **What the unattended run does.** Coverage passed: it moves on. Coverage failed (a measured drop, class code):
      the one counted repair of WP11, then the question. Coverage not measured: it moves on, the commit question
      lists it, and no rule ever repairs it. The planted bug score, whatever it is: it moves on, and the commit
      question shows it. Neither sends the run back to Build, as `policy_move` does today
      (`scripts/flow.py:1178-1180`).
- **Removed:** the gate row `mutation score >= threshold`; the key `check.mutation-threshold` (no reader is left);
  the template line `coverage-threshold: 80` and the default 80 in code; the ledger row
  `coverage tool missing: ...` as a failed row; the coverage half of `measurement_gap`; the mutation step inside
  `check run`.
- **Documents in the same change:** `reference/check.md:46` and `:179` (the coverage rule and the two measurements
  the gate needs), `docs/flow.md` (the Check rows and `check_markers` at `:285`), `README.md:35`, `agents/check.md`
  (no word that a missing coverage value fails the gate), `docs/trust.md` (one paragraph: what "not measured" means,
  and that the planted bug score gates nothing), `docs/getting-started.md:233` (the key in the sample config),
  `CHANGELOG.md`.
- **Done when:** `scripts/selftest/temper-cases-60.sh` and cases 1, 8, 9, 13, 15, 26 and 28 pass under
  `bash scripts/selftest/run-selftest.sh --changed`; `claude plugin test .` and `tsc -p tsconfig.mod.json` pass;
  `grep -rn "mutation-threshold\|coverage tool missing\|mutation score >=" scripts agents templates reference` prints
  nothing; `bash scripts/verify.sh quick` is green; `coverage-drop` passes in three modes and the coverage
  assertions of `slow-first-run` pass in plain and driver mode, while the scenario itself stays on the list until
  WP23; `D35b`, `D35c` and `D35d` have left `scripts/selftest/expected-fail.txt`.
- **Traps:**
  1. The view changes (`checks` gains `state`, `check_markers` gains an entry): regenerate both fixture files with
     `scripts/selftest/make-view-fixtures.sh`, or the mod's tests fail on a stale view.
  2. `scripts/temper` has little room. The rule lives in `scripts/check_run.py` and the row in
     `scripts/gate_rows.py`; this package must leave `scripts/temper` smaller than it found it.
  3. A coverage row with `exit_code: null` must not count as a test run: `runs.check` already skips rows whose exit
     is not a number (`scripts/runs.py:50`), but `check_markers` reads `exit_code` (`scripts/flow.py:2609-2612`).
  4. `scripts/caps.json` (WP05) is compared exactly. This package removes one gate row and one config key and adds
     none: lower the two numbers in the same commit.
  5. `scripts/selftest/temper-cases-15.sh` holds assertions on `check ahead` that WP22 rewrites again. Change here
     only the lines on coverage and mutation.
  6. Do not turn "no passing test run" into the third state. Tests that never ran stay a failed row; only coverage
     and the planted bug score change in this package.
  7. Stop 21 of `scripts/stops.json` (WP11: only the mutation row failed) names a row this package deletes, so the
     stop can no longer happen and its check is gone. A stop leaves the list only with a decision record (row
     `D76`): take row 21 out of `scripts/stops.json` and out of the table of stops in decision 3 of
     `docs/decisions/0019-a-run-that-asks-twice.md`, with one line there that says why. Take out no other stop.
- **Size:** M.

## WP20 Environment check, baseline and limits

- **Goal:** A fault of the environment or of the base is named before any agent is paid for: tool versions and
  services in under 5 s, the project's own suite once on the current code in the place Build uses. The measured
  time sets every later limit and the measured coverage sets the floor of WP19.
- **Depends on:** WP04, WP06, WP08, WP10, WP11, WP13, WP15, WP19.
- **Lane:** `flow core`.
- **Touches:** `scripts/baseline.py` (new), `scripts/doctor.py`, `scripts/check_run.py`, `scripts/run_env.py`,
  `scripts/task_ops.py`, `scripts/temper` (one dispatch line for `baseline`, `cmd_override`, the limits of
  `cmd_group_gate`, `cmd_task_test` and `cmd_integrate`, the cleanup in `cmd_state_clear` and `state init`), the flow
  modules that hold `core_next`, `ask`, `build_work`, `group_failed`, `setup_offer` and the view,
  `scripts/flow_base.py` (the question id and the option id of this package), `scripts/card.py` (the baseline line),
  `hooks/temper-mod/core/rules.ts` (`personOnly`), `tests/mod/guard.test.ts`, `scripts/selftest/`
  (`temper-cases-61.sh`, new; case 8, and every case that asserts the setup offer at the plan gate or the option with
  twice the time: cases 23 and 27 and the group question's cases), `scripts/selftest/case-helpers.sh` and
  `scripts/selftest/make-view-fixtures.sh` (step 18), both view fixture files,
  `scripts/e2e/scenarios.ts`, `scripts/e2e/slow.ts`, `scripts/e2e/broken.ts`, `scripts/e2e/accept.ts`
  (`approval-first`), `scripts/e2e/replay.ts`, `docs/flow.md`, `docs/commands.md`, `docs/trust.md`,
  `reference/autonomy.md`, `scripts/caps.json`, `scripts/e2e/floor.json`, `scripts/selftest/expected-fail.txt`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-61.sh` (new). Case `w20 owner order`:
     `python3 scripts/check_run.py owner` prints the configured command when `check.commands.test` is set; else the
     detected one; else, for a project whose only build file is `backend/pom.xml`, `cd backend && mvn -q verify` with
     source `detected`; else the plan's Integration line when a `tasks.md` is given; with two build files one folder
     down it prints none and says why.
  2. Case `w20 environment check`: a `pom.xml` one folder down that asks for JDK 24 and a fake `java` that prints
     version 21 gives a fault that names the file, the need and what the shell has. A `setup.services` entry on a
     closed port gives a second fault. The call ends in under 5 s (assert on the measured time) and starts no suite
     (the counter file is empty).
  3. Case `w20 three results`: a suite that exits 0 gives `green` with `seconds` and `coverage`; one that exits 1
     gives `red` with `fail_lines`; no test command, no commit, and a suite over the limit (`TEMPER_CHECK_TIMEOUT_S=1`)
     each give `unknown` with a reason. `unknown` is never read as green: the approval line says `unknown`.
  4. Case `w20 where it runs`: the suite's working folder is under `.claude/worktrees/`, HEAD of the project did
     not move, `git branch` lists no new branch, and `git status --porcelain` of the project is empty after
     `temper baseline clean`.
  5. Case `w20 start never fails`: `temper baseline start` exits 0 with a missing program, with no commit, and when
     the worktree cannot be made.
  6. Case `w20 red base question`: `temper next --json` on a red base before Plan gives one question with the id
     `base.red`; with a project file that names a JDK, its text holds the exact proposed block and the first option
     (`add-setup`) adds it; without one the options are run again (`check-again`), go on anyway (`go-on-anyway`)
     and save for later (`save`). No agent was launched. The add call with another block's hash writes nothing.
  7. Case `w20 go on is a recorded skip`: after `temper baseline accept-red --reason x`, `.temper/overrides.json`
     holds a row for `base-suite` by the person; a later suite run that fails with the base's fail lines only gives
     the row `tests pass` the state `skipped`; one new fail line gives a failed row.
  8. Case `w20 the answer is kept`: a second run on the same base, setup block and tool versions asks nothing and
     writes its own skip row; a changed setup block asks again.
  9. Case `w20 limits`: with 400 s measured on the base the group gate's limit is 1,200 s; with 10 s it stays 600 s;
     with no measured time it is 600 s; after one time out the next action is the CLI's own run with twice the
     limit, and after a second time out the run asks.
  10. Case `w20 fix run and door`: a fix run with a red base of kind `red-base` asks nothing and records it; a fix
      run whose setup line fails asks; a door into Review runs the environment check and no suite.
  11. `scripts/e2e/broken.ts`, the scenario `broken-first-run` that WP06 wrote on its broken project: the wrong
      tool version and the service that is down are named before the first agent; after the scripted repair of
      both, the one failing test is named as a red base before Plan is launched; no agent is launched for any of
      them. Plain and driver mode. These assertions pass here; the scenario leaves the list with WP21 (row `D13`):
      until then the plan gate still runs the Validate on the red base.
  12. `scripts/e2e/slow.ts`, the scenario `slow-first-run`, more assertions: no limit is hit, the baseline line of
      the approval card says `running` when the approval comes first, and the first group gate reads the result.
      `slow-at55` (row `D12`) passes and leaves the list here: its base value is the coverage of the baseline.
  13. `scripts/e2e/scenarios.ts`, a new scenario `red-base-after-approval` (the function `redBaseAfterApproval`):
      the baseline turns red while the first task agent works; no new task agent is launched, the work in flight
      is kept, and the run stops with the red base question and a notice.
  14. `scripts/e2e/replay.ts`: the JDK fault of the measured Java run is named before the Intent agent is launched,
      where the head names it at the plan gate.
  15. `tests/mod/guard.test.ts`: `baseline accept-red` is refused outside the person's answer.
- **Mechanism:**
  1. **The owner of the suite command.** Add `suite_owner(root, cfg, spec)` to `scripts/check_run.py`. In this
     order: the config's `check.commands.test` with `check.commands.coverage`; else `detect(root)`
     (`scripts/check_run.py:76-145`); else `detect` of each folder one level down that is not in `SKIP_DIRS`
     (`scripts/check_run.py:39`), taken only when exactly one answers, with `cd <folder> && ` in front of each
     command and the folder in front of each coverage file path; else, once a `tasks.md` exists, its
     `**Integration:**` line; else none. For Maven `detect` returns `mvn -q verify`, where the head returns
     `mvn -q test` (`scripts/check_run.py:141`): it is the form the plan gate asks of a group
     (`scripts/gate_rows.py:164`). The owner has a test text and a run text (the coverage form, or the same text).
  2. **The environment check.** Add `needs(project, setup)` to `scripts/doctor.py`. It only reads. Files, in the
     root and one folder down as `propose` reads them: `pom.xml` (`scripts/doctor.py:240-247`), `build.gradle` and
     `build.gradle.kts` (`:251-257`); in the root: `.java-version` and `.tool-versions` (`:261-266`), the CI files
     of `ci_facts` (`:119-151`), `package.json`; and from the config `setup.tools` and `setup.services`. It then
     makes one shell call through `run_env.run_cmd` under the setup block, limit 5 s, that prints `command -v` for
     each program the owner's command starts (`preflight.programs`, `scripts/preflight.py:64-70`) and the version
     line of `java` and `node` when a file names one. It connects to each `setup.services` address as `answers`
     does (`scripts/doctor.py:52-58`), all at once, 2 s each. A fault is structural: a program that does not
     resolve, a major version below the one a file names (`java_major`, `scripts/doctor.py:232-234`), a service
     that does not answer, a setup line that fails (exit 125). Each fault carries the file that states the need. A
     shell call over 5 s gives no fault and the note `not checked in 5 s`. A project whose files name nothing is
     told so in one line.
  3. **`temper baseline start`.** `scripts/baseline.py start` always exits 0, as `check ahead` does
     (`scripts/temper:4955`). It writes `.temper/evidence/baseline.json`. Steps: no commit gives `unknown`. The
     environment check runs; a fault gives `red` with the kind `tool-version`, `program-missing`, `service-down` or
     `setup-line`, and no suite run. No owner gives `unknown: no test command`. Else it starts a background process
     and returns with `running`.
  4. **The background run.** `git worktree add --detach .claude/worktrees/temper-baseline HEAD`, the place Build
     uses (`scripts/temper:2380, 2957`), not the system temp folder the preflight uses (`scripts/preflight.py:191`).
     The owner's run text goes through `run_env.run_cmd` with the limit `SUITE_TIMEOUT_S`
     (`scripts/check_run.py:43`, 1,800 s), then the coverage report. Result `green` on exit 0, `red` on any other
     exit, `unknown` on exit 124 with `seconds_over`. A red result has a `kind`: `setup-line` (exit 125),
     `program-missing` (exit 127), `service-down` (a declared service does not answer right after the run), else
     `red-base`. It records `seconds`, `coverage` (`coverage_value`,
     `scripts/check_run.py:155-171`) and the lines `fail_lines` picked by pattern (`scripts/task_ops.py:130-143`,
     without its fallback to the last three lines). A green run is kept in the reuse store with its seconds and
     coverage (`run_env.run_cached`, `scripts/run_env.py:169-170` gains the two fields).
  5. **The file.** Its fields:

     ```
     {"key", "head", "cmd", "source", "result", "kind", "why", "seconds", "seconds_over", "coverage",
      "fail_lines", "tail", "env": [...], "pid", "started", "ended", "answer", "limits": {}, "plan": {}}
     ```

     It sits under `.temper/evidence/`, so the mod guards it already (`hooks/temper-mod/core/rules.ts:110`) and a
     step back does not remove it (`scripts/temper:1876-1896` empties the stage ledgers only).
  6. **When it starts.** In `core_next` (`scripts/flow.py:2360`), before any other step of an active run: when the
     file is absent, the action is `auto` with the one call `temper baseline start`. `state init` empties
     `.temper/evidence` (`scripts/temper:733-734`), so every new run starts one, and a step back does not. It is
     the CLI's own action, so the count of dialogs does not change. Not inside `state init`: no spec folder exists
     then (`docs/plans/one-go/evidence/v-checks-once-early.md`, section 3). The file keeps the commit it ran on in
     `head`; the run's `base_sha` is only set at the approval (`scripts/temper:1166-1173`).
  7. **Nothing waits for it.** The approval card shows the baseline line in one of four forms: passes with seconds
     and the floor, running, fails on the current code, unknown with the reason. The first group gate waits for a
     baseline still in flight, because it needs the measured time for its own limit (`limit_for` does the waiting,
     up to the baseline's own limit).
  8. **The red base question.** One function in the flow, id `base.red`, asked in `core_next` whenever the result is
     `red` and no answer is stored. A fault of the environment check is asked before the first agent. A red suite that
     ends while the Intent agent works is asked when that agent returns, before Plan is launched; one that is known
     before the approval is asked before it, so the approval never hides a red base. Its text: the command, the exit,
     the seconds, the fault or the first fail lines, and the exact proposed block when there is one (run line through
     `run_env.mask`, variables, services). Options, by the ids of `docs/plans/one-go/contracts.md` section 5:
     `add-setup` "Add this setup block and run it again", first and recommended, only when the config has no block and
     `doctor.propose` gives one (the test of `setup_offer`, `scripts/flow.py:1192-1199`, without its read of
     `preflight.json`); calls `doctor --propose --write --expect <hash>`, then `baseline start --again`. `check-again`
     "Run it again", for a repair made by hand. `go-on-anyway` "Go on anyway", with a reason; call
     `baseline accept-red --reason '{reason}'`. `save` "Save for later". One fault is one dialog.
  9. **The block that is written is the block that was shown.** At the head `checked` refuses to write unless the
     preflight stored a fault (`scripts/doctor.py:471-478`), and at run start it stored none. From this package on
     `--propose --write` writes the proposed block when its hash (`block_hash`, `scripts/doctor.py:403-405`) is the
     one given with `--expect`, and refuses when the proposal changed since the question. The person read the
     block; the baseline that runs next is its check. A second red result asks again without the add option.
  10. **"Go on anyway" is a recorded skip.** `accept-red` writes the answer into the file and into the store under
     the baseline's key, and adds a row to `.temper/overrides.json` through `cmd_override`, which gains the name
     `base-suite` beside the stage names (`scripts/temper:4399-4424`). The call is the person's: add it to
     `personOnly` (`hooks/temper-mod/core/rules.ts:476-497`). From then on a failed run of that command is
     tolerated only while every fail line it shows is one of the base's (numbers masked as `same_failure` does,
     `scripts/flow.py:2573-2577`): its gate row gets the third state form of WP19 with `"state": "skipped"`, no
     repair is launched for it, and the commit card shows the failures before and after. One new fail line is a
     failed row. When the base run gave no fail line, the whole suite is information for this run and the skip row
     says so. Task tests, scenario tests and acceptance tests gate as before.
  11. **The answer is kept.** A later `baseline start` whose key (base tree, command, setup block, tool versions)
      has a stored answer asks nothing; it writes this run's own override row with the date of the answer, and the
      approval card shows it. A changed key asks again.
  12. **Red after the approval.** `build_work` (`scripts/flow.py:1635`) reads the file first. Result `red` with no
      answer: no new task agent is launched, agents in flight finish and their `after` calls run, and the run asks
      `base.red`. For an unattended run this is a recorded stop with a notice (WP11). An answer of go on is a skip,
      so the run asks at every later stage (rule 3).
  13. **Limits from measured time.** `baseline.limit_for(cmd, default)` returns the larger of the site's default and
      three times the seconds that command took on the base; `seconds_over` counts as measured. Sites and defaults:
      the group gate, 600 (`scripts/temper:2441`); a task's test, 600 (`scripts/temper:3053`) and its scenario
      tests (`scripts/task_ops.py:707-708`); `integrate`, 3,600 (`scripts/temper:3321, 3408, 3422`); Check, 1,800
      (`scripts/check_run.py:693, 720, 671`). The environment variables at those lines stay as the defaults.
  14. **A time out.** The first time out of a command stores twice its limit in `limits` of the file, and the next
      action is the CLI's own call with that limit (for a group, `group gate G --timeout-s N`, the flag at
      `scripts/temper:2444`). It is not counted in the budget of WP10 when the base time was measured, and counted
      once when it was not. A second time out asks. The option "Run the gate again with twice the time" goes
      (`scripts/flow.py:1990-1995`).
  15. **A fix run.** A red base of kind `red-base` (the suite fails and no sure sign of the environment shows) is
      recorded with the answer `fix-run` and is not asked: there the red suite may be the bug. Later gates judge as
      usual. Every other kind is asked as in any run.
  16. **A door.** A door into Build or an earlier stage is a run like any other. A door into Review or Check
      (`walked`, `scripts/flow.py:1110-1116`) calls `baseline start --env-only`: the environment check, no suite on
      the base, no red base question. Limits and the coverage base come from the store when it holds the base tree.
  17. **Cleanup.** `temper baseline clean` removes the worktree. `state clear` and `state init` call it; WP21 calls
      it when the plan's commands have run.
  18. **The suite's own runs.** No case of the base may see the new first step. Add one helper `_base_known` to
      `scripts/selftest/case-helpers.sh` that writes `.temper/evidence/baseline.json` with `result` `unknown` and
      `why` `not run in the selftest`; `fresh`, `m_setup` and every state builder that calls `state init` call it
      right after that call, and `scripts/selftest/make-view-fixtures.sh` writes the same file after each of its
      own `state init` calls (the first is at `:114`), for every fixture but the ones this package adds to show
      the baseline. Case file 61 removes the file where it tests the start itself. Before the package commit run
      the whole parallel selftest once in the background; a case of the base that still differs is repaired, or
      listed in `docs/plans/one-go/changed-tests.md` with its reason.
- **Removed:** the option "Run the gate again with twice the time"; the offer of the setup block at a failed plan
  gate (`scripts/flow.py:693-699`), which moves into `base.red`; the fixed limits as the only limits.
- **Documents in the same change:** `docs/flow.md` (a section "The environment check and the baseline" in place of
  the first half of `:132-155`), `docs/commands.md` (`temper baseline`), `docs/trust.md` (the baseline runs the
  project's test command before any approval; "go on anyway" is a skip that only the mod ties to a click; a reused
  green base is as old as its date), `reference/autonomy.md` (a red base after the approval is a stop),
  `CHANGELOG.md`.
- **Done when:** `scripts/selftest/temper-cases-61.sh` passes; `red-base-after-approval` passes in three modes;
  the assertions this package adds to `broken-first-run` and `slow-first-run` pass in plain and driver mode, while
  the two scenarios stay on the list until WP21 and WP23; `slow-at55` is off the list;
  `bash scripts/selftest/make-view-fixtures.sh` leaves no diff after it was run; `claude plugin test .`,
  `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` pass; `bash scripts/verify.sh quick` is green;
  `scripts/e2e/floor.json` still shows 2 dialogs for a clean feature run.
- **Traps:**
  1. Rule 1 says a run writes only its spec folder before the approval. The baseline writes a detached worktree
     under `.claude/worktrees/` and a file under `.temper/evidence/`: no project file, no branch, no commit. The
     rule check of WP07 (the scenario `approval-first`, `D30a`) must allow exactly these two places: add them
     there, and case `w20 where it runs` holds the rest.
  2. A failed call that is no gate is an error for `temper go` (`scripts/go.py:108-114`), and the driver hands an
     error back. `baseline start` must exit 0 whatever happens and must return in seconds: the suite runs in its
     own process. `temper go` also stops when the same calls would run twice (`scripts/go.py:98-103`), so the file
     must exist after the call, whatever the result.
  3. A scripted run must not race the background process. Give `baseline.py` one switch read from the environment,
     `TEMPER_BASELINE_FOREGROUND`, that makes `start` run the suite in the foreground, and set it in `scripts/e2e/`
     and in the selftest helpers. WP21 uses the same switch for the plan's commands.
  4. `doctor.propose` starts `docker info` and walks up to 6,000 files (`scripts/doctor.py:98-106, 73-87`). The
     environment check must not call it; only the red base question does.
  5. The first action of a run with no baseline file changes, so every scenario that asserts the first step
     changes. Step 18 keeps the cases of the base and their fixtures away from it.
  6. Count the sites: this package adds the question `base.red` and removes the setup offer at Plan and one option
     at the group question. No number of `scripts/caps.json` may rise.
  7. With `cd <folder> &&` in front, a coverage command writes its report under that folder. Join the report path
     with the folder, or the value is read as absent and coverage is "not measured" for no reason.
  8. The store entry is keyed by a clean tree until WP22 (`scripts/run_env.py:133-141`). Compute the key before the
     suite runs, as `run_cached` does at `:155`, or the suite's own byproducts void it.
  9. `state clear` removes `.temper/evidence` (`scripts/temper:1448-1449`). The answer survives a run only because
     it is also in the store; test that with two runs, not one.
- **Size:** L.

## WP21 A plan command runs once on the base; the preflight goes

- **Goal:** The plan gate runs no project command. A Validate or Integration command the plan wrote runs once on
  the current code, started by the CLI after the planner returned and never inside an agent's turn, under Build's
  own limit, judged by its exit code. The per command preflight, its text patterns and the environment agent go.
- **Depends on:** WP04, WP08, WP20.
- **Lane:** `flow core`.
- **Touches:** `scripts/baseline.py`, `scripts/preflight.py` (deleted), `scripts/run_env.py`, `scripts/doctor.py`,
  `scripts/check_run.py`, `scripts/task_ops.py`, `scripts/temper` (`gate_plan`, `cmd_plan`, the `doctor` line), the
  flow modules that hold `ask` for Plan, `stage_work`, `setup_offer`, `env_agent_work`, `core_next`, `env_task` and
  `group_failed`, `agents/env.md` (deleted), `.claude-plugin/plugin.json`, `agents/plan.md`,
  `templates/temper.config.default`, `scripts/selftest/temper-cases-22.sh`, `-23.sh`, `-24.sh`, `-27.sh` and
  `temper-cases-62.sh` (new), both view fixture files, `scripts/e2e/scenarios.ts`, `scripts/e2e/slow.ts`,
  `scripts/e2e/replay.ts`, `scripts/flow_base.py` (the question id and the option id of this package),
  `docs/flow.md`, `docs/commands.md`, `reference/plan.md`,
  `docs/decisions/0020-checks-judged-against-the-project.md` (new; it amends ADR 0018), `scripts/caps.json`,
  `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-62.sh` (new). Case `w21 the plan gate runs nothing`: every command of
     the demo plan appends to a counter file; `temper gate plan` leaves it empty and prints no row named
     `preflight`.
  2. Case `w21 which commands run`: after `temper baseline plan` the counter shows one run each for a group Validate
     and for an Integration line whose text is not the owner's; none for a task Test, a scenario Test, a command
     equal to the owner's test text, or a Validate that names a file a task creates.
  3. Case `w21 where and how long`: the run's folder is the baseline worktree; a Validate that sleeps past
     `TEMPER_TASK_TEST_TIMEOUT_S=1` gives the result `timeout`, never the class `environment`, and the question
     (`plan.command`) offers more time (`more-time`), another command and a skip with a reason, and no setup block.
  4. Case `w21 binary rule`: exit 0 is `pass` with its seconds stored; exit 1 on a green base is `fail`, class
     `command`; exit 1 on a red base is `fails like the base` and raises no second question; exit 125 and an
     unresolved first word are class `environment`. An output that holds the words `Connection refused` changes
     none of these.
  5. Case `w21 a failed result is not final`: after the fault is repaired, the option "Run it again"
     (`check-again`) runs the command again and the result is `pass`.
  6. Case `w21 no environment agent`: no question holds "Let an agent find the setup", `temper next` never returns
     an agent of type `temper:temper-env`, and `temper doctor --candidate x` is a usage error.
  7. Case `w21 task gate, sure signs only`: a GREEN run that prints `Connection refused` with exit 1 and no declared
     service is FAIL and spends the attempt; the same with a declared service that does not answer is ENV, and the
     question still has the option `it-is-the-code` of WP08 that sends the task back to its agent.
  8. `scripts/e2e/scenarios.ts`, a new scenario `plan-command-fails` (the function `planCommandFails`): the scripted
     planner writes a Validate that fails on the base; the person is asked before any task agent is launched, the
     scripted answer patches the command, and Build goes on with every task kept. Three modes.
  9. `scripts/e2e/replay.ts`: the filtered `verify` is caught by the row `maven filtered verify` as today. And in
     `slow-first-run` (`scripts/e2e/slow.ts`): the fake suite runs on the base once, not twice, because the plan's
     Validate is the owner's text and `baseline plan` then has nothing to run.
  10. Rewrite `scripts/selftest/temper-cases-22.sh` (the preflight's classes and store), `-23.sh` and `-27.sh` (the
      setup block's check and the environment agent) and the preflight lines of `-24.sh` to the cases above, and
      list each rewritten assertion in `docs/plans/one-go/changed-tests.md`.
  11. From `scripts/selftest/expected-fail.txt`: the scenario `broken-first-run` (row `D13`, and with it the last
      part of row `D33`) passes and leaves the list here. So do the checks of row `D99` in
      `scripts/selftest/temper-cases-45.sh`: the plan gate runs no command, and a slow one asks `plan.command` with
      its three ways on as options. `D55` (never an environment fault, never an agent) passed at WP08 and keeps
      passing: no line of the list names WP21 under that token.
- **Mechanism:**
  1. **The plan gate.** Delete the two lines that add the `preflight` row (`scripts/temper:3600-3601`). The Plan
     agent runs `temper gate plan` itself before it returns (`agents/plan.md:59-61`); from here on that call is
     static. The two Maven rows stay (`scripts/gate_rows.py:150-212`).
  2. **`temper baseline plan`.** A new entry of `scripts/baseline.py` that starts a background process and exits 0. It
     is an `after` call of the Plan agent, placed before `gate plan`, which stays the last call and the action's gate
     (`scripts/flow.py:1379-1383`; the `panel plan` call that stood between them went with WP15). The same call
     follows a fresh reviewer, a revision and a `plan patch` answer (`scripts/flow.py:2021-2027`). It only runs a
     command that has no result yet, so a second call is cheap. When the first Build action finds a command with no
     result, it makes the call itself. The switch `TEMPER_BASELINE_FOREGROUND` of WP20 keeps it in the foreground for
     the tests.
  3. **Which commands.** From `commands` (`scripts/preflight.py:44-61`, moved into `scripts/baseline.py`): the
     group Validates and the Integration line only. Left out: a text equal to the owner's test text (the baseline
     ran it), and a command that names a declared file that is not on the base (the test at
     `scripts/preflight.py:111-113`, on the command text only). Task Tests and scenario Tests never run on the
     base: they fail there by design.
  4. **How.** One after another in the baseline worktree of WP20, through the runner, each under Build's limit for
     it: a Validate under the group gate's default (`scripts/temper:2441`), the Integration line under
     `integrate`'s (`scripts/temper:3408`). A Maven command runs as written, not through `maven_loop`. Each result
     goes into `plan` of `.temper/evidence/baseline.json` under the command text:
     `{"result", "exit", "seconds", "class", "kind", "why", "fail_lines", "tail"}`. When the last one ends, the
     process calls `baseline clean`.
  5. **The binary rule.** Exit 0: `pass`; its seconds feed `limit_for`. Exit 124: `timeout`, a result of its own
     (in the record of WP23: class `command`, kind `timeout`, never class `environment`).
     Exit 125: class `environment`, the setup line failed. Exit 127, or a first word of the command that
     `command -v` does not resolve under the setup block: class `environment`, the program is missing. Any other
     exit: `fails like the base` when the baseline is red, else `fail` with class `command`. No output text takes
     part.
  6. **Programs resolve.** For every command of the plan, the task Tests and scenario Tests too, the same process
     resolves the first word of each segment (`programs`) in one shell call under the setup block. A program that
     does not resolve is an environment fault shown in `base.red`. This is the one static check on a command that
     cannot run on the base.
  7. **The question.** The function of `base.red` gains the scope `plan-command`, with the question id `plan.command`
     (one site with `base.red`). It is asked by `ask` for Plan when the gate passed and a result is `fail` or
     `timeout`, and by `build_work` when the result comes after the approval. Text: the command, where the plan wrote
     it, the exit, the seconds, the first fail lines. Options before the approval: "Revise the plan" (the call
     `state redo plan` with the failure as its reason), "Change the command" (a typed answer, `plan patch`), "Skip
     this check" with a reason (`baseline skip --cmd C --reason R`, an override row named `plan-command`), "Save for
     later" (`save`). For a time out, "Allow it more time" (`more-time`) comes first: it stores a limit in `limits` of
     the file. After the approval no new task agent is launched and the question keeps its options, with the loop back
     to Plan in place of "Revise the plan". An unattended run makes a recorded stop there: it may never change a
     gate's command, and it never plans again.
  8. **A result still running** is shown on the approval card as `running`. Nothing waits for it except the first
     group gate of the group whose Validate it is.
  9. **What stays of `scripts/preflight.py`.** Two functions move to `scripts/run_env.py`: `programs` (`:64-70`),
     and `env_fault` (`:73-96`) cut down to structure: the setup line failed (`:77-79`), exit 127 with a program of
     the command (`:90-93`), and, new, a `setup.services` address that does not answer right after the failed run.
     Its callers change their import: `scripts/check_run.py:36, 186` and `scripts/task_ops.py:19, 764`.
     `commands` moves to `scripts/baseline.py`. The file is deleted.
  10. **What goes with it.** `ENV_PATTERNS`, `CMD_PATTERNS` and `CLASSES` (`scripts/preflight.py:33-37`), the JDK
      range line and the offline line (`:82-85, 94-95`), `classify`, `quote`, `note_skip`, `store_key`, `make_row`,
      `run_all`, `run_classes`, `format_row`, `verify` and `main`; `.temper/preflight.json`;
      `temper plan preflight` (`scripts/temper:4568-4571`); the keys `plan.preflight-timeout` and
      `plan.preflight-skip` (`templates/temper.config.default:108-110`). A JDK out of range is now found by the
      environment check of WP20 from the project's files, a service that is down by its declared address, and
      everything else by the exit code of the baseline.
  11. **What stays of `scripts/doctor.py`.** The report, `version`, `answers`, `ci_facts`, `propose`, `parts`,
      `setup_of`, `write_block`, `block_hash` and `needs`. What goes: `--candidate` (`:496-503`), what is left of
      `checked` with its call of `preflight.verify` (`:457-483`), `record_failed`, `tried_and_failed` and
      `.temper/setup-tried.json` (`:400-429`). `--propose --write` stays as WP20 left it: the block the person
      read, bound by its hash, and the person's call in the mod (WP08).
  12. **The environment agent goes.** Delete `agents/env.md` and its line in `.claude-plugin/plugin.json:51`,
      `env_agent_work` (`scripts/flow.py:1207-1227`), its dispatch (`scripts/flow.py:2377-2379`), the second half
      of `setup_offer` (`scripts/flow.py:1200-1204`), the state key `env_agent`, the model name `env` (read at
      `scripts/flow.py:1222`) and `setup-proposal.yaml`. When no rule proposes a block, the question says what is
      missing, in the words of the fault. `setup_offer` is still called at Check (`scripts/flow.py:844`): there it
      loses its read of `preflight.json` (`:1189-1191`) and offers the block as the option `add-setup` of
      `base.red` does, shown whole and bound by hash.
  13. **ENV at a task gate.** The verdict's ENV branch (`scripts/task_ops.py:758-767`) calls the cut down
      `env_fault`, so only the three sure signs give ENV. The way out that WP08 added to `env_task`
      (`scripts/flow.py:1857-1870`) stays.
  14. **The plan brief.** In `agents/plan.md` replace the preflight paragraph (`:100-105`) by two sentences: a
      group's Validate and the Integration line must pass on the current code, the CLI runs each once after you
      return, and no time limit of 300 s applies.
- **Removed:** `scripts/preflight.py`; the plan gate row `preflight`; `temper plan preflight`;
  `.temper/preflight.json`; `.temper/setup-tried.json`; the keys `plan.preflight-timeout` and `plan.preflight-skip`
  and the model name `env`; the four classes and their text patterns; `agents/env.md` and the agent type
  `temper:temper-env`; `doctor --candidate`; the option "Let an agent find the setup"; the state key `env_agent`.
- **Documents in the same change:** `docs/flow.md:132-155` and `:201` (the preflight section becomes "A command the
  plan wrote", and the environment rule is the three sure signs), `docs/commands.md:212-263` (`temper doctor` without
  `--candidate`, no `temper plan preflight`), `reference/plan.md` (what a Validate must be), `agents/plan.md`, the
  config template, `CHANGELOG.md`, and the new decision record
  `docs/decisions/0020-checks-judged-against-the-project.md`, which amends ADR 0018 (decision 2 is replaced, decision
  3 is narrowed to the three sure signs, decision 4 is corrected: `doctor` writes the block the person chose; say why
  in ten lines and cite `docs/plans/one-go/evidence/pr-env.md`). WP31 later adds to it what WP19 and WP20 decided.
- **Done when:** the command below prints nothing; `bash scripts/validate-directory.sh` passes (the manifest lists no
  missing brief); `scripts/selftest/temper-cases-62.sh` and cases 22, 23, 24 and 27 pass; `plan-command-fails` passes
  in three modes; `broken-first-run` passes and is off the list; `claude plugin test .` passes;
  `bash scripts/verify.sh quick` is green.
  The rows this package turns green are listed under its id in "Rows by package" of `docs/plans/one-go/done.md`;
  that section wins over this list.

  ```
  grep -rn "preflight\|temper-env\|env_agent\|setup-tried\|--candidate" \
    scripts agents templates hooks commands .claude-plugin
  ```
- **Traps:**
  1. WP08 repaired M9, M13, M15, M16 and F4 of the merge list inside the preflight. Their tests then state
     behaviour of code this package deletes. Keep the intent of each as a case above (a slow command is never an
     environment fault; a failed result is never final; no block reaches the config unseen; a code bug that prints
     a connection error spends the attempt) and delete the rest with the code.
  2. `scripts/check_run.py:36` and `scripts/task_ops.py:19` import `preflight` at the top. Delete the file only in
     the commit that changes both, or every Check and every task gate stops.
  3. `scripts/caps.json` (WP05) counts briefs, keys, question sites and option labels. This package removes one brief
     (`agent_briefs` is 12 after it), the two `plan.preflight` keys, the model name `env` and the label "Let an agent
     find the setup", and adds no site (the scope `plan-command` is the site `base.red`). Reuse the labels that exist
     ("Revise the plan", "Save for later") and lower the numbers the file counts.
  4. `scripts/e2e/replay.ts` scripts the measured Java run around the preflight (its fake `mvn` prints the enforcer
     text, `:34`). The JDK fault must now come from the mock's `pom.xml` through the environment check. The mock's
     pom holds `<requireJavaVersion><version>[24,)` (`scripts/e2e/replay.ts:80`), which the reader of
     `scripts/doctor.py:244` matches; the fake `java` must print a version line `java_major` can read.
  5. `cannot_run` (`scripts/check_run.py:465-483`) keeps its own text signs for the acceptance lock. It is not part
     of the preflight; leave it.
  6. The project marker `<script>: SETUP: <reason>` (`scripts/check_run.py:183-185`) stays. It picks the next step
     only; the row stays red.
  7. A Validate that names no path and breaks on tests a later group changes cannot be told on the base. It still
     fails at the first group gate; do not add a pattern for it.
- **Size:** M.

## WP22 One digest, the reuse store, the flaky recheck

- **Goal:** The same command on the same tree runs once. One digest says what "the same tree" is, every row and
  every verdict names the tree it judged, a failure that is not the change's is checked once more before any agent
  is launched, and the person keeps a counted way to run a check whatever the store holds.
- **Depends on:** WP08, WP10, WP20, WP21.
- **Lane:** `flow core`.
- **Touches:** `scripts/run_env.py`, `scripts/check_run.py`, `scripts/scenario_ops.py`, `scripts/task_ops.py`,
  `scripts/baseline.py`, `scripts/temper` (`_gate_write_verdict`, `cmd_check`, the `--fresh` flag of
  `cmd_group_gate` and `cmd_integrate`), the flow modules that hold `stage_work` and `ask` for Check,
  `scripts/flow_base.py` (the option id `run-anyway`), `scripts/card.py` (the commit card),
  `hooks/temper-mod/core/rules.ts` (only if WP08 left the store unguarded), `tests/mod/guard.test.ts`,
  `scripts/selftest/` (`temper-cases-63.sh`, new; cases 5, 11, 15, 16 and 25), `scripts/e2e/scenarios.ts`,
  `scripts/e2e/slow.ts`, `scripts/e2e/broken.ts`, `scripts/e2e/floor.json` (`suite_runs`),
  `scripts/e2e/replay.ts`, `docs/trust.md`, `docs/flow.md`, `reference/check.md`,
  `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-63.sh` (new), for the runner. Every case counts runs with a counter file
     the test command appends to. Case `w22 one tree, two places`: the same command in a group worktree and in the
     project folder with the same content is one run, and the second row carries `reused` and the same `tree`.
  2. Case `w22 byproducts`: a command that leaves `__pycache__` and a `.coverage` file the project does not ignore
     is reused on the second call (the head runs it again, `scripts/run_env.py:135-138`).
  3. Case `w22 what ends a pass`: an edit of a tracked file, a new untracked file, a removed file, another command
     text, a changed setup block, another folder of the repository, another first version line of the command's
     program, and (for the acceptance command) a changed lock digest each cause a new run.
  4. Case `w22 a byproduct is never a tracked file`: a store whose byproduct list was edited by hand to hold a
     tracked file, a declared file or a test file ignores those entries; an edit of that file still ends the pass.
  5. Case `w22 a failure is not a pass`: a failed run is kept beside the pass and never returned as a pass; the same
     failed check on the same key is not run again, and the row says when it failed.
  6. Case `w22 flaky`: a command that passed on the base, fails once and then passes is run twice, the row and the
     store entry carry `flaky`, and no agent was launched between the two runs. A failure whose fail lines name a
     declared file is not run a second time.
  7. Case `w22 two at once`: two calls for one key at the same moment give one run; the second waits and reads the
     first one's entry. Two calls for different keys lose no entry.
  8. Case `w22 run it anyway`: `temper check run --fresh` runs although a pass is kept, marks the row `forced`,
     and spends one repeat of the budget of WP10; at the limit the call is refused.
  9. Case `w22 every verdict names its tree`: after `temper gate build` and `temper gate check`, each entry of
     `.temper/gates.json` holds `tree`, and an edit of a tracked file changes it.
  10. Rewrite the five assertions on `check ahead` and adopt in `scripts/selftest/temper-cases-15.sh`: with a suite
      that leaves `.coverage`, the run made beside Review is used by `check run` (one suite run in all).
  11. Add a run count (the floor key `suite_runs`) to `threeGroups` of `scripts/e2e/scenarios.ts` (the scenario
      `three-groups`) and to `slow-first-run` of `scripts/e2e/slow.ts`: the suite runs at most once per group plus
      once on the base, and each scenario test at most twice.
  12. `tests/mod/guard.test.ts`: a write to `temper-results.json` in the git folder is refused.
  13. From `scripts/selftest/expected-fail.txt`: the scenario `broken-flaky` of `scripts/e2e/broken.ts` (row
      `D14`), and `D15`, `D34b` and `D34c` of `scripts/selftest/temper-cases-44.sh` pass and leave the list
      here. `D34a` stays listed for WP30, which removes the last key that counted a claim. List the rewritten
      assertions of test 10 in `docs/plans/one-go/changed-tests.md`.
- **Mechanism:**
  1. **The digest.** Add `tree_key(wt, byproducts)` to `scripts/run_env.py`: the git tree of the work tree as it
     is (tracked files with their content now, every untracked file git does not ignore), without `.temper/`,
     `.claude/` and the byproducts. It replaces the clean tree rule of `result_key` (`scripts/run_env.py:133-141`)
     and `tree_digest` (`scripts/check_run.py:757-772`). The recipe, tried in a scratch repository for this kit:

     ```
     cp "$(git -C WT rev-parse --git-path index)" TMP/index
     GIT_INDEX_FILE=TMP/index GIT_OBJECT_DIRECTORY=TMP/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=<objects> \
       git -C WT add -A -- ':(top)' ':(exclude,top)<prefix>.temper' ':(exclude,top)<prefix>.claude' <one per byproduct>
     GIT_INDEX_FILE=TMP/index ... git -C WT write-tree
     ```

     `<prefix>` is `git rev-parse --show-prefix`, `<objects>` is `git rev-parse --git-path objects`. Results of the
     trial: a clean tree gives `HEAD^{tree}`; a linked worktree with the same content gives the same value; an edit
     and a new untracked file change it; the real index and the real object store are not touched.
  2. **Byproducts.** A byproduct is an untracked path, not ignored, that was absent before a run the runner made
     and is there after it: the logic of `scripts/task_ops.py:428, 438`, moved into the runner. A path is never
     recorded, and a listed one is dropped at each use, when git tracks it, when a task declares it
     (`approved_files` of the run state), or when it is a source or test file (`SOURCE_EXT` and `is_test_path`,
     `scripts/check_run.py:203-213`). The trial showed why: leaving a tracked file out of the `git add` keeps its
     old content in the digest, so an edit of it would not end a kept pass. Only the runner writes the list.
  3. **The store.** It stays `temper-results.json` in the git common folder (`scripts/run_env.py:124, 144-146`):
     one file for every worktree of the clone, outside every work tree, kept by `state clear`. New: a lock file
     beside it, held with `fcntl.flock` around read, change and replace (`scripts/run_env.py:156-177` has none).
     The byproduct list sits under one reserved key. `KEEP` stays 200. An entry:

     ```
     {"pass": {"ts", "tail", "seconds", "extra"},
      "fail": {"ts", "rc", "tail", "fail_lines", "answer"}, "flaky", "forced"}
     ```
  4. **The key.** The digest; the command text (for the suite, the owner's run text); the setup block; the folder
     inside the repository; the first version line of each program the command starts and of each `setup.tools`
     entry (`version`, `scripts/doctor.py:37-49`, read once per CLI call); and what the caller adds. The
     acceptance command adds the lock's file digests (`scripts/check_run.py:666-667`), because its tests live
     under `.temper/`. The time limit is not part of it. Not knowable and so not in it: ignored folders
     (`node_modules`, `target/`), a service's state, the clock. `docs/trust.md` says so.
  5. **Call sites through the store.** Already: the group's Validate (`scripts/task_ops.py:464`) and the
     Integration suite (`:488`). New: a task's owed scenario tests (`scenario_ops.run_owed`,
     `scripts/scenario_ops.py:124-130`), the scenario tests at `integrate` (`scripts/scenario_ops.py:145`), Check's
     suite, scenario tests and acceptance run (`scripts/check_run.py:693-696, 720, 671`), the baseline and the
     plan's commands on the base (`scripts/baseline.py`). Left out on purpose: a task's RED and GREEN
     (`scripts/task_ops.py:433, 435`), `cannot_run` (`scripts/check_run.py:475`), the planted bug runs (`:386`),
     the regression proof (`:421`).
  6. **Every row and verdict names its tree.** Each row a runner call makes carries `tree`, `key`, `seconds` and
     `reused` (the date, or null). `_gate_write_verdict` (`scripts/temper:1834-1851`) adds `tree`, the digest of
     the project folder at that moment, to the gate's entry.
  7. **One run in flight per key.** A lock file per key in the git common folder; a second caller waits and then
     reads the entry. This replaces the wait on a process id in `adopt` (`scripts/check_run.py:810-815`).
  8. **A kept failure.** The last failure per key is kept beside the pass and is never a pass. A failed check is
     not run again on the same key: the call returns the kept failure with its date. Three exceptions run: the
     class is `environment` or `not measured` (at most twice), the flaky recheck below, and `--fresh`. The
     person's "Run it again" of the base question (`baseline start --again`) is a fresh run and is not counted.
     With this the count `fix_empty` (`scripts/group_fix.py:79-86`) and the two text compares
     (`scripts/flow.py:756, 856`) say what the store already knows; keep them, and let the questions read the
     store first.
  9. **The flaky recheck.** In the runner: when a run fails, the same command has a pass on the base tree (the
     baseline, or a plan command of WP21), and no fail line names a file the plan declares, the runner runs it
     once more at once, on the same tree and limit. Fail then pass: the entry and the row get `flaky`, the pass
     counts, and the commit card lists it. Fail twice: the failure stands. It is the CLI's fixed rule, one per
     failed check, and is not counted in the budget.
  10. **`check ahead`.** Delete `tree_digest`, `ahead_paths`, `adopt` (`scripts/check_run.py:757-829`) and the
      `adopt` call (`:857-858`). `ahead` becomes: run Check's commands through the runner into a throwaway ledger
      (a warm store), then the planted bugs of WP19. `check run` finds each entry by key. The head threw the whole
      background run away whenever the suite left a file such as `.coverage`
      (`scripts/check_run.py:788, 797, 764-771`).
  11. **"Run it anyway".** One flag, `--fresh`, on `check run`, `group gate` and `integrate`: the call runs whatever
      the store holds. It is the person's option only (option id `run-anyway`, under More options of the Check
      and commit questions and of a failed check's question), it spends one repeat of the budget of WP10, and its
      row carries `forced`. An unattended run never takes it.
- **Removed:** `tree_digest`, `ahead_paths`, `adopt` and `.temper/check/ahead.json`; the clean tree rule of
  `result_key`; the direct `run_cmd` calls at the sites of step 5.
- **Documents in the same change:** `docs/trust.md` (what a reused pass proves and what it cannot see; one run per
  tree is the guarantee one CI run gives, weaker than the repeated runs of 9.8.4, the version users have),
  `docs/flow.md` (the digest and the store in ten lines, the rows `reused`, `flaky`, `forced`),
  `reference/check.md:190-194` (one suite run), `CHANGELOG.md`.
- **Done when:** `scripts/selftest/temper-cases-63.sh` and cases 5, 11, 15, 16 and 25 pass; the run counts of
  `three-groups` hold in three modes and those of `slow-first-run` in plain and driver mode; `broken-flaky`, `D15`,
  `D34b` and `D34c` are off
  the list; `grep -n "tree_digest\|adopt(" scripts/*.py` prints nothing; `claude plugin test .` passes;
  `bash scripts/verify.sh quick` is green.
  The rows this package turns green are listed under its id in "Rows by package" of `docs/plans/one-go/done.md`;
  that section wins over this list.
- **Traps:**
  1. Never put a tracked file, a declared file or a test in the byproduct list: that is where a stale pass comes
     from (`docs/plans/one-go/evidence/red-safety.md`, M13). Case 4 holds it.
  2. `git add` on the copied index writes a blob for each changed file. Without the temporary object folder those
     land in the project's object store on every gate call.
  3. No selftest names the store at the head (`grep` for `run_cached` and `temper-results` in `scripts/selftest/`
     finds nothing). The hits for `reused` in cases 5 and 6 are about worktrees, not about the store.
  4. Version probes cost time: `mvn --version` takes about a second. Read each once per CLI call and never inside a
     loop over commands.
  5. A pass in a group worktree is reused for the project folder. A test that depends on an absolute path is then
     not run where the code will live. Say so in `docs/trust.md`; do not add the folder's absolute path to the key,
     or the reuse this package is for is gone.
  6. Keep the return shape of `run_cached` (`scripts/run_env.py:149-150`): two callers unpack three values.
  7. The store decides gate rows. If the guard list of the mod does not hold it after WP08, add it there with a
     test, and run `bash scripts/check-mod-calls.sh`: a guard pattern is no host call, the list must not grow.
  8. A kept failure plus a database started by hand gives "it failed on this tree" for a check that would now
     pass. That is what `--fresh` is for; make sure every question about a failed check offers it.
- **Size:** M.

## WP23 The checks run when Build ends; one failure record

- **Goal:** The suite with coverage, the scenario tests and the locked acceptance tests run inside `integrate`,
  before Review. A failure there picks its next step by its class: the triage first for an acceptance test, in
  every mode; the setup question for an environment fault, and no fix agent. Every failure is one typed record
  that a step back does not erase.
- **Depends on:** WP09, WP10, WP11, WP16, WP17, WP19, WP20, WP21, WP22.
- **Lane:** `flow core`.
- **Touches:** `scripts/failure.py` (new), `scripts/check_run.py`, `scripts/gate_rows.py`, `scripts/scenario_ops.py`,
  `scripts/task_ops.py`, `scripts/group_fix.py`, `scripts/task_blocked.py`, `scripts/loop_step.py`,
  `scripts/baseline.py`, `scripts/output_ops.py`, `scripts/run_report.py`, `scripts/temper` (`cmd_integrate`,
  `gate_build`, `_group_gate_record`, `_integ_record`, `_task_gate_body`, `_gate_write_verdict`,
  `_archive_ledger`), the flow modules that hold `build_work`, `ask` for Build and Check, `setup_fault`,
  `acc_failure`, `acc_triage`, `acceptance_triage_work`, `acceptance_options`, `acceptance_fix_work`,
  `fault_lines`, `feedback_lines`, `group_fix_work`, `stage_work`, `core_next` and the view, `agents/acceptance.md`,
  `agents/build-task.md`, `scripts/selftest/` (`temper-cases-64.sh`, new; cases 8, 11, 15, 16, 25 and 26), both
  view fixture files, `scripts/e2e/scenarios.ts`, `scripts/e2e/replay.ts`, `scripts/flow_base.py` (the option id
  `correct-test`), `scripts/run_summary.py` (counts by class), `scripts/e2e/floor.json`, `docs/flow.md`,
  `docs/grouped-build.md`, `reference/check.md`, `reference/autonomy.md`, `scripts/selftest/expected-fail.txt`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. Selftest, `scripts/selftest/temper-cases-64.sh` (new). Case `w23 what integrate runs`: after `temper integrate`
     on a one group run the Build ledger holds, in this order, the suite row in the owner's run text, a coverage row,
     one row per scenario test and the acceptance row; the counter file shows one run of each.
  2. Case `w23 the Build gate reads them`: a failing acceptance row leaves the integration verdict PASS and fails
     `temper gate build` on the row `acceptance tests written before Build`; a coverage drop fails it on
     `coverage`; coverage not measured does not.
  3. Case `w23 Check reuses`: on the tree `integrate` left, `temper check run` runs no command (the counter does not
     move) and its ledger holds the suite, coverage, scenario and acceptance rows, each with `reused` and `tree`.
     After one edit of a tracked file every one of them runs.
  4. Case `w23 triage first, in every mode`: with a failing locked test at the Build gate, `temper next --json`
     returns the triage agent, also when the run is unattended (the head skips it there, `scripts/flow.py:1471`).
  5. Case `w23 the triage picks the step`: verdict `code`: one fix pass as the CLI's own action, one repeat spent.
     Verdict `test`: a question whose option "Correct the acceptance test" (`correct-test`) is the person's, and
     no agent that changes code. No verdict: the question.
  6. Case `w23 setup at Build`: a suite that exits 125 at `integrate` gives the setup question at Build with no
     fix agent; the second identical failure recommends "Save for later"; the option that says it is the code
     (`it-is-the-code`) launches the fix pass.
  7. Case `w23 a fix run`: after the Fix agent's `after` calls the Build ledger holds the suite row and the
     regression proof; a red suite fails the Build gate before any Review agent is launched.
  8. Case `w23 the record`: a failed group gate, a failed `integrate`, a blocked task and a red base each append
     one record with every field of the format; `class` is one of the five; the record of the failed `integrate`
     has the `scope` `gate:build`; the record of the group gate is still
     there after `temper state loop build plan`.
  9. Case `w23 a class never changes a verdict`: a record of class `environment` leaves its gate FAIL; it is
     resolved only by a pass of the same check on another key or by the person's skip with a reason.
  10. Case `w23 the record is archived`: `temper state archive` writes the records into the spec folder's
      `gate-ledger.json`, and `temper state clear` leaves that file.
  11. `scripts/e2e/accept.ts`, the scenario `acceptance-wrong-test` that WP07 wrote (row `D21`): a wrong locked test
      is met at `integrate`; one triage launch, one dialog, one writer launch, then Review; no builder launch for it.
      Three modes.
  12. `scripts/e2e/scenarios.ts`, a new scenario `setup-at-build` (the function `setupAtBuild`): an environment fault
      at `integrate` in an unattended run is a recorded stop with the setup question and no fix agent.
  13. Same file, `fixRun` (the scenario `fix`): assert that the suite ran before the Review agent was launched.
  14. `scripts/e2e/replay.ts` gets no acceptance test here. It records the acceptance step as skipped (`:237`),
      and a wrong locked test there would be a fourth question against row `D58` (3 questions) and the floor
      entry `replay`. The run that looped at Check on a wrong acceptance test is held by `acceptance-wrong-test`
      of test 11 alone; `bun scripts/e2e/replay.ts final` keeps its 3 questions.
  15. Rewrite the eleven acceptance assertions of `scripts/selftest/temper-cases-15.sh` and the SETUP cases of
      `-26.sh` to the stage they now happen at; keep the rule of WP08 that a second identical setup fault does not
      recommend the same repair. List each rewritten assertion in `docs/plans/one-go/changed-tests.md`.
  16. From `scripts/selftest/expected-fail.txt`: the scenarios `acceptance-wrong-test` (row `D21`) and
      `slow-first-run` (row `D11`), and `D35a` of `scripts/selftest/temper-cases-44.sh`, pass and leave the list
      here.
- **Mechanism:**
  1. **`build-checks`.** Add the entry `build-checks ROOT SPEC LEDGER BASE COMMAND` to `scripts/check_run.py`. Through
     the runner of WP22 it records into the Build ledger, in this order: the suite in the owner's run text, with
     the coverage report, the claim `Integration suite` and phase `integration`; the coverage row of WP19; each
     scenario test (the body of `scenario_ops.integrate`, `scripts/scenario_ops.py:133-155`); the locked acceptance
     tests (`acc_run`, `scripts/check_run.py:656-674`). A suite failure with a setup fault adds the row
     `setup fault: <why>` as Check does (`scripts/check_run.py:700-703`). It exits with the suite's exit code. A
     suite failure that the person's skip of WP20 covers is written as the third state row and exits 0.
  2. **One owner.** `integrate` runs the owner's run text of WP20, not the plan's Integration text, whenever the
     config or `detect` names a suite. The plan's line is the owner only when they name none; then a run never
     ends at Check for want of a test command (`scripts/check_run.py:680-682`). The row keeps the plan's text in
     `plan_cmd` when it differs. A group's Validate whose text equals the owner's test text is run in the owner's
     run text too (one function in the runner maps the text, used by `grouprun`, `scripts/task_ops.py:464`), so the
     last group's gate and `integrate` share one key on the merged tree. Choice: one owner,
     because without it Check never reuses the pass of `integrate`
     (`docs/plans/one-go/evidence/v-checks-once-early.md`, section 4) and the slow project cannot stay at three
     suite runs.
  3. **`cmd_integrate`.** Replace the `integrun` and `scenario_ops.py integrate` lines after the merge
     (`scripts/temper:3405-3423`) and in the branch for a run that is integrated already (`:3316-3331`) by one call
     of `build-checks`. A failing suite fails the integration as today (`:3413-3417`). A failing scenario test,
     acceptance test or coverage row leaves the verdict PASS, as scenario tests do today (`:3419-3420`), so the
     Build gate fails on the row. The Interfaces check stays (`:3424-3429`). The limit is `limit_for` of WP20.
  4. **The Build gate.** `build-rows` of `scripts/gate_rows.py` (`:335-338`, called at `scripts/temper:3651`) prints
     two more rows from the Build ledger: `acceptance tests written before Build`, with the logic of
     `scripts/temper:3932-3945`, and `coverage`, the row of WP19. The names are the ones Check uses, so the flow's
     matchers serve both stages. No line is added to the bash file.
  5. **The next step at a failed `integrate` or Build gate.** Read it from the open failure records, in this order.
     Class `environment`: the setup question, and no fix pass. A failed locked acceptance test and nothing else:
     the triage. Class `code`: one fix pass as the CLI's own action, counted in the budget of WP10; then the run
     asks. The fix pass rule at `scripts/flow.py:1658-1672` gets this test in front of it; today it launches a
     fix agent on whatever `fault_lines` names, an environment fault too.
  6. **The acceptance path moves to Build.** `acc_failure` (`scripts/flow.py:1445-1457`) reads the failed rows of
     the stage the run is at, not of `check`. `acceptance_triage_work` (`:1465-1485`) loses `r.armed()` from its
     guard at `:1471`, takes the stage for its text and its usage row, and is dispatched for Build too
     (`scripts/flow.py:2395` tests `stage == "check"`). Triage `code`: step 5, class `code`. Triage `test`: the
     question of the stage with `acceptance_options` (`:1487-1511`); the call `acceptance reopen` stays the
     person's, and no rule ever changes code for a test the triage does not blame on the code.
     `acceptance_fix_work` (`:1513-1538`) drops its test `r.stage != "check"` at `:1519`; at Build its last
     `after` calls are `integrate` and `gate build` in place of `state redo check`. The texts that name the Check
     question (`scripts/check_run.py:516, 519, 638`) name the stage the run is at.
  7. **The setup question at Build.** `setup_fault` (`scripts/flow.py:1229-1234`) reads the ledger of the stage the
     run is at. The SETUP branch of the Check question (`:837-851`) becomes one function used by the failed Build
     question first and by Check second. Options: add the proposed block (`add-setup`) when the config has none and
     `propose` gives one, with the exact block in the text; "I repaired it: run the checks again" (`check-again`;
     `integrate`, then `gate build`; the kept failure runs again because its class is `environment`); "It is the code"
     (`it-is-the-code`), which launches the fix pass; "Save for later" (`save`), recommended when the same fault came
     back (the rule of WP08 for M10). An unattended run makes a recorded stop here; it repairs no environment.
  8. **What Check still does.** On the tree `integrate` left: `check run` writes the suite, coverage, scenario and
     acceptance rows from the store, each marked `reused` with its key and tree, so the rows of `gate_check` keep
     their evidence (`scripts/temper:3869-3945`); no command runs. On a tree that changed after `integrate` (a
     repair at Review): every command runs, through the runner. In a run with no `integrate`: everything, for
     real. Always: the regression proof of a fix, the criteria validated by `code` or `metric`
     (`scripts/flow.py:1361-1373`), a criterion the person confirms by hand, the row `acceptance evidence`
     (`scripts/temper:3958-3969`).
  9. **A run with no `integrate`.** A `/temper:fix` run has no `tasks.md` (`scripts/temper:3692-3693`), and a door's
     run on code built earlier skips it (`:3618-3631, 3704`). For a fix run, add `temper check build-checks` to the
     Fix agent's `after` calls, before its gate: the suite and the regression proof are recorded when the Fix agent
     returns, and a red result fails the Build gate, which a fix run uses (`gate_of`, `scripts/flow.py:272-273`),
     so the repair happens in the Fix stage before Review is paid for. `gate_build` calls `build-rows` only inside
     its test for a `tasks.md` (`scripts/temper:3646-3653`); move the call out, and let it print `tests pass` and
     `regression proof` for a fix run. The head has no lock on a fix's regression
     test (`acceptance_work` returns for a fix run, `scripts/flow.py:1400`). So a regression proof that fails twice
     with the same text asks one question, whose option "The regression test is wrong" sends the person's reason
     to the Fix agent as a note. A door's run keeps Check as its first real run.
  10. **`check ahead`** for a feature run is now only the planted bugs of WP19, since the store is warm from
      `integrate`. For a fix run it stays the warm run of WP22.
  11. **The record.** One file, `.temper/evidence/failures.json`, a list, written only by `scripts/failure.py`:

      ```
      {"id": "F3", "ts": "...", "stage": "build",
       "scope": "base | plan-command | task:4 | group:G1 | gate:build | gate:check",
       "check": "suite | validate | task-test | scenario | acceptance | coverage | interfaces | regression
                 | row:<name>",
       "cmd": "...", "exit": 1, "ran_by": "cli | person", "tree": "<digest>", "setup": "<digest>", "limit_s": 600,
       "key": "<the runner's key>", "class": "environment | command | plan | code | not measured",
       "kind": "<one of a closed list>", "class_by": "exit | structure | base | triage | person",
       "why": "<at most 300 characters>", "fail_lines": [], "row": "build#412", "n": 1, "step": "", "resolved": null}
      ```

      `scope` is the budget key of WP10 wherever the failure has one, spelled the same (`gate:<stage>`,
      `group:<G>`, `task:<N>`, `acceptance`, `pipeline`; `docs/plans/one-go/contracts.md` section 8). A failed
      `integrate` spends its repeat under the key `gate:build`, so `gate:build` is the `scope` of its record, and
      the field `check` says which check of `integrate` failed.
      Choice of place: under `.temper/evidence/` the mod guards it already (`hooks/temper-mod/core/rules.ts:110`), a
      step back leaves it (`scripts/temper:1876-1896` empties the stage ledgers, and the reset of `groups.json` does
      not reach it), and `_archive_ledger` (`scripts/temper:1341`) copies it into `gate-ledger.json`.
  12. **The class, by structure only.** `environment`: exit 125, exit 127 with a program of the command, a declared
      service that does not answer, a fault of the environment check, a failure the base shows too (kinds
      `setup-line`, `program-missing`, `service-down`, `tool-version`, `red-base`). `command`: exit 124, a plan
      command that fails on a green base, a fix agent that changed nothing, a scenario test at which pytest found
      no test, `scripts/scenario_ops.py:118-120` (kinds `timeout`, `fails-on-base`, `fix-changed-nothing`,
      `no-test-found`). `plan`: a blocked task, an undeclared change, a merge conflict, a group with no Validate, a
      missing interface, a locked test the triage calls wrong (kinds `blocked-task`, `undeclared-change`,
      `merge-conflict`, `no-validate`, `interface-missing`, `test-wrong`). `not measured`: a value nobody took,
      said by the gate that knows it is absent (kinds `no-tool`, `no-base`, `no-run`). `code`: every other failed
      run the CLI made on a tree that differs from the base, a measured coverage drop, a finding (kinds
      `test-failed`, `coverage-drop`, `finding`). The list of kinds is closed and lives in `scripts/failure.py`. A
      class picks the next step. It never changes a verdict.
  13. **Where it is written.** One call of `failure.record` at each site: a failed task gate (`_task_gate_body`,
      near `scripts/temper:3145`); `_group_gate_record` (`scripts/temper:2518-2536`); `_integ_record`
      (`:3292-3298`); `_gate_write_verdict` (`:1834-1851`), one record per failed row that no run recorded yet;
      `build-checks` and `check_run.run`; the baseline and the plan's commands (`scripts/baseline.py`); a group fix
      that changed nothing (`scripts/group_fix.py:79-86`); `task blocked` (`scripts/task_blocked.py:56`). A pass of
      the same check and scope on another key sets `resolved`; so does the person's skip, with its reason.
  14. **Who reads it.** The step of 5. The prompt builders `fault_lines` (`scripts/flow.py:1236-1246`),
      `feedback_lines` (`:1248`) and `group_fix_work` (`:2048`), which take `why` and `fail_lines` from it. The
      loop record: `loop_step` names record ids where it copies text by three collectors today
      (`scripts/loop_step.py:35-53`). The budget of WP10: `n` is the count the budget holds for the record's
      `scope`; the counts stay in `.temper/budget.json` to the end and are not moved here
      (`docs/plans/one-go/contracts.md` section 14). `scripts/output_ops.py`, the view (the open records:
      class, why, step), the report, the commit card (each record's `step` is what a rule did), and the run
      summary of WP05 (`scripts/run_summary.py`: counts by class).
- **Removed:** the first run of the locked acceptance tests at Check; the armed run's skip of the triage; a fix
  pass on an environment fault; the second suite run and the second run of every scenario test on the merged tree;
  the three collectors of `scripts/loop_step.py` as the only memory of a failure.
- **Documents in the same change:** `docs/flow.md` (what `integrate` runs, the Build rows, the SETUP paragraph at
  `:201`, a section on the failure record with its five classes), `docs/grouped-build.md` (`integrate`),
  `reference/check.md` (what Check still runs), `reference/autonomy.md` (what a rule does at a failed Build gate,
  class by class), `agents/acceptance.md` (the triage and the correction name the stage they are at),
  `agents/build-task.md` and the line the flow gives builders (`scripts/flow.py:1436-1441`: "must pass at
  integration" is now true; "Check fails a change" becomes "the Build gate fails a change"), `CHANGELOG.md`.
- **Done when:** `scripts/selftest/temper-cases-64.sh` and cases 8, 11, 15, 16, 25 and 26 pass;
  `acceptance-wrong-test`, `setup-at-build` and `fix` pass in three modes, and the first is off the list;
  `bun scripts/e2e/run.ts both` reports every scenario identical with the mod and without it; on `slow-first-run` the
  suite ran at most three times and no limit was hit, and it is off the list; on `broken-first-run` every fault was
  named before Build with no agent launched for it; `bash scripts/verify.sh full` is green (this package ends phase
  5).
  The rows this package turns green are listed under its id in "Rows by package" of `docs/plans/one-go/done.md`;
  that section wins over this list.
- **Traps:**
  1. `scripts/temper` is near the file limit and `cmd_integrate` is 130 lines of it. This package must leave the
     file smaller: the order of the checks lives in `scripts/check_run.py`, the rows in `scripts/gate_rows.py`, the
     record in `scripts/failure.py`.
  2. A failed `integrate` is a verdict, not an error. WP09 made the carriers read it so; do not add a failing call
     in front of it, or a driven run is handed back.
  3. M1 of the merge list (a fix pass that breaks the suite strands the run) lives in the branch at
     `scripts/temper:3316-3327`. WP08 repaired it there; carry that repair into the one `build-checks` call.
  4. The Build gate gains two rows and the Check and Build questions change stage: regenerate both fixture files,
     and update `scripts/e2e/floor.json` only where a count truly changed (dialogs on a clean run must not).
  5. `scripts/selftest/temper-cases-15.sh` simulates Check with hand written ledgers. Rows now need `tree` and
     `reused` to be read as reused; a helper in `scripts/selftest/case-helpers.sh` saves forty edits.
  6. The record file must be listed where the run files are listed for archive and for the view, and it must not
     be removed by `_clear_evidence_downstream` or by the reset of the groups.
  7. Do not rewrite the question logic around the record. The plan lists "the next step as one function over the
     failure record" under Later. This package reads the record at the failed Build gate, in three prompt
     builders and in the loop record, and nowhere else.
  8. The suite now runs in its coverage form at `integrate`. On jest the coverage command is `npx jest`, not the
     project's `npm test` script (`scripts/check_run.py:122, 132`). A project whose script does more than run jest
     sets `check.commands.test`; say so in `reference/check.md`.
  9. The planted bug run reads the suite's seconds from the store entry of the current tree; with no entry it does
     not run and says why.
- **Size:** L.
