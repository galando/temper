# Phase 4, first half, the flow core: WP09, WP10, WP11, WP12, WP13 and WP14

This file holds the specs of work packages WP09 to WP14: the verdict marker, the one budget, the run to the commit,
the approval bound to what was shown, the rule that leaves Intent, and Design as questions in front of the approval.

The brief is `docs/plans/one-go/README.md`, and every shared name below is the one `docs/plans/one-go/contracts.md`
fixes. Every `file:line` is of the head `10e965a`. WP02 and WP03 land before these packages and move code: find each
function by its name, with the module table of WP03 (`Run` is in `scripts/flow_run.py`, `ask` and the option makers
in `scripts/flow_ask.py`, `policy_move` and `stage_work` in `scripts/flow_work.py`, the Build questions in
`scripts/flow_build.py`, the commit question in `scripts/flow_commit.py`, `Builder.next` and `core_next` in
`scripts/flow.py`, the view in `scripts/flow_view.py`, and the tables `MOVES` and `SEQ` with the registries
`QUESTIONS` and `OPTION_IDS` in `scripts/flow_base.py`).

## The order inside phase 4, and why

Build the packages of phase 4 in the order of the brief's section 5: WP09, WP10, WP18, WP14, WP11, WP12, WP13, then
WP15, WP16 and WP17 (WP15 to WP18 are in `docs/plans/one-go/wp/phase-4b-cards-handback-fix.md`). Each package ends
as the brief's section 4 says: `bash scripts/verify.sh quick` green, then the package commit, then the small
progress commit, in one push. Run `bash scripts/verify.sh full` once after WP13 and once after WP17. All ten
packages are in the lane `flow core`, so none of them runs beside another.

1. **WP09 first.** A run that goes on by itself asks nobody at a passed check, so the first failed check is where a
   carrier must hold the run. At the head a failed `group gate` or `integrate` exits 1 with no `-> FAIL` text
   (`scripts/temper:2509-2512`, `:3413-3416`), `temper go` reports `error` (`scripts/go.py:108-114`) and the driver
   hands the run to the main session for good (`hooks/temper-mod/core/driver.ts:352`). Flip the default on top of
   that and every failed group check moves the rest of the run into the model of the main session.
2. **WP10 second.** In a run that goes on by itself the recommended option is what runs, so a limit that only moves
   the recommendation is the real bound. Only three of the eleven limits of the head refuse a call
   (`docs/plans/one-go/evidence/v-failure-budget.md`, section 1.3). `state redo`, `group reopen` and `group fix` are
   counted nowhere (`scripts/temper:1455-1492`, `scripts/group_fix.py:68-69`). The budget must refuse inside the
   call, and the flow must ask before it offers a call that would be refused, before anything runs unattended.
