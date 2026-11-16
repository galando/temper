# Phase 0 and phase 9: setup and the final verification

This file holds the specs of work packages WP00 (setup and baseline, the first package) and WP32 (the final
verification, the last package). How the session works in between is in `docs/plans/one-go/session-mechanics.md`.

## WP00 Setup and baseline

- **Goal:** The build branch exists: `main`, the head of pull request 115 and the plan with its kit, merged and not
  copied. The tools are proven, and the numbers of the untouched head are on record, so every later number has a
  "before". The draft pull request is open.
- **Depends on:** none.
- **Lane:** `flow core` (serial, first; it edits no flow file, but nothing may start before it).
- **Touches:** `docs/plans/one-go/PROGRESS.md` (new). Nothing else.
- **Tests first:** none to write. This package changes no behaviour; its check is that every suite of the head is
  green on the merged tree before anything is changed. The dry run of 2026-11-16 found them green (the table in
  `docs/plans/one-go/session-mechanics.md` section 2); a red line now is news, not noise.
- **Mechanism:**
  1. **The branch.** Run the commands of `docs/plans/one-go/session-mechanics.md` section 1, part 1 and 2: fetch
     `main`, `ccr-e0b10914-a7hzu0` (pull request 115) and `ccr-88156f39-u643ta` (the plan and the kit); start from
     `origin/main` (`7c7a1c1`); `git merge --no-ff --no-edit 10e965a`; then
     `git merge --no-ff --no-edit origin/ccr-88156f39-u643ta`. Rehearsed in a clone: no conflict in either merge.
     Merge the plan branch at its tip: `8477375` holds only the plan, `65c7d42` adds the evidence, and the kit is
     a later commit.
  2. **Check the result.** `git merge-base --is-ancestor 10e965a HEAD` exits 0. `git diff --stat 10e965a HEAD`
     names only files under `docs/plans`. `ls docs/plans/one-go` shows `FRAME.md`, `done.md`,
     `session-mechanics.md`, `wp` and `evidence`. `.claude-plugin/plugin.json` says version 9.8.5.
  3. **The tools.** Part 3 of the same section: the versions, then the mod's types through Claude Code 2.1.287
     (`npx -y -p @anthropic-ai/claude-code@2.1.287 claude -p "hi" --plugin-dir .`), then
     `tsc -p tsconfig.mod.json`. Write the versions into the head of the baseline table.
  4. **The baseline.** `scripts/verify.sh` does not exist yet (WP01 writes it), so run the commands of `full` by
     hand, each as its own command, and note the result line and the seconds of each. Run the two long ones in the
     background, one after the other, never at once:
     - the validators: `quality-check.sh`, `validate-docs.sh`, `validate-readme.sh`, `validate-plugin.sh`,
       `validate-panels.py`, `validate-directory.sh`, `selftest/test-validate-directory.sh`, `check-mod-calls.sh`,
       `selftest/test-check-mod-calls.sh`, `check-known-limits.sh`;
     - `bash scripts/selftest/run-selftest.sh` (every case file, in parallel; background);
     - `bun scripts/e2e/run.ts all` (23 scenarios in 3 modes, one process; background, limit 90 minutes);
     - `claude plugin test .` and `claude plugin validate --strict .`;
     - `bash scripts/e2e/ab-replay.sh` (the table of 9.8.4 against 9.8.5);
     - the bytes of the five large files: `wc -c` on `scripts/temper`, `scripts/flow.py`, `CHANGELOG.md`,
       `scripts/selftest/view-fixtures.ts` and `scripts/selftest/view-fixtures-2.ts`.
  5. **Compare with what is known.** Fast tier of the selftest: 837 assertions. Case files 1, 2 with 3, 4, 7 and
     8 with 9: 214, 502, 248, 22 and 278. The serial total in CI: 2,575. The mod: 1774 tests in 40 files. End to
     end: 69 lines that start with `PASS` and a mode, and 23 lines that say the flow is identical with the mod
     and without it. The replay: 8, 8 and 4 questions; 10, 7 and 7 launches; 191, 92 and 92 agent minutes. Bytes:
     `scripts/temper` 260,504; `scripts/selftest/view-fixtures.ts` 259,060; `CHANGELOG.md` 246,956;
     `scripts/flow.py` 205,631. A number that differs goes under "Found on the way" with both values.
  6. **`PROGRESS.md`.** Write it in the exact format of `docs/plans/one-go/session-mechanics.md` section 5: the
     head, the baseline table, one line for each of WP00 to WP32 (all `todo`), the empty lists.
  7. **Commit, push, open.** The package commit holds only `PROGRESS.md`, with the subject
     `docs(wp00): the baseline of the one pass build`; the progress commit sets WP00 to `done`. Push. Open the
     draft pull request (section 7 of the mechanics file) and write its number into the head of `PROGRESS.md` with
     the next commit.
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

