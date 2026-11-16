# Phase 0 and phase 9: setup and the final verification

This file holds the specs of work packages WP00 (setup and baseline, the first package) and WP32 (the final
verification, the last package). How the session works in between is in `docs/plans/one-go/session-mechanics.md`.
The brief is `docs/plans/one-go/README.md`; the names both packages use are those of
`docs/plans/one-go/contracts.md`.

## WP00 Setup and baseline

- **Goal:** The build branch exists: `main`, the head of pull request 115 and the plan with its kit, merged and not
  copied. The tools are proven, and the numbers of the untouched head are on record, so every later number has a
  "before". The draft pull request is open.
- **Depends on:** none.
- **Lane:** `flow core` (serial, first; it edits no flow file, but nothing may start before it).
- **Touches:** `docs/plans/one-go/PROGRESS.md` (new: this package creates it, and every later package only updates
  it; WP01 adds its numbers and does not create the file). Nothing else.
- **Tests first:** none to write. This package changes no behaviour; its check is that every suite of the head is
  green on the merged tree before anything is changed. The dry run of 2026-11-16 found them green (the table in
  `docs/plans/one-go/session-mechanics.md` section 2); a red line now is news, not noise.
- **Mechanism:**
  1. **The branch.** Run the commands of `docs/plans/one-go/session-mechanics.md` section 1, part 1 and 2: fetch
     `main`, `ccr-88156f39-u643ta` (the plan and the kit) and `refs/pull/115/head` (pull request 115: the pull ref
     stays when its branch `ccr-e0b10914-a7hzu0` goes); stay on the branch the session was given, which starts
     from `origin/main` (`7c7a1c1`), or make one from there only when none was named;
     `git merge --no-ff --no-edit 10e965a`; then
     `git merge --no-ff --no-edit origin/ccr-88156f39-u643ta`. Rehearsed in a clone: no conflict in either merge.
     Merge the plan branch at its tip: `8477375` holds only the plan, `65c7d42` adds the evidence, and the kit is
     a later commit.
  2. **Check the result.** `git merge-base --is-ancestor 10e965a HEAD` exits 0. `git diff --stat 10e965a HEAD`
     names only files under `docs/plans`. `ls docs/plans/one-go` shows `README.md` (the brief), `contracts.md`,
     `done.md`, `pr-115-fixes.md`, `session-mechanics.md`, `wp` and `evidence`. `.claude-plugin/plugin.json` says
     version 9.8.5: the base already carries the number the result keeps, and no package bumps it (the brief,
     section 3, decision 7).
  3. **The tools.** Part 3 of the same section: the versions, then the mod's types through Claude Code 2.1.287
     (`timeout 120 npx -y -p @anthropic-ai/claude-code@2.1.287 claude -p "hi" --plugin-dir . || true`: the load
     has a time limit and may fail, as the CI step it copies), then `tsc -p tsconfig.mod.json`. Write the versions
     into the head of the baseline table.
  4. **The baseline.** `scripts/verify.sh` does not exist yet (WP01 writes it), so run the commands of `full` by
     hand, each as its own command, and note the result line and the seconds of each. Run the two long ones in the
     background, one after the other, never at once:
     - the validators: `quality-check.sh`, `validate-docs.sh`, `validate-readme.sh`, `validate-plugin.sh`,
       `validate-panels.py`, `validate-directory.sh`, `selftest/test-validate-directory.sh`, `check-mod-calls.sh`,
       `selftest/test-check-mod-calls.sh`, `check-known-limits.sh`;
     - `bash scripts/selftest/run-selftest.sh` (every case file, in parallel; background);
     - `bun scripts/e2e/run.ts all` (23 scenarios in 3 modes, one process; background, limit 90 minutes);
     - `claude plugin test .` and `claude plugin validate --strict .`;
     - `bash scripts/e2e/ab-replay.sh` (the table of 9.8.4 against the base);
     - the bytes of the five large files: `wc -c` on `scripts/temper`, `scripts/flow.py`, `CHANGELOG.md`,
       `scripts/selftest/view-fixtures.ts` and `scripts/selftest/view-fixtures-2.ts`.
  5. **Compare with what is known.** Fast tier of the selftest: 837 assertions. Case files 1, 2 with 3, 4, 7 and
     8 with 9: 214, 502, 248, 22 and 278. The serial total in CI: 2,575. The mod: 1774 tests in 40 files. End to
     end: 69 lines that start with `PASS` and a mode, and 23 lines that say the flow is identical with the mod
     and without it. The replay: 8, 8 and 4 questions; 10, 7 and 7 launches; 191, 92 and 92 agent minutes. Bytes:
     `scripts/temper` 260,504; `scripts/selftest/view-fixtures.ts` 259,060; `CHANGELOG.md` 246,956;
     `scripts/flow.py` 205,631. A number that differs goes under "Found on the way" with both values.
  6. **`PROGRESS.md`.** Create it, in the exact format of `docs/plans/one-go/session-mechanics.md` section 5: the
     head, the baseline table, one line for each of WP00 to WP32 (all `todo`) in the build order of
     `docs/plans/one-go/README.md` section 5 (WP18 and WP14 stand before WP11), the empty lists.
  7. **Commit, push, open.** The rhythm of `docs/plans/one-go/README.md` section 4, with one difference: here the
     package commit holds only `PROGRESS.md`, with the subject `docs(wp00): the baseline of the one pass build`.
     Then the small progress commit sets WP00 to `done` with the hash of the package commit. Then one push for
     both. Open the draft pull request (section 7 of the mechanics file) and write its number into the head of
     `PROGRESS.md` with the next commit.
  8. **The watch.** Schedule the first hourly check (section 12 of the mechanics file).