3. **WP18 third.** Once the Review question is gone, the Review gate is the only look at the change before the
   commit. Its two holes close first. From WP18 on `temper evidence resolve` refuses every call, until WP24 records
   a repair commit. This is meant (the brief's section 4): until then a blocking finding ends by the person's
   accept, or by the one counted loop back to Build of WP11 and a second Review. No test loosens the check.
4. **WP14 before WP11.** With Design in the run the option that starts the unattended run sits on the Design
   question (`scripts/flow.py:726-730`) and the plan question has none (`:681-689`). That variant was never run in
   a prototype (`docs/plans/one-go/evidence/v-auto-advance.md`, section 6, item 3). After WP14 Design follows only
   when the person asked for it, so WP11 changes one question in the default run. WP14 needs nothing of WP11 to
   WP13.
5. **WP11 is the flip.** It lands only when WP08 (the policy defects M1, M3, M4, M5, M6, M11 and the flip F1 of
   `docs/plans/one-go/evidence/v-pr115.md`), WP09, WP10, WP14 and WP18 are in.
6. **WP12 directly after WP11, before WP13.** WP13 lets one click accept an intent that had no question of its own.
   That click must carry the digests of what it showed, and the gates must fail when the intent changes later. WP13
   also needs the step that leaves Intent to make no branch and no commit, which WP12 builds.
7. **WP13 last of this file.** After it a clean scripted run asks two dialogs.

A check of `scripts/selftest/expected-fail.txt` leaves the list in the commit of the package named for it below.
A check that passed earlier is simply not on the list (`docs/plans/one-go/done.md`, note 7).
If one still fails there for a reason that belongs to a later package, do not weaken it: name that package on its
line of the list and in `docs/plans/one-go/PROGRESS.md`.

One decision record covers the phase: `docs/decisions/0019-a-run-that-asks-twice.md`. WP10 creates it with the
status Accepted and its own decision. WP14, WP11, WP12 and WP13 each add one numbered decision in their own package
commit, and WP25 later adds the one exception to decision 3.
It amends ADR 0011 (resolution 1 and the invariant list), ADR 0012 (decision 4), ADR 0013 (decision 1) and ADR 0016
(one row of its table).

Names of this phase that later packages use (`docs/plans/one-go/contracts.md` holds them all):

| Role | Name | Owner |
|---|---|---|
| the verdict marker | a stdout line `VERDICT: <scope> <PASS or FAIL or PARKED>` | WP09 |
| the budget record | `.temper/budget.json`, read through `scripts/budget.py` | WP10 |
| the question at the limit | question id `run.budget`, option id `grant-more`, call `temper budget grant` | WP10 |
| the call that starts the unattended run | `temper state set run_mode autonomous`, offered by option id `approve-run` | WP11 |
| the config key of the default | `run.default: to-commit`, `ask` or `never-unattended` | WP11 |
| the record of what a rule decided | `.temper/rule-log.json`, the view key `rule_log`, written by `scripts/rule_log.py` | WP11 |
| the sensitive path matcher | `scripts/sensitive.py`, key `autonomy.park-on-touch` | WP11 |
| the digest arguments | `--shown <file name>=<digest>` on `state advance`, `--digest <digest>` on `intent accept` | WP12 |
| the gate row of the binding | `intent unchanged since the approval` | WP12 |
| the write rule before the approval with the mod off | `scripts/guards/hold_before_approval.py`, kept only if the directory accepts it | WP12 |
| the option that asks for Design | option id `run-design` | WP14 |

Words such as "armed" and "parked" stay in every text that has them today. Taking them out of user text is left to
WP31. Do not rename a label, a `say` line or a state key in this phase; write new text without the two words.

## WP09 A verdict is a verdict for every carrier

- **Goal:** `gate`, `task gate`, `group gate` and `integrate` print one machine readable line when they recorded a
  verdict. `scripts/go.py`, the mod's driver, the scripted loop and the command page read that line, and nothing
  else, to tell a recorded verdict from a call that broke. A failed group check or a failed `integrate` reaches its
  question with no hand back.
- **Depends on:** WP02, WP03, WP04, WP07, WP08.
- **Lane:** `flow core`.
- **Touches:** `scripts/temper`, `scripts/go.py`, the flow modules (one comment, step 9),
  `hooks/temper-mod/core/driver.ts`, `scripts/e2e/loop.ts`, `scripts/e2e/scenarios.ts` (`policy-run` in driver mode),
  `commands/temper.md`, `commands/fix.md`, `docs/flow.md`, `scripts/selftest/temper-cases-50.sh` (new),
  `tests/mod/driver.test.ts`, `scripts/selftest/expected-fail.txt`, `scripts/e2e/floor.json`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-50.sh` (new; `docs/plans/one-go/contracts.md` section 10 reserves the number).
     Every name starts with `verdict:`. States are built with `fresh`, `gpass`, `gfail` and `nx` of
     `scripts/selftest/case-helpers.sh`, and a `groups.json` written as `_polg` writes it
     (`scripts/selftest/temper-cases-28.sh:33-38`).
     - `verdict: gate prints the marker as its last line`: after `temper gate intent` on a passing and on a failing
       intent the last line of stdout is `VERDICT: gate:intent PASS` and `VERDICT: gate:intent FAIL`.
     - `verdict: the line temper gate <stage> -> <verdict> is still printed` (five case files, one helper file
       and `scripts/e2e/loop.ts` read it).
     - `verdict: group gate prints it after a recorded FAIL`: a started group whose task has not passed gives exit 1
       and the line `VERDICT: group:G1 FAIL` (the record is made at `scripts/temper:2477-2478`, `:2509-2512`).
     - `verdict: a group gate that recorded nothing prints no marker`: `temper group gate G9` on a group that is not
       started (`scripts/temper:2467-2470`) and a call with a bad flag.
     - `verdict: integrate prints it for a recorded FAIL` (a group that has not passed, `scripts/temper:3356-3359`)
       and `verdict: integrate on a protected branch prints no marker` (exit 3, `:3336-3345`).
     - `verdict: a failed task gate prints it`, and
       `verdict: a task gate refused for a parked group prints group:<G> PARKED`.
     - `verdict: temper go goes on after a failed group gate`: from a state whose next action is the `group gate`
       call of `scripts/flow.py:1753`, `temper go` ends with `action` equal to `ask`, the call in `ran`, and
       `{"scope": "group:G1", "verdict": "FAIL"}` in `verdicts`.
     - `verdict: temper go goes on after a failed integrate`: from the action of `scripts/flow.py:1768` it runs
       `integrate` and then `gate build`, and ends with the Build question.
     - `verdict: a call that broke is still an error`: a `tasks.md` changed after the approval makes `group gate`
       fail in `_plan_fresh` (`scripts/temper:2459`); `temper go` ends with `action` equal to `error`.
     - `verdict: text alone is no verdict`: python imports `scripts/go.py` (as
       `scripts/selftest/temper-cases-22.sh:44` imports a module) and `recorded()` returns `None` for a marker
       whose scope is not the call's, and for a call that is not one of the four commands.
     - `verdict: only the marker tells a verdict`: `grep -c -- '-> FAIL' scripts/go.py` prints 0.
  2. `tests/mod/driver.test.ts`: a `group gate` that is a call of the person's answer and exits 1 with the marker
     does not hand back; an after call `integrate` that exits 1 with the marker does not hand back; an after call
     that exits 1 with no marker hands back as today; a marker of another scope hands back.
  3. From `scripts/selftest/expected-fail.txt`: the scenario `integrate-fail` of `scripts/e2e/accept.ts` (row `D07`
     of `docs/plans/one-go/done.md`) passes in driver mode and leaves the list here. `group-fail` and
     `group-fail-twice` stay listed until WP16 (row `D06`).
  4. `scripts/e2e/scenarios.ts`: the scenario `policy-run`, which WP08 wrote for plain and mod mode and left to
     this package for driver mode, passes in driver mode too: its failed group check is a recorded verdict, and the
     driver does not hand the run back.
- **Mechanism:**
  1. **The marker.** One line on stdout, alone on its line, printed after the record is written:
     `VERDICT: <scope> <verdict>`. The scope is `gate:<stage>`, `task:<N>`, `group:<G>` or `integrate`. The verdict
     is `PASS` or `FAIL`; `PARKED` exists only for `group:<G>`. Exit codes do not change. One bash helper prints it.
  2. **`cmd_gate`** (`scripts/temper:4229`): print the marker as the last line, after the rows
     (`:4326-4333`), before the return at `:4335`. Only when the verdict was recorded (`record` is 1, `:4293`) and
     the call did not come from the commit hook (`from_hook`, `:4232`): the reader of the hook's output is a person.
     The line of `:4312` stays.
  3. **`_group_gate_record`** (`scripts/temper:2518-2536`) and **`_integ_record`** (`:3292-3299`): print the
     marker at the end of the function. Their callers are `:2510`, `:2514` and `:3323`, `:3325`, `:3357`, `:3374`,
     `:3394`, `:3414`, `:3426`, `:3431`; check with `grep -n` that no other caller exists. The returns that record
     nothing print none: `:2448-2470`, `:3305-3308`, `:3336-3349`, `:3352`, `:3380-3383`.
  4. **`cmd_task_gate`** (`scripts/temper:3073`): `task:<N> FAIL` before the return at `:3186`, `task:<N> PASS`
     with the line `PASS: Task N` at its end. `_task_parked_refuse` (`:3064-3068`) prints `group:<G> PARKED`
     on stdout beside its message on stderr: the park is the recorded state, and `temper next` asks about it.
  5. **`scripts/go.py`.** New function `recorded(call, cli, out)`: the verdict when `call` starts with the CLI's
     path and one of `gate <stage>`, `task gate <N>`, `group gate <G>` or `integrate`, and the last line of `out`
     that matches `^VERDICT: (\S+) (PASS|FAIL|PARKED)$` names that call's scope (for `task gate`, its own task or
     any group); else `None`. At `:108-109`: a call that exits non zero is an error only when `recorded()` is
     `None`. It reads `r.stdout`, never stderr. `compact` (`:58-81`) gains the key `verdicts`, a list of
     `{"scope", "verdict"}` in the order they were read. The stop at the same calls twice (`:98-103`) stays: it
     bounds a verdict that never changes.
  6. **The driver.** One exported pure function `recordedVerdict(call, out)` with the rule of step 5. `runAll`
     (`hooks/temper-mod/core/driver.ts:255-264`, the test at `:261`) and the after calls (`:432`) use it in place
     of the two `-> FAIL` tests; `taskVerdict` (`:80-82`) becomes a call of it. What then remains of them is
     left to WP16.
  7. **The scripted loop.** `scripts/e2e/loop.ts:18-25` reads the marker by the same rule, for any call, not only
     the agent's gate call. Keep the old reading as the way back for a CLI that prints no marker: when the output
     of a gate call holds no `VERDICT:` line, `-> FAIL` still tells a verdict. The replay drives 9.8.4 and 9.8.5
     through `orchestrate` of this file (`scripts/e2e/replay.ts:20, 363`).
  8. **The page.** `commands/temper.md`, in the paragraph on `temper go` (`:69-75`) and in "A refused call"
     (`:171-172`), and the same place of `commands/fix.md`: a call that prints a `VERDICT:` line recorded a
     verdict; it is no failure whatever its exit code; run the calls after it, then `temper go`.
  9. **The flow.** Nothing changes in what `next` returns. The comment at `scripts/flow.py:2061-2063` gives a
     reason that no longer holds; correct the comment and keep the code.
  10. **What the marker may decide.** Only whether a carrier goes on to ask `temper next`. The next step always
      comes from `temper next`, which reads the recorded verdict. A carrier reads the marker only from a call it
      ran itself, never from an agent's text (`docs/plans/one-go/evidence/red-safety.md`, m2).
- **Removed:** the `-> FAIL` tests of `scripts/go.py:109` and of `hooks/temper-mod/core/driver.ts:261` and `:432`.
  The one of the scripted loop stays as the way back of step 7.
- **Documents in the same change:** `docs/flow.md` (the marker, in the section on `temper go`); `CHANGELOG.md`.
  The line of the package in `docs/plans/one-go/PROGRESS.md` is the progress commit that follows the package
  commit, in one push (`docs/plans/one-go/README.md` section 4).
- **Done when:**
  - `bash scripts/verify.sh quick` is green.
  - `bun scripts/e2e/run.ts driver integrate-fail policy-run` passes and `integrate-fail` is off the list.
  - `claude plugin test .` is green, `tsc -p tsconfig.mod.json` is clean, `bash scripts/check-mod-calls.sh` still
    prints 20 calls.
  - `bun scripts/e2e/run.ts all full-run default-run fix --floor scripts/e2e/floor.json` exits 0.
- **Traps:**
  - A test command's output never reaches the stdout of `group gate` or `integrate` (it goes to the row file,
    `scripts/temper:2495-2500`, `:3407-3412`). Keep it so: a test that prints a marker line must not be read.
  - `cmd_integrate` prints more lines after a record on its rerun path (`scripts/temper:3325-3331`), so readers
    take the last matching line of the whole output, not the last line.
  - After a failed `integrate` the next call `gate build` now runs and records FAIL with the row `integration`
    (`gate_build`, `scripts/temper:3613`). The Build question follows (`scripts/flow.py:764-765`). WP08 made the
    rerun path of a merged run return to the Build gate; do not undo that.
  - `scripts/temper` has 1,640 bytes of room at the head; WP02 frees 40 KB. This package adds about ten lines.
  - `scripts/e2e/replay.ts` drives the old plugin through `orchestrate` of `scripts/e2e/loop.ts`. After this
    package run `bash scripts/e2e/ab-replay.sh 10e965a` and see the base column as it was.
  - The fixtures do not change: `next` and the view are as before.
- **Size:** S.

## WP10 One budget in the CLI

- **Goal:** Every repeat that follows a failed check is counted by the CLI in one record: 2 for one failure and 6
  for one run. A call that would pass a limit is refused and writes nothing. The flow never offers such a call: at
  the limit it asks one question that shows the count, and only the person grants more. The old loop keys are read
  by nothing (rule 9).
- **Depends on:** WP02, WP03, WP04, WP07, WP08, WP09.
- **Lane:** `flow core`.
- **Touches:** `scripts/budget.py` (new), `scripts/temper` (the dispatcher, the word `budget`, `_RUN_FILES`,
  `cmd_state_clear`, `cmd_state_loop`), `scripts/loop_step.py`, the flow modules (`Run.can_loop`,
  `Run.loop_budget`, `round_limit`, `Builder.next`, and in `scripts/flow_base.py` the registries `QUESTIONS` and
  `OPTION_IDS` of WP04 and the table `MOVES`),
  `hooks/temper-mod/core/rules.ts`, `tests/mod/guard.test.ts`, `tests/mod/audit.test.ts`,
  `docs/decisions/0016-the-mod-answer-audit.md`, `docs/decisions/0019-a-run-that-asks-twice.md` (new),
  `templates/temper.config.default`, `.claude/temper.config`, `reference/status.md`,
  `reference/orchestrator-patterns.md`, `docs/flow.md`, `scripts/selftest/temper-cases-51.sh` (new), the case files
  that state the old keys, `scripts/selftest/make-view-fixtures.sh`, both fixture modules, `scripts/stops.json`,
  `scripts/caps.json`, `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-51.sh` (new), names start with `budget:`.
     - `budget: each kind of repeat spends one`: one assertion for each row of the table in Mechanism step 3; after
       the call `.temper/budget.json` holds one more entry with that row's key and kind.
     - `budget: the third repeat for one failure is refused`: exit 1, the line starts with `BLOCKED:`, and the
       record and the state are byte equal to before the call.
     - `budget: the seventh repeat of a run is refused` (three keys, two each, then a fourth key).
     - `budget: a change at a passed gate spends nothing`: `state redo build` on a passed Build gate, `group reopen`
       on a passed group, `state loop review build` from a passed Review gate.
     - `budget: no argument and no variable exempts a call`: an unknown flag and an environment variable named
       `TEMPER_BUDGET` change neither the count nor the refusal.
     - `budget: at the limit next asks run.budget`: the question id is `run.budget`, the first option is
       `save` with `recommended` true, `grant-more` is there, and no option of it or of its More question holds a
       call the CLI would refuse (run each call's key through `python3 scripts/budget.py room`).
     - `budget: no auto or work action holds a refused call`: with a record that already holds the limit of the
       run, `next` is never `auto` or `work` with a call of the table, at three states: a failed group check, a
       blocking finding at Review, a failed Check (the last two with the helper `_unattended` of WP07).
     - `budget: a grant adds two for the key and for the run, with its reason`.
     - `budget: the record survives a step back to Plan` (`groups.json` is archived, `scripts/temper:1276-1279`;
       the record is not) and `budget: state clear and state init remove it`.
     - `budget: the old keys are read by nothing`: a config with `loops.max-per-type: 9`, `fix.max-loops: 9`,
       `feedback.enabled: false` and an `autonomy.budget` block changes no count and no refusal, and `grep` finds no
       reader of those names under `scripts`.
     - `budget: an unattended run at the limit stops`: with the helper `_unattended` of WP07, `next` is the park
       call and then `run.budget`.
  2. `tests/mod/guard.test.ts`: `budget grant` outside the person's answer is refused; a write to
     `.temper/budget.json` is refused during a run. `tests/mod/audit.test.ts`: the fixture view of the limit
     question allows `budget grant` only on the exact match.
  3. From the list: `D38a`, `D38b`, `D38c`, `D38e` of `scripts/selftest/temper-cases-45.sh` and the scenario
     `budget-stop` (rows `D08` and `D38` of `docs/plans/one-go/done.md`) pass and leave it here.
- **Mechanism:**
  1. **The record.** `.temper/budget.json`, a file of its own, because every other store of a failure is deleted
     or archived by a step back (`docs/plans/one-go/evidence/v-failure-budget.md`, section 1.1):

     ```json
     {"v": 1, "run": "RUN ID",
      "used": [{"key": "group:G1", "kind": "group fix", "stage": "build", "why": "at most 200 characters",
                "ts": "2026-11-16T10:00:00Z"}],
      "grants": [{"key": "group:G1", "n": 2, "reason": "the person's words", "ts": "2026-11-16T10:05:00Z"}]}
     ```

     The limit of a key is `budget.per-failure` (2 in code) plus the grants of that key. The limit of the run is
     `budget.per-run` (6 in code) plus every grant. A record of another run id counts as empty. Add the file to
     `_RUN_FILES` (`scripts/temper:632-634`) and to the `rm -f` of `cmd_state_clear` (`:1448`).
  2. **The key.** A failure is the check that failed: `gate:<stage>`, `group:<G>`, `task:<N>`, `acceptance`,
     `pipeline`. A failed `integrate` has no key of its own: it spends its repeat under `gate:build`, and that is
     the `scope` of its failure record. The keys and the counts stay in this file to the end: the typed failure
     record of WP23 takes the budget key as its `scope` and moves no count (`docs/plans/one-go/contracts.md`
     section 14).
  3. **What spends.** One table in `scripts/budget.py`, `SPENDS`, read by the CLI and by the flow:

     | Call | Spends when | Key | Kind |
     |---|---|---|---|
     | `state loop <from> <to>` | the gate of `<from>` is FAIL and not skipped | `gate:<from>` | `step back` |
     | `state redo <stage>` | the gate of the stage is FAIL and not skipped | `gate:<stage>` | `run again` |
     | `group fix <G>` with no flag | always (the call needs a failed gate, `scripts/group_fix.py:65-67`) | `group:<G>` | `group fix` |
     | `group reopen <G> ...` | the group's gate is FAIL or the group is parked | `group:<G>` | `tasks again` |
     | `group gate <G> --timeout-s N` | the group's gate is FAIL already | `group:<G>` | `more time` |
     | `plan patch <G> ...` | always | `group:<G>` (a task target: `task:<N>`; Integration: `gate:build`) | `plan patch` |
     | `task retry <N>` | always | `task:<N>` | `task again` |
     | `task test <N> --phase green` | the task holds `env_fault` (`scripts/temper:3129`) | `task:<N>` | `check again` |
     | `acceptance reopen` | always | `acceptance` | `test corrected` |
     | `state set pipeline_round <N>` | always | `pipeline` | `CI fix` |

     Not counted: a task's attempts 1 to 3 (the CLI's own inner bound, `scripts/temper:3161`), `group continue`,
     `state advance`, and every call at a passed gate. The condition is read from the recorded verdict
     (`Run.verdict` and `Run.skip`, `scripts/flow.py:275-294`), never from an argument: that is how the person's
     own change at a passed gate costs nothing and no caller can exempt itself
     (`docs/plans/one-go/evidence/red-safety.md`, M8).
  4. **Where it is enforced.** In one place: the dispatcher at the end of `scripts/temper` (the `case` that holds
     `go)` at `:5036`). For a command whose first two words are in the table, and for no other, it first calls
     `python3 scripts/budget.py spend <words of the call>`. A bash `case` on those words keeps every other command
     from paying a process start. The call prints nothing and exits 0 when the condition of its row does not hold.
     For a call that spends it appends the entry and prints
     `OK: repeat 1 of 2 for group:G1 (3 of 6 in this run)`, or it exits 1 with
     `BLOCKED: <key> was repeated 2 times (limit 2); the person grants more at the question` and writes nothing,
     and the command does not run. No call site in the bash file changes. A call refused later for a reason of its
     own has spent its repeat: that errs toward asking the person sooner, and it keeps one place.
  5. **`state loop`.** `scripts/loop_step.py`: `budget()` (`:20-32`) and the refusal at `:68-71` go;
     `max_iterations` is written from the key's limit so the view keeps its `n/m`. `cmd_state_loop`
     (`scripts/temper:1249-1257`) no longer reads the two keys. The rule "Build to Plan once"
     (`scripts/loop_step.py:24-25`) goes with them: a step back to Plan is the person's only (WP08), and the
     budget bounds it.
  6. **The flow reads the same table.** `Run.loop_budget` (`scripts/flow.py:314-316`) goes. `Run.can_loop`
     (`:318-321`) becomes: true when the gate of `frm` did not fail, else whether `gate:<frm>` has room;
     `feedback.enabled` is no longer read. New `Run.room(key)` returns
     `{"used", "limit", "run_used", "run_limit", "ok"}` from `budget.py`. `round_limit` (`:991`) returns the limit
     of the key `pipeline`.
  7. **Never offer a refused call.** In `Builder.next` (`scripts/flow.py:2331-2346`), after `core_next`: walk the
     options of `ask`, of its `more`, `accept` and `change` questions. Drop every option whose calls hold a call
     that `SPENDS` would refuse now. For an `auto` or `work` action whose calls hold such a call, return the stop
     of the unattended run (the park call, as `scripts/flow.py:1153-1159` does today) or, with nobody armed, the
     question of step 8.
  8. **The question at the limit.** When step 7 dropped an option, the question becomes `run.budget` (kind
     `gate`, header `Temper gate`). Its text starts with the stage's own first sentence, then
     `<what> was repeated <n> times (limit <m>): <the kinds, in order>.` or
     `This run made <n> repeats (limit <m>).`, then `Save the run for later, or allow two more?`. Options, in
     order: `save` with `recommended` true; `grant-more`, label `Allow two more`, move `grant` (add it to `MOVES`,
     `scripts/flow.py:58-59`), calls `temper budget grant --key <key> --reason '{reason}'`, reasons
     `The next try is different` and `I changed something outside the run`; then the options of the stage's
     question that spend nothing (a skip, an accepted finding, a small change), each with `recommended` taken off
     through `set_rec` of WP04. After the grant `next` gives the stage's own question again.
  9. **The word.** `temper budget` prints the record as text; `temper budget grant --key K --reason R` appends a
     grant of 2 and needs a reason. `scripts/budget.py` holds both.
  10. **The mod.** `hooks/temper-mod/core/rules.ts`: `personOnly` (`:476-497`) gains `budget grant`;
      `PERSON_WORDS` (`:371`) gains `budget` and `grant`; the kind `state` of `PROTECTED` (`:109`) and
      `GUARDED_SAMPLES` (`:119-123`) gain `.temper/budget.json`. ADR 0016 gets the row (kind `budget grant`,
      question `run.budget`) and the fixtures get a view with the question (a new state in
      `scripts/selftest/make-view-fixtures.sh`).
  11. **The keys.** New, both with their default in code and as commented lines in the template: `budget.per-failure`
      and `budget.per-run` (WP29 later keeps both in its table of defaults and out of its short template). Gone from
      `templates/temper.config.default` and from `.claude/temper.config`: `fix.max-loops` (template `:48-51`),
      `feedback.enabled` (`:115-116`), `loops.max-per-type` (`:118-119`), `autonomy.budget.max-total-loops` and
      `max-stages` (`:151-153`). A config that still holds one is not an error; WP29 names it once.
  12. **The list of stops.** Add the stop `budget spent` to `scripts/stops.json` with the name of its check.
- **Removed:** `loop_step.budget`, `Run.loop_budget`, the per pair refusal, the five config keys above and their
  text in `reference/status.md`.
- **Documents in the same change:** `docs/decisions/0019-a-run-that-asks-twice.md` (created here: decision 1, one
  budget, what it counts, who grants more); the row in `docs/decisions/0016-the-mod-answer-audit.md`;
  `docs/flow.md` (the budget, the question, and that following the recommendation always ends);
  `reference/orchestrator-patterns.md` (the sentence on one step back to Plan per run); `reference/status.md`;
  `CHANGELOG.md`; `docs/plans/one-go/changed-tests.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green; `bash scripts/selftest/make-view-fixtures.sh` was run for both
    modules and the result is committed.
  - `bun scripts/e2e/run.ts all budget-stop` passes in the three modes and is off the list.
  - `grep -rn 'max-per-type\|max-loops\|max-total-loops\|max-stages\|feedback.enabled' scripts templates` prints
    nothing.
  - `python3 scripts/check_caps.py` exits 0 with the `now` value of `question_sites` moved by the one new site.
