# Phase 3 and phase 6: pull request #115, and repairs

This file holds WP08 (phase 3: the 16 defects and the 4 flips of pull request #115) and, of phase 6, WP24 (a finding
is repaired in its stage) and WP25 (`plan amend` by rule, `plan patch` for the person, the replan that keeps).

Every `file:line` below is of the head `10e965a`. WP02 and WP03 land before these packages and move code: find each
function by its name, with the module table of WP03 (`ask` and the option makers are in `scripts/flow_ask.py`,
`policy_move`, `setup_offer` and `stage_work` in `scripts/flow_work.py`, the Build questions in
`scripts/flow_build.py`, the commit question in `scripts/flow_commit.py`, `core_next` in `scripts/flow.py`, the view
in `scripts/flow_view.py`). The owner's reading of WP08 is `docs/plans/one-go/pr-115-fixes.md`: one decision for each
defect. Ids `M1` to `M16`, `F1` to `F4` and `U1` to `U29` are those of `docs/plans/one-go/evidence/v-pr115.md`.

The brief is `docs/plans/one-go/README.md`, and every shared name below is the one `docs/plans/one-go/contracts.md`
fixes. In the build order of the brief's section 5, WP08 is package 9 (after WP07), and WP24 and WP25 are packages
25 and 26 (after WP23). Each package ends as the brief's section 4 says: the package commit, then the small
progress commit, in one push.

## WP08 The defects of pull request #115: fixed, removed, or made safe

- **Goal:** No item of the merge list reproduces. Each of M1 to M16 and F1 to F4 is fixed, removed, or made safe until
  the later package that rebuilds its area, and each has a check that fails at the head. A default scripted run asks
  no more than 9.8.4 did and recommends no loop that 9.8.4 did not.
- **Depends on:** WP01 (room in the fixture file), WP02 (room in `scripts/temper`), WP03, WP04 (the registry
  `OPTION_IDS` of `scripts/flow_base.py`, to which this package adds the option ids `it-is-the-code` and
  `check-again`), WP05 (the floor counts the flips), WP07 (the checks `D41` to `D57` and the expected to fail
  list).
- **Lane:** `flow core`.
- **Touches:** `scripts/temper` (`cmd_integrate`, `_integ_record`, `_go_back`, `cmd_task_gate`, `_RUN_FILES`, the `rm`
  line of `state clear`, the two `doctor` help lines), `scripts/flow_ask.py`, `scripts/flow_work.py`,
  `scripts/flow_build.py`, `scripts/flow_commit.py`, `scripts/flow.py`, `scripts/task_ops.py`, `scripts/preflight.py`,
  `scripts/decisions.py`, `scripts/config_yaml.py`, `scripts/flow_base.py` (two entries of `OPTION_IDS`),
  `templates/temper.config.default`, `agents/check.md`,
  `reference/check.md`, `agents/plan.md`, `hooks/temper-mod/core/session.ts`, `hooks/temper-mod/core/rules.ts`,
  `tests/mod/session.test.ts`, `tests/mod/v975.test.ts`, `tests/mod/guard.test.ts`,
  `scripts/selftest/temper-cases-8.sh`, `-11.sh`, `-22.sh`, `-23.sh`, `-24.sh`, `-25.sh`, `-26.sh`, `-27.sh`,
  `-28.sh`, `-31.sh`, `-45.sh`, `scripts/selftest/expected-fail.txt`, both view fixture files,
  `scripts/e2e/scenarios.ts`,
  `scripts/e2e/replay.ts`, `scripts/e2e/floor.json`, `docs/flow.md`, `docs/commands.md`,
  `docs/plans/one-go/changed-tests.md`, `docs/plans/one-go/PROGRESS.md`, `CHANGELOG.md`.