- **Removed:** nothing.
- **Documents in the same change:** `docs/plans/one-go/PROGRESS.md` only.
- **Done when:**
  - `git log --oneline --merges -2` shows the two merges, and `git diff --name-only 10e965a HEAD` prints only paths
    under `docs/plans`.
  - Every line of the baseline table says pass, with its seconds; or a red line is named under "Found on the way"
    with the first failing check and its text.
  - `test -f .claude-plugin/types/claude-code/index.d.ts` and `tsc -p tsconfig.mod.json` both exit 0.
  - The branch is on `origin`, the pull request is a draft against `main`, and its number is in `PROGRESS.md`.
  - The table "Packages" of `PROGRESS.md` has 33 lines, WP00 to WP32 in the build order, and the line of WP00 says
    `done` with the hash of the package commit.
- **Traps:**
  - Fix nothing here. A red suite on the untouched head belongs to the package that owns the fault (WP08 for a
    defect of pull request 115); WP00 only records it.
  - The shell tool ends a foreground command after 10 minutes. The parallel selftest and the end to end suite take
    longer on 4 CPUs (the timings are in the mechanics file, section 2 and 3): start them in the background.
  - With Claude Code 2.1.325 the plugin load of `.github/workflows/quality.yml:116` wrote no types folder in the
    dry run, and `tsc` then fails with `TS2688: Cannot find type definition file for 'claude-code'`. That is the
    missing folder, not a type error.
  - `.claude-plugin/types/` is ignored (`.gitignore:58`); it must never be in a commit.
  - The local clone may be shallow. `scripts/e2e/ab-replay.sh:9` checks out `7c7a1c1` into a work tree and fails
    with an unknown revision when the commit is not there: `git fetch --unshallow origin` first.
  - `scripts/e2e/ab-replay.sh:12-13` adds a git work tree under `/tmp` and removes it on exit. A run that was
    killed leaves the entry: `git worktree prune`.
  - `gh` had an invalid token on the planning machine. Open the pull request with the GitHub tool of the session.
  - The first push starts a CI run of 30 to 60 minutes, and so does every later push until WP01 adds the cancel.
    Do not wait for it.
  - If the session was started on a branch that already holds the kit, do not make a second branch: merge
    `10e965a` there. Push only to the branch the session was given.
- **Size:** S.

## WP32 Final verification, adversarial review, a real run, the pull request text and the summary

- **Goal:** The branch is proven done or says exactly where it is not: `bash scripts/verify.sh final` is green on a
  fresh work tree, `scripts/selftest/expected-fail.txt` has no entry, agents that wrote none of the code tried to
  break each of the eleven rules and what they could reproduce is fixed, the replay and the migration checks hold,
  the bench ran with its model test or the pull request says in plain words that cost and time are not measured,
  and the pull request text carries the scorecard. One run with a real model was made, or the summary says in
  plain words that none was. The owner gets a summary of what happened, as a file and as the last message.
- **Depends on:** WP01 to WP31. A package that is `blocked` does not stop WP32: its open rows go into the text.
- **Lane:** `flow core` (serial, last: a fix that a review finding needs may touch any file).
- **Touches:** `scripts/e2e/ab-replay.sh`, `scripts/e2e/replay_compare.py` (new), `scripts/verify.sh` (two steps
  of the `final` mode, which WP07 made), `scripts/check_done.py` (two rules of `--final` and the mode
  `--summary`), `scripts/e2e/live-smoke.sh` (one check, `approval`), one new case file
  `scripts/selftest/temper-cases-80.sh` (the number `docs/plans/one-go/contracts.md` section 10 reserves for this
  package), the case files 81 to 89 for the checks the reviewers add, `scripts/e2e/accept.ts` (the scenarios the
  reviewers add), `docs/evidence/ab-replay-9.8.5.md` (rewritten in place: at the base it compares 9.8.4 with the
  base), `CHANGELOG.md` (the measured lines of the one 9.8.5 entry), `docs/history/build-9.8.5.md` (new, written
  last) and `docs/history/README.md` (its pointer), `docs/plans/one-go/PROGRESS.md`,
  `docs/plans/one-go/changed-tests.md`,
  `docs/plans/one-go/evidence/` (removed), and whatever the fixes of the review touch. Only when the bench ran:
  `bench/run-all.sh` (one variable), `docs/evidence/scorecard-9.8.5.json`, `docs/evidence/bench-9.8.5.md` and
  the folder `docs/evidence/bench-9.8.5/` (all new), and the one line on cost and time of the product's
  `README.md`. Only when the model test changes the default: the default
  table of WP27 in `scripts/cli_ctx.py`, `agents/plan.md` (its `model:` line), the two cases that state the
  table in `scripts/selftest/temper-cases-46.sh` and `scripts/selftest/temper-cases-71.sh`, and the live line
  `plan: opus` of `templates/temper.config.default` and of `.claude/temper.config` with its case in
  `scripts/selftest/temper-cases-73.sh`, `scripts/caps.json` and the key table of `docs/commands.md`.