## WP32 Final verification, adversarial review and the pull request text

- **Goal:** The branch is proven done or says exactly where it is not: `bash scripts/verify.sh final` is green on a
  fresh work tree, `scripts/selftest/expected-fail.txt` has no entry, agents that wrote none of the code tried to
  break each of the eleven rules and what they could reproduce is fixed, the replay and the migration checks hold,
  the bench round ran or the pull request says in plain words that cost and time are not measured, and the pull
  request text carries the scorecard.
- **Depends on:** WP01 to WP31. A package that is `blocked` does not stop WP32: its open rows go into the text.
- **Lane:** `flow core` (serial, last: a fix that a review finding needs may touch any file).
- **Touches:** `scripts/e2e/ab-replay.sh`, `scripts/e2e/replay_compare.py` (new), `scripts/verify.sh` (the `final`
  mode), `scripts/check_done.py` (two rules of `--final`), one new case file `scripts/selftest/temper-cases-N.sh`
  with the next free number, `docs/evidence/ab-replay-10.0.0.md` (new), `CHANGELOG.md` (the measured lines of
  the 10.0.0 entry), `docs/plans/one-go/PROGRESS.md`, `docs/plans/one-go/changed-tests.md`,
  `docs/plans/one-go/evidence/` (removed), and whatever the fixes of the review touch. Only when the bench ran:
  `docs/evidence/scorecard-10.0.0.json`, `docs/evidence/bench-10.0.0.md` and the folder
  `docs/evidence/bench-10.0.0/` (all new).
- **Tests first:** in the new case file; every name starts with `final:`. Each is written, seen failing and made to
  pass inside the first commit of this package, so none goes on the expected to fail list.
  1. `final: the replay compare fails when this tree is worse than the base`. The call is
     `python3 scripts/e2e/replay_compare.py BASE.json THIS.json`, with two made up result lines of
     `scripts/e2e/replay.ts` (the keys read at `scripts/e2e/ab-replay.sh:24-34`): exit 0 when every counted number
     of THIS is at or under BASE; exit 1 and the name of the row when `questions` is one higher; exit 1 when
     `shipped` is false; exit 1 when `defect_in_commit` is true. This is the check of row `D59` of
     `docs/plans/one-go/done.md`. It fails today: `ab-replay.sh` prints a table and exits 0 whatever the numbers.
  2. `final: cli_seconds and mvn_calls are printed and never compared`. The same call with only those two higher
     exits 0. The first is machine time and follows the load of the machine. The second is not a row of the
     published table (`docs/evidence/ab-replay-9.8.5.md:26-35`), and the baseline of WP20 adds a run on purpose.
  3. `final: check_done --final fails while a package line is todo or doing`. A made up `PROGRESS.md` in a
     throwaway folder with the line of WP17 `doing`: exit 1 and the id. All lines of WP00 to WP31 `done` or
     `blocked`: this rule passes, whatever the line of WP32 says.
  4. `final: check_done --final fails while the evidence folder is tracked or cited by code`. A throwaway git
     folder with one tracked file under `docs/plans/one-go/evidence`: exit 1; without it: this rule passes.
  5. `final: verify.sh final runs the replay against 9.8.5`. A grep of `scripts/verify.sh` finds the call
     `scripts/e2e/ab-replay.sh 10e965a` in the `final` mode and in no other mode.