- **Tests first:** WP07 wrote one assertion a promise in `scripts/selftest/temper-cases-45.sh` (tokens `D41` to
  `D57d`; `D32b` is in `-44.sh`), and they are on `scripts/selftest/expected-fail.txt`. This package makes them pass
  and takes each off the list in the commit that makes it pass. Beside them it adds the narrow cases below, each in
  the case file that already builds the state. Each must fail at the head before its fix. Where a case rewrites an
  assertion that states the old behaviour on purpose, list the old name in `docs/plans/one-go/changed-tests.md`.
  `docs/plans/one-go/contracts.md` section 10 reserves case file 47 for this package; it stays unused unless a
  case needs a file of its own. `D55` asserts only "never an environment fault, never an agent" and passes here.
  The three ways on as options of a question are row `D99` of `docs/plans/one-go/done.md`, which passes at WP21:
  no line stays on the list for WP21 under the token `D55`.
  1. M1, `temper-cases-25.sh`, after the integrate block (`:50-66`):
     `m1 integrate: a suite broken after a pass fails, is repaired, and passes again`. A PASS record as at `:53-59`,
     then a commit that makes the Integration command exit 1: `temper integrate` exits 0, the record has `verdict`
     FAIL and `merged` true, `temper gate build` prints FAIL with the row `integration`, and `temper next` is `ask` at
     Build. Then a commit that repairs the command: `temper integrate` records PASS. No output of the three calls
     holds `not something we can merge`.
  2. M1, `temper-cases-26.sh`, beside `:43`: `m1 the fix pass names the failure`. With a loop record that carries a
     finding and an integration record at FAIL, the fix pass prompt holds the finding line and the line
     `What failed: integrate:`.
  3. M1, `scripts/e2e/scenarios.ts`, scenario `fix-breaks-suite` (the function `fixBreaksSuite`), three modes:
     the scripted reviewer leaves one High
     finding, the person takes the recommended loop back, the scripted fix agent breaks the Integration suite once,
     the run asks the Build question, the second pass repairs it, and the run reaches the commit. Assert that no call
     of the trace failed with `not something we can merge` and that the fix agent ran twice.
  4. M2 and F1, `temper-cases-25.sh:46-48` (rewrite):
     `a passed Review with an open Medium names the counts and recommends Continue to Check`; the first two labels are
     `Continue to Check (Recommended)` and `Loop back to Build`, and the labels of the More question are
     `Accept a finding`, `Grill Me`, `Make a small change`, `Save for later`. Add:
     `no fixture view holds a More question with a More options entry`, read from both fixture modules as
     `scripts/selftest/temper-cases-8.sh:459-460` reads them.
  5. F1, same file: `the Check question at a pass lists the open findings`: with one Medium finding open and Check
     passed, the question text holds `open findings: 1 medium` and the first 120 characters of its claim.
  6. F1, `temper-cases-28.sh:12-16` (rewrite): `policy: an open Medium finding goes on to Check by itself`; add
     `policy: an open High finding under block-on critical loops back once`.
  7. M3, `temper-cases-28.sh`, with `_polg`: `policy: after group fix G1 the fix agent is launched`. With
     `"fix": {"requested": "x"}, "fix_tries": 1` and a failed gate, `temper next` is `work` with one agent of type
     `temper:temper-build`.
  8. M4, same file: `policy: a recommended step back to Plan parks`. With `"fix_tries": 1`, no `fix` key and a failed
     gate that ran, the action is `auto`, its call holds `park --verdict PARKED-NEEDS-DECISION`, and no call holds
     `state loop build plan`.
  9. M5, same file: `after a step back to Plan an armed run is interactive`: in an armed run, after
     `temper state loop build plan --reason x`, `temper state get run_mode` prints `interactive`; the same after
     `temper state set next_stage plan`.
  10. M6, same file, with `_pol check`: `policy: a criterion only the person can confirm parks`. The failed row is
      `acceptance evidence` with the detail `AC-2 has no supported passing evidence row` for a criterion whose
      Validate is `manual`: the action is `auto` with a park, never `state loop check build`. After the park call
      runs, `temper next` asks, and the first label is `Confirmed (Recommended)`.
  11. M7, `temper-cases-31.sh`, in a project whose config has no `evidence.claimed-runs` key (not the shared fixture
      of `scripts/selftest/test-temper.sh:78`): `evidence run at Check passes tests pass`, and
      `a claimed test run at Check does not`. Add the grep case `the Check brief records no claimed test run`: no line
      of `agents/check.md` or `reference/check.md` holds both `evidence add` and `--claim "tests"`.
  12. M7, `temper-cases-11.sh` (it holds the small change cases at Check, `:490`):
      `a small change at Check is checked by the CLI`: after `adhoc close` at Check in a project the CLI can read,
      `temper next` is `work` with the calls `check run` and `gate check` and no agent.
  13. M8, `temper-cases-23.sh` (it reads the template at `:18`):
      `the template with the grouped block uncommented keeps it`: a copy of the template with lines `:124-130`
      uncommented gives `claude-haiku-5-5` for `temper config get build.grouped.task-model`.
      `two autonomy blocks keep park-on-touch`: a config with the template and an appended `autonomy:` block that
      holds only `policy: decide` still returns the three patterns for `temper config get autonomy.park-on-touch`.
  14. M9, `temper-cases-24.sh`, after `:40`: `ENV: the question offers it-is-the-code`: the option with that id has
      the call `task gate 1 --model haiku --no-env`; running it prints FAIL and the attempt count rises by one.
      `ENV: the same reason twice does not recommend Check it again`: after a second ENV verdict with the same reason
      the first label is `Save for later (Recommended)`. Rewrite `:40`, which lists two labels.
  15. M10, `temper-cases-26.sh`, after `:55`: `SETUP: the same fault after a run again recommends Save for later`.
      With `redo` in the state holding `stage: check` and the reason `SETUP: no Postgres answering on 127.0.0.1:5432`,
      and the same setup fault row, the first label is `Save for later (Recommended)` and no other label carries the
      mark.
  16. M11, `temper-cases-8.sh`, beside `:392`: `only the commit gate's own row failed: Check again is first`. With the
      state of `:359-365`, the first option has the id `check-again` and its calls end in `gate commit`.
  17. M12, `tests/mod/session.test.ts`: move the two lines of `:68-70` to the refused list, and add
      `git push https://example.org/x.git HEAD:temper-backup/x`, an `ssh` remote, a remote named `backup`, and
      `git push origin refs/stash:temper-backup/x`.
  18. M13, `tests/mod/v975.test.ts`: `doctor --propose --write` and `doctor --candidate F --write` typed by the
      session or by an agent are refused; `doctor --propose --write` passes as a call of the option the person picked.
      `temper-cases-27.sh`: rewrite `:36` to
      `a block that does not fix the command is not offered again, and no agent is offered` (no label holds
      `Let an agent find the setup`); rewrite `:118-121` to
      `a saved request for the environment agent launches nothing` (`state set env_agent requested`, then no agent of
      type `temper:temper-env` in `temper next`); add `the question shows the proposed block whole`: every line that
      `temper doctor --propose` prints for the block is in the question text.
  19. M14, `tests/mod/guard.test.ts`: during a run, a Write, a Bash redirect and an `rm` are refused for each of
      `.git/temper-results.json`, `.temper/preflight.json`, `.temper/decisions.json` and `.temper/setup-tried.json`;
      `rm .temper/*.json` is refused.
  20. M15 and F4, `temper-cases-22.sh`: rewrite `:43` to `a command over the limit is not checked and passes the row`:
      the row passes, its detail holds `not checked: over 2 s` and names `plan.preflight-timeout`, `plan patch` and
      `plan.preflight-skip`, and no line holds `environment fault`. Rewrite `:37` (four commands, four classes) to
      `only the Validates and the Integration line run`: each command of the plan appends its name to a counter file,
      and after the gate the file holds no task Test and no scenario Test. Add `one total limit`: two Validates of
      `sleep 2` under a limit of 3: the first runs and the second is `not checked: the total limit of 3 s was spent`.
      F4 has a token of its own, `D57d`, which passes here. The final form of M15, M16 and F4 (the plan gate runs
      no command, a slow one asks the question `plan.command`) is row `D99`, which passes at WP21.
  21. M16, `temper-cases-22.sh`, after `:61-67`: `a stored failure is not returned`: a Validate that reads a marker
      file fails as an environment fault; the marker is written; the next `preflight.py row` call runs the command
      again and passes. `:61` stays: a stored pass is still read. `temper-cases-27.sh`, beside `:48`:
      `the failed plan question offers check-again`, an option whose calls are `plan preflight` and `gate plan`.
  22. F2, `temper-cases-25.sh:21` (rewrite): `a Design answer newer than the tasks passes its row with a note`: the
      row `tasks agree with decisions` passes, its detail names the answer, and the Design question recommends
      `Continue to Build`.
  23. F3: no change. `D57c` holds at the head; it must never be on the list.
  24. The reuse store (U4), `temper-cases-23.sh`, with its helper `_re`:
      `reuse: a pass on a clean tree is kept and the second call does not run` (a counter file);
      `reuse: a failure is never kept`; `reuse: a tree with an uncommitted change runs again`;
      `reuse: another command, another tree and another setup block each run again`;
      `reuse: the output of a reused pass says so`.
  25. The policy path (U21), `scripts/e2e/scenarios.ts`, scenario `policy-run` (the function `policyRun`), plain
      and mod mode: the config gets
      `autonomy.policy: decide` in a second `autonomy:` block, the person arms at the plan question, one group check
      fails once, the reviewer leaves one High finding. Assert: one launch of `temper:temper-plan`, one group fix
      launch, no call `state loop build plan`, no question between the approval and the commit question, the change
      committed. Driver mode is left to WP09: `scripts/go.py:108-109` reports a failed `group gate` as an error and
      the driver hands the run back.
  26. Run files (U19), `temper-cases-45.sh` or the case file of `temper init`:
      `the run files of 9.8.5 are listed and cleared`: after `temper init`, `.git/info/exclude` holds
      `preflight.json`, `setup-tried.json` and `decisions.json`; after `temper state clear` none of the three is left
      under `.temper`.