- **Tests first:** in the new case file `scripts/selftest/temper-cases-80.sh`; every name starts with `final:`.
  Each is written, seen failing and made to pass inside the first commit of this package, so none goes on the
  expected to fail list.
  1. `final: the replay compare fails when this tree is worse than the base`. The call is
     `python3 scripts/e2e/replay_compare.py BASE.json THIS.json`, with two made up result lines of
     `scripts/e2e/replay.ts` (the keys read at `scripts/e2e/ab-replay.sh:24-34`): exit 0 when every counted number
     of THIS is at or under BASE; exit 1 and the name of the row when `questions` is one higher; exit 1 when
     `shipped` is false; exit 1 when `defect_in_commit` is true. This is the check of row `D59` of
     `docs/plans/one-go/done.md`. It fails today: `ab-replay.sh` prints a table and exits 0 whatever the numbers.
  2. `final: cli_seconds and mvn_calls are printed and never compared`. The same call with only those two higher
     exits 0. The first is machine time and follows the load of the machine. The second is not a row of the
     published table (`docs/evidence/ab-replay-9.8.5.md:26-35`, the page as the base has it), and the baseline
     of WP20 adds a run on purpose.
  3. `final: check_done --final fails while a package line is todo or doing`. A made up `PROGRESS.md` in a
     throwaway folder with the line of WP17 `doing`: exit 1 and the id. All lines of WP00 to WP31 `done` or
     `blocked`: this rule passes, whatever the line of WP32 says.
  4. `final: check_done --final fails while the evidence folder is tracked or cited by code`. A throwaway git
     folder with one tracked file under `docs/plans/one-go/evidence`: exit 1; without it: this rule passes.
  5. `final: verify.sh final runs the replay against the base`. A grep of `scripts/verify.sh` finds the call
     `scripts/e2e/ab-replay.sh 10e965a` in the `final` mode. `full` has run the same replay since WP05 for its
     base column. The compare that fails on a worse number stays in `final` only: the case also asserts that the
     call carries `--base-only` in every mode but `final`.
  6. `final: check_done --summary holds the form of the summary` (row `D107`). A made up summary and a made up
     plan in a throwaway folder. Exit 0: the eight headings of `docs/plans/one-go/contracts.md` section 8 in
     their order, at most 150 lines, and in part 3 one line for each item id of the made up plan with one of the
     three states. Exit 1 with the name of what is wrong: a heading missing or out of order, 151 lines, an item
     id with no line, a line with none of the three states, no file. The case also greps `scripts/verify.sh`:
     the mode `final` runs the call when `docs/history/build-9.8.5.md` exists and prints
     `OPEN: the summary of the build` when it does not.
  7. `final: the live smoke knows the word approval and runs nothing unless it is switched on`. With
     `TEMPER_E2E_LIVE` unset, `bash scripts/e2e/live-smoke.sh approval` prints that it is off and exits 0, and
     the usage line of the script names `approval`. What the check does with a model has no case: it is the
     block "A real run" of step 7.