- **Mechanism:**
  1. **Take stock.** Read `PROGRESS.md`. Every line of WP01 to WP31 is `done` or `blocked`. For each `blocked`
     line collect its rows of `done.md` and its entries on the expected to fail list: they are the section "Not
     done" of the pull request text. Run `python3 scripts/check_done.py` and keep its output.
  2. **The replay gate (`D58`, `D59`).** Move the table code of `scripts/e2e/ab-replay.sh:19-43` into
     `scripts/e2e/replay_compare.py`: it prints the same table and exits 1 when THIS is worse than BASE. Counted,
     lower or equal: `questions`, the length of `manual_repairs`, `agent_launch_total`, `agent_minutes_estimate`,
     the length of `loops_recommended`, `setup_clicks`. Must hold: `shipped` true, `defect_in_commit` false.
     Printed only: `mvn_calls`, `cli_seconds`, `version`. If WP11 removed the `REPLAY_POLICY` branch
     of `scripts/e2e/replay.ts:27`, the third column (`ab-replay.sh:17`) goes with it. Add
     `bash scripts/e2e/ab-replay.sh 10e965a` to the `final` mode of `scripts/verify.sh`, after `full`.
  3. **The final rules of `scripts/check_done.py --final`** (tests 3 and 4): no line of WP00 to WP31 in the table
     "Packages" of `docs/plans/one-go/PROGRESS.md` is `todo` or `doing`; `git ls-files docs/plans/one-go/evidence`
     prints nothing; no tracked file outside `docs/plans/one-go` names that folder. Commit steps 2 and 3 with
     their tests after a green `quick`. From here to step 10 `final` is red on the evidence rule by design, so the
     gate of the steps between is `full`.
  4. **The expected to fail list.** It must hold no entry. For each entry left: the package that owns it is not
     done. Go back to that package if its dependencies allow; else the line stays and the pull request text names
     it. A line is never deleted to empty the list: `check_done.py` fails on a listed check that passes and on a
     check that fails unlisted.
  5. **The adversarial review.** Eight reviewers, each a fresh agent that gets none of the package specs and none
     of the session's notes: only its rules in the words of `FRAME.md`, `docs/plans/one-go/done.md`, the work
     tree, and the diff of its slice (`git diff origin/main...HEAD -- <paths>`). Two at a time. Each is told: try
     to break the rule in a throwaway project with the real CLI; a finding counts only with a reproduction, as a
     new selftest case (helpers of `scripts/selftest/case-helpers.sh`) or a new scenario (`scripts/e2e/accept.ts`)
     that fails on this branch; give a level (High: a rule of the eleven is broken; Medium: a promise of `done.md`
     is not met; Low: the rest); change no file but the new check.

     | Reviewer | Rules | Where to dig |
     |---|---|---|
     | 1 | 1 and 2 | what a run writes before the approval; the digests of the intent and the plan; a change after the approval |
     | 2 | 3 and 4 | every way an unattended run starts and ends; each word of the never list against every `auto` action of `next` |
     | 3 | 5 and 6 | who records a run; whether each verdict names its tree; a failure class that turns into a verdict; "not measured" shown as passed or failed |
     | 4 | 7 and 8 | the lock on the acceptance tests; `evidence resolve`; the repair commit, the recheck and the revert |
     | 5 | 9 and 10 | every repeat that is not counted; the budget after a step back; what the commit question lists |
     | 6 | 11 | every rule again in plain mode; a rule that only `hooks/temper-mod/core/rules.ts` holds |
     | 7 | the tests | `git diff 10e965a -- scripts/selftest tests/mod scripts/e2e` against `changed-tests.md`; `git log -p` of `expected-fail.txt`, `scripts/caps.json`, `scripts/e2e/floor.json`, `scripts/stops.json`; a check that can never fail |
     | 8 | migration and surface | a user of 9.8.5 after the upgrade: the old config, a saved run, the installed commit hook, the removed commands; README and Getting Started followed word for word |

     The conductor runs each new check itself. Reproduced: fix it in the serial lane, the check and the fix in one
     commit whose message quotes the failing line seen before the fix; the fix is written by an agent that did not
     write the check. Not reproduced: listed in the pull request text under "Claimed by the review, not
     reproduced". Then one second round: two fresh reviewers read only the fix commits. A High finding that is
     still open after it stays in the text, first line. Run `full` after the last fix.
  6. **Migration (`D60` to `D65`).** `TEMPER_CASES_ONLY=46 bash scripts/selftest/test-temper.sh` ends `FAIL: 0`
     and its output names `D60a` to `D60e`, `D61a`, `D61b`, `D62a` to `D62c`, `D64a`, `D64b` and `D65` on no
     failing line. Then one walk by hand of what the cases cannot show: in a throwaway folder outside the
     repository, make a project with the config template of `git show 10e965a:templates/temper.config.default`,
     call `scripts/temper next --json` of the new tree, and read the first question as a user would: it is the one
     time config question, in plain words, with a way to say no. Put its text into the pull request.
  7. **The bench (`D90` to `D97`).** Apply the rule of the mechanics file, section 9. With a credential:
     `npm install` in `bench`; set `TEMPER_BENCH_RESULTS` to a folder outside the repository; the round before
     from a work tree of `10e965a` whose `bench` folder is replaced by this tree's (the harness is the measuring
     tool, only the plugin under test differs, as `scripts/e2e/ab-replay.sh:14` does it for the replay); the round
     after from this tree; both with the commands of `docs/plans/one-go/done.md`, note 1. After each task copy its
     `run.json` and `grade.json` files into `docs/evidence/bench-10.0.0/` and commit, so a restart pays for no run
     twice. Then `python3 bench/scorecard.py --gate docs/evidence/scorecard-10.0.0.json` and the write up
     `docs/evidence/bench-10.0.0.md`. A missed line of part H is reported with its numbers and is not tuned away
     (`done.md`, note 2). Without a credential: nothing is run, `final` prints its `OPEN:` line, and the text of
     step 8 carries the words given there.
  8. **The pull request text.** Every number in it is pasted from the output of a command, none is typed from
     memory. In this order:
     - One paragraph: what a run does now, in run units (two dialogs, repairs in the stage, checks once).
     - The line `Supersedes pull request 115; its 16 commits are inside this one.`
     - **Scorecard.** Per part of `done.md` (A to H): rows that hold, rows open, from `check_done.py --final`. The
       floor: for `default-run`, `fix` and the replay, the value at `10e965a` (the baseline of WP00), now, and the
       final. The caps: each key at `10e965a`, now, and the final (`check_caps.py --final`). The replay table of
       step 2. The suites: totals and seconds of the last `final`, beside the baseline of WP00.
     - **Cost and time.** With a bench: the lines of part H from the scorecard file. Without, these words:

       ```
       Cost and time are not measured. No model credential was available to the build session, so part H of
       the definition of done (rows D90 to D97) is open. Every dollar and second in the plan is still a target.
       The round costs about 80 dollars and 6 hours; its commands are in docs/plans/one-go/done.md, note 1.
       ```
     - **Not done**, **Claimed by the review, not reproduced**, **Found on the way** (from `PROGRESS.md`), and
       **Changed tests** (the count of `changed-tests.md` and where to read it).
     - **For the owner to do:** mark ready and merge; close pull request 115; change a branch rule that names the
       old CI checks (WP01); the manual list of `docs/mods-testing.md`; order the bench if it did not run; decide
       what stays of `docs/plans/one-go`.
     - **How to check this yourself:** `bash scripts/verify.sh final`, with its seconds.
  9. **The last commit.** `git rm -r docs/plans/one-go/evidence`, and the line of WP32 in `PROGRESS.md` set to
     `done`; nothing else. The plan says the working papers are not part of the repository
     (`docs/plans/two-approval-run.md`, appendix A). For this package alone there is no separate progress commit:
     the Commit cell of WP32 holds the hash of the commit before this one. The subject is
     `docs(wp32): the working papers leave the tree`.
  10. **The gate on a fresh tree.** `git worktree add --detach ../final-check HEAD`, make the types there (mechanics
      file, section 1), and run `bash scripts/verify.sh final` there in the background with a limit of 90 minutes.
      A file that exists only in the main work tree and was never committed shows up here and nowhere else. Green:
      push. Red: repair in a new commit and run it again; the removal is not done twice.
  11. **Close.** Write the final pull request text with the seconds of that run. Read the CI result of the last
      push when it arrives; a red job is repaired by the rule of the mechanics file, section 11. Schedule no
      further check. The pull request stays a draft: marking it ready is the owner's.