- **Mechanism:** one commit a defect where the files allow it; M2 with F1, M15 and M16 with F4, and M3 to M6 each go
  together. Run `bash scripts/verify.sh quick` after each. Each of these commits carries `(wp08)` in its subject.
  The last one is the package commit; after it comes the small progress commit, and one push for both
  (`docs/plans/one-go/README.md` section 4).
  1. **M1, `cmd_integrate`** (`scripts/temper:3301-3433`). Today the rerun after a PASS records FAIL and returns 1
     (`:3323`); the next call no longer sees PASS (`:3316`), falls into the merge (`:3387-3397`) and fails for good,
     because the PASS deleted the group branches (`:3430`). Change three things. `_integ_record` (`:3292-3298`) writes
     `merged: true` on the PASS at `:3431` and keeps a `merged` it finds in the record it replaces. The test at
     `:3316` becomes: the record is PASS, or it is merged. Inside, the suite runs again when the head moved or the
     verdict is FAIL. A failed rerun records FAIL, prints its `FAIL:` line and returns 0: the verdict is recorded, and
     `gate build` (the next call of every caller, `scripts/flow.py:1663, 1669-1670`) fails the row `integration`
     (`scripts/temper:3707`). The Build question then holds it with its failed the same way rule
     (`scripts/flow.py:753-763`). A record with no `merged` key and the verdict PASS counts as merged, so a run saved
     by 9.8.5 goes on. In the fix pass (`scripts/flow.py:1659`) send both lists:
     `self.feedback_lines() + self.fault_lines()`. Tested by the verifier in a clone (`e3.sh` of
     `docs/plans/one-go/evidence/v-pr115.md`, section 6 point 1).
  2. **M2, `add_adhoc`** (`scripts/flow.py:915-952`). At `:925` drop the test `startswith("Continue")`: at a passed
     Review with an open finding Teach Me gives way to the small change, whatever the first label. In the last branch
     (`:943-947`) never replace a More question that exists: when `q.get("more")` is set and full, leave the question
     as it is. Case 4 holds that no fixture view meets that state.
  3. **F1, the Medium flip.** `scripts/flow.py:780`: the tuple becomes `("critical", "high")`. The same tuple at
     `:1167` (the policy) and the sentence at `:1141` ("findings at high or above are repaired"). The counts stay in
     the question text (`:786`). In the passed Check question (`:813-821`) add `self.finding_counts(opens)` and the
     first three claims, so a Medium finding is listed where the person commits; WP15 moves that line onto the commit
     card.
  4. **M3.** `scripts/flow.py:1754`: `and (not r.armed() or r.policy())`.
  5. **M4, way A** of `docs/plans/one-go/evidence/v-pr115.md`, section 4: at `scripts/flow.py:1968` the policy does
     not take an option whose `move` is `back`. It falls through to the park at `:1973-1977`, whose reason gets the
     words "a step back to Plan is yours to decide".
  6. **M5, `_go_back`** (`scripts/temper:1269-1295`): when the target is `intent`, `plan` or `design`, set `run_mode`
     to `interactive` with `_json_set_path`, beside the reset at `:1277-1279`. `ran_unattended` stays.
  7. **M6, `policy_move`** (`scripts/flow.py:1173-1180`): before the `loop` at `:1180`, park when a manual criterion
     is among the failed rows, with the same match as `:825-826`. `park` turns the run interactive
     (`scripts/temper:4520`), so the next question is the confirmation of `:827-836`.
  8. **M7, the briefs.** `agents/check.md:30-31` becomes one command:
     `temper evidence run --stage check --claim "tests" -- <the exact test command>` (the form of
     `scripts/temper:1737`). `reference/check.md:8` names `evidence run` for a run and `evidence add` for a measured
     value. In `small_change_work` (`scripts/flow.py:966-971`): when `self.cli_check()` holds, the step `check` is the
     calls `check run` and `gate check` with no agent, as `stage_work` does at `:1359-1364`.
  9. **M8.** Template: lines `:155` and `:158` become comments (`# build:`, `# evidence:`), so no live key is empty.
     Reader, `scripts/config_yaml.py:27-30`: a key with no value whose parent already holds a map under that key
     reuses the map (`container = parent[key] if isinstance(parent.get(key), dict) else {}`).
  10. **M9.** `cmd_task_gate` (`scripts/temper:3073`) takes `--no-env` and passes it to the verdict of
      `scripts/task_ops.py:761-767`, which then skips the ENV branch: the verdict is FAIL and the attempt is spent.
      Where the gate stores the ENV verdict (`scripts/temper:3129`), add `again`: one more than the stored value when
      the new reason equals the stored one as `same_failure` compares, else 0. In `env_task`
      (`scripts/flow.py:1857-1870`) add the option `it-is-the-code` ("It is the code: send the task back to its
      agent") with the one call `task gate N --model M --no-env`: the gate reads the failed GREEN run it has, so no
      test runs again. With `again` above 0, Save for later is first and recommended and Check it again loses its
      mark.
  11. **M10.** In the SETUP branch of the Check question (`scripts/flow.py:837-851`) apply the rule of `:855-863`:
      when `redo` names Check and `same_failure` holds for the reason `SETUP: <fault>`, Save for later is first and
      recommended, and neither the repair nor the proposed block carries the mark.
  12. **M11, the commit question** (`scripts/flow.py:2247-2277`): when `own` holds and `outside` is empty, put the
      option `check-again` ("Check again", the call `gate commit`, move `redo`) first, with no recommended mark. The
      text keeps its sentence. The exit for a person who meant the change is WP11's.
  13. **M12, removed.** Delete `BACKUP_DEST` and `backupPush` (`hooks/temper-mod/core/session.ts:120-134`) and the
      line that calls it (`:154`), and the paragraph at `docs/flow.md:259-260`.
  14. **M13.** (a) `personOnly` (`hooks/temper-mod/core/rules.ts:476-497`): `doctor` with `--write` is the person's.
      The option of `scripts/flow.py:1197-1199` carries that call, so the audit of `tests/mod/audit.test.ts:76` finds
      its question. (b) The environment agent is no longer offered: delete the second half of `setup_offer`
      (`scripts/flow.py:1200-1204`), `env_agent_work` (`:1207-1227`) and its dispatch in `core_next` (`:2377-2379`).
      The brief, the manifest line and `doctor --candidate` stay for WP21, which deletes them with the preflight. (c)
      The question that offers the block (`scripts/flow.py:697-699`, and the SETUP branch at `:849-851`) shows every
      line of the block, with `run_env.mask` on the run line, not only `run` and the variables (`:1194-1196`). (d) The
      help line `scripts/temper:5093` and the comment at `:5025` say that `doctor` reads, and that `--propose --write`
      adds the block as the call of the person's answer. A block that fakes a tool passes the check of
      `scripts/preflight.py:227-243`; no cheap check exists, and the person who reads the block is the control.
  15. **M14.** In `PROTECTED` (`hooks/temper-mod/core/rules.ts:103-116`): extend the `state` pattern at `:109` with
      `preflight`, `decisions` and `setup-tried`, and add `['gates', /(^|\/)\.git\/temper-results\.json$/i]`. Add the
      four paths to `GUARDED_SAMPLES` (`:119-123`).
  16. **F4, M15 and M16, `scripts/preflight.py`.** `commands` (`:44-61`): drop the task Tests (`:48`) and the scenario
      Tests (`:50-54`). `classify` (`:99-115`): exit 124 returns the new class `not checked` before `env_fault` is
      called; add it to `CLASSES` (`:33`). `run_classes` (`:189-210`) keeps a total: each command gets what is left of
      the limit, and a command that finds none left is `not checked: the total limit of N s was spent`. `format_row`
      (`:213-224`) passes a row whose only faults are `not checked`, and writes for each the three ways on: a longer
      `plan.preflight-timeout`, another command (`temper plan patch`), a skip with a reason (`plan.preflight-skip`).
      `make_row` (`:167-171`) returns a stored row only when it passed. The failed plan question
      (`scripts/flow.py:693-701`) gets the option `check-again` (the calls `plan preflight` and `gate plan`) first
      whenever a failed row is `preflight`; with five options use `with_more`.
  17. **F2, `scripts/decisions.py:60-69`.** `row` returns `pass: True` in both cases; with stale answers the detail is
      "N Design answer(s) came after the plan: <the names>. They go to every Build task." Delete the branch of the
      Design question at `scripts/flow.py:733-739`. The answers still reach each task prompt (`decisions_line`,
      `scripts/flow.py:1715`).
  18. **Run files (U19).** Add `preflight.json setup-tried.json decisions.json` to `_RUN_FILES`
      (`scripts/temper:632-634`) and to the `rm -f` of `state clear` (`:1448`).
  19. **Hand on the follow ups.** Copy section 3 of `docs/plans/one-go/pr-115-fixes.md` into
      `docs/plans/one-go/PROGRESS.md` as one open line a follow up with its package, under the heading "Follow ups
      of pull request 115" (the format is in `docs/plans/one-go/session-mechanics.md` section 5). The package that
      closes one ticks
      it; WP32 reads the list in its first step, and a line that is open and not marked dropped is not done: its
      text of the pull request says so.
- **Removed:** the backup push of the mod; the offer and the launch of the environment agent; the Medium loop as a
  recommendation and as a policy move; the failing form of the row `tasks agree with decisions` and its question
  branch; the task Tests and scenario Tests of the preflight; the class `environment fault` for a time out; the two
  empty keys of the template.
- **Documents in the same change:** `docs/flow.md` (`:228-233`: Medium goes on, a step back to Plan parks; `:132-155`:
  what the preflight runs, `not checked`, a stored failure runs again; `:259-260` removed); `docs/commands.md`
  (`temper doctor`, `task gate --no-env`); `templates/temper.config.default` (`:109` and `:146-148` say the new
  rules); `agents/plan.md:100-105` (the row runs the Validates and the Integration line under one limit);
  `agents/check.md`; `reference/check.md`; `CHANGELOG.md` (the entry of 10.0.0: one line a defect);
  `docs/plans/one-go/changed-tests.md`; `docs/plans/one-go/PROGRESS.md`. ADR 0018 is not edited here: the record
  that amends it, `docs/decisions/0020-checks-judged-against-the-project.md`, is left to WP21.
- **Done when:**
  - `bash scripts/verify.sh quick` is green, and `bash scripts/verify.sh full` is green at the end of the phase.
  - `grep -c "D4[1-9]\|D5[0-7]\|D32b" scripts/selftest/expected-fail.txt` prints 0: `D55` and `D57d` pass here,
    and what WP21 adds to them is row `D99`, a token of its own.
  - `bun scripts/e2e/run.ts all fix-breaks-suite` and `bun scripts/e2e/run.ts both policy-run` pass.
  - `claude plugin test .`, `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` pass.
  - `bash scripts/e2e/ab-replay.sh` shows no more questions and no more recommended loops than its 9.8.4 column.
  - `python3 scripts/check_floor.py` holds with the values this package lowered, and none raised.
- **Traps:**
  1. `scripts/selftest/view-fixtures.ts` and `view-fixtures-2.ts` hold the Review, Check, plan and commit questions
     this package changes. Regenerate with `make-view-fixtures.sh` after M2, F1, M11 and M16, and run
     `claude plugin test .`: the mod's tests pin labels of these questions.
  2. The reader merge of M8 changes every test that appends a second block and relied, without saying so, on the first
     being dropped: `_pol` and `_polg` (`scripts/selftest/temper-cases-28.sh:5, 34`), `temper-cases-8.sh:359` and
     `scripts/e2e/replay.ts:309`. After the merge `park-on-touch` and `max-blast-radius` of the first block apply in
     them. Fix the test's files, never the merge.
  3. `integrate` returning 0 with a FAIL line is right only on the rerun path. The first integrate keeps exit 1 for a
     conflict and for a red suite (`scripts/temper:3394-3396, 3413-3417`); WP09 gives every recorded verdict one mark
     and may then change both. Do not remove the rerun: WP24 needs it.
  4. The preflight work of items 16 and 14 lands in code that WP21 deletes. Keep it to the lines named, and write the
     cases so that WP21 can keep their intent (its trap 1 lists them).
  5. A question holds four options at most (`scripts/selftest/temper-cases-26.sh:31`). M9, M11 and M16 each add one:
     use `with_more` and keep Save for later reachable.
  6. The scripted person of the end to end suite takes the recommended option. After F1 no scenario loops back for a
     Medium finding; a scenario that needs the loop plants a High one.
  7. `tests/mod/audit.test.ts` walks every option of every fixture view; an option id that is not in the closed list
     of WP04 fails `ids:` in `scripts/selftest/temper-cases-40.sh`. Add `it-is-the-code` and `check-again` to
     `OPTION_IDS` first.
  8. Hooks and the guard fail open except on their one detected violation. The new guard patterns of M14 are that
     path; do not add a deny for a path that cannot be parsed.
  9. `scripts/temper` is under the file limit only by what WP02 freed. The `merged` rule of M1 and the `again` count
     of M9 are a few lines each; anything longer goes into the module WP02 made for that function.
- **Size:** L (twenty small fixes, about 30 cases, two scenarios, one fixture regeneration).

## WP24 A finding is repaired in its stage

- **Goal:** One High or critical finding of Review, or one failed row of Check whose class is code, is repaired where
  it was found with 0 dialogs and no second full Review: a fresh Build agent fixes, the CLI commits, runs its checks
  again on the new tree, and a reader that did not write the fix confirms each finding. Only then does the CLI resolve
  it, for that commit. A repair that made things worse is reverted and asked about.
- **Depends on:** WP08, WP09 (a recorded verdict is no error for any carrier), WP10 (the budget), WP11 (the default
  run, its stops, the one counted loop back this package replaces), WP15 (`scripts/card.py`), WP16, WP18
  (`evidence resolve` checks its commit; the completion row names the files read), WP22 (every verdict names its tree;
  `tree_key`), WP23 (the locked acceptance tests and coverage inside `integrate`; `scripts/failure.py`).
- **Lane:** `flow core`.
- **Touches:** `scripts/repair_ops.py` (new), `scripts/temper` (the word `repair`, `cmd_evidence_add`, `gate_commit`,
  `gate_review`), `scripts/cli_ctx.py` (`setup_calls`), `scripts/findings.py`, `scripts/adhoc_ops.py`,
  `scripts/loop_step.py`,
  `scripts/flow_base.py` (`MOVES`, and the registry of WP04: `QUESTIONS` gains `repair.stop`, `OPTION_IDS` gains
  `repair-again` and `revert-repair`), `scripts/flow_ask.py`, `scripts/flow_work.py`,
  `scripts/flow.py`, `scripts/flow_view.py`, `scripts/card.py`, `scripts/guards/install.sh` (only if the hook body
  changes, see the traps), `agents/build.md`, `agents/review.md`, `hooks/temper-mod/core/rules.ts`,
  `hooks/temper-mod/core/runview.ts`, `hooks/temper-mod/adapter.ts`, `tests/mod/guard.test.ts`, `dialog.test.ts`,
  `view.test.ts`, `hardening.test.ts`, `audit.test.ts`, the new case file `scripts/selftest/temper-cases-65.sh`,
  `scripts/selftest/temper-cases-45.sh`,
  `-46.sh`, `-8.sh`, `-9.sh`, `-11.sh`, `-13.sh`, `-15.sh`, `-25.sh`, `-28.sh`, `scripts/selftest/expected-fail.txt`,
  both view fixture files, `scripts/e2e/accept.ts`, `scripts/e2e/scenarios.ts`, `scripts/e2e/replay.ts`,
  `scripts/e2e/floor.json`, `scripts/stops.json`, the new decision record
  `docs/decisions/0021-a-finding-is-repaired-in-its-stage.md`, `docs/flow.md`, `docs/trust.md`,
  `reference/review.md`, `reference/check.md`, `reference/autonomy.md`, `commands/temper.md`,
  `templates/temper.config.default`, `.claude/CLAUDE.md`, `CHANGELOG.md`.
- **Tests first:**
  1. From the list of WP07, made to pass here: `scenario repair-finding` (`D05`, `D37d`, `D39b`: the questions asked
     are the approval and the commit; the launches after Build are one full Review, one Build agent, one recheck; the
     trace order is repair commit, `integrate`, `gate build`, recheck, resolve; the commit card lists the repair, its
     files and the recheck's answer); `scenario repair-worse` (`D37e`: a repair that breaks a row that passed is
     reverted, the tree equals the reviewed tree, and one question names what broke); `case 45 D37b`
     (`evidence resolve` is refused for a commit the CLI did not record as a repair, and while no recheck row follows
     the commit); `case 45 D37c` (a repair diff that removes a line of a test file that existed at the reviewed HEAD
     is never resolved by rule: the run stops and the question shows the removed lines); `case 46 D64a` and `D64b`
     (see mechanism 7).
  2. A new selftest case file, `scripts/selftest/temper-cases-65.sh` (the number
     `docs/plans/one-go/contracts.md` section 10 reserves; the runner of WP01 finds it), names `repair:`:
     - `repair: start is refused outside its conditions`, one assertion each: the gate passed; a failed row is not on
       the repairable list; no completion row; HEAD is not the reviewed HEAD; the tree is dirty; a stage of the run
       was skipped; the budget has no room; a finding is contested; a finding's file is under a sensitive path; the
       run is a fix run; the stage is `commit`.
     - `repair: the launch holds the whole finding`: the prompt holds the claim, the detail, the suggested fix and the
       proof field of each finding, uncut.
     - `repair: commit with no change records it and launches no recheck`.
     - `repair: commit refuses a file outside the approved set`, and one each for the spec folder, the config, a file
       under `.git`, a locked acceptance test, a lockfile, a CI file, a sensitive path.
     - `repair: commit refuses when HEAD moved since the window opened`.
     - `repair: the hook passes exactly the commit the CLI staged`: with a window open, a `git commit` of the same
       files by hand is refused by `gate commit --from-hook`; the CLI's commit passes; a second commit in the same
       window is refused; at the commit stage no carve out applies.
     - `repair: the checks ran again on the new tree`: the integration record names the repair commit as its head, and
       the Build verdict names the new tree.
     - `repair: a behaviour finding stays open without a RED and a GREEN on an unchanged test file`.
     - `repair: close resolves only the ids a recheck row written after the commit confirms`; a `fixed` row written
       before `repair commit` counts for nothing.
     - `repair: a worse result is reverted`, one each: a row that passed fails; the open blocking findings are not
       fewer; the recheck names a new blocking finding; the recheck did not complete.
     - `repair: a large diff gets a full Review, not a revert`.
     - `repair: one by rule, one more on the click, then gone`, and
       `repair: the same finding open after a repair is not recommended again`.
     - `repair: a spent budget still offers the four ways on`: Accept a finding, Override and continue, Loop back to
       Build and Save for later.
     - one assertion a row of the Check table of mechanism 11.
     - `repair: the commit gate passes a Review verdict that differs from the commit by closed repairs only`, and
       fails it when a repair between them has no completed recheck.
  3. Rewrite, and list in `docs/plans/one-go/changed-tests.md`: the first label at a failed Review or Check
     (`scripts/selftest/temper-cases-8.sh:111, 172, 177`, `temper-cases-13.sh:126`, `temper-cases-15.sh:361, 521`),
     the policy cases (`temper-cases-28.sh:12-20`, by now cases of the default run), the small change cases of
     `temper-cases-9.sh`, `-11.sh` and `-15.sh` that name the window's guard fact.
  4. `scripts/e2e/scenarios.ts`: `coverage-drop` (the function `coverageDrop`) of WP19 now asserts the repair in
     place (no call
     `state loop check build`). `scripts/e2e/replay.ts final` with the floor `replay` (`D58`): the High defect is
     repaired in its stage, 0 loops are recommended and Plan is launched once.
  5. `tests/mod`: `repair start` typed by an agent or the session is refused; inside a repair window a write to a file
     outside the plan is refused with the scope drift text, and a write to a planned file passes; a small change
     window still allows any path. Update the label pins at `guard.test.ts:146, 285`,
     `dialog.test.ts:93, 106, 143, 149, 330`, `view.test.ts:95-98, 169-176`, `hardening.test.ts:463`.
- **Mechanism:** the design is `docs/plans/one-go/evidence/v-repair-in-place.md`, section 7; the conditions are
  blocker B2 of `docs/plans/one-go/evidence/red-safety.md`, carried here in full. No prototype diff exists: the file
  `docs/plans/one-go/evidence/prototypes/v-repair-in-place-exp-work.diff` is empty. The verifier ran three facts in a
  clone: a change at Review keeps Build's ledger and verdict (X2), `integrate` runs again at the Review stage when
  HEAD moved (X3), and the hook refuses a code commit at Review (X5b).
  0. **Two facts first, in a clone, before any code of this package.** (a) Under the CLI's lock run `git commit`
     with the installed hook: if `gate commit --from-hook` waits on the lock, step 6.5 writes the token under the
     lock, releases it, commits, and takes the lock again to clear the token and record the commit. (b) Install the
     guardrails pack's hooks and make one commit from a script as the CLI will: note whether it is asked. Write
     both results into `docs/plans/one-go/PROGRESS.md`.
  1. **Where the code goes.** All of it in `scripts/repair_ops.py`, standard library only. `scripts/temper` gets the
     word `repair` with `start`, `test`, `commit`, `close`, `revert` and `status`, each one line in the form WP02 set,
     under the CLI's lock, with the identity arguments of `_git_id_args` for a commit.
  2. **The whole finding.** `cmd_evidence_add` (`scripts/temper:1513-1577`) takes `--detail`, `--fix` and
     `--proof test|none` with `--stage review` and a `--severity`. The reviewer sets them (`agents/review.md:35-39`);
     the fixer cannot change `proof`, it can only contest (`scripts/findings.py:124-132`), which keeps the finding
     open for the person. Today a finding is one claim line, cut to 300 characters by the loop
     (`scripts/loop_step.py:115`) and to 200 by the prompt (`scripts/flow.py:1258-1262`); the repair prompt cuts
     nothing.
  3. **Who opens the window: only the CLI, by `repair start --stage review|check`.** One function, `can_start`, holds
     every condition, and the flow, the question and the call all ask it. All must hold:
     - the stage's gate failed, and every failed row is on the repairable list: `no blocking findings` (open findings
       at or above `review.block-on`), and at Check a red suite, a scenario row or an `acceptance evidence` row whose
       failure record has the class `code`;
     - Review recorded its completion (`review completed` passes, with the read list of WP18);
     - HEAD is the `head` of `review_snapshot` and the tree is clean (`tree_key` of WP22 equals the tree of HEAD);
     - no stage of the run was skipped or overridden;
     - the budget of WP10 has room for this failure and for the run;
     - the run is a `/temper:temper` run on its own branch whose Build was integrated; a fix run never repairs by rule
       (its Fix agent commits nothing, so no reviewed HEAD exists);
     - nothing of the never by rule list (mechanism 12) holds.

     It then spends one step of the budget (`python3 scripts/budget.py spend`; the key is the budget key of the
     failure, its record's `scope`, as `docs/plans/one-go/contracts.md` section 8 says), and writes `repair` into
     the run state:

     ```
     {"n": 1, "stage": "review", "base": "<HEAD>", "base_tree": "<tree>", "findings": [3], "rows": ["..."],
      "before": {"blocking": 1, "passed": ["<row names>"]}, "ledger_rows": 12, "ts": "..."}
     ```

     It opens the window with `adhoc_ops.open_window` (`scripts/adhoc_ops.py:83-97`) and the mark `kind: repair`.
  4. **The fixer.** A new method `repair_work` beside the fix pass (`scripts/flow.py:1655-1672`) launches one agent of
     type `temper:temper-build`, a fresh one, with the findings in full, the failed rows with their kept output from
     `scripts/failure.py`, the open findings it must not touch, and the line `Repair in place:`. The brief
     (`agents/build.md`, a section beside "A group fix", `:27-35`): fix exactly what is named; for a finding with
     `proof: test` write the test first and run `temper repair test ID --phase red -- <command>`, then the code, then
     the same call with `green`; commit nothing; change no file outside the plan and no locked acceptance test; never
     accept, override or skip; when the fix needs the plan or the intent changed, stop and say so. Its `after` calls:
     `usage add`, `repair commit`.
  5. **`repair test`.** The CLI runs the command through the runner. A RED counts when it fails on an assertion, by
     the rule of the task gate (`red_ok`, `scripts/task_ops.py:194-196`); the row carries the repair number, the
     finding id and the hashes of the test files the command names. A GREEN counts only when those hashes are
     unchanged.
  6. **`repair commit`, the CLI's.** The agent commits nothing. In this order:
     1. Refuse when HEAD is not `repair.base`: a commit the CLI did not make stops the run, as in Build.
     2. List the changed files as `close_window` does (`scripts/adhoc_ops.py:119-128`). None changed: record
        `changed: 0`, close the window, launch no recheck; the run asks (the rule of `scripts/group_fix.py:79-86`).
     3. Every changed file must be in `approved_files` or match the test pattern of `scripts/temper:4174`, and none
        may be in the spec folder, the config, the git folder, a locked acceptance test, a dependency manifest or
        lockfile, a CI file, or under a sensitive path (the one matcher, `match` of `scripts/sensitive.py`, which
        WP11 made). One that is: nothing is committed, the change stays in the
        working tree, and the run asks the Scope drift question (`scope.drift`) for that file.
     4. The one test rule: a diff that deletes a test file, or removes a line from a test file that existed at
        `repair.base`, is never resolved by rule. Nothing is committed and the run asks, showing the removed lines;
        the options are Revert the repair (recommended), Loop back to Build, Save for later. The question has the
        id `repair.stop`, and the first option the id `revert-repair`; the other two keep the ids of the head
        (`back`, `save`).
     5. Stage exactly those files, write `repair.token = {"parent": HEAD, "tree": <git write-tree>}`, commit with the
        message `fix(<slug>): repair N at <stage>`, clear the token, record the commit in `repairs` of the run state
        and in `cli_commits` of `.temper/groups.json`, close the window, and take the Review snapshot again
        (`_review_code save`, as `scripts/temper:4615-4620` does after a small change).
     6. Run again, by the CLI on the new tree: `integrate` (the rerun of `scripts/temper:3316-3331`, which since WP23
        holds the suite, every scenario test, the interfaces, the locked acceptance tests with their digest unchanged,
        and coverage), then `gate build`; at Check also `check run`. Every result is recorded, and the call exits 0 on
        a recorded verdict: a failed `after` call is a hand back (`hooks/temper-mod/core/driver.ts:432`).
  7. **The hook's carve out.** In the commit gate, beside the checkpoint carve out (`scripts/temper:4066-4110`): the
     gate passes with the one row `repair commit` when a token is set, HEAD is the token's parent, the staged tree
     (`git write-tree`) is the token's tree, the run is at Review or Check on its own branch, and every staged file is
     approved or a test. Anything else meets the whole gate. One commit a window: the token is cleared after the
     commit. It never applies to the final commit: `repair start` refuses at the commit stage, so no token exists
     there. The carve out lives in the CLI, which the installed hook calls (`gate commit --from-hook`), so a hook
     installed by 9.8.5 gets it with no new install (`D64a`: it still blocks a commit under a failed gate). `D64b`:
     when this build changed the hook body (`scripts/guards/install.sh:167-272`), `setup_calls`
     (`scripts/cli_ctx.py:106`, the hook tests at `:117-129`) tests for one string only the new body has and asks
     for `temper guards install`. The bash twin `_setup_calls` (`scripts/temper:4551-4555`) was dead code at the
     head and went with WP02, so the live function is the one to change.
     When no package changed the hook body, `D64b` asserts that a hook of 9.8.5 is not asked to install again. Row
     `D64` of `docs/plans/one-go/done.md` states both cases, and its case reads from `git diff 10e965a` of the
     installer which of the two holds.
  8. **The recheck.** A section `Re-check:` in `agents/review.md`, as `agents/plan-review.md:49` has for the plan; no
     new agent. Launched by the flow after `repair commit`, on Sonnet at effort medium, with `check ahead` as its
     `before` call (`scripts/flow.py:1375-1378`). The CLI writes the diff from `repair.base` to the repair commit into
     the spec folder and records a launch mark (the ledger row count and the time), as the plan review does
     (`scripts/fresh_review.py:165-190`). Input: that diff whole, the findings the repair answers with the fixer's
     note, the findings still open, the CLI's results on the new tree. Three questions and no other lens: is each
     finding fixed; did the changed lines add a defect; was a test weakened or removed. Its rows: `recheck #ID: fixed`
     with exit 0 or `recheck #ID: not fixed` with exit 1, new findings only on changed lines, and one completion row
     that names the changed files with `--read` and the count of ids checked. A row counts only when it was written
     after `repair commit` and after the launch mark. A diff over 300 changed lines, or one that touches a file no
     finding names, gets a full Review in place of the recheck, not a revert. A repair at Check gets the same recheck
     whenever a file that is not a test changed, and `gate review` is computed again.
  9. **`repair close`.** For each finding of the repair, resolved means all of: a `fixed` row that counts; the reruns
     of step 6.6 passed on the repair tree; for `proof: test` a RED before the fix and a GREEN after it by the CLI on
     unchanged test files. The CLI then calls the resolve function of WP18 inside itself with `fixed_by` the repair
     commit, and adds the fifth condition there (a recheck row written after the commit). No model calls
     `evidence resolve`. From WP18 until this package that call refuses every commit
     (`docs/plans/one-go/README.md` section 4); the repair commit recorded here is the first it takes. Then it
     compares with `repair.before` and reverts (step 10) when: a row that passed before
     the repair fails after it; the open blocking findings are not fewer; the recheck names a new blocking finding;
     the recheck did not complete.
  10. **`repair revert`.** The CLI's own commit that restores `repair.base_tree` (a token with the repair commit as
      parent and the base tree, through the same carve out). It checks that the tree of the new HEAD equals
      `base_tree`, runs `integrate` and `gate build` on it (the pass is reused by its key), takes the snapshot again,
      records the revert in `repairs`, and the run asks one question that names what broke (the same id,
      `repair.stop`).
  11. **A failure at Check.** The table of `docs/plans/one-go/evidence/v-repair-in-place.md`, section 6, holds. A red
      suite, a scenario row or an acceptance evidence row of class `code`: one repair by rule; the fixer gets the
      failed row with its whole kept output; no new failing test is asked for, the CLI's failed row is the RED. A
      measured coverage drop: one repair by rule; a diff of test files alone needs no recheck. A locked acceptance
      test: only when the triage blames the code. The planted bug score: never by rule (it is information since WP19).
      After WP23 most of these are found at Build, so Check's repair is the small case.
  12. **Never by rule.** `can_start` refuses, and the run asks, for: a contested or accepted finding; a finding whose
      fix needs a file outside the plan, or the plan or the intent changed; an unfinished Review; the row
      `no code changed at Review`; an environment fault (SETUP); a check that was not measured; a criterion only the
      person can confirm; a locked acceptance or regression test the triage does not blame on the code; a failure
      whose class is not `code`; anything under a sensitive path, and any run whose plan touches one (risk H: named in
      the approval, nothing there is repaired by rule); a diff that removes test lines.
  13. **The budget.** One repair by rule a stage (Review, Check), counted in the one budget of WP10 with no exemption
      a caller can set. One more on the person's click, the option "Repair again" (the id `repair-again`, move
      `repair`, the call `repair start --stage S --again`); then the option is gone. The same finding or the same
      failed row open after a
      repair is not recommended again (`same_failure`, `scripts/flow.py:756, 856`). With the budget spent the question
      offers Accept a finding, Override and continue, Loop back to Build and Save for later: the loop back stays as
      the way out and is never taken by rule.
  14. **The flow.** `repair_opt` beside `back_opt` (`scripts/flow.py:588-593`); the move `repair` in `MOVES`
      (`:58-59`); in `core_next`, before the rule move and before `self.ask(stage)` (`:2468-2473`), an `auto` action
      with the call `repair start` whenever `can_start` holds, in every mode; then `repair_work`, the recheck with the
      `after` calls `usage add`, `repair close`, `gate review`, and the stage's gate. The rule of WP11 that loops back
      to Build once for a blocking finding is replaced by the repair. The failed Review (`:792-808`), the passed
      Review with an open blocking finding (`:779-788`) and the failed Check (`:874-875`) offer Repair again while the
      budget allows.
  15. **Verdict and tree.** WP22 gave each verdict the tree it judged. After a closed repair every gate ran again, so
      Build, Review and Check name the repair tree. Review's entry also keeps `reviewed` (the tree the full Review
      read) and `repairs` (the numbers between). The commit gate's tree row passes when each verdict is of the
      committed tree, or of a tree that differs from it only by repair commits the CLI recorded whose reruns passed
      and whose recheck completed. Any other difference fails it and names both trees.
  16. **The card.** Each repair is an entry of the rule log with the kind `repair`, appended to
      `.temper/rule-log.json` through `scripts/rule_log.py append` and to no other writer, and shown by the card
      section `rule_log` of `scripts/card.py`, where this package adds its rows: the finding's text, the files
      and the count of lines changed, the recheck's answer, and the revert when there was one.
  17. **The mod.** `repair start` is person only unless it is the CLI's own action
      (`hooks/temper-mod/core/rules.ts:460-461, 476-497`); `repair commit`, `close` and `revert` pass only as calls of
      the action the view names. A repair window applies Build's write rule (`:292-305`) in place of the `ALLOW` of
      the small change window (`:252`): the view's guard gets `adhoc_kind` (`scripts/flow.py:2832`), read at
      `hooks/temper-mod/core/runview.ts:73, 219` and `hooks/temper-mod/adapter.ts:218`. No host call is added.