- **Traps:**
  - `BLOCKED` with exit 1 is an `error` to `temper go` (`scripts/go.py:108-114`) and so a hand back. It must never
    be reached on a path the flow offers: the two cases of the limit in Tests first are the guard. The marker of
    WP09 is not printed for it: a refusal is no verdict.
  - The limits that only move a recommendation stay: the text compare of `scripts/flow.py:755-756` and `:855-856`,
    the group counters at `:1981-1991`, the `reopened` mark at `:2117`. They choose the option; the budget is the
    bound. Do not delete them here. WP22 and WP23 keep them as well: from WP22 the questions read the reuse store
    first, and WP23 does not rewrite the question logic around its record.
  - `scripts/budget.py` needs the verdict and the skip of a stage. Import the `Run` class of the flow (after WP03,
    `scripts/flow_run.py`) so the skip rule exists once.
  - Tests that state the old behaviour on purpose: every assertion on `BLOCKED: max iterations` and on
    `loops.max-per-type` (find them with `grep -ln` under `scripts/selftest`;
    `docs/plans/one-go/evidence/v-failure-budget.md`, section 6.1, names the case files 1, 2, 8, 12, 17 and 18).
    Each one goes into `docs/plans/one-go/changed-tests.md`.
  - A scripted scenario that repeats one step more than twice by design now meets the limit question. Run
    `bun scripts/e2e/run.ts plain failing-scenario three-groups` before the commit.
  - The new script must not name a path with a folder called `hooks`, `tests`, `mod`, `core` or `ui`, and must not
    call `glob` (`scripts/validate-directory.sh:17-34`).
  - No argument of `budget.py spend` may say who is calling. A flag that marks a repeat as the person's is the way
    round the budget.
- **Size:** M.

## WP14 Design runs only when asked; design concerns are questions in front of the approval

- **Goal:** A default run launches no Design agent at any tier or risk. What Design asked becomes questions that
  Plan writes and the person answers in front of the approval. The plan is written under each first choice, and
  the plan gate fails only for another answer the tasks do not follow yet.
- **Depends on:** WP03, WP04, WP07, WP08 (its flip F2), WP10.
  Extended later by WP11, which is built after this package and calls `Builder.may_run_alone()`.
- **Lane:** `flow core`.
- **Touches:** the flow modules (`Run.has_design`, the plan question, `advance_ok`, `Builder.next`),
  `scripts/decisions.py`, `scripts/answer_ops.py`, `scripts/fresh_review.py`, `scripts/temper` (`gate_design`,
  `gate_plan`, `gate_intent`), `agents/plan.md`, `reference/plan.md`, `reference/design.md`,
  `packs/architecture-depth/rules.md`, `templates/temper.config.default`, `commands/design.md`,
  `docs/decisions/0019-a-run-that-asks-twice.md`, `docs/flow.md`, `scripts/selftest/temper-cases-55.sh` (new),
  `scripts/selftest/temper-cases-8.sh`, `-15.sh` and `-25.sh`, `scripts/selftest/make-view-fixtures.sh`, both
  fixture modules, `scripts/e2e/scenarios.ts`, `scripts/e2e/floor.json`, `scripts/selftest/expected-fail.txt`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-55.sh` (new), names start with `design:`.
     - `design: no tier and no risk adds the stage`: with `complexity` complex, risk H (the helper `riskH`,
       `scripts/selftest/case-helpers.sh:24-30`) and an Intent that asked, `nx` of the passed plan question names
       Build as the next stage.
     - `design: phases.design true adds nothing`.
     - `design: an existing design.md, a run at Design and the person's ask each add it`.
     - `design: the approval offers run-design`, and its calls end in `state advance plan_complete design`.
     - `design: an answer that is the first choice passes the row with a note`.
     - `design: another answer fails the plan gate until tasks.md changes`: the row is
       `tasks agree with decisions`, on the plan gate.
     - `design: the first revision is the CLI's own step, the second failure asks`: after the failing row, `next`
       is `work` with `state redo plan`; with the same answers still unmet it is the failed plan question with
       `Revise the plan` recommended.
     - `design: an answer given after tasks.md exists reaches the Build prompt whatever its prefix`.
     - `design: plan_complete is refused while a Blocking question is open`.
     - `design: at risk H the fresh review applies with no request`, and
       `design: at risk H a plan with no fresh round offers no approve-run`.
     - `design: the Design gate has no decisions row`.
  2. `scripts/e2e/scenarios.ts`: `designRun` starts its Design by the option `run-design`; the floor entry `design`
     keeps its Design launch. Every other entry of `scripts/e2e/floor.json` has no `temper:temper-design`.
  3. From the list: the scenario `design-on-ask` (row `D20`) passes and leaves it here. `vague-run` (row `D04`)
     keeps failing on its dialog count until WP13, the package its row of `docs/plans/one-go/done.md` names, and
     stays on the list until then.