- **Mechanism:**
  1. **Take stock.** Read `PROGRESS.md`. Every line of WP01 to WP31 is `done` or `blocked`. For each `blocked`
     line collect its rows of `done.md` and its entries on the expected to fail list: they are the section "Not
     done" of the pull request text. Run `python3 scripts/check_done.py` and keep its output. Read the follow up
     lines WP08 copied from `docs/plans/one-go/pr-115-fixes.md` section 3: each is ticked or marked dropped, and
     one that is still open goes under "Not done" too.
  2. **The replay gate (`D58`, `D59`).** Move the table code of `scripts/e2e/ab-replay.sh:19-43` into
     `scripts/e2e/replay_compare.py`: it prints the same table and exits 1 when THIS is worse than BASE. Counted,
     lower or equal: `questions`, the length of `manual_repairs`, `agent_launch_total`, `agent_minutes_estimate`,
     the length of `loops_recommended`, `setup_clicks`. Must hold: `shipped` true, `defect_in_commit` false.
     Printed only: `mvn_calls`, `cli_seconds`, `version`. If WP11 removed the `REPLAY_POLICY` branch
     of `scripts/e2e/replay.ts:27`, the third column (`ab-replay.sh:17`) goes with it. `full` has called
     `bash scripts/e2e/ab-replay.sh 10e965a` since WP05 and has checked only its base column against the entry
     `replay_base` of the floor. Give the script the flag `--base-only`: with it the table is printed and the
     result of the compare is not returned. In `scripts/verify.sh` the call carries that flag in the mode `full`
     and not in the mode `final`, where a worse number fails. WP07 made that mode with its closing checks; this
     is one of the two steps this package adds to it (the other is the check of the summary, step 3).
     Then the page. `docs/evidence/ab-replay-9.8.5.md` exists at the base, where it compares 9.8.4 with the
     base and calls the base "9.8.5". Rewrite it in place as one page with one table of three columns: 9.8.4
     (`7c7a1c1`), the base (`10e965a`) and the result. The first column is the base column of
     `bash scripts/e2e/ab-replay.sh 7c7a1c1`, the second the base column of
     `bash scripts/e2e/ab-replay.sh 10e965a`, the third the column `this` of the second call. Write the text
     under the table new: what is replayed, how to run it again, what the replay does not show, and one line
     that says whether any counted number of the result is above that of 9.8.4. Only the compare against the
     base is a gate (`D59`); the column of 9.8.4 is printed. No second replay page is made.
  3. **The final rules of `scripts/check_done.py --final`** (tests 3 and 4): no line of WP00 to WP31 in the table
     "Packages" of `docs/plans/one-go/PROGRESS.md` is `todo` or `doing`; `git ls-files docs/plans/one-go/evidence`
     prints nothing; no tracked file outside `docs/plans/one-go` names that folder.
     The mode `--summary` (test 6) reads `docs/history/build-9.8.5.md` and `docs/plans/two-approval-run.md`. It
     exits 1 when the file is missing, has more than 150 lines, lacks one of the eight headings of
     `docs/plans/one-go/contracts.md` section 8 or has them in another order, or when part 3 has no line for an
     item id of the plan or a line there holds none of the three states. An item id is one digit and one
     letter at the start of a list item under the plan's headings `### Release 0.` to `### Release 7.`, as in
     `- **2e. The approval runs to the commit.**`: 44 ids, `0a` to `7e`. A comma follows the id of `0a`
     (`- **0a, first, as its own small change on main.**`), a period every other. The entries `Pass line`,
     `Room under the file limit`, `Documents in this release` and `Go or no go` are not items. A line of part 3
     is a table row whose first cell is the id. In `scripts/verify.sh` the mode `final` runs the call when the
     file exists and prints `OPEN: the summary of the build` when it does not: the file is written in step 11,
     after the first green `final`.
     The check `approval` of `scripts/e2e/live-smoke.sh` (test 7) is written here too; the block "A real run" of
     step 7 says what it does.
     Commit steps 2 and 3 with
     their tests after a green `quick`. From here to step 10 `final` is red on the evidence rule by design, so the
     gate of the steps between is `full`.
  4. **The expected to fail list.** It must hold no entry. For each entry left: the package that owns it is not
     done. Go back to that package if its dependencies allow; else the line stays and the pull request text names
     it. A line is never deleted to empty the list: `check_done.py` fails on a listed check that passes and on a
     check that fails unlisted.
  5. **The adversarial review.** Eight reviewers, each a fresh agent that gets none of the package specs and none
     of the session's notes: only its rules in the words of the brief (`docs/plans/one-go/README.md` section 6),
     `docs/plans/one-go/done.md`, the work tree, and the diff of its slice
     (`git diff origin/main...HEAD -- <paths>`). Two at a time. Each is told: try
     to break the rule in a throwaway project with the real CLI; a finding counts only with a reproduction, as a
     new selftest case (helpers of `scripts/selftest/case-helpers.sh`, in a case file numbered 81 to 89, which
     `docs/plans/one-go/contracts.md` section 10 keeps for these checks) or a new scenario
     (`scripts/e2e/accept.ts`) that fails on this branch; give a level (High: a rule of the eleven is broken;
     Medium: a promise of `done.md` is not met; Low: the rest); change no file but the new check.

     | Reviewer | Rules | Where to dig |
     |---|---|---|
     | 1 | 1 and 2 | what a run writes before the approval; the digests of the intent and the plan; a change after the approval |
     | 2 | 3 and 4 | every way an unattended run starts and ends; each word of the never list against every `auto` action of `next` |
     | 3 | 5 and 6 | who records a run; whether each verdict names its tree; a failure class that turns into a verdict; "not measured" shown as passed or failed |
     | 4 | 7 and 8 | the lock on the acceptance tests; `evidence resolve`; the repair commit, the recheck and the revert |
     | 5 | 9 and 10 | every repeat that is not counted; the budget after a step back; what the commit question lists |
     | 6 | 11 | every rule again in plain mode; a rule that only `hooks/temper-mod/core/rules.ts` holds |
     | 7 | the tests | `git diff 10e965a -- scripts/selftest tests/mod scripts/e2e` against `changed-tests.md`; `git log -p` of `expected-fail.txt`, `scripts/caps.json`, `scripts/e2e/floor.json`, `scripts/stops.json`; a check that can never fail |
     | 8 | migration and surface | a user of 9.8.4 after the upgrade, and then a project that ran the base: the old config, a saved run, the installed commit hook, the one time question and notice, the removed commands; the README of at most 80 lines and Getting Started followed word for word |

     The conductor runs each new check itself. Reproduced: fix it in the serial lane, the check and the fix in one
     commit whose message quotes the failing line seen before the fix; the fix is written by an agent that did not
     write the check. Not reproduced: listed in the pull request text under "Claimed by the review, not
     reproduced". Then one second round: two fresh reviewers read only the fix commits. A High finding that is
     still open after it stays in the text, first line. Run `full` after the last fix.
  6. **Migration (`D60` to `D65`).** `TEMPER_CASES_ONLY=46 bash scripts/selftest/test-temper.sh` ends `FAIL: 0`
     and its output names `D60a` to `D60e`, `D61a`, `D61b`, `D62a` to `D62c`, `D63b`, `D64a`, `D64b` and `D65` on
     no failing line. The cases of `D60` to `D64` run first on what 9.8.4 left (`7c7a1c1`, what users have) and
     second on what the base left. Then one walk by hand of what the cases cannot show, made twice: in a throwaway
     folder outside the repository, make a project with the config template of
     `git show 7c7a1c1:templates/temper.config.default`, and a second one with that of
     `git show 10e965a:templates/temper.config.default`. In each
     call `scripts/temper next --json` of the new tree, and read the first question as a user would: it is the one
     time config question, in plain words, with a way to say no. Read the one time notice too, in a project
     that an earlier run left, as the case of row `D102` makes one: one line that starts
     `Temper 9.8.5 asks twice`. Put both texts into the pull request, and the name of every saved state of
     9.8.4 that row `D60` let end in the restart question.
  7. **The bench and the model test (`D90` to `D98`).** Apply the rule of the mechanics file, section 9: the bench
     runs when the owner's first message says it may, on the access that message names. Then `npm install` in
     `bench`, and `TEMPER_BENCH_RESULTS` set to a folder outside the repository, one folder for each of the three
     rounds: a graded run is not run again (`bench/run-all.sh:13`), and the name of a run's folder holds only the
     task, the arm and the repetition (`:12`). The six tasks and the commands are those of
     `docs/plans/one-go/done.md`, note 1: three runs a task and arm, one run at a time. In this order:
     - **(a) The round before:** the bench tasks on `10e965a` and on plain Claude Code (the arms `temper` and
       `vanilla`), from a work tree of `10e965a` whose `bench` folder is replaced by this tree's. The harness is
       the measuring tool, only the plugin under test differs, as `scripts/e2e/ab-replay.sh:14` does it for the
       replay.
     - **(b) The round after:** the same tasks on the result with the default config, the planner on Opus.
     - **(c) The model test:** the same tasks once more on the result, with the planner on Sonnet below risk H:
       the config lines `models.plan: sonnet` and `models.high.plan: opus` (the second keeps Opus at risk H, as
       the changed table would), which `bench/run.mjs` takes as `--config-yaml` (`:119-131`).
       `bench/run-all.sh` hands no config line on: give it one variable for it, `BENCH_CONFIG_YAML`. The
       scorecard reads the folder of this round as a third arm.
     - **(d) The rule,** fixed before the round: the default table changes to Sonnet below risk H only if, against
       (b), hidden tests are equal, rules met stay at least 95%, and blocked tasks and steps back to Plan do not
       rise. Else Opus stays.
     - **(e) If it changes:** one small commit that changes the default table of WP27 with its test: the
       `standard` value of `plan` in `scripts/cli_ctx.py`, the `model:` line of `agents/plan.md`, which the case
       `w27 the model table` holds equal to it, and the value that case and the case of row `D28` expect, each
       listed in `docs/plans/one-go/changed-tests.md`. The `high` column keeps Opus. A config line wins over the
       table, and the template of WP29 holds the live line `plan: opus` under `models`: in the same commit that
       line becomes a comment in `templates/temper.config.default` and in this repository's `.claude/temper.config`,
       so a new project follows the table. The case `w29 the template has 10 live lines` then expects 9,
       `config_live_keys` of `scripts/caps.json` follows the measure, and the key table of `docs/commands.md` is
       made again with `temper config show --markdown`. Then the two anchor tasks
       once more on that commit (`vague-refunds` and `partial-payments`, the feature tasks of
       `docs/plans/one-go/evidence/evidence-bench.md` section 2.1), then `final` as step 10 runs it.
     - **(f) The text:** the pull request text shows the scorecard of all arms and says which planner the release
       ships with and why. The lines of part H (`D90` to `D96`) are read from the arm of that planner: round (b)
       when Opus stays, round (c) when the default changed (`--arm` of `bench/scorecard.py --gate`, WP05).
     - **(g) The README:** only now may the product's `README.md` state a figure. Its one line on cost and time
       gets the figures of the scorecard and names `docs/evidence/scorecard-9.8.5.json`; the page stays at 80
       lines or under (`D108`). The line keeps its start, `**Cost and time:**`, and stays the only such line:
       the case `w31 the README has its parts` of WP31 holds that, and it must stay green. If the line count
       of the page moved, write the new `now` of `readme_lines` in `scripts/caps.json` in the same commit.
       With no bench the line stays as WP31 wrote it: where the earlier measurements are, and no figure.

     All three cost about 110 to 125 dollars and 9 to 11 hours, one run at a time (the two rounds about 80 dollars
     and 6 hours, the model test about 30 to 45 dollars and 3 to 5 hours). After each task copy its
     `run.json` and `grade.json` files into `docs/evidence/bench-9.8.5/` and commit, so a restart pays for no run
     twice. Then `python3 bench/scorecard.py --gate docs/evidence/scorecard-9.8.5.json` and the write up
     `docs/evidence/bench-9.8.5.md`. In these names 9.8.5 is the result; the round before is of the base and is
     called so in the write up. A missed line of part H is reported with its numbers and is not tuned away
     (`done.md`, note 2). If the Agent SDK cannot use the access the message names: one line under "Blockers",
     and part H stays open. With no such sentence in the first message: nothing is run, `final` prints its
     `OPEN:` line, and the text of step 8 carries the words given there. The session never asks for a key.

     **A real run (`D109`).** Every check of `done.md` but part H uses scripted agents, so one run with a real
     model is wanted before the summary is written. In this order of preference:
     - **One: the bench ran.** Its runs are the proof. Report from the `run.json` and `grade.json` files of the
       round whose planner ships: runs made, runs that reached the commit, hidden tests passed, and the dialogs
       and launches of each run.
     - **Two: the bench could not run, but the owner's first message allowed model use and a nested `claude -p`
       answers.** Run `TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh approval`, the check this package wrote
       in step 3. It builds a scratch project outside the repository: a small Python service with a passing
       suite, as `seed` of the script builds one (`scripts/e2e/live-smoke.sh:52`), with its config, the `.temper`
       scaffold of `temper init` and one commit, and with no run started. Then one headless session with the
       plugin and one clear request, `claude -p "/temper:temper \"<request>\"" --plugin-dir <plugin>`, with the
       permissions and the limit of the check `fresh` (`:123-124`). The request names the file, the function,
       its exact behaviour and where its tests go, so that it leaves no rule open. The session cannot answer a
       dialog, so it must end at the approval. The check reads what the run left and passes when:
       `.temper/asked.json` holds one question and its id is `plan.approve`; `.temper/view.json` holds a `card`
       of the kind `approval`; the spec folder holds `intent.md` and `tasks.md`; and the project is as rule 1
       wants it: the branch and the commit count are as at the start, and `git status --porcelain` names
       nothing outside `.temper/` and the baseline worktree `.claude/worktrees/temper-baseline`. It runs twice,
       with the mod (the plugin as it loads) and without it (`--settings '{"disableAllHooks": true}'`), and
       both legs must end in that state. When Claude Code prints that it did not load the mod, the leg with the
       mod fails, as in the check `fresh` (`:126-128`). A model words a plan differently each run, so the check
       compares outcomes, never text. A leg that fails is a finding of the level High. When its cause is in
       the tree (a brief, the command page, a call of the CLI), repair it in the serial lane and run that leg
       once more; report both runs. A cause that was not found goes under "Not done", first line. Two runs a
       leg at most. This proves the front half only (Intent, Plan, the approval card and rule 1 with a real
       model): say so wherever the result is told.
     - **Three: neither.** No run with a real model is made, and the summary and the pull request text say so
       in plain words.

     The older checks of the script (`start`, `fresh`, `cost`) are not part of this proof and are not run here.
     They were written for the plan question of the base (`fresh` seeds a run with `temper intent accept`,
     the call WP12 and WP13 change), and nothing in this build shows that they still pass on the result. Say
     so in one line of the script's header comment, beside the line for `approval`, and name it under "Found
     on the way": bringing them up to the result is the owner's to order.
     Write which case happened and what it showed into `PROGRESS.md`, under "Found on the way"; part 8 of the
     summary (step 11) and the pull request text take it from there.
  8. **The pull request text.** Every number in it is pasted from the output of a command, none is typed from
     memory. It holds every part `docs/plans/one-go/README.md` section 8 names. Its title stays
     `Temper 9.8.5: a run that asks twice`. In this order:
     - **Summary:** parts 1, 2 and 6 of `docs/history/build-9.8.5.md` in short, and the path of the file. The
       draft of this step leaves the place open; step 12 fills it once step 11 has written the file.
     - One paragraph: what a user sees change, that is what a run does now, in run units (two dialogs, repairs in
       the stage, checks once).
     - The line `Supersedes pull requests 115 and 116; their commits are inside this one.` Pull request 115 is
       the 16 commits up to `10e965a`; pull request 116 is the plan and the kit (branch `ccr-88156f39-u643ta`).
       Closing both is left to the owner.
     - **The number.** One sentence, said once and nowhere else in the text: the release removes commands and
       changes the default run, which a major version would usually mark; the owner chose the number 9.8.5.
     - **What a user of 9.8.4 must know:** users have 9.8.4, so this part is about them. The commands that went,
       what an old config and a saved run do, the installed commit hook, and the texts of the one time config
       question and of the one time notice from step 6. Then one line for a project that ran the head of pull
       request #115: what it had that is gone (the policy key, the preflight, the environment agent).
     - **Decisions:** the list of the settled decisions of the brief's section 3, one line each.
     - **Scorecard.** Per part of `done.md` (A to J): rows that hold, rows open, from `check_done.py --final`. The
       floor: for `default-run`, `fix` and the replay, the value at `10e965a` (the baseline of WP00), now, and the
       final. The caps: each key at `10e965a`, now, and the final (`check_caps.py --final`). The replay table of
       step 2. The suites: totals and seconds of the last `final`, beside the baseline of WP00.
     - **Cost and time.** With a bench: the lines of part H from the scorecard file, the scorecard of all arms
       (plain Claude Code, the base, the result on Opus, the result on Sonnet below risk H), and which planner the
       release ships with and why, by the rule of step 7 (d). Without, these words:

       ```
       Cost and time are not measured. The first message of the build session did not allow the bench, so part
       H of the definition of done (rows D90 to D98) is open. Every dollar and second in the plan is still a
       target. The model test was not run: the planner stays on Opus, and the cost line for a clear feature is
       then expected to miss (about 2.7 times, not 2). The two rounds and the model test cost about 110 to 125
       dollars and 9 to 11 hours; the commands are in docs/plans/one-go/done.md, note 1.
       ```
     - **A real run:** which of the three cases of the block "A real run" of step 7 happened and what it
       showed; in the second case, that it proves the front half only (row `D109`).
     - **Not done**, **Claimed by the review, not reproduced**, **Found on the way** (from `PROGRESS.md`), and
       **Changed tests** (the list of `changed-tests.md` with the reason for each, its count and where to read
       it).
     - **Not built in this pass:** what the brief's section 9 leaves out, by name.
     - **Three sample cards** (the approval, the commit, a stop), as row `D23` of `done.md` asks, and one line on
       the looser Interfaces check (U23 of `docs/plans/one-go/pr-115-fixes.md`), so the choice is the owner's.
     - **For the owner to do:** every item of the brief's section 10 (the two README videos, the price figures,
       the bench, a cap or a floor recorded as not met); mark ready and merge; push the tag; close
       pull requests 115 and 116; change a branch rule that names the old CI checks (WP01); the manual list of
       `docs/mods-testing.md`; order the bench if it did not run; decide what stays of `docs/plans/one-go`.
     - **How to check this yourself:** `bash scripts/verify.sh final`, with its seconds.
  9. **The commit that removes the working papers.** `git rm -r docs/plans/one-go/evidence`, and the line of
     WP32 in `PROGRESS.md` set to
     `done`; nothing else. The plan says the working papers are not part of the repository
     (`docs/plans/two-approval-run.md`, appendix A). This is where WP32 differs from the rhythm of
     `docs/plans/one-go/README.md` section 4 (the package commit, then the small progress commit, in one push):
     for this package alone there is no separate progress commit after this one, and
     the Commit cell of WP32 holds the hash of the commit before this one. The subject is
     `docs(wp32): the working papers leave the tree`. The earlier commits of this package (steps 3, 5 and 7)
     each follow the gate their step names. Only the commit of the summary (step 11) comes after this one.
  10. **The gate on a fresh tree.** `git worktree add --detach ../final-check HEAD`, make the types there (mechanics
      file, section 1), and run `bash scripts/verify.sh final` there in the background with a limit of 90 minutes.
      A file that exists only in the main work tree and was never committed shows up here and nowhere else. Green:
      push. Red: repair in a new commit and run it again; the removal is not done twice. This run prints
      `OPEN: the summary of the build`, by design: the summary is the next step.
  11. **The summary of what happened (`D107`).** Written last, after the green `final` of step 10, because its
      numbers come from that run. The file is `docs/history/build-9.8.5.md`: at most 150 lines, with front
      matter as the other files of `docs/history` have it. It is for the owner, who did not follow the build,
      so it is in plain words: no package id without its title, no row id of `done.md` without what the row
      proves, no word of this kit that the product's documents do not use. Every number is pasted from the
      output of a command or from a committed file. A cell with no measured source says `not measured`, never
      a target of the plan. Its eight parts stand under the eight headings of
      `docs/plans/one-go/contracts.md` section 8, word for word and in this order:
      - **In five lines.** What Temper does now that it did not do before.
      - **The numbers, before and after.** One table: the number, before, after, where it comes from. Before is
        the base, and 9.8.4 too where a number of it exists (the replay). The rows: the dialogs of a clean
        feature run (`default-run` of the floor), of a clean bug run (`fix`) and of a run with one repaired
        High finding (`repair-finding`); the bound on repeats; the agent launches of a clean feature run; the
        whole suite runs on the slow project (`slow-first-run`); the replay of the measured bad run (questions,
        launches, agent minutes and the High defect, from the page of step 2); and cost and time against plain
        Claude Code, from the scorecard when the bench ran, else the words `not measured`. The last cell of
        each row says which it is: a scripted run, the replay, or the bench.
      - **The plan, item by item.** One table row for every item of releases 0 to 7 of
        `docs/plans/two-approval-run.md`, 44 rows from `0a` to `7e`: the id, the item in a few words, one of
        `built and proven`, `built and not proven` or `not built`, and then for the first the check that proves
        it, said in words (what the check does, not its row id alone), and for the other two the reason. The
        table at the end of this step is the kit's reading of which package builds an item and which rows
        prove it; what in fact holds is read from `PROGRESS.md` and from `python3 scripts/check_done.py --final`.
        Every row of the item is `ok`: built and proven. Its package is `done` while one of its rows is
        `open`, still on the list or recorded as wrong: built and not proven. Its package is `blocked`, or the
        brief's section 9 leaves it out: not built. Where the last column of the table names something, the
        line says it in a few words. This part is the owner's proof that everything of the plan is there:
        write no state that the two sources do not show.
      - **What changes for someone who used 9.8.4.** The commands that went and the two that stay; the config
        (the old file still works, the one time question, the copy it keeps); the first run after the upgrade
        (the one line notice, a saved run, the installed commit hook). One line for a project that ran the
        head of pull request #115.
      - **What went differently from the plan.** From `PROGRESS.md`: packages that needed a second attempt,
        specs that were wrong, checks recorded as wrong, caps or floors that were not met, anything dropped.
      - **What is not done, and what is yours to do.** The part "Not done" of the pull request text in short,
        and the items of the brief's section 10.
      - **The build in numbers.** Counted from the second merge of WP00, so that neither pull request #115 nor
        the kit counts as work of the build: the days from the first commit to the last, the packages done and
        blocked, the commits (`git rev-list --count <that merge>..HEAD`), the tests added (the totals of the
        `final` of step 10 beside the baseline of WP00), the lines added and removed
        (`git diff --shortstat <that merge> HEAD`, and the same without `docs/plans`), and the CI runs of the
        pull request with their median wall time.
      - **Was it run for real.** Which of the three cases of the block "A real run" of step 7 happened and what
        it showed, with its numbers. In the second case: that it proves the front half only. In the third
        case these words: `No run with a real model was made. Every check of this build used scripted agents.`

      Add the pointer to `docs/history/README.md` in that file's own style. Then
      `python3 scripts/check_done.py --summary` exits 0 and `bash scripts/verify.sh quick` is green. Commit the
      two files as `docs(wp32): the summary of the build` and push. This is the one commit after the `final` of
      step 10; it changes nothing but those two files and is not run through `final` again.

      | Item | Built by | Rows whose checks prove it | What no check shows |
      |---|---|---|---|
      | 0a | WP01 | `D87` | the minutes of CI are `D88`, read off the pull request |
      | 0b | WP08; the line a finished run leaves is WP05 | `D41` to `D57`; `D100` | the 29 smaller points are `D106`, a list for the owner |
      | 1a | WP01 | `D87` | `D88` |
      | 1b | WP05 (the scorecard), WP06 (the two scripted projects) | `D11`, `D13`; the scorecard has its own test on made up runs | real runs, unless the bench ran |
      | 1c | WP32, only when the bench was allowed | `D93`, `D98` | without the bench: not built |
      | 1d | WP19 | `D35`, `D12` | none |
      | 1e | WP29 | `D71`, `D61`, `D62`, `D63` | none |
      | 1f | WP04 | `D16` (its case of ids), `D65` | none |
      | 1g | WP05 | `D09`, `D66` to `D69`, `D72`, `D75`, `D79` | none |
      | 2a | WP09 | `D07` | none |
      | 2b | WP10 | `D08`, `D38` | none |
      | 2c | WP14 | `D20` | none |
      | 2d | WP13; the flagged map WP15 | `D01`, `D02` | none |
      | 2e | WP11 | `D16` to `D19`, `D32`, `D33` | that a person and not the model clicked: only the mod holds it |
      | 2f | WP12 | `D30`, `D31` | none |
      | 2g | WP13 | `D01`, `D04` | none |
      | 2h | WP18 | `D34`, `D37` | none |
      | 3a | WP15 | `D22`, `D02` | `D23`: nobody timed a reader |
      | 3b | WP16 | `D06`, `D78`, `D101` | none |
      | 3c | WP17 | `D03` | none |
      | 3d | WP17 | `D25` | none |
      | 3e | WP12, only if the plugin directory takes the hook | `D30`, `D40` | when the hook was dropped: not built, and `docs/trust.md` says so |
      | 4a | WP23 | `D21`, `D36` | none |
      | 4b | WP24 | `D05`, `D37`, `D39` | a real fix agent may not mend the finding; then the run asks |
      | 4c | WP24 | `D05`, `D33` | none |
      | 4d | WP25 | `D26` | none |
      | 5a | WP26 | `D27` | none |
      | 5b | WP26 | `D27` | that every section left has a reader |
      | 5c | WP27 | `D24` | none |
      | 5d | WP14 | `D04`, `D18`, `D20`, `D57` | none |
      | 5e | WP27 builds the table and the keys | `D28` | the cheaper planner itself: only the model test decides it (`D98`) |
      | 5f | not built: the brief, section 9 | none | it needs a bench arm of its own |
      | 5g | WP27 | `D10` | none |
      | 6a | WP20 | `D13` | another stack than the scripted Maven project |
      | 6b | WP20 | `D11`, `D12`, `D35` | a real slow build: `D97` |
      | 6c | WP21 | `D99`, `D55`, `D56` | none |
      | 6d | WP22 | `D14`, `D15`, `D34` | none |
      | 6e | WP23 | `D35` | none |
      | 6f | WP25 | `D26`, `D31` | none |
      | 7a | WP28 | `D29`, `D70` | none |
      | 7b | WP30; the default packs WP29 | `D104`, `D70` | none |
      | 7c | WP30 | `D104`, `D34` | none |
      | 7d | WP31 | `D29` | a text built only in a state no fixture holds |
      | 7e | WP31 | `D103`, `D102` | that the page is right: a reviewer follows it word for word |
  12. **Close.** Write the final pull request text with the seconds of the run of step 10; it opens with the
      summary in short, as step 8 says. Read the CI result of the last push when it arrives; a red job is
      repaired by the rule of the mechanics file, section 11. Then send the summary, whole, as the last message
      of the session: the owner reads that, not the log. Schedule no further check. The pull request stays a
      draft: marking it ready is the owner's.