- **Removed:** `docs/plans/one-go/evidence/` (42 files at `65c7d42`, more after the kit commit); the table code
  inside `scripts/e2e/ab-replay.sh` (moved); the third replay column if its switch is gone.
- **Documents in the same change:** `docs/evidence/ab-replay-10.0.0.md` (the table of step 2 and how to run it
  again, in the form of `docs/evidence/ab-replay-9.8.5.md`); `CHANGELOG.md`, the 10.0.0 entry: the measured table
  or the sentence that cost and time are not measured; `docs/plans/one-go/PROGRESS.md`; the pull request text.
- **Done when:**
  - In a fresh work tree of the pushed head, `bash scripts/verify.sh final` ends `verify final: PASS`; or it ends
    `FAIL` only on rows the pull request text names under "Not done".
  - `grep -cvE '^[[:space:]]*(#|$)' scripts/selftest/expected-fail.txt` prints 0, or the text lists every line.
  - `bash scripts/e2e/ab-replay.sh 10e965a` exits 0 and its table is in the text and in
    `docs/evidence/ab-replay-10.0.0.md`.
  - `git ls-files docs/plans/one-go/evidence | wc -l` prints 0.
  - Every High finding of the review has its check in the tree, and that check passes.
  - `docs/evidence/scorecard-10.0.0.json` exists and `final` printed no bench failure; or the text holds the
    words of step 8 and `final` printed its `OPEN:` line.
  - The pull request is a draft against `main` whose text has every part of step 8.
- **Traps:**
  - The harness of this tree must still drive the CLI of `10e965a`: `ab-replay.sh` runs this tree's
    `scripts/e2e/replay.ts` against the old plugin folder (`:14-15`, `scripts/e2e/world.ts:16-17`). After WP04 the
    scripted person selects by id and by the `recommended` field, and 9.8.5 sends neither. If the base column
    stops early or shows numbers far from 8 questions, 7 launches and 92 agent minutes (plus the one Context check
    question the faithful fixtures of WP05 add), the person lost its way on the old view: give it the label as the
    way back for a view with no ids, and do not read the table until the base column is right.
  - `ab-replay.sh` needs `10e965a` in the clone and a free work tree entry; see the traps of WP00.
  - `final` takes as long as `full` and more; it is a background command. Do not run it beside the reviewers'
    suites: let the reviewers finish a round first.
  - A reviewer that is given the specs argues with the specs. Give it the rule and the code.
  - A reviewer's new scenario may assert a label text. Checks select by id (WP04); correct that before it goes in.
  - The review will find things that are true and out of scope (the "Later" list of the plan). They go under
    "Found on the way", not into a fix.
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
- **Size:** L. The review and its fixes are the open end; the bench adds about 6 hours of machine time when it runs.
