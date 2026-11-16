# Phase 2: the definition of done

This file holds the specs of work packages WP04, WP05, WP06 and WP07.
They build the ids, the counters, the two scripted projects and the checks every later package is judged by.
The brief is `docs/plans/one-go/README.md`. Every shared name below is the one `docs/plans/one-go/contracts.md`
fixes. Each package ends as section 4 of the brief says: the package commit, then the small progress commit, in
one push. A package that names `CHANGELOG.md` writes its lines under the one heading of the result,
`## v9.8.5: a run that asks twice`, and adds no version heading.

## WP04 Ids in the protocol

- **Goal:** Every question and every option that `temper next --json`, `temper go` and `.temper/view.json` carry has
  a stable `id`, a question has a `kind`, an option says when it is `recommended`, and a registry names for every
  question the decision it asks for.
  The policy, `scripts/go.py`, the mod's driver and the scripted persons select by these fields and never by label
  text. No label changes, the view stays version 1, and the output is byte equal apart from the added keys.
- **Depends on:** WP01 (the fixtures one view per line give the room), WP03 (the flow split).
- **Lane:** `flow core`.
- **Touches:** `scripts/flow.py` and the `scripts/flow_*.py` modules WP03 made of it, `scripts/go.py`,
  `hooks/temper-mod/core/runview.ts`, `hooks/temper-mod/core/driver.ts`, `hooks/temper-mod/core/decisions.ts`,
  `scripts/e2e/loop.ts`, `scripts/e2e/scenarios.ts`, `scripts/e2e/replay.ts`, `scripts/selftest/view-fixtures.ts`,
  `scripts/selftest/view-fixtures-2.ts`, `scripts/selftest/temper-cases-40.sh` (new), `tests/mod/ids.test.ts` (new),
  `docs/flow.md`, `CHANGELOG.md`, `docs/plans/one-go/contracts.md` (section 5: one line for each id step 3 adds).
- **Tests first:**
  1. `scripts/selftest/temper-cases-40.sh` (new; WP01 made the runner find case files, so no list is edited).
     Every case name starts with `ids:`. The cases read both generated
     fixture modules with python, as `scripts/selftest/temper-cases-8.sh:459-460` does, and walk `ask`, `ask.more`,
     `ask.accept`, `context_check`, `restart`, each entry of `blocking_asks`, and each `reason_question` and
     `answer_question` of an option.
     - `ids: every question has an id of the registry and a kind, and the registry holds its decision`.
     - `ids: option ids are unique in a question and come from the closed list`.
     - `ids: recommended is true exactly where the label ends in the suffix, and absent elsewhere`.
     - `ids: at most one recommended option in a question and its More question together`. If a fixture view
       breaks this at the head, record the view in `PROGRESS.md` as a found defect and assert the views that hold.
     - `ids: the question that goes to the dialog has no new key`: the keys of `ask.question` are `header`,
       `question`, `multiSelect`, `options`, and each of its options has `label` and `description` only.
     - `ids: temper go passes id, kind, move and recommended` (state: `fresh; gpass intent`, then `"$TEMPER" go`
       read with `_ev` of `scripts/selftest/case-helpers.sh:4-15`).
     - `ids: only opt() and set_rec() know the suffix`: a `grep -cE` over the flow modules for
       `endswith\(.\(Recommended\)`, `replace\(. \(Recommended\)` and `\["label"\] *\+=` prints 0 outside those two
       functions (the style of `scripts/selftest/temper-cases-28.sh:26`).
     - `ids: an unknown question id and an unknown option id are refused` (python imports the module and expects
       `ValueError`, as `scripts/selftest/temper-cases-22.sh:44` imports `preflight`).
     - `ids: every call of question(), with_more() and opt() passes qid or oid` (python `ast` over the flow modules).
  2. `tests/mod/ids.test.ts` (new, the style of `tests/mod/answers.test.ts:1-30`):
     - `parseRunView` gives each option of the view `plan-pass` its `id`, `kind` and `recommended`; a view with none
       of the keys (a view of the base, `10e965a`) still parses, with `id: null` and `recommended: false`.
     - The driver opens the More question by `kind: 'more'` when the option's label is changed in a doctored view;
       it goes back on `kind: 'cancel'` at a reason question; it runs the `carry` call on `kind: 'carry'`.
     - `answersIn` still counts nothing for a reworded question whose ids are right: an id is a lookup, never what
       makes an answer count (`hooks/temper-mod/core/answers.ts:33, 70-76`; ADR 0016 decision 1).
  3. `scripts/e2e/scenarios.ts`: no new scenario. `bun scripts/e2e/run.ts all full-run fix armed-run` stays green
     with the plain and mod traces equal after the person and the trace move to the fields (step 10).