- **Mechanism:**
  1. **`Run.has_design`** (`scripts/flow.py:251-266`): true for a `/temper:temper` run when `design.md` exists
     (`:254-255`), when the run is at Design or has a Design verdict (`:256-257`), or when the state key
     `want_design` is `true`. The rule of `:263-266` goes: `phases.design`, `complexity`, `risk` and `intent_asked`
     no longer decide it. Delete the write of `intent_asked` in `gate_intent` (`scripts/temper:2099-2100`): it has
     no other reader.
  2. **The option.** The passed plan question gets `run-design`, label `Run Design first`, move `approve`, in
     its More list (every variant of `scripts/flow.py:677-689`). Its calls: `state set want_design true`, then the
     calls of `leave_plan` (`:567-571`) with `design` as the next stage. `advance_ok` (`:2510-2535`) reads the
     sequence after the first call ran, so the advance to Design is accepted. The Design question (`:703-741`) is
     then the last question before Build, as today.
  3. **Plan writes the concerns.** `agents/plan.md` (beside the triggers at `:129`) and `reference/plan.md` take
     the rule of `reference/design.md:29-42`: a policy conflict or a product call becomes one line in the Open
     Questions of `intent.md`, `- Blocking: {question} choices: {the answer the plan assumes} | {another} | ...`,
     and the tasks are written under the first choice. A choice marked `(house rule)` must be the first one,
     because the flow shows it first (`scripts/flow.py:375-386`). The flow already asks every open Blocking
     question before the gate question (`:2478-2481`), four to a dialog.
  4. **`scripts/decisions.py`.** `record` (`:40-50`): drop the test for the prefix `Design:` (`:42`); keep the
     test that `tasks.md` exists; store `first: true` when the answer equals the first choice of the question's
     line, compared after the normalising of `scripts/answer_ops.py:38-39`. `scripts/answer_ops.py:147` passes
     the choices. `stale` (`:53-57`) returns only entries with `first` false. `row` (`:60-69`): the detail of a
     pass says how many answers were the first choice; the detail of a fail names `Revise the plan`, not a step
     back. `prompt` (`:93-105`) lists the answers of the store for this spec, not the rows with the prefix.
  5. **The hold moves.** Take the row out of `gate_design` (`scripts/temper:3735-3736`) and add it to `gate_plan`
     (`scripts/temper:3494`), beside the rows it takes from `scripts/gate_rows.py`. In the flow the branch of the failed
     Design question (`scripts/flow.py:733-739`) moves to the failed plan question: its recommended option is
     `Revise the plan` (the call of `:666-669`, reason: the answers), and its skip keeps the first reason
     `The tasks already agree`. Before that question, once: when the only failed rows are this one and the person
     rows (`PERSON_ROWS`, `:2633`), and the state holds no `redo` of Plan for the same answers (the compare of
     `:755-756`), `next` returns `work` with the one call `state redo plan --reason <the answers>`. The budget of
     WP10 counts it under `gate:plan`.
  6. **`advance_ok`** (`scripts/flow.py:2510-2535`): `plan_complete` is refused while `intent.md` holds an open
     Blocking question (`Run.blocking`, `:371-373`). This holds the order with the mod off.
  7. **Risk H.** `scripts/fresh_review.py`, `applies` (`:117-125`): under the mode `ask`, a plan of risk H applies
     with no request; `status` (`:198-210`) passes the risk it already reads at `:205`. The option that starts
     the unattended run (`scripts/flow.py:674-675`, `:726-728`) is offered at risk H only when the fresh round was
     launched for the plan as it is and left no open finding at high. One method, `Builder.may_run_alone()`,
     holds this; WP11 calls it.
  8. **The pack.** `packs/architecture-depth/rules.md:2`: `phases: [plan, design, review]`, so its rules have a
     reader before Build.
- **Removed:** the risk and tier trigger of Design; the state key `intent_asked`; the config key `phases.design`
  (`templates/temper.config.default:111-112`); the row `tasks agree with decisions` of the Design gate.