- **Removed:** `docs/plans/one-go/evidence/` (42 files at `65c7d42`, more after the kit commit); the table code
  inside `scripts/e2e/ab-replay.sh` (moved); the third replay column if its switch is gone.
- **Documents in the same change:** `docs/evidence/ab-replay-9.8.5.md` (rewritten in place: the table of step 2
  in three columns and how to run it again); `CHANGELOG.md`, the one 9.8.5 entry: the measured table or the
  sentence that cost and time are not measured, and whether a run with a real model was made;
  `docs/history/build-9.8.5.md` and its pointer in `docs/history/README.md`; `docs/plans/one-go/PROGRESS.md`; the
  pull request text.
- **Done when:**
  - In a fresh work tree of the pushed head of step 10, `bash scripts/verify.sh final` ends `verify final: PASS`;
    or it ends `FAIL` only on rows the pull request text names under "Not done". The commit of the summary is
    the only one after that head.
  - `grep -cvE '^[[:space:]]*(#|$)' scripts/selftest/expected-fail.txt` prints 0, or the text lists every line.
  - `bash scripts/e2e/ab-replay.sh 10e965a` exits 0 and its table is in the text and in
    `docs/evidence/ab-replay-9.8.5.md`, which has the three columns 9.8.4, the base and the result.
  - `git ls-files docs/plans/one-go/evidence | wc -l` prints 0.
  - Every High finding of the review has its check in the tree, and that check passes.
  - `docs/evidence/scorecard-9.8.5.json` exists, `final` printed no bench failure and the text says which
    planner the release ships with and why; or the text holds the words of step 8 and `final` printed its
    `OPEN:` line.
  - `PROGRESS.md`, part 8 of the summary and the pull request text say which of the three cases of "A real run"
    happened and what it showed (`D109`).
  - `python3 scripts/check_done.py --summary` exits 0 on the pushed head, `docs/history/build-9.8.5.md` has at
    most 150 lines, and the last message of the session is that summary, whole (`D107`).
  - The pull request is a draft against `main` whose text has every part of step 8 and opens with the summary
    in short.