- **Mechanism:** line numbers are of `scripts/flow.py` at the head; after WP03 find each function by name.
  1. **The registry.** Beside `MOVES` (`:58-59`), in the base module of the flow (`scripts/flow_base.py` after
     WP03). Not a module of its own: `blocking_asks` lives in the base module and needs it, and WP03's case lets
     the base module import no other flow module.
     `QUESTIONS` maps a question id to `{"kind", "decision"}`; `QUESTION_KINDS` is `gate`, `group`, `resume`,
     `drift`, `blocking`, `context`, `reason`, `name`; `OPTION_IDS` is the closed set of option ids; `OPTION_KINDS`
     is `more`, `accept`, `cancel`, `carry`, `type`. `decision` is one plain sentence that says what only the
     person can decide there (the plan, section 9: every question names the decision it asks for).
  2. **Question ids.** The rule is `<stage or scope>.<state>`. Sites that share one decision share one id. Fixed
     names, because `docs/plans/one-go/done.md` and WP07 select by them: `intent.accept` (`:634`), `intent.fail`
     (`:638`), `rca.approve` (`:617`), `plan.approve` (every variant of `:673-689`), `plan.fail` (`:697-700`),
     `design.pass` (`:729`), `design.fail` (`:738-740`), `build.pass` and `fix.pass` (`:751`), `build.fail` and
     `fix.fail` (`:762-764`), `review.pass` (`:786`), `review.fail` (`:805`), `check.pass` (`:821`), `check.fail`
     (`:834-874`),
     `commit.confirm` (`:2244`), `commit.fail` (`:2246-2275`), `group.pass` (`:1943`), `group.fail`
     (`group_failed`, `:1957`), `group.parked` (`parked`, `:2067`), `task.covered` (`:1832`), `task.manual`
     (`:1872`), `task.env` (`:1857-1870`), `build.foreign` (`:1772`), `plan.context` (`context_question`,
     `:2306`), `run.restart` (`restart`, `:2279`), `intent.blocking` (`blocking_asks`, `:2478`), `scope.drift`
     (`drift_info`, `:2850`). Name the rest by the rule. A follow up question takes its parent's id and a suffix:
     `.more`, `.accept`, `.reason`, `.name`. The closed list is section 5 of `docs/plans/one-go/contracts.md`;
     later packages add `run.budget`, `base.red`, `plan.command`, `repair.stop` and `config.tidy` to the registry
     when they add the question.
  3. **Option ids.** One id per meaning, kept when the label changes. Fixed names: `approve-run` for the option
     whose move is `arm` (`:674-675, 726-728`); `ask-every-stage` for the plain approval of the plan (`:673`,
     `:682-688`); `continue` for a passed stage's first option; `commit`; `back`; `redo`; `override`; `save`
     (`save()`, `:483-485`); `more`; `accept-finding`; `small-change`; `confirm`; `as-planned`; `carry`; `cancel`;
     `type`; `add-setup` (`:1197`); `start-over`. Later packages add `it-is-the-code` and `check-again` (WP08),
     `grant-more` (WP10), `run-design` (WP14), `go-on-anyway` (WP20), `more-time` (WP21), `run-anyway` (WP22),
     `correct-test` (WP23), `repair-again` and `revert-repair` (WP24), `add-file` (WP25), `tidy-config` and
     `keep-config` (WP29) to the same list when they add the option; the table is section 5 of
     `docs/plans/one-go/contracts.md`. The head has 71 distinct labels and far fewer fixed names: the rest get
     their ids by the rule. Every id this package gives to a question or an option of the head that the tables
     of `contracts.md` section 5 do not name is added there, one line each, in this commit: the persons of WP07
     and the later packages read that page.
  4. **`opt()` (`:459-481`).** New keyword `oid`, required, refused when it is not in `OPTION_IDS`, in the way an
     unknown move is refused at `:460-461`. `opt()` sets `recommended` from the label it is given (true when the
     label ends in the suffix) and takes an optional `kind`. Call sites keep their label text. The options of the
     reason question and of the name question, built by hand at `:463-480`, get `kind: 'cancel'` and `kind: 'type'`.
  5. **`set_rec(o, on)`.** One new helper that adds or removes the suffix and sets the field. The six sites that
     edit a label after `opt()` call it: `:761`, `:846`, `:861`, `:2009`, `:2031`, `:2109`. The readers use the
     field: `:867`, `:869`, `:872`, `:1967`, `:1972`, `:2035`. Chosen over a `rec=` argument at every call: it
     changes 12 sites, not 60, and the labels cannot drift from the field.
  6. **`question()` (`:492-507`) and `with_more()` (`:509-516`).** New keyword `qid`, required, refused when unknown.
     The result gets `id` and `kind` beside `stage`, `step` and `run_id` (`:501-502`); the decision stays in the
     registry. An option carries `id` always, `recommended` only when true and `kind` only when set, to keep the
     fixture modules small. The More question
     both functions build (`:493-498`, `:513-515`) gets `<qid>.more`, and its opening option gets `oid='more'`,
     `kind='more'`. `question()` raises `ValueError` when two options share an id.
  7. **Questions built by hand.** `restart()` (`:2279-2285`), `blocking_asks()` (`:2478-2505`: the choices get
     `choice-1` to `choice-3`, Carry forward gets `carry` with `kind: 'carry'`), `context_question()`
     (`:2306-2330`), `drift_info()` (`:2850`), and the `accept` question of Review.
  8. **`scripts/go.py`.** `SLIM_KEYS` (`:41`) gains `id`, `kind`, `move`, `recommended`; `slim()` (`:44-55`) copies
     the question's `id` and `kind`. The docstring at `:45-47` says the move was dropped to save characters; a few
     short keys an option are the price of selecting by field.
  9. **The mod.** `runview.ts`: `Option` (`:11-23`) gains `id: string | null`, `kind: string | null`,
     `recommended: boolean`; `Ask` (`:25`) gains `id` and `kind`; read them in `option()` (`:111-123`), `ask()`
     (`:125-130`) and `contextCheck()` (`:132-137`). `VIEW_VERSION` stays 1 (`:5`, `:150`). `driver.ts`: the types
     at `:8-20`; `:290` selects `kind === 'more'`; `:291` selects `kind === 'accept'`; the `'Cancel'` compares at
     `:301` and `:311` and the `'Carry forward'` compare at `:383` look the picked label up in the question's
     options and test its kind. `optionOf` (`:226-228`) keeps matching by label, because the dialog returns the
     label. `decisions.ts:11-13`: the gate decision gains an optional `questionId` and `optionId`, written where the
     decision is made from an answer; nothing reads them to decide.
  10. **The scripted persons and traces.** `scripts/e2e/scenarios.ts:119-123`: `recommended` takes the option
      whose `recommended` is true, else the first. `scripts/e2e/loop.ts:94, 169`: the trace line is
      `ask:<stage>:<question id>:<option ids joined by |>`; `:198` opens More by kind. `scripts/e2e/replay.ts:343`
      reads the field when present and falls back to the label, because the same script drives 9.8.4 and the
      base through `TEMPER_E2E_ROOT` (`scripts/e2e/world.ts:17`, `scripts/e2e/ab-replay.sh`).
  11. **Fixtures.** Run `bash scripts/selftest/make-view-fixtures.sh` and the same with `extra`; commit both files.
- **Removed:** every read of the suffix text outside `opt()` and `set_rec()`; label compares in the driver for More,
  Accept, Cancel and Carry forward; the label rule of the scripted person.