- **Documents in the same change:** `reference/design.md` and `reference/plan.md:40-41` (when Design runs);
  `agents/plan.md:129`; `commands/design.md` (the door starts Design on the person's ask);
  `docs/decisions/0019-a-run-that-asks-twice.md`, decision 2; `docs/flow.md`; `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green and both fixture modules are regenerated.
  - `bun scripts/e2e/run.ts all design design-on-ask full-run --floor scripts/e2e/floor.json` exits 0.
  - `grep -rn 'intent_asked\|phases.design' scripts templates` prints nothing.
- **Traps:**
  - `scripts/selftest/temper-cases-8.sh:262-267` builds a Design run through `intent_asked`, and
    `scripts/selftest/temper-cases-15.sh:217-221` through risk H; both need `want_design` or a `design.md`.
    `scripts/selftest/temper-cases-25.sh` holds the case of the Design row. Each changed assertion goes into
    `docs/plans/one-go/changed-tests.md`.
  - `Run.seq` (`scripts/flow.py:228-236`) removes Design by `has_design`; a run saved at Design by 9.8.5 keeps it
    through `:256-257`.
  - The More list of the plan question grows by one option. A list of more than four makes a second level
    (`scripts/flow.py:492-498`), the path that broke in pull request 115 (M2 of
    `docs/plans/one-go/evidence/v-pr115.md`). Add a case that every option of the plan question is reachable in
    at most two dialogs.
  - `state set want_design` is no call only the person may cause. It adds a stage and decides nothing; do not
    add it to the mod's tables.
  - A plan of risk H now launches the fresh reviewers by rule: the floor entry of every scenario with `riskH`
    gains those launches. Move the `now` values in the same commit.
- **Size:** M.

## WP11 The approval runs to the commit by default

- **Goal:** The first option of the approval approves the plan and lets the run go on to the commit: a passed
  check moves on as the CLI's own action, a failed check gets at most one counted repair by rule, and every other
  case is a recorded stop that asks. `run.default` chooses the first option. Rules 3 and 4 hold in the CLI.
- **Depends on:** WP04, WP07, WP08, WP09, WP10, WP14, WP18.
- **Lane:** `flow core`.
- **Touches:** the flow modules (`Run.armed`, `Run.policy`, `Run.run_default`, the plan and Design questions,
  `armed_text`, `policy_move`, the Build stops, `commit`, `pr_options`, `Builder.next`, `run_info`, the view),
  `scripts/temper` (`cmd_state_set`, `_state_migrate_legacy`, `cmd_park`, `cmd_override`, `cmd_evidence_accept`,
  `gate_commit`, `cmd_risk`, the dispatcher line of `go`), `scripts/go.py`, `scripts/rule_log.py` (new),
  `scripts/sensitive.py` (new), `scripts/risk.py`, `hooks/temper-mod/core/driver.ts`,
  `hooks/temper-mod/core/commands.ts`, `hooks/temper-mod/core/rules.ts` (the protected list),
  `hooks/temper-mod/register.tsx`, `commands/temper.md`, `templates/temper.config.default`, `.claude/temper.config`,
  `reference/autonomy.md`, `docs/flow.md`, `docs/trust.md`, `docs/mod.md`, `docs/auto-mode.md`,
  `docs/grouped-build.md`, `README.md`, `.claude/CLAUDE.md`, `docs/decisions/0019-a-run-that-asks-twice.md`,
  `scripts/check-known-limits.sh`, `scripts/selftest/temper-cases-52.sh` (new), `scripts/selftest/temper-cases-8.sh`,
  `-14.sh`, `-15.sh`, `-28.sh`, the helper `_unattended` of WP07, `scripts/selftest/make-view-fixtures.sh`, both
  fixture modules, `tests/mod/dialog.test.ts`, `guard.test.ts`, `hardening.test.ts`, `answers.test.ts`,
  `driver.test.ts`, `scripts/e2e/scenarios.ts`, `scripts/e2e/persons.ts`, `scripts/e2e/replay.ts`,
  `scripts/e2e/floor.json`, `scripts/stops.json`, `scripts/selftest/expected-fail.txt`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-52.sh` (new), names start with `run:`.
     - `run: the default approval`: the options of `plan.approve` are, by id, `approve-run` (recommended, move
       `arm`, first call `state set run_mode autonomous`), `ask-every-stage` (first call
       `state set run_mode interactive`), then the third option and More as before.
     - `run: run.default ask puts ask-every-stage first and recommended`, and
       `run: autonomy.enabled false with no run.default means ask`.
     - `run: never-unattended offers no approve-run, and the CLI refuses the call`.
     - `run: the CLI refuses to start the unattended run away from the approval`: at Build, and at Plan with a
       skipped gate.
     - `run: a run whose approving calls stopped half way is not armed`: after the first call of `approve-run`
       alone, `next` is the approval again and `guard.armed` of the view is false.
     - `run: a passed Build, Review and Check move on as auto`, one assertion a stage, and
       `run: a passed group moves on` for a plan of two groups.
     - `run: a blocking finding gets one loop back by rule, the second stops`.
     - `run: a finding below review.block-on starts no loop and is named at the commit question`.
     - `run: a failed Check whose only failed row is the mutation row stops`.
     - `run: no repair by rule when the plan declares a sensitive path`: with a file under `src/auth/` in the
       plan, a failed group check and a blocking finding each stop.
     - `run: a declared sensitive path makes risk H` (`temper risk` prints H and the reason names the path).
     - `run: a stop keeps run_mode`: after `temper park`, `state get run_mode` is `autonomous`, `next` is the
       stage's question, its text says the run goes on by itself, and every option with calls ends in
       `park --end --answer <its id>`.
     - `run: after the answer the same stage goes on as auto` (Build with two groups: no group question follows).
     - `run: a skip, an accepted finding and a step back to Plan end it`: `run_mode` is `interactive` after each,
       with the mod off.
     - `run: a task that failed on the environment is a recorded stop`: `next` is the park call first.
     - `run: the commit question of an unattended run`: ids `commit`, a pull request option, `back` with the call
       `state loop check build`, and under More the stacked option, the small change and `save`.
     - `run: the record steps open the pull request after that option` (the steps of `scripts/flow.py:2209-2214`).
     - `run: a changed sensitive file outside the plan has an exit`: the failed commit question holds
       `check-again` and `confirm`; after `confirm` with a reason the row passes.
     - `run: a run taken up again asks its stage once`: `temper go --taken-up` on an unattended run in Build
       gives the park call, the Build question is asked once, and Review then passes as `auto`.
     - `run: a 9.8.5 run saved armed asks at every stage`.
     - `run: the rule log holds each advance, repair, stop and answer`, and `run: view.json carries rule_log`.
  2. The mod: `tests/mod/dialog.test.ts`, `guard.test.ts`, `hardening.test.ts` and `answers.test.ts` hold the two
     old labels in 18 places; move them to the new labels. `tests/mod/driver.test.ts`: a drive with no request
     passes `--taken-up` on its first `go` and never again; a view whose `run.parked` turns from null to a stage
     gives one toast.
  3. `scripts/e2e/scenarios.ts`: `full-run` and every scenario that tests a later gate's question take the person
     who picks `ask-every-stage` (`stagePerson` of `scripts/e2e/persons.ts`); `default-run` keeps the person who
     takes the recommended option; `armedRun` (`:445-462`, the scenario `armed-run`) is rewritten as the default
     run with one failed group. The scenario `policy-run` of WP08 loses its `autonomy.policy` block and stays, as
     a default run. The scenario `ask-every-stage` (row `D17`) must still pass.
  4. From the list: `D16`, `D18a`, `D18b`, `D18c`, `D19`, `D32a`, `D32d`, `D33a`, `D33b`, `D39d`, `D60c` and the
     scenario `stop-keeps-mode` (`D32c`) pass and leave it here; `D32b` left with WP08. `group-fail-twice` holds
     its assertion `D33c` from here and stays listed until WP16 for row `D06`. The floor of `default-run` drops by
     the group, Build, Review and Check questions: lower `now`.
- **Mechanism:**
  1. **`Run.run_default`.** Reads `run.default`; `to-commit` in code. With the key absent and `autonomy.enabled`
     set to false it is `ask`. An unknown value is `ask`.
  2. **`Run.armed`** (`scripts/flow.py:300-303`): `run_mode` is `autonomous`, the state key `unattended_from`
     names a stage other than the one the run is at, and `parked` is not set. So a run whose approving calls
     stopped half way (a refused digest of WP12, a commit that failed) is not armed at the approval: the question
     is asked again, the mod draws a gate, and no `auto` advance passes the digest check by.
     `Run.policy` (`:296-298`) goes: there is one unattended run, the run to the commit. Its readers take the
     policy branch: `armed_text` (`:1138-1142`), `group_failed` (`:1963`), `core_next` (`:2457-2461`, `:2468`).
     The key `autonomy.policy` is read by nothing.
  3. **The call that starts it.** `cmd_state_set` (`scripts/temper:878-879`, `:912`): `run_mode autonomous` is
     refused when `run.default` is `never-unattended`, and unless the run is at Plan or Design with that stage's
     gate PASS and not skipped. It writes `ran_unattended` as today and `unattended_from` with the stage the run
     is at. `state set` refuses `unattended_from` in the list of `:861-864`. `_state_migrate_legacy` (`:781-789`,
     with one more test in its fast path): a state with `run_mode autonomous` and no `unattended_from` becomes
     `interactive`. A run armed by 9.8.5 was approved for Build alone.
  4. **The approval's first options.** One method builds them for the plan question (`scripts/flow.py:672-680`,
     the three variants) and for the Design question (`:726-730`):
     - `approve-run`: label `Approve and build`, description `armed_text()`, move `arm`, calls
       `state set run_mode autonomous` and then the stage's calls.
     - `ask-every-stage`: label `Ask me at every stage`, description
       `Approve the plan; every later stage asks you.`, move `approve`, calls `state set run_mode interactive`
       and then the stage's calls.
     - `to-commit`: `approve-run` first and recommended, `ask-every-stage` second. `ask`: the other way round.
       `never-unattended`: `ask-every-stage` alone.
     - `approve-run` is left out when the stage was skipped, when Design follows the plan question (the Design
       question is then the approval, and the plan question keeps `:681-689`), and when `may_run_alone()` of WP14
       says no.
     - When the person asked for Design, the Design question is the approval: it carries the approval card (WP15)
       and the digests (`--shown`, WP12) exactly as `plan.approve` does.
     `armed_text` becomes one sentence: the run goes on by itself, a passed check moves on, a failed check gets
     one repair and then asks, the commit asks, nothing is pushed.
  5. **Passed checks move on.** In `core_next` the block of `scripts/flow.py:2441-2472` becomes one: an armed run
     at Design, Build, Fix, Review or Check with a verdict. The Design stops of `:2443-2453` stay. PASS gives the
     `auto` advance of `:2455`; the two lines that turn the run interactive after Build (`:2457-2459`) go. Build
     or Fix FAIL is a stop (`:2464-2466`). Review and Check go to `policy_move`.
  6. **`policy_move`** (`scripts/flow.py:1144-1181`), the closed list:
     - Review: an open finding at a level of `review.block-on` (`Run.open_findings`, `:419-421`; WP08 moved the
       list of `:1167` to it) takes `repair`. A PASS moves on; a finding below the level is carried. Anything
       else stops (`:1172`).
     - Check: PASS moves on. A setup fault, a missing measurement, the acceptance rows (`:1176-1179`), a criterion
       only the person can confirm (WP08), and a Check whose only failed row is `mutation score >= threshold`
       stop. Anything else takes `repair`.
     - `repair(stage, reason)` is the one seam of the repair by rule. It stops when the plan declares a sensitive
       path, when the budget of WP10 already holds a repeat for `gate:<stage>`, or when that key has no room. Else
       it is the `auto` call `state loop <stage> build --reason 'rule: <reason>'` of `:1160-1161`. So a blocking
       finding gets one counted loop back to Build, and a second one asks. WP24 replaces the body of this method
       by the repair in place, and nothing else of this package. Until WP24 nothing resolves a finding by rule:
       `temper evidence resolve` refuses every call since WP18, so a blocking finding ends by the person's accept
       or by this one counted loop back and a second Review.
  7. **The Build stops** keep their code; each calls one method `stop(stage, reason)`, the lifted `park` of
     `scripts/flow.py:1153-1155`. Changes: `env_task` (`:1857-1870`) and `no_groups` (`:1621-1633`) call `stop`
     first in an armed run, so no question waits without a record. `group_failed` (`:1963-1972`) takes the option
     whose `recommended` is true (WP04) only when it has calls, no `answer_question`, no `stop`, a move other than
     `back` (WP08), and the group declares no sensitive file.
  8. **A stop does not end the run.** `cmd_park` (`scripts/temper:4510-4538`): delete the write of `:4520`. The
     mark `parked` makes `Run.armed` false, so the stage asks its own question, and it ends when the run changes
     stage (`scripts/temper:1018`). New form `temper park --end [--answer ID]`: it removes `parked` unless the run
     is at Commit. In `Builder.next` (`scripts/flow.py:2331-2346`), for a question asked while `parked` is set at
     a stage other than Commit: add the sentence `After your answer the run goes on by itself.` to the text; give
     every option that has calls and no `stop` the last call `park --end --answer <its id>`; add to the More list
     `ask-every-stage`, label `Ask me at every stage from here`, calls `state set run_mode interactive` and
     `park --end --answer ask-every-stage`.
  9. **What ends it, in the CLI.** `cmd_override` (`scripts/temper:4399-4424`) and `cmd_evidence_accept`
     (`:1665`) write `run_mode interactive` when it was `autonomous`. `_go_back` to Intent, Plan or Design does
     the same since WP08 (`:1269-1295`). A step back to Build keeps the mode.
  10. **The commit question.** `commit` (`scripts/flow.py:2222-2246`): the park of `:2227-2231` stays. The
      question of `:2242-2244` becomes `with_more` with, first, `commit` (recommended, steps `report_steps()`),
      `Commit and open PR` (a `/temper:temper` run only; calls `state set pr one`, the same steps), and `back`,
      label `Loop back to Build`
      (`state loop check build --reason '{reason}'`, or `check fix` in a fix run; the CLI accepts it from Commit,
      `scripts/temper:1237-1245`). Under More: the stacked option for a plan of two or more groups (`:893-895`),
      the small change `add_adhoc` adds (`:2382-2383`), `save`. Its text names the open findings by level
      (`finding_counts`). `pr_options` (`:891`) and `record_steps` (`:2210`, `:2215`) test `r.armed()`; at this
      question `parked` is set, so the pull request steps run. Hold that with the test of step 1.
  11. **An exit for the commit gate's own row.** `gate_commit` (`scripts/temper:4204-4223`): a changed file under
      a pattern passes when `overrides.json` holds `sensitive-path:<path>`. `cmd_override` (`:4404-4410`) accepts
      that form for a file the run changed. The failed commit question (`scripts/flow.py:2247-2277`) gains
      `confirm`, label `Confirm the change to <path>`, move `commitOverride`, calls
      `override sensitive-path:<path> --reason '{reason}'` and `gate commit`. `override` is already the person's
      (`hooks/temper-mod/core/rules.ts:478`). The sentence of `:2275-2276` goes.
  12. **Sensitive paths.** `scripts/sensitive.py`: `match(path, pattern)`, the matcher of `_glob_touch_match`
      (`scripts/temper:4008`) moved to Python, and `declared(spec, patterns)`. `gate_commit` replaces its loop
      (`scripts/temper:4207-4216`) by one call that reads the changed files on stdin.
      `scripts/risk.py`, `compute` (`:72-93`): a declared file that matches makes the risk H with the reason
      `sensitive path <path>`; `cmd_risk` (`scripts/temper:4625-4631`) passes the patterns of
      `autonomy.park-on-touch`. The approval's text gains
      `The plan touches a sensitive path: <paths>. Nothing there is repaired by rule.` (WP15 moves it to the card.)
  13. **Taken up again.** `scripts/go.py` takes `--taken-up` (the dispatcher line `scripts/temper:5036` passes
      its arguments): before its loop, when `run.armed` of `next` is true, it runs
      `park --verdict PARKED-NEEDS-DECISION --reason 'the run was taken up again'`. `run_info`
      (`scripts/flow.py:438-441`) gains `armed`, the value of `Run.armed`. `commands/temper.md`: the first
      `temper go` after the command was typed with no words carries the flag. `driveSteps`
      (`hooks/temper-mod/core/driver.ts:330-337`): the same on its first turn when `request` is null.
  14. **The rule log.** `scripts/rule_log.py append` adds `{"kind", "stage", "what", "ts"}` to
      `.temper/rule-log.json`. Kinds `advance`, `repair`, `group fix` and `covered` are appended only while the
      state says unattended and not parked, from one line each in `cmd_state_advance`, `cmd_state_loop`,
      `cmd_state_redo`, the `group fix` and `task accept` words. Kinds `stop` (from `cmd_park`), `answer` (from
      `park --end --answer`) and `ended` (step 9) are always appended. The file joins `_RUN_FILES`, the `rm -f`
      of `cmd_state_clear`, and the mod's protected list (`rules.ts:109`, `:119-123`). The view gains `rule_log`
      (`scripts/flow.py:2809-2846`); version 1 stays.
  15. **The notice of a stop.** The `say` of the park action names the stop; the page and the driver show it
      (`driver.ts:353`). The mod toasts once when `run.parked` of the view (`core/runview.ts:44`) turns from null
      to a stage, through `showToast` (`hooks/temper-mod/register.tsx:47-49`): no new host call.
  16. **Texts of the mod.** `hooks/temper-mod/core/commands.ts:29`. The refusal text of `rules.ts:330-332` stays
      true. No table of the guard changes: the call that starts the run stays the call of the option the person
      picked (`rules.ts:493`), and the CLI's own advances are calls of its action
      (`hooks/temper-mod/adapter.ts:231`).
  17. **Tests and fixtures.** `_pol` and `_polg` (`scripts/selftest/temper-cases-28.sh:4-10`, `:33-38`) and the
      helper `_unattended` of WP07 start the run at the approval, then advance. The case "without
      autonomy.policy" (`:27-30`) states the old rule: rewrite it as the run that asks at every stage.
      `scripts/e2e/replay.ts:27`, `:309` and `:349-350` lose the policy switch and select `approve-run` by id.
  18. **The stops an unattended run keeps.** `scripts/stops.json` holds rows 1 to 18 since WP05 and row 19 since
      WP10; add rows 20 to 22 here, each with the name of its check. `D33a` walks every row. A stop is the park
      call, then the question, unless the row says otherwise.

      | # | Where | Trigger | Code at the head | After this package |
      |---|---|---|---|---|
      | 1 | Design | Design changed the plan's tasks | `scripts/flow.py:2443-2447` | stays |
      | 2 | Design | open areas of concern | `:2448-2453` | stays |
      | 3 | Design, Build, Fix | the stage's gate failed | `:2464-2466` | stays |
      | 4 | Build | a manual task | `:1890-1893` | stays |
      | 5 | Build | commits the CLI did not make on a group's branch | `:1806-1809` | stays |
      | 6 | Build | merging again after such commits were settled | `:1795-1798` | stays |
      | 7 | Build | a parked group | `:2074-2077` | stays |
      | 8 | Build | a failed group check whose recommended option needs typing or saves the run | `:1966-1977` | stays; chosen by field, not by label |
      | 9 | Build | a failed group check whose recommended option is a step back | `:1966-1972` | a stop since WP08 |
      | 10 | Build | a task that failed on the environment | `:1857-1870` | now recorded: the park call first |
      | 11 | Build | tasks with no groups | `:1621-1633` | now recorded |
      | 12 | Build | a DRIFT row of a fix pass | `commands/temper.md:180-187` | stays; never answered for the person |
      | 13 | Review | a failed row with no blocking finding; a second blocking finding | `:1172` | stays |
      | 14 | Check | a setup fault, a missing measurement, the acceptance rows | `:1176-1179` | stays |
      | 15 | Check | a criterion only the person can confirm | `:1180` | a stop since WP08 |
      | 16 | Commit | always | `:2227-2231`, `:2242-2244` | stays; more options |
      | 17 | Commit | the commit gate failed | `:2247-2277` | stays; with an exit |
      | 18 | Plan | the plan question after any step back to Plan | `:2441` | stays; the mode is off after it |
      | 19 | any | the budget of WP10 has no room for the next repeat | new | the question `run.budget` |
      | 20 | Build, Review | a failed check in a plan with a sensitive path | new | no repair by rule |
      | 21 | Check | only the mutation row failed | new | stays until WP19 makes the score information; WP19 then takes this row off the list, with a line in decision 3 of `docs/decisions/0019-a-run-that-asks-twice.md` |
      | 22 | any | the person took the run up again | new | the stage's question, once |

      Not stops: a task an earlier task built is taken as done (`scripts/flow.py:1837-1842`); a passed group goes on
      (`:1759-1760`). WP12 adds stop 23: the row `intent unchanged since the approval` failed.