- **Removed:** the loop back to Build as a rule move for a blocking finding; the forced failing test for a finding
  that has no behaviour to test (it came from the wipe of the ledger at a step back,
  `scripts/temper:1876-1896, 3633-3645`); the cut of a finding to 200 characters in a repair prompt.
- **Documents in the same change:** a new decision record,
  `docs/decisions/0021-a-finding-is-repaired-in-its-stage.md` (the number of `docs/plans/one-go/contracts.md`
  section 11; extended later by WP25, which adds its decision to it): a finding is repaired in its
  stage; a verdict is of the tree it judged or of a tree whose difference the CLI checked and a reader rechecked; it
  amends ADR 0009 (a second carve out) and ADR 0011 resolution 1 (the list of commits the CLI makes in an unattended
  run), and says that ADR 0012 point 3 still holds for a step back. Its line of amended records is the one of
  `docs/plans/one-go/contracts.md` section 11: 0009, 0011 and 0013. Then `docs/flow.md` (the Review and Check
  sections, the list of what a rule may do), `docs/trust.md` (what resolves a finding; what the recheck does not
  prove: a defect outside the changed lines is caught only by the CLI's runs), `reference/review.md`,
  `reference/check.md`, `reference/autonomy.md`, `commands/temper.md` (the line on a finding), the header of
  `templates/temper.config.default` (`:138-141`), `.claude/CLAUDE.md` (Known mistakes: a finding is resolved by
  `repair close`, never by a brief), `CHANGELOG.md`.
- **Done when:** `bash scripts/verify.sh quick` is green;
  `bun scripts/e2e/run.ts all repair-finding repair-worse coverage-drop` passes; neither the two listed scenarios nor
  `D37b`, `D37c`, `D64a` and `D64b` are left on `scripts/selftest/expected-fail.txt`;
  `bun scripts/e2e/replay.ts final` passes;
  `python3 scripts/check_floor.py` holds with `repair-finding.dialogs` at 2 and one full Review launch;
  `python3 scripts/check_caps.py` holds; the mod's three checks pass;
  `git grep -n "evidence resolve" agents commands reference` prints nothing.
  The rows this package turns green are listed under its id in "Rows by package" of `docs/plans/one-go/done.md`;
  that section wins over this list.
- **Traps:**
  1. `repair commit` holds the CLI's lock while git runs the hook, and the hook starts a second CLI process for
     `gate commit --from-hook`. Whether this call waits on the lock (the depth count of `scripts/temper:396` is per
     process) is decided by step 0 of the mechanism, before any code: if it does, the commit is made after the lock
     is released and the token is written under it.
  2. The guardrails pack has a second commit hook inside the agent (`scripts/guards/block-uncommitted-gate.sh`). The
     CLI's own `git commit` is no tool call, so it should not be asked; no verifier ran it. Decided by step 0 of
     the mechanism. Run one repair with the pack's hooks installed before this package is called done.
  3. The fixer must not be able to write the recheck's rows early. The order rule of step 8 is the hold without the
     mod; do not rely on telling the agents apart.
  4. The narrow recheck reads the diff, not the code around it. A project with a thin suite gets less than a second
     full Review gave; `docs/trust.md` must say so, and the fall back to a full Review must stay.
  5. Labels move at the failed Review and Check questions: regenerate both fixture files (the views `review-fail`,
     `check-fail` and the unattended ones) and fix the pinned labels in one commit.
  6. The caps: this package adds one option label ("Repair again"), one question site (the repair stop, with the
     one new question id `repair.stop`) and one gate row (`repair commit`). Each must take the place of one that
     went; a cap this package cannot meet is written to
     `docs/plans/one-go/PROGRESS.md`, never raised.
  7. `scripts/stops.json` lists the stops an unattended run keeps. Every entry of the never by rule list is one; add
     each with the name of its assertion, or `case 46 D76` fails.
  8. A run saved by 9.8.5 at Review with an open finding (`D60d`) has findings with no `detail` and no `proof`. Treat
     a missing `proof` as `none` and a missing detail as the claim; never refuse the repair for it.
  9. `scripts/repair_ops.py` is a new script: run `bash scripts/validate-directory.sh` before the commit.
- **Size:** L.

## WP25 The plan amendment, the plan patch, and a replan that keeps

- **Goal:** A plan fault that a narrow change repairs costs no replan. `plan amend`, by rule and logged so, only adds
  to a task a file the same group already owns. `plan patch` is the person's: every command line and every file
  outside the approved set. The approved record is appended to and never overwritten, a group with no Validate fails
  the plan gate, and a full replan keeps the built tasks whose approved fields did not change.
- **Depends on:** WP08, WP10 (the budget), WP11, WP12 (the approval's digests and its record), WP15
  (`scripts/card.py`), WP21 (a patched command runs once on the base), WP23 (the failure record and its kinds
  `blocked-task` and `no-validate`), WP24 (the sensitive path rule it shares, on the matcher `scripts/sensitive.py`
  that WP11 made).
- **Lane:** `flow core`.
- **Touches:** `scripts/plan_amend.py` (new), `scripts/plan_patch.py`, `scripts/approval.py` (`plan_digest`),
  `scripts/tasks_md.py`, `scripts/plan_rows.py`,
  `scripts/temper` (`cmd_plan`, `_plan_digest`, `_go_back`, `_groups_reset`, the step that leaves Plan),
  `scripts/groups_ops.py`, `scripts/task_ops.py` (the kept refs), `scripts/flow_run.py`, `scripts/flow_build.py`
  (`parked`, `group_failed`), `scripts/card.py`, `hooks/temper-mod/core/rules.ts`, `tests/mod/guard.test.ts`,
  `scripts/selftest/temper-cases-20.sh`, `-29.sh`, `-45.sh`, `-46.sh`, `scripts/selftest/expected-fail.txt`, both view
  fixture files, `scripts/e2e/scenarios.ts`, `scripts/stops.json`, `agents/plan.md`, `agents/build-task.md`,
  `docs/flow.md`, `docs/grouped-build.md`, `docs/commands.md`, `reference/autonomy.md`, the two decision records
  `docs/decisions/0019-a-run-that-asks-twice.md` and `docs/decisions/0021-a-finding-is-repaired-in-its-stage.md`,
  `scripts/flow_base.py` (`OPTION_IDS` gains `add-file`), `CHANGELOG.md`.
- **Tests first:** `docs/plans/one-go/contracts.md` section 10 reserves case file 66 for this package; its cases go
  into the files 20, 29 and 46, as below, and 66 stays unused unless a case needs a file of its own.
  1. From the list of WP07, made to pass here: `case 46 D26a` (the amendment and each refusal), `D26b` (a command line
     and a file outside the approved set are refused by `plan amend` and taken by `plan patch`), `D26c` (the approved
     record is byte equal before and after an amendment and a patch; `amendments.json` gains one entry each), `D26d`
     (the row for a group with no Validate; a replan keeps an unchanged built task), and `case 45 D39c` (an amendment
     by rule is on the commit card).
  2. `scripts/selftest/temper-cases-29.sh`, names `amend:`. One assertion a refusal: the plan is not approved;
     `tasks.md` differs from the current plan; the file is declared by no other task of the group; it is declared only
     by a task of another group; it is not in `approved_files`; it is a test file another task declares; it is under
     the acceptance folder of the spec; it is under a sensitive path; the task is running; the task passed; a static
     row fails on the result (then `tasks.md` is byte equal to before); the budget has no room. And:
     `amend: the result adds one file and one Depends entry and nothing else` (the field by field compare prints two
     lines); `amend: the ledger row says amended by rule and never the person`;
     `amend: the task is reopened and the owner's work is kept` (the owner's commit is still on the group branch, the
     owner is still passed); `amend: plan_hash moved in the state and in groups.json`.
  3. Same file, names `patch:`: `patch: fix_empty, fix_tries and fails are reset` (U1);
     `patch: a missing Validate line is inserted`; `patch: a changed Test line reopens its passed task`;
     `patch: a failed static row refuses the patch and restores the file` (U2);
     `patch: --add-file takes a file outside the approved set and adds it to approved_files`;
     `patch: the ledger row does not say by the person`;
     `patch: the question and the card show the command word for word`.
  4. `scripts/selftest/temper-cases-20.sh` (the plan rows): `group validate command fails a group with no Validate`
     and passes the demo plan; `the three digests are one function` (U24: a grep finds one definition).
  5. A new block in the same file or in `-46.sh`, names `replan:`: after `state loop build plan` and a new plan in
     which Task 1 is unchanged and Task 2 has a new Test line, the approval restores Task 1 as passed with its commit
     on the group branch, and Task 2 runs again; a changed group Depends restores nothing of that group or of the
     groups that depend on it; a kept task whose commit is no longer in the kept ref is not restored.
  6. `scripts/e2e/scenarios.ts`, scenario `blocked-task-amended` (the function `blockedTaskAmended`), three modes:
     a scripted task agent records
     `task blocked` for a file an earlier task of its group declares. Assert: no question, no launch of
     `temper:temper-plan`, the task runs again and passes, the commit card lists the amendment. Scenario
     `blocked-outside-plan` (the function `blockedOutsidePlan`), plain mode: the file is declared by no task; the
     run asks, and the scripted answer takes the option `add-file`, whose call is
     `plan patch task N --add-file F`.
  7. `tests/mod/guard.test.ts`: `plan patch` typed by an agent stays refused (`rules.ts:481`); `plan amend` typed by
     an agent passes the guard, and the CLI's own refusals are what hold it.
- **Mechanism:** the split is blocker B3 of `docs/plans/one-go/evidence/red-safety.md`; the steps are section 4 of
  `docs/plans/one-go/evidence/v-failure-budget.md`. Where the two differ the red team wins: `plan amend` is not a
  person only call, because its whole effect is bounded by the CLI whoever calls it.
  1. **One digest (U24).** The digest has three copies at the head: `_plan_digest` (`scripts/temper:2163-2174`),
     `digest` (`scripts/plan_patch.py:25-35`) and `plan_core_digest` of the flow. The one function is `plan_digest`
     of `scripts/approval.py`: WP12 moved the digest there first (`docs/plans/one-go/contracts.md` section 14), so
     no second one is put into `scripts/tasks_md.py`. Have every copy that is left call it;
     `scripts/selftest/temper-cases-29.sh:8` keeps guarding it.
  2. **The record.** `evidence/approved-tasks.json` is the plan as the person approved it. It is written at the
     approval (`scripts/temper:1144`) and at a later approval only (a replan's, or the Design answer of `:1185-1209`),
     never by an amendment or a patch. A new file `.temper/evidence/amendments.json`, a list, is appended by both
     calls:

     ```
     {"n": 1, "ts": "...", "kind": "amend | patch", "what": "Task 4 gains src/a.py", "old": "...", "new": "...",
      "hash_before": "...", "hash_after": "...", "failure": "F3", "reopened": [4]}
     ```

     `plan_hash` in the run state and in `.temper/groups.json` moves to `hash_after`, so `_plan_fresh` (`:2179-2196`)
     holds. `approved_files` does not move for an amendment (the file is in the set already: that is the rule); a
     patch that adds a file appends it. The mod guards the folder already (`hooks/temper-mod/core/rules.ts:110`).
  3. **`temper plan amend task N --add-file F [--failure ID]`**, in `scripts/plan_amend.py`. The caller passes no
     text: the CLI writes Task N's `**File:**` line with F added and its `**Depends:**` line with the owner added, as
     the row `file ownership` forces (`scripts/plan_rows.py:99-123`). It refuses unless all hold:
     - the plan is approved and `tasks.md` has the digest of the current plan (the test of
       `scripts/plan_patch.py:102-111`);
     - another task M of the same group declares F, and F is in `approved_files`;
     - F is not a test file M declares (the pattern of `scripts/temper:4174`), not a locked acceptance test, and not
       under a sensitive path (`match` of `scripts/sensitive.py`);
     - Task N is neither running nor passed (a blocked task is parked, `scripts/temper:3147-3149`);
     - the field by field compare of the result with the current plan (the logic of `tasks_change_summary`,
       `scripts/flow.py:155-181`) shows `Task N gains F` and the new Depends entry and nothing else: no group, no
       group Depends, no command and no other task differs, and no task that passed loses a file;
     - `plan_rows.py` and `gate_rows.py plan-rows` pass on the result; on a failed row the file is restored;
     - the budget of WP10 has room; the call spends one step with the key `task:<N>` and the kind `plan amend`
       (`python3 scripts/budget.py spend`). The budget has keys and kinds and no classes
       (`docs/plans/one-go/contracts.md` section 14).

     Then it writes the file in one rename, moves the two hashes, appends the entry, writes the plan ledger row
     `plan amended by rule: Task N gains F (Task M declares it)` with a label that is not `PERSON`, and reopens Task N
     through `_group_reopen_body` (`scripts/temper:2603-2776`). The reopen starts with `_plan_fresh` (`:2639`), so it
     runs after the hashes moved. It clears `blocked`, the group's gate and the integration verdict, and resets
     `fails`, `fix_tries` and `fix_empty`. The Depends on M is what keeps the reopen's restore from undoing M's work.
  4. **Where the rule takes it.** In `parked`, the blocked branch (`scripts/flow.py:2095-2111`): when every blocked
     record (`scripts/task_blocked.py:55-56`) names an owner and `plan_amend.can` holds for each, the next action is
     `auto` with the `plan amend` calls, in every mode; it is the CLI's own action and it is on the card, as an
     entry of the rule log with the kind `amend`, appended through `scripts/rule_log.py append`. When it does
     not hold, the run asks. A file no task declares: the first option is "Add the file to the task" (the id
     `add-file`), the person's `plan patch task N --add-file F`. A file of a later task or of another group, and a
     group parked twice with no
     blocked record: the first option is Loop back to Plan, which is the person's and which an unattended run never
     takes. WP27 later puts a narrow revision behind that option.
  5. **`plan patch`, completed.** It stays the person's (`hooks/temper-mod/core/rules.ts:481`). Changes in
     `scripts/plan_patch.py`: reset `fix_empty`, `fix_tries` and `fails` of the patched group beside the gate
     (`:123-124`); insert a `**Validate:**` line after the group's `**Depends:**` line when `patch_lines` finds none
     (`:70-77`); reopen a passed task whose Test line changed; a new form `task N --add-file F` for a file outside the
     approved set; run the two static row scripts on the result and refuse on a failed row; append the entry; write
     the ledger row as `plan patch: <what>: <old> -> <new>` with no claim of who called. After the call the flow runs
     `baseline plan` of WP21 so the new command runs once on the base. Every question that offers a patch shows the
     old command, and the card shows the new one word for word. Whether a patch spends the budget is what WP10 wrote
     for it; add no flag that exempts a call.
  6. **The row.** In `scripts/plan_rows.py`, beside `integration command` (`:195`): the row `group validate command`
     fails for each group whose `validate` is empty (`scripts/tasks_md.py:83`). The prototype is row 1 of
     `docs/plans/one-go/evidence/prototypes/v-failure-budget-static-rows-proto.py`. Today the fault is first seen at
     the group gate (`scripts/temper:2481-2482`). The other three rows of that prototype are not built: no measured
     run has shown their fault.
  7. **A replan keeps.** Today a step back to Plan archives `.temper/groups.json` and moves each group branch to
     `refs/temper/kept/<slug>/replan-<ts>/<G>` (`_groups_reset`, `scripts/temper:1297-1328`), and Build starts from
     nothing. Add `temper group keep`, called by the first Build action after the new approval. For each group of the
     new plan it reads the archived record and the new plan. A task is kept when its files, Depends and Test are equal
     to the archived plan's (the fields of the digest), every task it depends on is kept, and its group's Depends, and
     the groups those name, are unchanged and fully kept. For a group with at least one kept task it brings the branch
     back from the kept ref (`scripts/task_ops.py:306-310`), resets it to the commit of the last kept task in order
     (`commit` in the task record, `scripts/temper:3256`), and restores those task records as passed with their
     entries of `cli_commits`. The group's gate verdict is kept only when every task of the group is kept and its
     Validate and Interfaces are equal. Everything else runs as a new group does. The summary line of the approval
     card says how many tasks are kept.
- **Removed:** the words "by the person" from the ledger row of `plan patch`; the recommendation of Loop back to Plan
  for a blocked task whose file its own group owns; the reset of every built task at a replan.
- **Documents in the same change:** `docs/flow.md` (the blocked task, the group question, the replan),
  `docs/grouped-build.md` (what a replan keeps), `docs/commands.md` (`plan amend`, `plan patch` with its forms,
  `group keep`), `reference/autonomy.md` (the closed list: a rule may add to a task a file the same group already
  owns, and nothing else of the plan), `agents/plan.md` (a group needs a Validate), `agents/build-task.md` (when to
  record `task blocked`), the header of `templates/temper.config.default` (`:138-141`: "never plans again by itself"
  stays true and gains the one exception by name), the decision record that holds the closed list
  (`docs/decisions/0019-a-run-that-asks-twice.md`: this package adds the one exception to its decision 3), the
  record `docs/decisions/0021-a-finding-is-repaired-in-its-stage.md` that WP24 made (this package adds its
  decision on `plan amend` and `plan patch` to it), `CHANGELOG.md`.
- **Done when:** `bash scripts/verify.sh quick` is green, and `bash scripts/verify.sh full` is green at the end of
  the phase (this package ends phase 6); `bun scripts/e2e/run.ts all blocked-task-amended` and
  `bun scripts/e2e/run.ts plain blocked-outside-plan` pass; `grep -c "D26\|D39c" scripts/selftest/expected-fail.txt`
  prints 0; `python3 scripts/check_caps.py` holds (the new row takes the place the `preflight` row left);
  `claude plugin test .` passes; `cmp` of `evidence/approved-tasks.json` before and after an amendment in the scenario
  prints nothing.
- **Traps:**
  1. Without the mod any caller can run either call. `plan amend` is safe then because its effect is bounded;
     `plan patch` is not, and that is today's state. Do not write "by the person" anywhere the CLI cannot know it;
     `docs/trust.md` says only the mod checks the click.
  2. A task that gains a file a passed task wrote can lose that task's work at the reopen unless it depends on it. The
     static rows force the order only when they run on the result: run them before the reopen.
  3. `fresh_review.task_hashes` (`scripts/fresh_review.py:146-162`) hashes a task block's text, and the CLI ticks a
     box inside the block. Do not use it to tell a kept task; use the digest's fields.
  4. A group's worktree base is fixed at `group start` (`scripts/temper:2419`). A kept group whose dependencies were
     rebuilt has a stale base: that is why a changed dependency keeps nothing downstream.
  5. Step 7 has no prototype and no verifier ran it. Build it in a clone on the two group fixture first, and check
     with `git log` that a restored branch holds only commits of `cli_commits`; `integrate` refuses any other
     (`scripts/temper:3361-3378`).
  6. The view's plan and its fixtures change when `tasks_change_summary` reads the amendments: regenerate both fixture
     files, and keep the view at version 1 (add fields, rename none).
  7. `scripts/plan_amend.py` is a new script: run `bash scripts/validate-directory.sh` before the commit. The row of
     step 6 counts against the cap on gate rows.
  8. An existing case states the old behaviour on purpose: `scripts/selftest/temper-cases-29.sh:12` wants "a person's
     row is kept". Rewrite it and list it in `docs/plans/one-go/changed-tests.md`.
- **Size:** L (M without step 7).