- **Documents in the same change:** `docs/flow.md` (the field tables of `next` and of the view, and one sentence:
  an id is a lookup, the answer still counts only on the exact header, question, label, run and step);
  `CHANGELOG.md`; one line in `docs/plans/one-go/PROGRESS.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green.
  - A throwaway script removes `id`, `kind` and `recommended` from question and option objects only (the head
    already has `id` on groups, tasks and findings and `kind` in two views) and the result is byte equal to the
    modules of the commit before. This is the proof that no label, call or order moved.
  - `claude plugin test .` is green, `tsc -p tsconfig.mod.json` is clean, `bash scripts/check-mod-calls.sh` still
    prints 20 calls.
  - `bun scripts/e2e/run.ts all full-run fix armed-run` passes with the plain and mod traces equal.
  - `wc -c` of each fixture module is under the 200,000 bytes that WP01's case holds them to.
- **Traps:**
  - The new keys go beside `question`, never inside it. `ask.question` goes to the question dialog word for word
    (`scripts/e2e/world.ts:108-110`) and the mod's session guard compares it; an unknown key there can be refused
    by the host.
  - The larger fixture module holds 185 options with a move and about 67 questions (`grep -c '"move"'` and
    `grep -c '"run_id"'` less one a view). The ids add about 10 KB to the 187,069 bytes WP01 leaves, and WP01's
    case fails a module of 200,000 bytes. If the module passes that line, move views to the second module through
    the `extra` set of `scripts/selftest/make-view-fixtures.sh:325-329`; never raise the line.
  - A `ValueError` for a duplicate or unknown id is raised in a person's run too. The fixtures reach 34 views, not
    every site: before the commit, run `bash scripts/selftest/run-selftest.sh` once with an environment variable
    that makes `question()` append each id it builds to a file, and add an `nx` case for each registry id the file
    lacks. Remove the variable after.
  - 149 selftest lines and 126 mod test lines match label text. They do not move here: no label changes. Move a
    test to ids only when a later package changes its question.
  - `scripts/e2e/replay.ts` must keep working against a plugin folder with no ids.
  - A bash case and a Python script must not name a path with a folder named `hooks`, `tests`, `mod`, `core` or
    `ui` (directory rules 9 and 10, `scripts/validate-directory.sh:17-27`). Everything about the mod's files is a
    test in `tests/mod`.
  - `bench/person.mjs` chooses by the `move` of the view (`bench/run.mjs:77-88`). Leave it.
- **Size:** M.

## WP05 The floor, the caps, faithful fixtures and the run summary

- **Goal:** One file holds, for each scripted scenario and mode, the dialogs, the launches by agent type, the steps
  the CLI took by itself, the steps back, the hand backs and the suite runs of a run with no model call, and CI
  compares it exactly. A second file holds the growth caps. A third lists the stops that must stay. The fixtures
  write what a real planner writes. A finished run leaves one line in the project.
- **Depends on:** WP01, WP04.
- **Lane:** `flow core` (it edits `scripts/temper`, the flow's view writer and the fixtures of the scenarios).
- **Touches:** `scripts/e2e/world.ts`, `scripts/e2e/loop.ts`, `scripts/e2e/run.ts`, `scripts/e2e/project.ts`,
  `scripts/e2e/pyjokes.ts`, `scripts/e2e/replay.ts`, `scripts/e2e/scenarios.ts`, `scripts/e2e/floor.json` (new),
  `scripts/check_floor.py` (new), `scripts/caps.json` (new), `scripts/check_caps.py` (new), `scripts/stops.json`
  (new), `scripts/run_summary.py` (new), `scripts/temper` (two lines), `scripts/flow_view.py` (`write_view`),
  `scripts/quality-check.sh`, `scripts/verify.sh`, `.github/workflows/quality.yml`, `bench/run.mjs`,
  `bench/agentlog.py` (new), `bench/scorecard.py` (new), `bench/report.py`, `bench/README.md`,
  `scripts/selftest/temper-cases-41.sh` (new), `scripts/selftest/temper-cases-32.sh` (one case of WP02 goes,
  step 8), `scripts/e2e/ab-replay.sh` (step 7), `docs/flow.md`, `.claude/CLAUDE.md`, `CHANGELOG.md`.
- **Tests first:**
  1. `scripts/selftest/temper-cases-41.sh` (new), names start with `floor:`, `caps:` or `summary:`.
     - `caps: every cap is measured and equals its now value` (`python3 scripts/check_caps.py` exits 0).
     - `caps: a now value one above the measure fails, and one below fails` (copy the file, change one number).
     - `caps: a now value above its final fails only in the final mode`.
     - `caps: a final value above its first committed value fails` (in a throwaway git folder with two commits:
       a raise is refused also after it was committed; a key with no earlier commit is exempt).
     - `floor: a final value above its first committed value fails` (the same rule in `scripts/check_floor.py`).
     - `floor: a count that differs from the file fails with the scenario, the mode and both numbers`
       (`python3 scripts/check_floor.py` on a made up counts file).
     - `floor: the base column of the replay equals replay_base` (`python3 scripts/check_floor.py --replay-base`
       on a made up line: equal passes, one number moved fails with its name).
     - `floor: every check that scripts/stops.json names exists` (the name is found by `grep -rF` in
       `scripts/selftest` or `scripts/e2e`; a stop with no check yet is allowed here and closed by WP07).
     - `summary: state clear appends one line to .temper/runs.jsonl and the line survives state init`.
     - `summary: the line counts the questions the CLI asked once each` (`next` run twice at one step counts one).
     - `summary: the steps back of the run are in the line` (state: `state loop review build`, then `state clear`).
     - `summary: the file keeps the last 200 lines`.
  2. `scripts/e2e/scenarios.ts`, scenario `default-run`, modes plain, mod and driver: the project of `full-run`
     with the Context Map as `agents/plan.md:89-94` tells a planner to write it, and the person who takes the
     recommended option everywhere. It asserts nothing about numbers itself: the floor holds them.
  3. `bun scripts/e2e/run.ts all default-run full-run fix --floor scripts/e2e/floor.json` exits 0; with one number
     of the file changed it exits 1.
- **Mechanism:**
  1. **Counters.** `World` gets `counts` with the fields `dialogs`, `by_stage`, `by_kind`, `launches`, `auto`,
     `back`, `handbacks` and `suite_runs`.
     Count a dialog in `guardAsk` (`scripts/e2e/world.ts:108-110`) and a launch in `guardAgent`
     (`:105-107`): both are called by the plain loop (`scripts/e2e/loop.ts:179, 191, 201`) and by the driver's port
     (`:117, 123`). Count `auto` at `loop.ts:173` and from the `ran` list of `temper go` (`:109`); count a step back
     when the applied option's `move` is `back` (`applyOption`, `:44-55`); count a hand back at `:150` when the end
     is not `done`. The prototype is `docs/plans/one-go/evidence/prototypes/w2-floor-counts-and-default-run.diff`
     (5 lines of counters and the `default-run` scenario, run at the head in three modes).
  2. **Blocking dialogs in the plain loop.** The driver asks the Blocking questions four to a dialog
     (`hooks/temper-mod/core/driver.ts:372-390`); `commands/temper.md:163-170` tells the model the same; the plain
     loop does not ask them at all. Add the same step to `loop()` so a vague run counts the same in every mode.
  3. **Suite runs.** The whole suite is named three times: as `check.commands.test` and inside
     `check.commands.coverage` (`scripts/e2e/scenarios.ts:30`), and as the Integration line of `TASKS_MD`
     (`scripts/e2e/project.ts:5`). Put the command behind one script of the fixture project that appends a line
     to the file named by the environment variable `TEMPER_E2E_COUNT` and then runs the suite; `suite_runs` is the
     line count. The variable passes through the CLI's runner as `MOCK_LOG` does in
     `scripts/e2e/replay.ts:288-290`.
  4. **Faithful fixtures.** `scripts/e2e/project.ts:4`, `scripts/e2e/pyjokes.ts:119` and
     `scripts/e2e/replay.ts:132` write `- reviewed: auto`, which no brief tells a planner to write. Write
     `- reviewed: pending`, and have the scripted Plan agent add the Blocking line of `agents/plan.md:91-92` to
     `intent.md`, as `scripts/e2e/scenarios.ts:343-344` already does for one scenario. Every scenario then meets
     the Context check; the `recommended` person answers it. `default-run` and `full-run` are then the same run
     until WP11 moves `full-run` to the person who asks at every stage; keep both entries of the floor.
  5. **`scripts/e2e/run.ts`.** Two flags: `--floor FILE` compares each finished scenario's counts with the file and
     fails on any difference; `--write-floor FILE` writes the `now` values. A scenario with no entry fails.
     `--write-floor` is refused together with `--shard`: the file is written by one process. Both flags may stand
     anywhere after the mode, as WP01 made `run.ts` read them.
  6. **`scripts/e2e/floor.json`.** The shape:

     ```json
     { "version": 1,
       "scenarios": {
         "default-run": {
           "plain":  { "now":   { "dialogs": 8, "launches": { "temper:temper-intent": 1, "temper:temper-plan": 1,
                                  "temper:temper-acceptance": 1, "temper:temper-build-task": 2,
                                  "temper:temper-review": 1 }, "auto": 0, "back": 0, "suite_runs": 0 },
                       "final": { "dialogs": 2, "back": 0,
                                  "launches": { "temper:temper-intent": 1, "temper:temper-plan": 1,
                                  "temper:temper-acceptance": 1, "temper:temper-build-task": 2,
                                  "temper:temper-review": 1 } } },
           "driver": { "now": { "dialogs": 8, "handbacks": 0 }, "final": { "dialogs": 2, "handbacks": 0 } } } },
       "replay": { "now": { "questions": 8, "agent_launch_total": 7, "loops_recommended": 1, "manual_repairs": 0,
                            "setup_clicks": 1, "agent_minutes_estimate": 92, "shipped": true,
                            "defect_in_commit": false },
                   "final": { "questions": 3, "agent_launch_total": 7,
                              "agent_launches": { "temper:temper-plan": 1 }, "loops_recommended": 0,
                              "manual_repairs": 0, "setup_clicks": 1, "agent_minutes_estimate": 92,
                              "shipped": true, "defect_in_commit": false,
                              "bad_validate_line_in_plan_at_end": false } },
       "replay_base": { "questions": 8, "agent_launch_total": 7, "loops_recommended": 1, "manual_repairs": 0,
                        "setup_clicks": 1, "agent_minutes_estimate": 92, "shipped": true,
                        "defect_in_commit": false } }
     ```

     `now` is compared exactly, so the file never drifts above or below the truth. `final` is the number of
     `docs/plans/one-go/done.md`; `bash scripts/verify.sh final` fails while a `now` value is above its `final`
     (in `launches`, a type that `final` does not name stands at 0; `launch_total` is the sum).
     A package that lowers a count lowers `now` in the same commit. Nothing raises a `final`:
     `scripts/check_floor.py` refuses a `final` above its value in the commit that first added the key, as
     `scripts/check_caps.py` does (step 8).
     The `replay` entry holds every key row `D58` of `done.md` names: besides the counts, `shipped`,
     `defect_in_commit`, `bad_validate_line_in_plan_at_end` and `agent_launches`, the launches by agent type, in
     `now` (read off the first run) and in `final`. A count of `final` is an upper bound; `true` and `false` must
     be equal. The lists the replay prints (`loops_recommended`, `manual_repairs`) are held as their lengths.
     `replay_base` holds the same keys for the CLI of `10e965a`, read off `bash scripts/e2e/ab-replay.sh 10e965a`
     after step 4. It has no `now` and no `final`, it is compared exactly, and no package changes it.
     Measured at the head in a clone, to check the first write against: `default-run` 8 dialogs and 6 launches in
     all three modes; `full-run` 7 and 6 (before step 4); `design` 8 and 7; `armed-run` 4, 6, and 3 steps by the
     CLI; `fix` 4 dialogs and 3 launches in driver mode. In plain mode `fix` counts 2 launches, because the scenario
     calls the root cause agent by hand (`scripts/e2e/scenarios.ts:640`): route that call through a helper that
     counts. Read every other `now` value off the first run.
  7. **The replay in the gate.** `bash scripts/verify.sh full` runs `bun scripts/e2e/replay.ts final`, takes the
     last line, and `python3 scripts/check_floor.py --replay` compares it with the `replay` entry. The values
     above are those of `docs/evidence/ab-replay-9.8.5.md:26-35`, the page as the base has it: its column
     "9.8.5" is the base.
     The same step of `full` runs `bash scripts/e2e/ab-replay.sh 10e965a` (about 55 seconds). The script gets
     one check: when its base is `10e965a`, it hands the JSON line of its base run to
     `python3 scripts/check_floor.py --replay-base`, which compares it with the entry `replay_base` and fails the
     script on a difference. The harness of this tree must still drive the CLI of the base to the same numbers: from
     WP08 on a package can move them only by breaking what the two sides share (`scripts/e2e/loop.ts`, the
     persons), and `full` then says so at the next phase gate and not at WP32.
  8. **`scripts/caps.json` and `scripts/check_caps.py`.** Python 3 and git only, under a second, called from
     `scripts/quality-check.sh` as one more block before the summary (`:158`). Each key has `now` and `final`.
     The keys and how each is measured (the measure is code in the script, named in a comment beside the key):

     | Key | Measure | Value at the head |
     |---|---|---|
     | `question_sites` | calls of `self.question(` and `self.with_more(` in the flow modules | 53 (41 and 12) |
     | `option_sites` | calls of `self.opt(` in the flow modules | 89 |
     | `option_labels` | distinct first arguments of those calls | 71 |
     | `question_ids` | entries of `QUESTIONS` in the base module of the flow, `scripts/flow_base.py` | set by WP04 |
     | `gate_rows` | distinct `_req "<name>"` names of the CLI, distinct `row("<name>"` names of `scripts/*.py` and `name = "` lines of `gate_rows.py`, added up | 55 (32, 19 and 4) |
     | `agent_briefs` | files of `agents/*.md` | 13 |
     | `listed_commands` | `commands` of `.claude-plugin/plugin.json` | 11 |
     | `listed_skills` | `skills` of the same file | 5 |
     | `config_live_keys` | key lines of `templates/temper.config.default` that are not comments | 30 |
     | `config_comment_keys` | commented key lines of the same file | 46 |
     | `config_lines` | lines of the same file | 171 |
     | `prompt_bytes` | bytes of `commands/*.md`, `agents/*.md` and `reference/**/*.md` | 307,712 |
     | `pack_skill_bytes` | bytes of the markdown under `packs` and `skills` | 79,658 |
     | `cli_bytes` | bytes of `scripts/temper` | the measure after WP02 as `now`, 222144 as `final`; and delete the case `room: scripts/temper leaves 40,000 bytes free` of case file 32 in this commit |
     | `readme_lines` | lines of the product's `README.md`, in the root | 89 as `now`, 80 as `final`: the owner asked for a concise README, and WP31 rewrites the page under the cap (row `D108`) |

     The regular expressions are in `docs/plans/one-go/evidence/v-targets-scorecard.md` section 5; the values in
     the last column were counted again at the head and agree. Take the file list of the flow from one key of the
     file (`flow_files`), so WP03's module names are stated once.
     Three rules in the script: `now` equals the measure; a `final` is not above its value in the commit that
     first added the key, which the history of the file gives; in the final mode no `now` is above its `final`.
     A rule that read only `HEAD` would be passed by the very commit that raises a value. The `final` values are
     part F of `docs/plans/one-go/done.md`, and row `D108` for `readme_lines`; that each `final` of the caps and
     of the floor equals the number of
     that table is checked by `python3 scripts/check_done.py --final` (WP07, `D75b`).
     From this commit on `cli_bytes` is a cap like the others: a package may use the room WP02 made, `now`
     follows the measure, and the line of 222,144 bytes is held at the end by `--final`.
  9. **`scripts/stops.json`.** A list of `{ "id", "where", "trigger", "check" }`: the 18 stops of
     `docs/plans/one-go/evidence/v-auto-advance.md` section 2 and the person only calls of
     `hooks/temper-mod/core/rules.ts:476-497`. `check` names the case or scenario that walks the stop and is empty
     here. WP07 writes those checks and fills the names; this package writes the list and the test that every
     name that is set exists. A stop leaves the list only with a decision record.
  10. **The run summary.** `scripts/run_summary.py` appends one JSON line to `.temper/runs.jsonl`:
      `{ "v": 1, "at", "run", "slug", "command", "version", "mode", "ended", "asks": { "n", "by_stage", "by_kind" },
      "steps_back": [ { "from", "to", "n" } ], "launches": { "by_stage" }, "seconds", "agent_seconds", "skips" }`.
      Call it in `cmd_state_clear` on the line before the `rm -f` of `scripts/temper:1448`, which deletes
      `feedback-loops.json` and `usage.json`, the two files the line is made from. `ended` is `committed` when
      the commit gate's verdict is PASS, else `cleared`. Add `runs.jsonl` and `asked.json` to `_RUN_FILES`
      (`scripts/temper:632-634`) so git ignores them; add `asked.json` to the `rm -f`, after the line is written,
      and keep `runs.jsonl` out of it. Neither file decides a gate row.
      The asks: when the flow writes a view whose `ask` is set (`write_view`, `scripts/flow.py:2885`, beside the
      call of `write_named`; since WP03 in `scripts/flow_view.py`), it records
      `<run id>:<step>:<question id>` in `.temper/asked.json` once, with the
      stage and the kind; a Blocking set counts one for every four questions. Follow up dialogs (More, a reason)
      are asked by the carrier and are not seen here: the page says the count is the CLI's questions.
  11. **The bench scorecard.** No other package of the brief (`docs/plans/one-go/README.md` section 5) owns it and
      part H of `done.md` needs it, so it is here.
      `bench/run.mjs:167, 187-188`: write the question id, the `move` and a dialog index on each line of
      `person.jsonl`; `:248-264`: add the plugin version, the commit, the Claude Code version and mod on or off to
      `run.json`. `bench/agentlog.py`: the four helpers of `bench/compare_models.py:25-108`, with the agent type
      matched whole. `bench/scorecard.py`: `scorecard.json` for a results folder, and `--gate FILE` that compares
      it with the pass lines of part H and writes `docs/evidence/scorecard-9.8.5.json`. `bench/report.py:14`:
      free arm names; median, minimum and maximum beside the mean. The scorecard takes several results folders
      and keeps one block an arm, by name: the model test of WP32 is a third arm in a folder of its own. `--gate`
      holds one arm against the pass lines: the one `--arm NAME` names, by default the round after. WP32 names
      the arm of the planner the release ships with. Test it on a made up results folder: no model.
  12. **CI.** One job `Floor and caps` in `.github/workflows/quality.yml`: bun as the e2e job pins it (`:92-94`),
      then the two floor commands of step 3 and `python3 scripts/check_caps.py`. `bash scripts/verify.sh quick`
      runs `default-run` and `fix` in plain mode with `--floor`; `full` runs every scenario with it.
- **Removed:** `reviewed: auto` from the three fixture files; the `REPLAY_POLICY` branch stays until WP11 removes
  the key it sets.
- **Documents in the same change:** `docs/flow.md` (the run summary and what it counts); `.claude/CLAUDE.md`, Known
  mistakes: a cap is never raised by a building session, and a count of the floor moves only in the commit that
  moves the behaviour; `bench/README.md` (the scorecard, and one source for cost); `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green and prints the floor and the caps blocks.
  - `bun scripts/e2e/run.ts all --floor scripts/e2e/floor.json` exits 0 (this is the whole end to end suite: run it
    once here, in the background; the `full` that ends phase 2 comes after WP07, as
    `docs/plans/one-go/README.md` section 5 says).
  - `python3 scripts/check_caps.py` exits 0 and `bash scripts/quality-check.sh` stays under 30 seconds.
  - `bun scripts/e2e/replay.ts final | tail -1` agrees with the `replay` entry, and
    `bash scripts/e2e/ab-replay.sh 10e965a` exits 0 with its base column equal to the entry `replay_base`.
  - `TEMPER_CASES_ONLY=32 bash scripts/selftest/test-temper.sh` no longer holds the case
    `room: scripts/temper leaves 40,000 bytes free`, and `scripts/caps.json` holds `cli_bytes` with `final` 222144.
  - `python3 bench/scorecard.py` runs on the made up folder of its test.
- **Traps:**
  - After step 4 every scenario asks one more question. A scenario person that answers by question text may stop at
    the wrong one: `saveAndResume` (`scripts/e2e/scenarios.ts:466-474`) and `modGuards` (`:144-161`) match the
    start of the plan question and are safe; read each `person` of `scenarios.ts` and `pyjokes.ts` once.
  - `contextCheck` builds its map by replacing the `reviewed: auto` line of `PLAN_MD`
    (`scripts/e2e/scenarios.ts:343`): change the text it replaces with the fixture, or the replace finds nothing
    and the scenario asks another question than it expects.
  - `scripts/e2e/replay.ts` runs `main()` when imported (`:393`): never import it; run it as a process.
  - The replay drives 9.8.4 too. Its plan with `reviewed: pending` is asked the Context check on both sides; the
    `now` numbers of the `replay` entry are read after step 4, and the table of
    `docs/evidence/ab-replay-9.8.5.md` is printed again in the same commit if a number moved. Until WP32 that
    page is the page of the base, 9.8.4 against the base; WP32 rewrites it in place with a third column for the
    result.
  - `scripts/quality-check.sh` must need python3 and git only (`:3-6`): the floor needs bun and is its own step.
  - `scripts/check_caps.py` and `scripts/check_floor.py` are scripts: no path with a folder named `hooks`,
    `tests`, `mod`, `core` or `ui`, no `glob` call, no wildcard after a variable, no `..` after a variable
    (`scripts/validate-directory.sh:17-34`). List files with `git ls-files` and a pathspec. The mod's count of
    reviewed calls stays in `scripts/check-mod-calls.sh` and in `tests/mod`. The count of hand back kinds is not
    built here: it is left to WP16, which adds the key `handback_kinds` to `scripts/caps.json` and counts it from
    `NEEDS` of `scripts/flow_base.py`, so the checker names no file of the mod
    (`docs/plans/one-go/contracts.md` section 12).
  - `.temper/runs.jsonl` must survive `state init` and `state clear`; U19 of
    `docs/plans/one-go/evidence/v-pr115.md` is the same list missing three files.
  - The view fixtures do not change here. If `write_view` changes what it writes into the view, regenerate them.
- **Size:** L.

## WP06 Two scripted projects with no model cost: slow, and broken

- **Goal:** Two projects that the end to end suite builds in seconds and that behave like an ordinary existing
  project: one whose suite is slower than every default limit, with its build file one folder down and no coverage
  tool; one with a wrong tool version, a service down, a test that is red on the current code and two flaky tests.
  Their scenarios state the final promises and are expected to fail until phase 5.
- **Depends on:** WP04, WP05.
- **Lane:** `side`. Its files are new or are files of the test harness: `scripts/e2e/faketools.ts`,
  `scripts/e2e/slow.ts`, `scripts/e2e/broken.ts`, `scripts/e2e/persons.ts`, `scripts/e2e/xfail.ts`. It also edits
  `scripts/e2e/run.ts`, `scripts/e2e/replay.ts` and `scripts/e2e/floor.json`, which WP05 and WP07 edit too: merge
  it between them, not beside them.
- **Touches:** `scripts/e2e/faketools.ts` (new), `scripts/e2e/slow.ts` (new), `scripts/e2e/broken.ts` (new),
  `scripts/e2e/persons.ts` (new), `scripts/e2e/xfail.ts` (new), `scripts/e2e/replay.ts`, `scripts/e2e/run.ts`,
  `scripts/e2e/floor.json`, `scripts/selftest/expected-fail.txt` (new, four lines), `scripts/verify.sh`.
- **Tests first:** the scenarios are the tests. Each is registered in `scripts/e2e/run.ts` and listed in
  `scripts/selftest/expected-fail.txt` with the package that makes it pass: `slow-first-run` WP23, `slow-at55`
  WP20 (the last column of row `D12`), `broken-first-run` WP21, `broken-flaky` WP22. Each of the four starts
  with a bare `origin` and a fake `gh` and calls the shared assert of row `D105` (steps 1 and 5); what `D11`,
  `D13` and `D105` of `done.md` say is part of the lists below (its note 8). Before them, the scenario half of the
  expected to fail mechanism that WP07 defines (its mechanism, steps 1 and 3) is built and checked here, because
  these scenarios are its first users: `bun scripts/e2e/xfail.ts --check` asserts, on made up input, the four
  outcomes (listed and throws, listed and passes, not listed and throws, not listed and passes) and the reader of
  the list.
  1. `slow-first-run`, modes plain and driver (`D11` of `done.md`). The default person. It asserts: the questions
     asked are `plan.approve` and `commit.confirm` and no other; no line of the tool log has exit 124; the log
     holds at most 3 whole suite runs; the Check gate passed with the coverage row in the state not measured;
     no call of its trace steps back to Plan; `.claude/temper.config` at the end is byte equal to the file
     `temper init` left.
  2. `slow-at55`, mode plain (`D12`). The same project with `check.commands.test` and `check.commands.coverage`
     set before the run; the coverage command runs the suite and prints the line of `backend/coverage-total.txt`,
     which holds `TOTAL 100 45 55%` on the base. It asserts: Check passes at 55%. A second pass of the scenario, in
     which the scripted builder writes 50% into that file, asserts: Check fails with a row that names the drop.
  3. `broken-first-run`, modes plain and driver (`D13`). It asserts, in this order: the first question is asked
     with no agent launched and names the tool version and the service; its recommended option adds the setup
     block; the block written to the config is byte equal to the block that question showed; the red test is
     named in a question before `temper:temper-plan` is launched; no launch of `temper:temper-env` and no fix pass
     of `temper:temper-build` in the whole run; no call of its trace steps back to Plan; the last question is
     `commit.confirm`, with the red test and the first flaky test listed on the commit card; the run asks at most
     4 dialogs.
  4. `broken-flaky`, mode plain (`D14`). The second flaky test passes on the base and fails once at the first
     gate that runs it on another tree. It asserts: the CLI ran it once more before any agent, the ledger holds
     a row that calls it flaky, and no agent was launched for it.
  5. `bash scripts/e2e/ab-replay.sh` prints the same table as before step 1 of the mechanism.
- **Mechanism:**
  1. **`scripts/e2e/faketools.ts`.** Move the fake tool chain out of `scripts/e2e/replay.ts`: `MVN` (`:31-62`),
     `JAVA` (`:63-65`), `PG` (`:66-74`), `POM` (`:76-85`) and the lines that install them on `PATH`
     (`:280-292`). `replay.ts` imports them and behaves as before. Add switches to `MVN`, read from the
     environment, all off by default:
     - `MOCK_SLOW_S`: a run with no `-Dtest=` filter sleeps this many seconds before it answers.
     - `MOCK_RED`: a class name; a run with no filter fails with that class in its failure lines, on every tree.
     - `MOCK_FLAKY_BASE`: a class that fails the first time it runs at all and passes after.
     - `MOCK_FLAKY_LATER`: a class that passes on the base tree and fails the first time it runs on another tree.
       The script keeps its marks as files under `MOCK_DB`, keyed by `git rev-parse HEAD^{tree}`.
     Every call stays one line of `MOCK_LOG`; add the exit code to the line.
     The same file gets `withRemote(w)`: the fake `gh` that logs its calls and the bare `origin` that
     `prAndPipeline` builds (`scripts/e2e/scenarios.ts:258-265`), as one exported function. Every scenario of
     `scripts/e2e/slow.ts`, `scripts/e2e/broken.ts` and `scripts/e2e/accept.ts` calls it before its project
     starts, so a push or a pull request that a run makes is seen in the world (`D105`).
  2. **The slow project (`scripts/e2e/slow.ts`).** `backend/pom.xml` and no build file in the root: the shape
     the measured run had, which `detect()` cannot read (`scripts/check_run.py:76, 140-141`). JDK right, no
     service. One group of two tasks in a chain, so the three suite runs of the promise are the base, the group
     and Check, whoever owns the suite command. The scripted planner writes the Validate and the Integration line
     as `cd backend && mvn -s settings.xml verify -DskipITs`, the form both Maven rows accept
     (`scripts/e2e/replay.ts:89`). No `check.commands` in the config, except in `slow-at55`.
  3. **Slow without waiting.** The suite takes 3 seconds (`MOCK_SLOW_S=3`) and the fixture sets the existing
     default limits below it through the environment of the `World`: `TEMPER_TASK_TEST_TIMEOUT_S=1`
     (`scripts/temper:2441`, `scripts/task_ops.py:708`), `TEMPER_CHECK_TIMEOUT_S=1` and
     `TEMPER_MUTATION_BUDGET_S=1` (`scripts/check_run.py:42-43`). At the head each group gate then ends in exit
     124. Once a limit is three times the measured time on the base and never under the default, it is 9 seconds
     and nothing times out. Chosen over a clock factor in `scripts/run_env.py`: no test only switch enters the
     product. The preflight's own limit is a config key (`scripts/preflight.py:31, 161`) and is left alone: WP21
     removes that run.
  4. **The broken project (`scripts/e2e/broken.ts`).** The project of the replay (`scripts/e2e/replay.ts:294-303`:
     the pom that wants JDK 24 while the shell has 21, the database down, `scripts/ensure-jdk24.sh`, the test that
     reads `IT_POSTGRES_PORT`), with a plan that is right (`GOOD_VALIDATE`, `:89`) and a reviewer that finds
     nothing, so every fault is one of the environment or of the base. `MOCK_RED=LegacyTest`,
     `MOCK_FLAKY_BASE=ClockTest`, and in `broken-flaky` `MOCK_FLAKY_LATER=RetryTest`.
  5. **The persons (`scripts/e2e/persons.ts`).** `defaultPerson(allowed)` takes the option whose `recommended` is
     true and throws `unexpected question <id>` at a question whose id is not in `allowed`. A scenario that is
     still expected to fail then fails at its first extra question, in seconds, and never walks 400 steps.
     `stagePerson` takes `ask-every-stage` at `plan.approve` and the recommended option elsewhere.
     The same file holds the shared assert of row `D105`, `worldCheck(w)`. Both persons take its picture of the
     project when they meet the approval (`plan.approve`, `rca.approve`); every scenario of the three files ends
     with one call of it. It asserts what the row says, at the approval and at the last question, from the
     project itself (git, the `gh` log, the files) and never from the names of calls, and each message starts
     with `D105`. Rule 1 cannot hold in the world before WP12, while rows that pass earlier (`D07`, `D08`, `D17`,
     `D20`) use the same scenarios. So while a line of `approval-first` is on the expected to fail list, the
     shared assert prints what it found as `XFAIL world <scenario> [<mode>]: <line>` and returns; once WP12 has
     taken that line off, a failure of it fails the scenario.
  6. **The list and the scenario runner.** Create `scripts/selftest/expected-fail.txt` and the handling of it in
     `scripts/e2e/run.ts`, as steps 1 and 3 of WP07's mechanism say; the decision is a pure function of
     `scripts/e2e/xfail.ts`. `bash scripts/verify.sh quick` runs `bun scripts/e2e/xfail.ts --check`.
  7. **The floor.** Add `slow-first-run` and `broken-first-run` to `scripts/e2e/floor.json` with `final` values
     only: `dialogs` 2 and `suite_runs` 3 for the slow one; `dialogs` 4 for the broken one (the setup, the red
     base, the approval, the commit; fewer is fine). A scenario on the list has no `now` until it passes.
- **Removed:** nothing.
- **Documents in the same change:** a header comment in each new file that says what the project is and which fault
  each switch plants; `docs/plans/one-go/PROGRESS.md`.
- **Done when:**
  - `bun scripts/e2e/run.ts plain slow-first-run slow-at55 broken-first-run broken-flaky` prints `XFAIL` for each
    and exits 0, in under a minute.
  - `bash scripts/e2e/ab-replay.sh` and `bun scripts/e2e/replay.ts final | tail -1` give the numbers of the
    `replay` entry of the floor.
  - `bash scripts/verify.sh quick` is green.
- **Traps:**
  - The numbers of the replay are evidence (`docs/evidence/ab-replay-9.8.5.md`, the page of the base). Step 1
    must not move one: run the
    replay before and after, and compare the JSON lines but for `cli_seconds`.
  - `bash scripts/e2e/ab-replay.sh` runs this tree's `replay.ts` against a worktree of the base
    (`scripts/e2e/ab-replay.sh:13-17`): the new import must resolve from this tree, not from the base.
  - The tool log is the only witness of a suite run. A reused pass prints a note and runs nothing
    (`scripts/run_env.py:163-166`), which is the wanted effect: count runs in the log, never rows of the ledger.
  - The 3 second suite against a 1 second limit and a 9 second limit leaves a factor of three on each side. Do not
    shorten the sleep to save time: a loaded CI machine then flips the result.
  - `.claude/temper.config` is compared with what `temper init` wrote, after the template of the day. When WP29
    shrinks the template the compare still holds; a compare with a stored copy would not.
  - The broken project's setup block reaches the config by the person's answer. Assert that the config changed
    only in a `setup:` block; that is rule 4 of the brief (`docs/plans/one-go/README.md` section 6) seen from
    the outside.
- **Size:** M.

## WP07 The acceptance scenarios and the eleven rule checks, written failing first

- **Goal:** Every promise of `docs/plans/one-go/done.md` that needs no model has its automated check in the
  repository before the change that makes it pass. A check that is still expected to fail is on one list, and the
  result is done only when that list is empty and every count meets its final value.
- **Depends on:** WP04, WP05, WP06.
- **Lane:** `side`. It adds files and edits the test runners: `scripts/selftest/test-temper.sh`,
  `scripts/selftest/run-selftest.sh`, `scripts/e2e/run.ts`, `scripts/verify.sh`. It edits no flow module, not the
  CLI, not `scripts/go.py`, not the view.
- **Touches:** `scripts/selftest/expected-fail.txt`, `scripts/selftest/test-temper.sh`,
  `scripts/selftest/run-selftest.sh`, `scripts/e2e/accept.ts` (new), `scripts/e2e/run.ts`,
  `scripts/selftest/temper-cases-43.sh` to `scripts/selftest/temper-cases-46.sh` (new),
  `scripts/selftest/saved-old.json` (new), `scripts/selftest/make-saved-old.sh` (new), `scripts/check_done.py`
  (new), `scripts/check_changed_tests.py` (new), `scripts/verify.sh`, `scripts/stops.json`,
  `docs/plans/one-go/done.md`, `docs/plans/one-go/changed-tests.md` (new), `.claude/CLAUDE.md`.
- **Tests first:** this package is tests. The table of `docs/plans/one-go/done.md` is its list: write every check
  of the table that is a `scenario` item or a `case 44`, `case 45` or `case 46` item, with its token as the first
  word of its name.
  For each row read "Tests first" and "Mechanism" of the package in its last column: the calls that build its
  state are named there and in `contracts.md` section 2. Note 8 of `done.md` is part of this spec, and of the
  specs of WP05 and WP06: it lists the tokens the audit added (`D02b` to `D105`) and what the owner's decisions
  of 2026-11-16 added (the token `D108`, and the half of 9.8.4 in the cases of `D60` to `D64`), and every one is
  written here, failing first.
  First write the checks of the mechanism itself, in `scripts/selftest/temper-cases-43.sh`, names `xfail:` and
  `done:`:
  1. `xfail: a listed selftest check that fails is counted apart and the file still ends FAIL: 0`.
  2. `xfail: a listed selftest check that passes is a failure that names the list`.
  3. `xfail: a check that is not listed and fails is a failure` (the list never hides an unlisted failure).
  4. The scenario half is `bun scripts/e2e/xfail.ts --check`, built in WP06: a listed scenario that throws is
     reported and `run.ts` exits 0; one that passes makes it exit 1.
  5. `xfail: an entry that matches no check is a failure` (a stale line cannot stay).
  6. `xfail: the final mode fails while the list has an entry`.
  7. `done: every row of done.md that needs no model names a check that exists`.
  8. `done: a removed or changed assertion of a test of the base fails until changed-tests.md lists it`, and the
     same name with another expected value fails until it is listed.
  9. `done: a token that left the list cannot come back` (a throwaway git folder: the line is taken off in one
     commit and added again in the next).
  10. `done: a token is a whole word` (`D10` does not match an assertion named `D100`), and
      `done: a line of the list names a token of the table or a scenario of the three files`.
  11. `done: the final mode compares each final with the number of done.md` (`D75b`: a `final` of a made up caps
      file that differs from the value after `=` fails, and so does one above its first committed value).
  12. `done: a scenario of the three files that does not call the shared assert fails` (`D105`), and
      `done: a changed check of done.md fails until it is listed` (`D84b`, the second base).
  Each runs the runner on a throwaway copy of a two case file or a two scenario map, never on the real suite.
- **Mechanism:**
  1. **The list.** `scripts/selftest/expected-fail.txt`, tracked, one check a line, `#` for a comment:

     ```
     # suite:name                   passes after   promise
     selftest:D31a                  WP12           D31
     e2e:two-dialogs                WP13           D01
     e2e:slow-first-run:plain       WP23           D11
     ```

     `selftest:<token>` matches every assertion whose name starts with that token and a space.
     `e2e:<scenario>` matches the scenario in every mode; `e2e:<scenario>:<mode>` in one. Nothing else may be
     listed: a mod test is never written failing across packages, because `claude plugin test .` can read no file
     and passes or fails as a whole. A package that needs a mod test writes it with its own change.
  2. **The selftest runner.** In `assert_eq` and `assert_exit` (`scripts/selftest/test-temper.sh:28-51`): take the
     first word of the name; when it is on the list, a failure adds to a third counter and prints
     `XFAIL: <name>`, and a pass adds to `FAIL` and prints `UNEXPECTED PASS: <name>` with the words
     `take <token> off scripts/selftest/expected-fail.txt`. Print `XFAIL: <n>` before the last line and leave the last
     line as it is (`PASS: N  FAIL: M`): `scripts/selftest/run-selftest.sh:67-76` reads that line. Have the
     parallel runner add up and print the third counter too. With `TEMPER_CASES_ONLY` set, skip the stale entry
     check of step 4.
  3. **The scenario runner** (built in WP06, stated here so the mechanism reads whole).
     `scripts/e2e/run.ts:14-27`: a listed scenario that throws prints `XFAIL <name>
     [<mode>]: <first line of the error>` and is not counted as failed; a listed scenario that returns prints
     `FAIL <name> [<mode>]: unexpected pass` and is. The compare of the plain trace with the mod trace (`:28-32`)
     and the floor are skipped for a listed scenario. Register the scenarios of `scripts/e2e/accept.ts` in
     `SCENARIOS` (`:7`).
  4. **`scripts/check_done.py`.** Python 3 and git only. It reads the table of `docs/plans/one-go/done.md` and the
     list, and fails when: a row that needs no model names no check; a `case` token is not found in its case file
     or a `scenario` name is not found in `scripts/e2e` (`grep -F`); a line of the list matches no check; a row id
     is used twice; a test file holds `.skip(`, `.only(` or `.todo(` (found with `git grep` and the pathspecs
     `*.test.ts` and `*.test.tsx`); a line of the list whose token is not a token of the table of `done.md` or
     whose scenario is not one WP06 or WP07 created (a scenario of `scripts/e2e/accept.ts`, `slow.ts` or
     `broken.ts`; `contracts.md` section 9); and, where the history is there (not in a checkout of depth 1), a
     line that an earlier commit of the branch had taken off the list (`git log -p` of the file shows it removed
     and added again). A token is compared as a whole word, so `D10` never matches `D100`. A scenario of the
     three files that does not call the shared assert `worldCheck` fails too (`D105`). A `mod` item is not looked
     up: the mod's own suite runs every test file. It reads the value an item of the table writes after `=`. With
     `--final` it also fails when the list has an entry, and it runs `D75b`: each `final` of
     `scripts/caps.json` and `scripts/e2e/floor.json` equals the value the table writes after `=` for its key,
     and none is above its value in the commit that first added the key. It prints one line a row: the id, `ok`,
     `expected to fail` or `open`.
  5. **`scripts/check_changed_tests.py`.** It takes the removed lines of `git diff 10e965a` for the pathspecs
     `scripts/selftest/temper-cases-*.sh`, `scripts/selftest/test-temper.sh`, `scripts/e2e/*.ts`, `*.test.ts` and
     `*.test.tsx` that hold `assert_eq`, `assert_exit`, `expect(` or `test(`. For each removed line it takes the
     first quoted string as the name and the whole statement as the text (a statement that ends in a backslash
     runs through its last line). It fails when that statement is not in the tree byte for byte and its name is
     not in a code span of `docs/plans/one-go/changed-tests.md`. A changed expected value under an unchanged name
     is a changed assertion. That file is one table: the name, the file, what changed, why, the
     package. The generated fixture modules are left out.
     A second base (`D84b`): for the case files 43 to 46, `scripts/e2e/accept.ts`, `scripts/e2e/slow.ts`,
     `scripts/e2e/broken.ts` and `docs/plans/one-go/done.md` the base is the commit that first added the file,
     and an assertion or a row of the table that changed or went since then must be listed too. Without it a
     failing check of the table could be edited until it passes.
  6. **`scripts/verify.sh`.** `quick` and `full` run `python3 scripts/check_done.py` and print the count of
     expected failures. A new mode `final` is `full`, then `python3 scripts/check_done.py --final`,
     `python3 scripts/check_caps.py --final`, `python3 scripts/check_floor.py --final`,
     `python3 scripts/check_changed_tests.py`, and the bench block: when
     `docs/evidence/scorecard-9.8.5.json` exists it must be inside the lines of part H; when it does not,
     print `OPEN: the bench gate (needs the owner's word and a model access)` and go on. The mode is extended
     later by WP32, which adds the compare of the replay against the base and the check of its summary to it.
  7. **How a scenario reads and answers.** The persons are those of `scripts/e2e/persons.ts` (WP06).
     Scenarios select options by id and read results from `next --json`,
     `.temper/view.json`, `.temper/gates.json`, git and the tool logs. They name a CLI call only where the plan
     names it: `plan amend`, `plan patch`, `evidence resolve`.
  8. **The scenarios.** One function a scenario, built on `startProject`, `AGENTS` and `script` of
     `scripts/e2e/scenarios.ts:20-36, 93-130` and on the projects of WP06. The names, each with the rows it proves:
     `two-dialogs` (`D01`), `approval-first` (`D30a`), `flagged-map` (`D02`), `fix-two` (`D03`), `vague-run`
     (`D04`), `repair-finding` (`D05`, `D37d`, `D39b`), `repair-worse` (`D37e`), `group-fail` (`D06`),
     `group-fail-twice` (`D06`, `D33c`), `integrate-fail` (`D07`), `budget-stop` (`D08`, `D38d`),
     `criteria-by-cli` (`D10`), `ask-every-stage` (`D17`), `design-on-ask` (`D20`), `acceptance-wrong-test`
     (`D21`), `stop-keeps-mode` (`D32c`), `revise-narrow` (`D24`). Every one ends with the shared assert of `D33b`
     on its own trace. Every one also starts with `withRemote(w)` and ends with `worldCheck(w)`, the shared
     assert of row `D105` that WP06 wrote into `scripts/e2e/persons.ts`: it only reports until WP12 takes
     `approval-first` off the list, so a row that passes earlier is not held back by it. The scenarios of
     `scripts/e2e/slow.ts` and `scripts/e2e/broken.ts` assert what rows `D11` and `D13` say; add here what WP06
     left out. `default-run` of WP05 stays as it is, with no assert of a final number: it must pass at
     every commit so that the floor keeps counting it, and its `final` values are the failing first device there.
     What each scenario asserts is in its row of `done.md`, and each `expect` starts its message with the token
     of the row it proves, so `scripts/check_done.py` finds it. A scripted agent that plants the fault follows the
     patterns of `failingScenario` (`scripts/e2e/scenarios.ts:409-441`) and of the replay's reviewer
     (`scripts/e2e/replay.ts:266-271`).
  9. **The rule cases.** `scripts/selftest/temper-cases-44.sh` (the run unit rows that are cases, and rules 1 to
     6), `-45.sh` (rules 7 to 11 and the rows of pull request #115), `-46.sh` (migration, the front, the surface,
     and `D108`, the README of at most 80 lines, whose case reads the product's `README.md` as its row says).
     Build each state
     with the helpers of `scripts/selftest/case-helpers.sh` (`fresh`, `gpass`, `gfail`, `m_setup`, `nx`, `vw`)
     and assert on what `next` returns, on `gates.json` and on git. One new helper, `_unattended <stage>`, builds an
     unattended run at a stage. At the head that is an armed run under `autonomy.policy: decide`, as `_pol` of
     `scripts/selftest/temper-cases-28.sh:4-10` builds it; WP11 changes the helper, never the cases.
     Rule 4 is one static case and one walk. The static case: no `auto` action in any fixture view and in any
     trace of the scenarios above runs a call that matches `state loop \w+ (plan|intent)`, `plan patch`,
     `override`, `evidence accept`, `doctor .* --write`, `git push`, `gh pr` or the final commit. The walk: for
     each stop of `scripts/stops.json`, build its state in an unattended run and assert that `next` is a question
     or a recorded stop, never an `auto` that passes it; write the name of the assertion into the stop's `check`.
     Rule 11 is in `scripts/check_done.py`: each of the rows `D30` to `D39` must name a check in a selftest file
     or a scenario that runs in plain mode.
     The case of `D34d` asserts on the row `review completed`, the name `docs/plans/one-go/contracts.md` section
     6 fixes; WP18 adds no row.
     One assertion a token. Where a row names several states under one token (`D05b`, `D18d`, `D31b`, `D32e`,
     `D33f`), join the results into one `assert_eq`, in the `a|b|c` style of the base. The list works by token: a
     token of which one half passes today is red as an unexpected pass while listed and red as a failure once
     taken off.
  10. **Runs and configs of an older Temper.** Users have 9.8.4 (`7c7a1c1`); the base (`10e965a`) was never
      released. So every migration case runs first on what 9.8.4 left and second on what the base left.
      `scripts/selftest/make-saved-old.sh` runs once, against a work tree of `7c7a1c1` and against one of
      `10e965a` (`git worktree add --detach`, each removed after), because this tree already writes ids and two
      new run files. In each
      it drives the scripted run of that tree's own `scripts/selftest/make-view-fixtures.sh` to five points
      (the plan question; Build with a group running; an armed run in Build; Review with an open finding; a
      parked run) and
      writes every file of `.temper` and of the spec folder at each point into `scripts/selftest/saved-old.json`
      as text, under the key of its commit (`7c7a1c1`, `10e965a`). Under the same key it stores that tree's
      `templates/temper.config.default` (the same text as `git show 7c7a1c1:templates/temper.config.default` and
      `git show 10e965a:templates/temper.config.default`), so the cases of `D61` to `D63` read both old
      templates from the file and need no old commit when they run. The script and the file are committed; no
      case runs the script.
      The cases of `D60` restore each state and run the new CLI on it: one token a state (`D60a` to `D60e`), and
      each joins the result for 9.8.4 and the result for the base in one `assert_eq`. `D61a` runs on the
      template of 9.8.4 and `D61b` on that of the base; the cases of `D62` and `D63` run on both and join the
      two results. `D64a` uses the hook as `scripts/guards/install.sh` of
      `7c7a1c1` writes it: no file under `scripts/guards` differs between the two commits, so that one hook
      stands for both; the script stores its text too, with the path of the plugin as a mark the case fills in.
      A state of 9.8.4 that the tree of this package cannot take up is no reason to weaken its case: the token
      goes on the list for WP11, and row `D60` says what WP11 may then assert.
  11. **Close the loop.** For every check that fails now, add its line to the list with the package that will
      make it pass. For every check that passes now, leave it off. The package is the one of the last column of
      `done.md`, and for a single assertion the one "Rows by package" names; the audit of the kit already put
      `D04`, `D12`, `D33`, `D34d`, `D55` and `D64b` where the build order needs them
      (`docs/plans/one-go/contracts.md` section 13), so nothing is noted for them. Nobody edits the row. A row
      that passes in parts has one line for each check. `D33`: `D33a` and `D33b` WP11, `group-fail-twice` WP16,
      `D33f` and `broken-first-run` WP21. `D55` asserts only "never an environment fault, never an agent", and
      its line names WP08. The options of a slow plan command are row `D99` (`D99a`, `D99b`), listed for WP21:
      no line is listed for WP21 under the token `D55`. Then `bash scripts/verify.sh full` is green with a known
      count of expected failures, and that count goes into `PROGRESS.md`.
- **Removed:** nothing.
- **Documents in the same change:** `docs/plans/one-go/done.md` (the check column corrected where a name changed
  while writing); `docs/plans/one-go/changed-tests.md` (the table starts with the statements WP02 step 10, WP04
  and WP05 changed, each with its reason); `.claude/CLAUDE.md`, Known mistakes: a check
  is taken off the expected to fail list by the commit that makes it pass and by no other, and its assertion is
  never weakened to get there; `docs/plans/one-go/PROGRESS.md`.
- **Done when:**
  - `bash scripts/selftest/run-selftest.sh` ends `PASS: N  FAIL: 0` with an `XFAIL:` line.
  - `bun scripts/e2e/run.ts all` exits 0 and prints `XFAIL` for each listed scenario.
  - `python3 scripts/check_done.py` prints a line for every row of `done.md` and exits 0;
    `python3 scripts/check_done.py --final` exits 1 and names the entries of the list.
  - `python3 scripts/check_changed_tests.py` exits 0 against the base `10e965a`, with the table of
    `changed-tests.md` holding the statements WP02 step 10, WP04 and WP05 changed, each with its reason.
  - Each scenario on the list fails in under 10 seconds (time one mode of each).
- **Traps:**
  - A check that is expected to fail must fail for the reason of its promise, not for a typing mistake. Where a
    part of the check can pass today, make it pass today: a scenario asserts first what holds at the head and last
    what does not, and its error line names the promise.
  - A bash case that calls a command the CLI does not have yet must not abort the file: keep the call inside
    `$( ... )` or end it with `|| true`, and compare the output.
  - A later package may name a call or a row differently from the check. It corrects the name in the check in its
    own commit and lists the change in `changed-tests.md` (`D84b`). It never changes what is asserted; if the
    assertion is wrong, it says so in `PROGRESS.md`, and the pull request text carries it. The row of `done.md`
    is not edited (`docs/plans/one-go/README.md` section 4).
  - One scenario may prove several rows; it stays listed until all of them hold. Keep one promise a scenario
    where two packages far apart make the parts pass.
  - `scripts/selftest/run-selftest.sh` runs the pairs 2 with 3 and 8 with 9 in one process (`:33-35`). The list is
    read once a process; a token must not be shared by two case files.
  - `10e965a` must stay reachable from the branch, or `scripts/check_changed_tests.py` has no base. The case of
    `D64b` reads `git diff 10e965a` when it runs, in CI too: the selftest job fetches the whole history for it
    (WP01's workflow).
  - Directory rule 10 forbids a shell or Python script to name a path with a folder named `hooks`, `tests`, `mod`,
    `core` or `ui` at all, comments included (`scripts/validate-directory.sh:17-27`). So the two new scripts and
    every bash case reach the mod's tests only through git pathspecs by file ending, and never name their folder;
    rule 11 forbids a `glob` call in a Python file. Run `bash scripts/validate-directory.sh` before the commit.
  - The new case files are 43 to 46 and those of this phase 40 and 41; WP01 to WP03 use 32, and 42 is reserved
    for WP06. Other packages take the numbers `docs/plans/one-go/contracts.md` section 10 reserves for them (47
    for WP08, the rest from 50 up), so two packages never write one file.
  - `scripts/e2e/accept.ts` is a new file so that `scripts/e2e/scenarios.ts` (46,572 bytes) is not edited by every
    package at once.
- **Size:** XL: the largest package of the build; give its three rule case files and its scenarios to separate
  agents, as the brief allows.