- **Removed:** `Run.policy` and the key `autonomy.policy` (template `:146-148`); the labels
  `Stage by stage (Recommended)` and `Autonomous Build: run Build unattended`; the unattended run of Build alone;
  the write of `run_mode` in `cmd_park`; the dead end sentence of the failed commit question; `_glob_touch_match`.
- **Documents in the same change:** `docs/decisions/0019-a-run-that-asks-twice.md`, decision 3: the closed list of
  what a rule may do and may never do (`docs/plans/one-go/README.md` section 3, decision 2), what starts and what ends
  the unattended run, the table of stops, and that removing a stop needs a decision record. `reference/autonomy.md`
  (nearly whole: `:15-16`, `:18-19`, `:30`, `:35-39`); the header of the autonomy block of the template (`:133-144`)
  and one commented line `run.default`; `docs/flow.md:224-235`; `README.md:30`; `.claude/CLAUDE.md` (the paragraph on
  Autonomous Build and "The person decides each gate"); `docs/grouped-build.md`; `docs/mod.md`; `docs/auto-mode.md`;
  `docs/trust.md` (Temper pushes only after the person chose a pull request option at the commit question);
  `commands/temper.md:117-119`; the sentences `scripts/check-known-limits.sh` holds; `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green; both fixture modules are regenerated.
  - `bun scripts/e2e/run.ts all --floor scripts/e2e/floor.json` exits 0 with the plain and mod traces equal (the
    whole suite: nearly every trace moved).
  - `python3 scripts/check_done.py` shows `D16`, `D18`, `D19`, `D32` and `D60` as ok; `D33a` and `D33b` are off
    the list, and row `D33` is whole only after WP16 and WP21 (`docs/plans/one-go/contracts.md` section 13).
  - `claude plugin test .`, `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` (20 calls) are green.
  - `grep -n 'autonomy.policy\|def policy' scripts/*.py` prints nothing.
- **Traps:**
  - `autonomy.enabled: false` was the shipped default before 9.8.0 (the comment at `scripts/flow.py:301-302`), so
    most upgraded projects hold the line without having chosen it, and they start at `ask`. That is the settled
    decision. WP29's one time question must name this line and what removing it changes.
  - The mod draws any run whose `guard.armed` is true as one that never asks (`hooks/temper-mod/core/view.ts:126`).
    A question in an unattended run is safe only because `parked` makes `armed` false (`scripts/flow.py:2829`).
    Never ask from an armed run without the park call first.
  - The scripted person takes the recommended option (`scripts/e2e/scenarios.ts:119-123`), so every scenario that
    reaches the approval changes its trace. `modGuards` pins the old label (`:153-154`).
  - Labels are matched in `scripts/selftest/temper-cases-8.sh:73`, `:78`, `:94`, `:267`, `-14.sh:47`, `:100`,
    `:105`, `-15.sh:215`, `:221`. Move each to option ids and list it in `docs/plans/one-go/changed-tests.md`.
  - After one long `auto` chain the session without the mod runs the task gate, the group gate, `integrate` and
    the Build gate in one `temper go`. Whether the host cuts such a call at its time limit is not determined;
    write what you see into `PROGRESS.md`.
  - `scripts/caps.json`: the question sites stay as they are; option sites and option labels move. Set each `now`
    to the measure. If a `now` passes its `final`, write the number into `PROGRESS.md`; never raise a `final`.
  - The two new scripts follow the directory rules (`scripts/validate-directory.sh:17-34`).
  - Do not add a state key that turns the run on by itself. `unattended_from` is written only inside the call
    the person's option makes, and `state set` refuses it.
- **Size:** L.

## WP12 The approval is bound to what was shown

- **Goal:** The approving calls carry the digests of the intent and the plan as shown, and the CLI refuses them
  when a file changed. A later change to either fails the Build, Check and commit gates until the person approves
  again. Before the approval a run makes no branch and no commit (rules 1 and 2).
- **Depends on:** WP02, WP04, WP07, WP11.
- **Lane:** `flow core`.
- **Touches:** `scripts/approval.py` (new), `scripts/temper` (`cmd_state_advance`, `cmd_state_set`, `cmd_intent`,
  `gate_build`, `gate_check`, `gate_commit`), the flow modules (`leave_intent`, `leave_plan`, `to_branch`, the
  Intent question, the plan question, `policy_move`), `hooks/temper-mod/core/rules.ts`, `tests/mod/guard.test.ts`,
  `scripts/guards/hold_before_approval.py` (new; kept only as step 9 says), `hooks/hooks.json` (its entry),
  `scripts/selftest/temper-cases-53.sh` (new), `scripts/selftest/make-view-fixtures.sh`, both fixture modules,
  `scripts/e2e/scenarios.ts`, `scripts/caps.json`, `scripts/stops.json`, `scripts/selftest/expected-fail.txt`,
  `docs/decisions/0019-a-run-that-asks-twice.md`, `docs/flow.md`, `docs/trust.md`,
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-53.sh` (new), names start with `bound:`.
     - `bound: the approving options carry both digests`: the last call of `approve-run` and of `ask-every-stage`
       ends in `--shown intent.md=<H1> --shown tasks.md=<H2>`, and the two values equal
       `python3 scripts/approval.py digest` of the files. The same holds for the approving options of the Design
       question in a run where the person asked for Design, and a stale digest is refused there too.
     - `bound: a stale digest is refused and nothing advances`: change a criterion after `next`, run the calls;
       `state advance` exits 1, the stage is still Plan, no branch and no commit were made by it.
     - `bound: the advance records intent_hash beside plan_hash`, also when no `--shown` was given.
     - `bound: state set refuses intent_hash`.
     - `bound: a changed criterion fails the Build, Check and commit gates`, three assertions on the row
       `intent unchanged since the approval`.
     - `bound: the CLI's own lines are exempt`: `intent accept` and `intent complete` leave the row passing.
     - `bound: a changed Test line of tasks.md fails the three gates too`, and the detail names `tasks.md`.
     - `bound: a run with no recorded digest passes the row` (a run saved by 9.8.5).
     - `bound: a step back to Plan and a new approval record the new digests`.
     - `bound: an unattended run stops at the failed row`: `next` is the park call, never a loop back.
     - `bound: leaving Intent makes no branch and no commit`: the calls of the Intent question's first option
       hold neither `spec branch` nor `spec commit`, and `git rev-parse HEAD` and the branch are as before.
     - `bound: the approval makes the branch and one commit`: `spec branch`, then one `spec commit`, then the
       advance; after them `git log` has one more commit, on the run's branch.
     - `bound: with the mod off a project file cannot be committed before the approval`: with the commit hook
       installed, `git commit` of a staged source file at Plan is refused.
     - `bound: with the mod off a project file cannot be written before the approval`: the classic hook of step 9,
       `python3 -I scripts/guards/hold_before_approval.py`, fed the input of a PreToolUse call that writes a source
       file in a project whose run is at Plan and not yet approved, prints one answer with `permissionDecision`
       `deny`. It prints nothing and exits 0 for a write into the run's spec folder, for the same write once the
       run is at Build, with no run active, in a fix run before its approval, for a shell command that writes
       the same file, in a folder that is no Temper project, and for an input it cannot
       read. Feed it as the cases of `block_stdin_wait.py` do (`scripts/selftest/temper-cases-16.sh:307-324`). If
       step 9 drops the hook, this case goes with it.
  2. `tests/mod/guard.test.ts`: a write to the run's `intent.md` is refused at Build, Review, Check and Commit
     and allowed at Intent, Plan and Design.
  3. From the list: `D30b`, `D30c`, `D31a`, `D31b`, `D31c` and the scenario `approval-first` (`D30a`) pass and
     leave it here. Taking `approval-first` off the list arms the shared assert of row `D105` (`worldCheck`,
     `docs/plans/one-go/contracts.md` section 8) in every scenario of `scripts/e2e/accept.ts`,
     `scripts/e2e/slow.ts` and `scripts/e2e/broken.ts`: from this commit a failure of it fails the scenario and
     no longer only reports. Before the package commit run every scenario of the three files that is already
     off the list, and repair in the product what the assert finds.
- **Mechanism:**
  1. **What is hashed.** `scripts/approval.py`:
     - `intent_digest(path)`: SHA 256 of the text of `intent.md` without the lines the CLI writes itself, those
       that start with `**Status:**`, `**Accepted-by:**` or `**Completed:**` (`scripts/temper:4479-4498`). The
       criteria, the scenarios Plan wrote, the out of scope bullet, the assumptions and the Decisions are all
       inside it.
     - `plan_digest(path)`: the digest `_plan_digest` already makes of `tasks.md` (`scripts/temper:2163-2174`):
       each task's files, Depends and Test, each group's Depends, Validate, Interfaces and Context, and the
       Integration line. Move the function here and call it from the bash file and from `Run.plan_core_digest`
       of the flow, so the rule exists once.
     - `digest FILE`, `row STATE SPEC` and `check STATE SPEC name=digest...` are its three commands.
  2. **Where it is stored.** In `.temper/build-state.json`: `intent_hash` beside `plan_hash` and
     `approved_files`, all three written by `state advance plan_complete` (`scripts/temper:1136-1165`) from the
     files as they are at that call, whoever calls. `state set` refuses `intent_hash` in the test of `:843-846`.
     `state advance design_complete` writes both hashes again, as it writes `plan_hash` today (`:1178-1212`): the
     person's answer at the Design question approves what Design changed.
  3. **The arguments.** `state advance plan_complete <next> --shown intent.md=<H1> --shown tasks.md=<H2>`: before
     anything is written (`scripts/temper:1134-1136`) each named file is hashed and compared; a difference is
     `FAIL: intent.md changed since the question was shown; ask again`. `plan_complete` is also refused while
     `intent.md` exists with the status `draft`. `intent accept --digest <H1>` (`cmd_intent`,
     `scripts/temper:4437-4505`) refuses the same way before it writes. The arguments are optional, so a call
     without them still records what it found; with the mod the option's calls are matched word for word, so the
     click is bound to the digests the question carried. When the person asked for Design, the Design question is
     the approval (WP11 step 4) and carries the digests exactly as `plan.approve` does: `leave_design`
     (`scripts/flow.py:1093-1097`) puts the same two `--shown` arguments on `state advance design_complete`, which
     compares and refuses in the same way before it writes.
  4. **The flow.** `leave_plan` (`scripts/flow.py:567-571`) computes both digests in the same `next` call that
     builds the question and puts them on its advance. The card of WP15 is built in that call too, from the same
     reads.
  5. **No branch and no commit before the approval.** `leave_intent` (`scripts/flow.py:557-565`): drop
     `to_branch()` and `spec_commit`; it is `intent accept` and the advance, and the description of the Intent
     question's first option (`:635`) loses the commit. `leave_plan` keeps `to_branch()`
     first and its one `spec commit`, whose message names the intent too. A branch clash
     (`branch_clash`, `:535-545`) is no longer a question of its own (`:621-632` goes). The approval's text names
     it in two sentences: `The branch <name> exists from an earlier run; its last commit is <subject>.` and
     `The approval continues on it.` Its `to_branch()` is then the carried switch of `:547-555`, and its More list
     gains `Build on a new branch <new>` with the one call `state set branch <new>`, after which the approval is
     asked again with no clash. WP16 turns the raw switch into a CLI call.
  6. **The row.** `python3 scripts/approval.py row` prints the row `intent unchanged since the approval`:
     pass when no `intent_hash` is recorded, or when both digests equal the recorded ones; else fail with the file
     that changed. Add it to `gate_build` (`scripts/temper:3613`), `gate_check` (`:3862`) and `gate_commit`
     (`:4033`, after the stage rows of `:4132-4144`, so a spec only commit and a Build checkpoint commit of the
     hook do not compute it). One row name for both files: the cap on gate rows has room for one row, not two.
  7. **The way on from a failed row.** The stage's failed question as it is: a step back to Plan and a new
     approval, restoring the file, or the person's skip. In an unattended run `policy_move` and the Build stop
     treat the row as a stop (stop 23 of `scripts/stops.json`): a rule never changes the intent or the approved
     file set.
  8. **The mod.** `hooks/temper-mod/core/rules.ts`, beside the rule for `tasks.md` (`:245-247`): from Build on a
     write to the run's `intent.md` is refused, with a text that names the step back to Plan. `GUARD_KEYS` (`:335`)
     gains `intent_hash`. The CLI's own writes are not tool writes and stay possible.
  9. **Without the mod: a classic hook holds the write rule (the plan's item 3e).** With the mod loaded its rule
     refuses a project file write before the approval (`stageWriteRuleCore`,
     `hooks/temper-mod/core/rules.ts:238-275`); with no mod loaded nothing does. Add
     `scripts/guards/hold_before_approval.py`, a classic PreToolUse hook of the plugin: one entry in
     `hooks/hooks.json` beside `block_stdin_wait.py` (`hooks/hooks.json:14-24`), with a matcher for the tools that
     write a file, and a clause in the description at `hooks/hooks.json:2`. It answers as that hook does: one JSON
     answer on standard output with `permissionDecision` `deny` and the reason, or nothing. Its one refusal: the
     folder is a Temper project, a feature run (`/temper:temper`) is active, the run is not yet approved (it is at
     Intent, Plan or Design), and the call writes a project file, which is a path outside `.temper/` that the
     mod's rule for that stage would refuse too. It holds only for those three stages of a feature run and only
     for the tools that write a file. A fix run (before `rca.approve` as after it) and a shell command that
     writes a file are outside it, and `docs/trust.md` says so. On every other path it fails open, with no output
     and exit 0: no run, a fix run, a run from Build on, a tool that is not one of the file writers,
     a path under the run's spec folder or under `.temper/`, a state file it cannot read, an input it cannot
     parse, any error of its own. It only ever refuses, and it never changes the input of a tool call.
     The hook is kept only if `claude plugin validate --strict .` and `bash scripts/validate-directory.sh` both
     accept the plugin with it. If either refuses it, drop the hook: delete the script, its entry in
     `hooks/hooks.json` and its case, and write one line under "Found on the way" in
     `docs/plans/one-go/PROGRESS.md`. `docs/trust.md` then says that with the mod off the commit hook alone holds
     rule 1 (the case `D30c`).
- **Removed:** the branch and the commit of the step that leaves Intent; the branch clash question; the twin of
  the plan digest in the flow.
- **Documents in the same change:** `docs/decisions/0019-a-run-that-asks-twice.md`, decision 4 (what the approval
  binds, and that nothing checks the click with the mod off); `docs/flow.md` (the arguments, the row, the state
  key); `docs/trust.md` (with the mod the click is checked against the digests, without it the gates still fail
  on a later change; and, when the hook of step 9 is kept, that it holds the write rule before the approval with
  the mod off, beside `block_stdin_wait.py` at `docs/trust.md:24`, for the stages Intent, Plan and Design of a
  feature run and for the tools that write a file only: a fix run and a shell command are outside it);
  `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green; both fixture modules are regenerated (every approving option's last
    call changed).
  - `claude plugin validate --strict .` and `bash scripts/validate-directory.sh` exit 0 with the hook of step 9 in
    `hooks/hooks.json`, or the hook is gone and `docs/plans/one-go/PROGRESS.md` holds its one line.
  - `bun scripts/e2e/run.ts all approval-first default-run full-run branch-clash branch-clash-carry` passes.
  - `python3 scripts/check_caps.py` exits 0 with `gate_rows` moved by one in `now`.
- **Traps:**
  - The digests in the fixtures are of fixture files: a fixture whose spec files change needs both modules made
    again. A test must compute the digest, never hold one as text.
  - Hundreds of selftest lines call `state advance plan_complete build` bare (the loop of
    `scripts/selftest/temper-cases-28.sh:7` is one). That is why the arguments are optional. Do not make them
    required.
  - The Plan agent may write `intent.md` at Plan (`hooks/temper-mod/core/rules.ts:266`); it writes the scenarios
    there. The digest is taken when the question is built, after the agent returned.
  - With Design asked for, a Design answer changes the Decisions of `intent.md` after `plan_complete`. The row
    is computed at Build, after `design_complete` wrote the hashes again; do not add it to the Design gate.
  - `spec deviations` writes `plan.md` and the report writes the spec folder at Commit: neither is hashed.
  - `scripts/e2e/scenarios.ts` holds `branchClash` and `branchClashCarry`: both answered the old question. They
    become the approval with the clash sentence and the option of step 5.
  - Until WP13 the Intent question still accepts the intent, so `Accepted-by` keeps its text here.
  - `approved-tasks.json` lives in `.temper/evidence` (`scripts/temper:1144`); it is not a ledger and no step
    back may clear it.
  - The hook of step 9 is a script under the directory rules (`scripts/validate-directory.sh:17-34`), and a hook
    fails open except on its one detected violation (`.claude/CLAUDE.md`, known mistakes). It must refuse no path
    that the mod's own rule lets through before Build, or the two carriers hold two rules.
- **Size:** M.

## WP13 The run leaves Intent by rule; the approval accepts the intent

- **Goal:** A passed Intent gate with an `intent.md` and nothing open moves on to Plan as the CLI's own action.
  The person accepts the intent with the plan, in one click. A clean Context Map asks nothing. A clean scripted
  run asks two dialogs.
- **Depends on:** WP05 (the faithful fixtures), WP07, WP11, WP12, WP14.
- **Lane:** `flow core`.
- **Touches:** the flow modules (`intent_by_rule`, `core_next`, `leave_plan`, the plan question, the Intent
  question, `agent`, `Builder.next`, `context_question`), `scripts/plan_ops.py`, `scripts/intent_draft_rows.py`,
  `scripts/temper` (`cmd_intent`), `agents/plan.md`, `agents/intent.md`, `reference/plan.md`,
  `hooks/temper-mod/core/rules.ts` (one text), `scripts/selftest/temper-cases-54.sh` (new),
  `scripts/selftest/temper-cases-11.sh`, `scripts/selftest/make-view-fixtures.sh`, both fixture modules,
  `scripts/e2e/project.ts`, `scripts/e2e/pyjokes.ts`, `scripts/e2e/replay.ts`, `scripts/e2e/scenarios.ts`,
  `scripts/e2e/floor.json`, `scripts/selftest/expected-fail.txt`, `README.md`, `docs/getting-started.md`,
  `docs/ai-native-sdlc.md`, `docs/directory-submission.md`, `reference/autonomy.md`, `docs/flow.md`,
  `docs/decisions/0019-a-run-that-asks-twice.md`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-54.sh` (new), names start with `intent rule:` or `context:`.
     - `intent rule: a passed Intent with nothing open is work, not a question`: `nx` gives `action` equal to
       `work`, no agents, and the one call `state advance intent_complete plan`.
     - Six cases named `intent rule: the question stays when <condition>`, one for each row of the table in
       Mechanism step 1 after the first, each ending in `action` equal to `ask` with the question id
       `intent.accept` or `intent.fail`.
     - `intent rule: after the rule the intent is still a draft`.
     - `intent rule: the approval accepts it`: the calls of `approve-run` hold, in this order,
       `state set run_mode autonomous`, `spec branch`, `intent accept --digest`, one `spec commit` and the advance;
       after them the status is `accepted` and `Accepted-by` reads `the person, at the plan approval`.
     - `intent rule: a failed or skipped plan gate never accepts the intent`: with a draft intent and a failed
       plan gate the skip option holds no `intent accept` and no advance; after the skip `next` asks
       `intent.accept` at Plan, and the plan question after it offers no `approve-run`.
     - `intent rule: the approval offers a step back to Intent`, and after it `run_mode` is `interactive` and the
       Intent question is asked when the Intent agent returned.
     - `intent rule: the Plan agent gets the request`: its prompt holds the `Feature:` line.
     - `intent rule: a draft with scenarios passes the Intent gate once tasks.md exists`.
     - `context: a clean pending map passes the row and asks nothing`.
     - `context: a map with a gap still asks under auto when a line cannot be shown whole` (a flagged line of 95
       characters). This case holds until WP15: the card then shows a line of any length whole, and WP15 rewrites
       the case to the final rule of row `D02b` of `docs/plans/one-go/done.md`.
     - `context: a flagged map that fits is folded`: no `context_check`, the approval's text holds each flagged
       line whole, the approving calls hold `plan review --answer`, and after them `plan.md` holds
       `reviewed: human` and an answer line that says it was given at the approval.
     - `context: always still asks`, and `context: off never asks`.
  2. `scripts/e2e/scenarios.ts`: `contextCheck` (`:343-357`, the scenario `context-check`) keeps its own question
     by a flagged line too long to show; a new variant folds a short one. The long line keeps the question only
     until WP15, which gives the scenario the config line `plan.context-check: always` to keep it.
  3. From the list: the scenarios `two-dialogs` (row `D01`) and `vague-run` (row `D04`) pass and leave it here.
     `default-run` drops to 2 dialogs in the three modes: its `now` equals its `final`.
- **Mechanism:**
  1. **The rule.** `Builder.intent_by_rule()`, as in the prototype
     `docs/plans/one-go/evidence/prototypes/v-one-approval-prototype.diff`. The run leaves Intent with no question
     only when all of these hold; else the Intent question of `scripts/flow.py:621-640` is asked as today.

     | Condition | Read from | Why the question stays otherwise |
     |---|---|---|
     | a `/temper:temper` run | `r.command` | a fix run has no Intent |
     | the gate passed and was not skipped | `r.verdict`, `r.skip` (`scripts/flow.py:275-294`) | a skip is the person's |
     | `intent.md` exists | `r.intent` | the gate passes with no file (`scripts/temper:2039`), the trivial path |
     | no Blocking question is open | `r.blocking()` (`:371-373`) | they are asked first |
     | the run did not come back to Intent | `r.loop_into`, `r.loop_through` (`:323-343`) | the criteria changed after the person saw them |
     | the person typed no note at Intent | `r.notes("intent", "input")` (`:184-189`) | they see what became of it |
     | no door walked Intent | `walked()` (`:1110-1116`) | a door checks and asks (`:600-614`) |

     The prototype also tests the branch clash; WP12 moved that to the approval, so it is not a condition here.
  2. **The move.** In `core_next`, before `q = self.ask(stage)` (`scripts/flow.py:2473`): at Intent, when the
     rule holds, return an action `work` for the stage `intent` with the one call
     `state advance intent_complete plan`, no agents, and a `say` that the person approves the intent with the
     plan. It is `work`, never `auto`:
     `temper go` runs a `work` with calls and no agents by itself (`scripts/go.py:95-97`), and the mod draws any
     `auto` as an armed run (`hooks/temper-mod/core/view.ts:126`). The call writes nothing but the state.
  3. **What the approval's first option runs**, in this order: `state set run_mode autonomous` (WP11);
     the `plan review` call of step 8 when the map is folded; `spec branch` when the project is on another
     branch; `intent accept --digest <H1>` when the status is `draft`; one `spec commit` with the message
     `docs(plan): accept the intent and approve the plan of <slug>`; `state advance plan_complete <next>` with the
     two `--shown` arguments of WP12. `ask-every-stage` runs the same with `run_mode interactive`. The question's
     text and the description of both options say that the click accepts the intent.
  4. **`cmd_intent`** (`scripts/temper:4474`): with `--digest` the `Accepted-by` value is
     `the person, at the plan approval`; without it the text of today stays, for the separate Intent question.
  5. **When the separate Intent question stays.** The rows of step 1, and one more case at Plan: the intent is a
     draft and the plan gate failed or was skipped. Then the failed plan question's skip (`scripts/flow.py:700-701`)
     is `override plan` alone, with no advance; `next` asks `intent.accept` at stage Plan with the one call
     `intent accept --digest <H1>`; the plan question follows, with `ask-every-stage` and no `approve-run`. A skip
     of the plan check never accepts the intent under a question that names neither
     (`docs/plans/one-go/evidence/red-safety.md`, B1).
  6. **The way back.** The passed plan question gains `back`, label `Loop back to Intent`, in its More list:
     `back_opt()` (`scripts/flow.py:588-593`) as the failed question has it (`:699-701`). The step back spends
     nothing at a passed gate (WP10) and turns the mode off (WP08).
  7. **The planner gets the request.** `agent` (`scripts/flow.py:1126-1130`): the `Feature:` line for `plan` as
     well as `intent`.
  8. **The Context check.** `scripts/plan_ops.py`: `asks(m, mode)` is true under `always`, false under `off`, and
     under `auto` true only when the map holds an `ignore` or a `gap`; `gate_row` (`:92-94`) passes a `pending`
     map that is not asked about; `map_json` (`:115-120`) gains `flagged`. In the flow the test of
     `scripts/flow.py:2338` uses the same rule. That is the prototype, and with it a clean map asks nothing.
     The fold: a flagged map under `auto` is not asked on its own when every flagged line can be shown whole,
     which until WP15 means at most three `ignore` and two `gap` lines of at most 90 characters each (the cuts
     of `context_text`, `:2289-2303`). Then the row passes with the detail
     `N flagged line(s), answered at the approval`, the approval's text gains the sentence `context_text` builds,
     the approving options run `plan review --answer 'As planned (at the approval, N flagged lines shown)'`, so
     the record says where the answer was given and how many lines were shown, and `Include what is left out`
     (`:2312-2318`) joins the More list. Else the Context check stays its own question. `context_check` stays in
     `next` and the view as null when not asked. WP15 widens "shown whole" to the card. What holds at the end is
     row `D02b`: the answer is recorded at the approval only when the `context` section of the card holds every
     flagged line; a card whose section is cut records no answer and the Context check is asked; `always` still
     asks.
  9. **The row `no scenarios in draft`** (`scripts/intent_draft_rows.py:169-173`) passes when `tasks.md` is beside
     the intent: Plan wrote those scenarios. Without this a draft fails its gate on the two paths that compute
     it again, a door that walks Intent and a step back to it.
  10. **The briefs.** `agents/plan.md:91-92`: drop the instruction to add the `Blocking: Context check` line to
      `intent.md`. `agents/plan.md` where it says a human accepted the intent, and `agents/intent.md:47-49`: the
      wording.
  11. **The mod's text.** `hooks/temper-mod/core/rules.ts:259-261`: the refusal at Intent names the approval, not
      "Continue to Plan". No rule changes: `state advance intent_complete` stays the person's (`:491`) and is let
      through as a call of the CLI's own action (`hooks/temper-mod/adapter.ts:231`).
- **Removed:** the Intent question on the clean path; `Run.context_choices` (`scripts/flow.py:392-396`) and the
  Blocking line it read; the options `Something else` and `Carry forward` of the folded case.
- **Documents in the same change:** every sentence that says the intent is approved first or at its own gate:
  `README.md:30`, `docs/getting-started.md`, `docs/ai-native-sdlc.md`, `docs/directory-submission.md`,
  `reference/autonomy.md:18-19`. The promise reads: "You approve the intent and the plan in one question before
  any code is written, and you approve the commit." `docs/flow.md` (the rule, the conditions, the fold);
  `docs/decisions/0019-a-run-that-asks-twice.md`, decision 5; `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh full` is green (this package ends the first half of the phase).
  - `bun scripts/e2e/run.ts all two-dialogs vague-run default-run --floor scripts/e2e/floor.json` exits 0 and
    `default-run` shows 2 dialogs in plain, mod and driver mode.
  - `python3 scripts/check_done.py` shows `D01` and `D04` as ok.
- **Traps:**
  - WP05 made the scripted Plan agent add the `Blocking: Context check` line, as the brief said then. Remove it
    from `scripts/e2e/project.ts`, `scripts/e2e/pyjokes.ts` and `scripts/e2e/replay.ts` in this commit. Once the
    check is folded nothing answers that line, and the row `blocking question open` reads it in a draft
    (`scripts/gate_rows.py:34-40`) whenever the Intent gate is computed again.
  - `plan review` stays the person's (`hooks/temper-mod/core/rules.ts:481`). In the fold it runs only as a call
    of the option the person picked. Never run it from an `auto` or `work` action.
  - A map that Plan wrote with no `ignore` and no `gap` is Plan's own claim. Do not write `reviewed: human` for
    it: the line stays `pending` and the row's detail says `not asked: no flagged line`.
  - `scripts/selftest/temper-cases-11.sh` holds the Context Map cases and expects a `pending` map to fail under
    `auto`. List each changed assertion.
  - The Intent agent returns the word TRIVIAL with no `intent.md` (`commands/temper.md:176-179`). The rule needs
    the file, so that path still reaches the page as today; WP17 turns it into a recorded verdict.
  - A request that Intent asks about fails its gate on the open Blocking questions; the carrier asks them, runs
    `gate intent`, and the rule then moves on. Answers are not notes: do not let them trip the note condition.
  - The intent of the selftest fixture is `accepted` (`scripts/selftest/test-temper.sh:82`). The cases of this
    package that need a draft set the status first.
  - Every test that builds `fresh; gpass intent` to get a question now gets the move to Plan. The `ids:` case of
    `scripts/selftest/temper-cases-40.sh` that runs `temper go` there is one: give each such test a state that
    still asks (a note at Intent, or the plan question) and list it in `docs/plans/one-go/changed-tests.md`.
  - Fixtures: nearly every view of the Intent and Plan stages changes; run
    `bash scripts/selftest/make-view-fixtures.sh` for both modules.
- **Size:** M.