- **Traps:**
  - The harness of this tree must still drive the CLI of `10e965a`: `ab-replay.sh` runs this tree's
    `scripts/e2e/replay.ts` against the old plugin folder (`:14-15`, `scripts/e2e/world.ts:16-17`). After WP04 the
    scripted person selects by id and by the `recommended` field, and the base sends neither. If the base column
    stops early or shows numbers far from 8 questions, 7 launches and 92 agent minutes (plus the one Context check
    question the faithful fixtures of WP05 add), the person lost its way on the old view: give it the label as the
    way back for a view with no ids, and do not read the table until the base column is right. Every `full` from
    WP08 on has held that column equal to the entry `replay_base` of `scripts/e2e/floor.json`, so a column that
    differs here was moved by a commit after the last green `full`.
  - The column of 9.8.4 on the page of step 2 comes from the same harness on a work tree of `7c7a1c1`, and no
    `full` ever held it. The published table has 8 questions, 10 launches and 191 agent minutes for it
    (`docs/evidence/ab-replay-9.8.5.md:26-35` at the base), plus the one Context check question. If the run
    stops early or lands far from that, do not print its numbers: keep the published ones for that column and
    say on the page that they are of the page of the base.
  - `ab-replay.sh` needs `7c7a1c1` and `10e965a` in the clone and a free work tree entry; see the traps of WP00.
  - `final` takes as long as `full` and more; it is a background command. Do not run it beside the reviewers'
    suites: let the reviewers finish a round first.
  - A reviewer that is given the specs argues with the specs. Give it the rule and the code.
  - A reviewer's new scenario may assert a label text. Checks select by id (WP04); correct that before it goes in.
  - The review will find things that are true and out of scope (the "Later" list of the plan, and what
    `docs/plans/one-go/README.md` section 9 leaves out). They go under "Found on the way", not into a fix.
  - Every fix here is a change like any other: `quick` before its commit, and caps, floor and file sizes still
    hold. `scripts/temper` has little room; a fix goes into a module.
  - The bench bypasses permissions inside its scratch folder (`bench/run.mjs:154-155`) and must run outside the
    plugin folder (`bench/README.md:49`). One run can take up to 90 minutes (`bench/run-all.sh:15`); the round is
    hours. The container's home folder does not survive a restart: that is why step 7 commits the small result
    files after each task. Never commit a `transcript.jsonl`: it can pass 256 KiB.
  - The round before needs the scorecard to read runs of a CLI that sends no question ids. Try
    `bench/scorecard.py` on one run of `10e965a` before paying for 36.
  - Removing the evidence leaves citations of `docs/plans/one-go/evidence/...` in the kit's own files. They are
    code spans, not links, so `scripts/validate-docs.sh` (rule 2) stays green; no product document may cite the
    folder, and test 4 holds that.
  - Do not squash, rebase or amend to make the history pretty. The owner chooses how to merge.
  - The live smoke spends the session's model access. Run it only in the second case of the block "A real run",
    never in CI and never as a step of `final`. It is a shell script under the directory rules
    (`scripts/validate-directory.sh:17-34`): run that validator after the edit.
  - The summary is read by someone who did not follow the build. Before its commit read it once for words of
    this kit (a package id alone, a row id alone, "the floor", "the caps", "the list", "the head"): each is
    said in plain words or goes. "9.8.5" in it is the result; what the build started from is "the unmerged
    pull request #115".
  - In part 3 of the summary a row that needs a reader, a model or the owner's order is never a proof. An
    item that rests on such a row alone is `built and not proven`, with that reason.
  - 150 lines are few for eight parts and a table of 44 rows: one row an item, no blank line inside a table, and
    parts 1, 4, 5, 6 and 8 of a few lines each. A table row may be longer than 120 characters; no other line.
- **Size:** L. The review and its fixes are the open end; the bench with its model test adds about 9 to 11 hours of
  machine time when it runs. The live smoke is about ten minutes, and the summary about an hour.
