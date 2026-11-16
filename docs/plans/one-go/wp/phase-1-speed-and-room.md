# Phase 1, speed and room: work packages WP01, WP02 and WP03

This file holds WP01 (CI, the gate script, fixture layout, changelog), WP02 (code out of `scripts/temper`) and WP03
(the split of `scripts/flow.py`). None of the three changes what a run does, asks or prints.

The brief is `docs/plans/one-go/README.md`; the shared names below are those of `docs/plans/one-go/contracts.md`.
Each package ends as section 4 of the brief says: the package commit, then the small progress commit, in one push.

## WP01 CI split and cancel, one gate script, fixtures one view per line, older changelog entries moved

**Goal:** A push gets its CI answer in about 10 minutes (a median under 12, no run over 20) and a superseded run is
cancelled. One script gives the same answer locally: `scripts/verify.sh quick` in about 3 minutes after a package,
`scripts/verify.sh full` at the end of a phase. The fixture file and the changelog get room with no change of content.

**Depends on:** WP00.

**Lane:** flow core (it rewrites the fixture files and the selftest runner that every later package uses).

**Touches:**

- `.github/workflows/quality.yml`
- `scripts/verify.sh` (new)
- `scripts/selftest/run-selftest.sh`, `scripts/selftest/test-temper.sh`
- `scripts/selftest/temper-cases-32.sh` (new), `scripts/selftest/check-names.py` (new)
- `scripts/selftest/temper-cases-5.sh`, `scripts/selftest/case-helpers-5.sh`, `scripts/selftest/temper-cases-31.sh`
- `scripts/selftest/make-view-fixtures.sh`, `scripts/selftest/view-fixtures.ts`, `scripts/selftest/view-fixtures-2.ts`
- `scripts/e2e/run.ts`, `scripts/e2e/world.ts`
- `CHANGELOG.md`, `docs/history/changelog-before-9.7.md` (new), `docs/history/README.md`
- `CONTRIBUTING.md`, `.claude/CLAUDE.md`, `docs/mods-testing.md`
- `docs/plans/one-go/PROGRESS.md` (WP00 created it; this package only adds its numbers to it)

**Tests first:** all in the new case file `scripts/selftest/temper-cases-32.sh` (bash cases with the helpers of
`case-helpers.sh`; it reads files of the repository and runs no CLI call). Write the eight cases, see seven fail and
case 5 pass, then make the change.

1. `tooling: the runner lists every case file once`. `bash scripts/selftest/run-selftest.sh --list` prints each
   `temper-cases-N.sh` that sits next to the runner exactly once. Fails today: there is no `--list`.
2. `tooling: six shards cover every case file once, pairs together`. The lines of `--shard 1/6 --list` to
   `--shard 6/6 --list` together equal the lines of `--list`, and 2 with 3 and 8 with 9 are each in one shard.
3. `tooling: the fixture modules hold one view per line and are under 200,000 bytes`. Each of
   `view-fixtures.ts` and `view-fixtures-2.ts` has two comment lines, the export line, one line per view, and a
   closing line; `wc -c` of each is below 200,000. Fails today (259,060 bytes, 15,869 lines in the two files).
4. `tooling: case-helpers-5.sh holds no assertion`. `grep -c 'assert_'` on the file prints 0. Fails today (214).
5. `tooling: no script reads a name it does not define`. `python3 -I scripts/selftest/check-names.py` over every
   tracked `scripts/*.py` prints `ok`. The checker imports nothing it checks. With the standard `symtable` module it
   walks every scope of a file: a name the scope reads as a global must be bound at module level (assigned,
   imported, a function or a class, or assigned in a function under a `global` statement) or be a builtin, and a
   star import fails the file. It passes today on all 49 files (prototyped); it is the guard WP02 and WP03 lean on.
6. `tooling: the changelog starts at 9.7.0 and the older entries are in docs/history`. `CHANGELOG.md` has no
   heading `## v9.6` and is below 196,608 bytes; `docs/history/changelog-before-9.7.md` has the heading `## v9.6.8`
   and `## v5.0.1`. The same case holds the one entry of the result (row `D86` of `done.md`): exactly one
   heading of `CHANGELOG.md` starts with `## v9.8.5`, and it reads `## v9.8.5: a run that asks twice`. It does
   not assert that this heading is the first, so the case still holds when a later release adds its own.
   Fails today on both halves. The line leaves room for that one 9.8.5 entry, to which every package adds (the
   9.8.0 entry alone is 37,629 bytes).
7. `tooling: verify.sh names quick and full and refuses another word`. `bash scripts/verify.sh bogus` exits 2 and
   its text names both words. Fails today: no such script.
8. `tooling: the workflow cancels a superseded pull request run and ends in one gate job`. A grep of
   `.github/workflows/quality.yml` finds `concurrency:`, `cancel-in-progress:` and a job with `if: always()`,
   and the `changes` job names `github.base_ref`.

The fixtures compare of `scripts/selftest/temper-cases-8.sh:455-458` stays as it is and is the proof of step 4 below.

**Mechanism:**

1. **Case files are found, not listed** (`scripts/selftest/run-selftest.sh`). Replace the hand lists at `:34`
   (`ALL`), `:37` (the fast tier) and the tail of `:49` by one function that lists the numbers of the
   `temper-cases-N.sh` files next to the script, in number order. Keep `group_of` (`:35`) as the one place that
   says 2 runs with 3 and 8 with 9. `--fast` becomes every number from 10 up. Add three words: `--list` (print the
   groups the chosen tier would run, one per line, and exit 0), `--shard K/N` (of the groups in order, keep those
   whose index modulo N is K minus 1) and `--touched [REV]` (only the case files that themselves differ from REV,
   default `HEAD`, or are untracked; a changed `temper-cases-5.sh` or `case-helpers-5.sh` also selects 6 and 31).
   `--changed` keeps its map (`:42-46`) and loses nothing else. Correct the stale comment at `:33`, which still
   says 5 runs with 6.
2. **The serial runner sources what it finds** (`scripts/selftest/test-temper.sh:235-265`). Replace the 31 lines by
   one loop over the same discovery. A file that goes on from the one before (3, 6 and 9; the comment at `:227`)
   is sourced without `_fresh_fixture`; keep those three numbers in one variable beside the loop. The three safety
   assertions (`:268-271`) and the total line (`:275`) stay. Add the new case file 32 by creating it; no list changes.
3. **Case file 6 stops running case file 5** (`docs/plans/one-go/evidence/dev-efficiency.md` section 2.5). The
   generator copies a helper up to the first line that is exactly `}` (`scripts/selftest/make-helpers-5.sh:17-26`).
   Six helpers of `scripts/selftest/temper-cases-5.sh` do not end so (`gg_ready_g1` at `:793`, `gi_int` at `:896`,
   `gr_json` at `:1036`, `us_json` at `:1107`, `h5_hook` at `:1263`, `slow_hook` at `:1330`; `us_json` and
   `slow_hook` show only once the ones before them are closed), so 214 assertion lines of case file 5 are in the
   generated file and run again when case file 6 runs alone (`scripts/selftest/temper-cases-6.sh:11`). Close each
   of the six with a line that is exactly `}` (for `h5_hook` and `slow_hook` move the comment to the line above),
   then regenerate with `bash scripts/selftest/make-helpers-5.sh > scripts/selftest/case-helpers-5.sh`. With all
   six closed the generated file has 291 lines and no assertion, and case file 6 alone passes with 114 assertions
   (rehearsed at `10e965a`; with four closed, test 4 still counts 102). The drift case at
   `scripts/selftest/temper-cases-31.sh:34-35` stays. I chose the edit of six helpers over a smarter generator:
   it makes the generator's stated rule true and changes no assertion.
4. **One view per line** (`scripts/selftest/make-view-fixtures.sh:329`). Replace the one print of
   `json.dumps(views, indent=1, sort_keys=True)` by: the export line ending in `{`, then one line per view in sorted
   key order, each a space, the key as JSON, a colon and a space, and the view as
   `json.dumps(view, sort_keys=True, separators=(",", ":"))`, lines joined by a comma and a newline, then `}`.
   Regenerate both files (`make-view-fixtures.sh` and `make-view-fixtures.sh extra`). Run in a clone at `10e965a` on
   2026-11-16: `view-fixtures.ts` is 187,069 bytes (75,075 free, was 3,084) and `view-fixtures-2.ts` is 57,975; the
   reader at `scripts/selftest/temper-cases-8.sh:462`, which splits on the first `= `, still parses;
   `claude plugin test .` passes with 1,774 tests; and this command, run on a copy of the two files alone, exits 0:
   `npx -p typescript@5.6 tsc --noEmit --strict --target es2023 view-fixtures.ts view-fixtures-2.ts`.
   Keep the two files; together they are 245,044 bytes, too close to the limit to merge.
5. **End to end: shards, a time limit, a trace dump** (`scripts/e2e/run.ts`, `scripts/e2e/world.ts`).
   In `run.ts` (`:9-11`) accept flags anywhere after the mode (here `--shard K/N`; WP05 adds `--floor FILE` and
   `--write-floor FILE`) and keep the scenarios of `SCENARIOS` (`:7`) whose index modulo N is K minus 1; every
   mode of a scenario stays in one process, because the check that the flow is equal with the mod and without it
   compares two traces of one process (`:28-31`). When the variable
   `TEMPER_E2E_TRACE_DIR` is set, write each finished trace, calls included, to `<dir>/<scenario>.<mode>.txt` with
   the world's folder replaced by `/project` (tried on `full-run` and `small-change` in plain mode: two runs are
   byte equal). Besides the world's folder, replace every commit id (7 to 40 hex digits after `git rev-parse`
   output or in a call) and every time stamp by fixed text, as `snap` does: a trace line holds the first 80
   characters of every call, and the dump was tried on two scenarios in one mode only. In `world.ts` record the
   start time in the constructor (`:33-38`) and make `next()` (`:122-126`) throw
   `the scenario ran over its time limit of N s` once `TEMPER_E2E_LIMIT_S` seconds (default 300) have passed.
   Today only a step count bounds a scenario (`scripts/e2e/loop.ts:163`, `:212`), and a looping scenario took 21
   minutes per mode before it failed (`docs/plans/one-go/evidence/pr-tests-ci.md` section 1.3).
6. **`scripts/verify.sh`** (new; find the plugin folder as `scripts/quality-check.sh:11-13` does). It runs every
   step, prints one line per step with its seconds and PASS or FAIL, ends with `verify quick: PASS` or `FAIL` (or
   `full`), and exits 0 only when every step passed. Another word exits 2. The third word, `final`, is left to
   WP07, which adds it with its closing checks.

   | Step | `quick [REV]` | `full` |
   |---|---|---|
   | `quality-check.sh`, `validate-directory.sh`, `validate-docs.sh`, `validate-readme.sh`, `validate-plugin.sh`, `validate-panels.py`, `check-known-limits.sh` | yes | yes |
   | `check-names.py` over the tracked Python scripts | yes | yes |
   | selftest | `run-selftest.sh --touched REV` | `run-selftest.sh` (every file, in parallel) |
   | both fixture compares (the output of `bash scripts/selftest/make-view-fixtures.sh` piped into `cmp - scripts/selftest/view-fixtures.ts`, and the same with `extra` and `view-fixtures-2.ts`) | only when a file under `scripts` outside `scripts/selftest` changed: the fixtures the mod's tests read are what the CLI writes now (about 40 seconds, 29 measured for the first) | inside case file 8 |
   | end to end | `bun scripts/e2e/run.ts both full-run`, only when a file under `scripts` outside `scripts/selftest` changed | `run.ts all` as shards side by side, one per CPU up to 4 |
   | the mod | `claude plugin test .` and `check-mod-calls.sh`, only when a `.ts` or `.tsx` file changed | `claude plugin test .`, `claude plugin validate --strict .`, `test-check-mod-calls.sh`, `check-mod-calls.sh` |
   | type check | see below | see below |
   | `test-validate-directory.sh` | no | yes |

   REV defaults to `HEAD` when the work tree has changes and to `HEAD~1` when it is clean. The type check is
   `npx -p typescript@5.6 tsc -p tsconfig.mod.json` when `.claude-plugin/types/claude-code/index.d.ts` exists (make
   it first the way `.github/workflows/quality.yml:112-117` does). When that file cannot be made, run the same
   compiler on copies of the two fixture files alone and print one line that says the full type check is left to
   CI. The dry run could make the file: `docs/plans/one-go/session-mechanics.md` section 1 says how (Claude Code
   2.1.287 through `npx`), so expect the whole type check to run locally. Later packages add their own steps
   here: WP05 the floor, the caps and the replay with its base column, WP06 the check of the expected to fail
   rule, WP07 `scripts/check_done.py` and the word `final`, WP32 the compare of the replay against the base
   (`10e965a`) and the check of its summary.
7. **The workflow** (`.github/workflows/quality.yml`). Keep the eight short jobs and their names. Change this:

   ```yaml
   concurrency:
     group: quality-${{ github.event.pull_request.number || github.ref }}
     cancel-in-progress: ${{ github.event_name == 'pull_request' }}
   jobs:
     changes:      # output long: 'false' only when every changed file is under docs/decisions, docs/evidence,
                   # docs/history or docs/plans, or is CHANGELOG.md; any error in the diff gives 'true'
     temper-cli:   # needs changes; if long; fail-fast false; matrix shard 1..6; timeout-minutes 20
                   # checkout with fetch-depth: 0 (cases from WP07 on read the history and the commit 10e965a)
                   # bash scripts/selftest/run-selftest.sh --shard ${{ matrix.shard }}/6
     e2e:          # needs changes; if long; fail-fast false; matrix shard 1..4; timeout-minutes 20
                   # bun scripts/e2e/run.ts all --shard ${{ matrix.shard }}/4
     gate:         # needs every job; if: always(); fails when a needed result is failure or cancelled
   ```

   The `changes` job: the changed files are those of the whole pull request
   (`git diff --name-only origin/${{ github.base_ref }}...HEAD`, after a fetch of the base branch) and, on `main`,
   those of the push (`${{ github.event.before }}..${{ github.sha }}`). Never the last commit alone: every push
   of this build ends with a commit that changes only `docs/plans/one-go/PROGRESS.md`, and a job that read that
   commit would skip both long suites on every push.

   The serial unit job (`:18-24`) and the one end to end job with its 60 minute limit (`:81-96`) go. Pin the
   manifest job to the version the mod job uses: `:77` installs with no version, `:107` installs `2.1.287`. Runs on
   `main` are never cancelled, so each commit there keeps a result. With the groups in number order, shard 4 of 6
   holds case file 5 (with 12, 18, 24 and 30) and is the longest. The serial job took 24.7 to 33.1 minutes and the
   end to end job 30.5 (`docs/plans/one-go/evidence/dev-efficiency.md` section 1.2); a sixth and a quarter of that,
   plus the long pole, is where the 10 minutes come from. It is an estimate until the first run. When a shard
   passes 10 minutes of wall time in CI, raise the matrix count of that suite in the next package commit (the
   flag takes any N) and write it into PROGRESS.md; the e2e suite more than doubles during the build.
8. **The changelog.** Move `CHANGELOG.md` from line 1159 (`## v9.6.8`, the first entry before 9.7.0) to the end
   into `docs/history/changelog-before-9.7.md`, under front matter like `docs/history/tokenomics.md` has, and add
   one closing line to `CHANGELOG.md` that names the new file. 109,769 bytes stay (it was 246,956, with 15,188
   free) and 137,187 move. Add one entry to `docs/history/README.md` in that file's own style.
   Then the one entry of the result. The version of the result is 9.8.5, the number the base already carries
   (the brief, section 3, decision 7), so no package adds a version heading. Change the heading of the first
   entry, `CHANGELOG.md:6`, which at the base reads
   `## v9.8.5: a run that checks its own environment first, and asks less`, to `## v9.8.5: a run that asks twice`,
   and leave the text under it as it is. From this package on every package writes its lines under that heading,
   above the text of the base. WP31 gives the entry its final parts and cuts the text of the base down to what
   stays of pull request #115 (`docs/plans/one-go/pr-115-fixes.md` section 4).
9. **Add the base numbers to `docs/plans/one-go/PROGRESS.md`**: the serial total of the selftest, the parallel
   total before and after step 3, the seconds of `verify.sh quick` and `full`, and the bytes of the four files of
   the Traps table. Later packages compare against them. WP00 created the file with its baseline table; this
   package adds lines to it, replaces none and does not create it.

**Removed:** the four hand lists of case files (`run-selftest.sh:34`, `:37`, `:49`; `test-temper.sh:235-265`); the
serial CI unit job; the single 60 minute end to end job; 214 assertion lines from `case-helpers-5.sh`; the entries
before 9.7.0 from `CHANGELOG.md` (moved, not deleted); the words of the first changelog heading of the base (the
number 9.8.5 stays).

**Documents in the same change.** `CONTRIBUTING.md:16` (the check to run is `bash scripts/verify.sh quick`, then
`full` before a push); `.claude/CLAUDE.md:42-45` (the same two commands, and that a case file is found by its name);
`docs/mods-testing.md:42`; the header comment of `run-selftest.sh` (`:2-12`); the pointer in `docs/history/README.md`.

**Done when:**

- `bash scripts/verify.sh full` ends with `verify full: PASS`, and `bash scripts/verify.sh quick` with nothing
  changed ends with `verify quick: PASS` in under 180 seconds. Run this closing `full` with
  `TEMPER_E2E_TRACE_DIR` set and keep the folder: it is the base of WP02.
- Two runs of `TEMPER_E2E_TRACE_DIR=<dir> bun scripts/e2e/run.ts all` at this commit give folders that `diff -r`
  finds equal (the closing `full` is one of the two).
- `bash scripts/selftest/run-selftest.sh` ends with `FAIL: 0`. Its total falls by the assertions that ran twice:
  by the arithmetic of `docs/plans/one-go/evidence/pr-tests-ci.md` section 3 it is 2,879 before step 3 and 2,659
  after it, plus the eight new cases and the three safety assertions of the new file's own process (the serial
  total at the head is 2,575). Record the real numbers.
- `wc -c scripts/selftest/view-fixtures.ts` prints about 187,000 and `git diff --stat` shows no fixture change after
  a second regeneration.
- `grep -m1 '^## v' CHANGELOG.md` prints `## v9.8.5: a run that asks twice`, `grep -c '^## v9.8.5' CHANGELOG.md`
  prints 1, and `bash scripts/quality-check.sh` still prints its version match.
- `TEMPER_E2E_LIMIT_S=1 bun scripts/e2e/run.ts plain full-run` fails within seconds with the time limit text, and
  `bun scripts/e2e/run.ts all --shard 1/4` passes.
- The type check: with the types made as `docs/plans/one-go/session-mechanics.md` section 1 says, the whole type
  check of step 6 exits 0 locally; the compile of the two fixture files alone exits 0 too (it is the fallback
  where the types cannot be made); and the step `Type check the mod` of the Mod job is green in CI on this commit.
- On the draft pull request the run of this commit is green, its wall time is under 20 minutes, and a second push
  made while it runs cancels it.
- What the two points above say of CI (the step `Type check the mod`, and the run on the draft pull request)
  can only be read off CI. These are read at the start of WP02, when the run has ended, and written into
  PROGRESS.md under "Found on the way" with the wall time. They do not hold back the `done` mark of this
  package; a red job is repaired by section 11 of the mechanics before the package commit of WP02.

**Traps:**

- Sizes at the head and after this package. No tracked file may pass 262,144 bytes (`scripts/quality-check.sh:21-29`).

  | File | Bytes at `10e965a` | Free | After WP01 |
  |---|---|---|---|
  | `scripts/temper` | 260,504 | 1,640 | unchanged (WP02) |
  | `scripts/selftest/view-fixtures.ts` | 259,060 | 3,084 | 187,069 |
  | `CHANGELOG.md` | 246,956 | 15,188 | about 109,900 |
  | `scripts/flow.py` | 205,631 | 56,513 | unchanged (WP03) |

- The directory rules read every shell script, Python file and workflow file, the selftest included
  (`scripts/validate-directory.sh:24-38`, names at `:548`). In `verify.sh`, the runner and the workflow: name no path
  with a folder called `hooks`, `tests`, `mod`, `core` or `ui` (find a changed mod file by its `.ts` ending, never
  by its folder); list no folder by a wildcard after a variable (discover case files with a pattern that has no
  variable in front, after a `cd`); no `..` after a variable. `validate-directory.sh` takes 4 seconds: run it first.
- The path filter must stay narrow. The selftest reads `docs/flow.md`, `docs/trust.md` and `docs/grouped-build.md`,
  and `scripts/selftest/temper-cases-4.sh:76-77` reads the first heading of `CHANGELOG.md`; the short jobs read that
  heading too (`scripts/quality-check.sh:111-123`), so skipping the long jobs for a changelog edit loses nothing.
- A workflow level `paths-ignore` would leave a required check waiting for ever. Use the `changes` job and a job
  level `if`; the owner then requires the one `gate` check. The matrix changes the names of the two long checks:
  say so in PROGRESS.md, because a branch rule on the old names must be changed by the owner.
- Case file 5 alone takes 783 seconds on the idle 4 CPU machine (445 assertions) and is the long pole of every
  shard plan. Do not split it here. If its shard passes 12 minutes in CI, write that into PROGRESS.md and go on.
  Its 13 minutes alone are the floor of every shard plan and of the local `full`; `D88` (a median under 12) is
  the owner's to judge against that.
- `verify.sh quick` holds its 3 minutes only while none of the case files 1, 2, 3, 5, 6, 8 and 9 changed. Put new
  cases into new files from 32 up, never into those. `docs/plans/one-go/contracts.md` section 10 reserves the
  number of every later package's new case file.
- The mod type check needs `.claude-plugin/types`, which only a load of the plugin writes. In the container of
  2026-11-16 (Claude Code 2.1.325, no sign in) that load wrote nothing, so only CI ran the whole type check. A
  later dry run found the way: the load through `npx` with Claude Code 2.1.287, the version CI pins, wrote the
  folder (`docs/plans/one-go/session-mechanics.md` section 1). Use that, once a work tree.
- The moved changelog text holds three markdown links, all `https`; `validate-docs.sh` rule 2 checks links under
  `docs`, so run it after the move. Lines 1 to 1158 of `CHANGELOG.md` keep their numbers, and the plan and the
  evidence files cite only those.
- The new heading keeps the number: the checks of the base compare the version in the first `## v` heading with
  the manifest (`scripts/quality-check.sh:111-123`, `scripts/selftest/temper-cases-4.sh:76-77`), and both say 9.8.5
  at the base. Change the words after the colon and nothing else. No file of the base reads those words.
- Do not change a view, a label or a count in the fixtures here: the layout changes, the parsed content must be
  equal (compare the parsed JSON of the old and the new file once, by hand).
- No prototype diff for this phase is in `docs/plans/one-go/evidence/prototypes/`. Steps 4 and 5 and the checker of
  test 5 were run in a clone at `10e965a` on 2026-11-16; the numbers in this section are from those runs.

**Size:** M.

## WP02 Code out of `scripts/temper` into Python modules, at least 40 KB free

**Goal:** `scripts/temper` is at most 222,144 bytes (40,000 free; it has 1,640 today), and for every command the
standard output, the files written and the exit code are byte equal to the head `10e965a`.

**Depends on:** WP01.

**Lane:** flow core.

**Touches:**

- `scripts/temper`
- new modules, standard library only: `scripts/json_ops.py`, `scripts/state_ops.py`, `scripts/ledger_ops.py`,
  `scripts/spec_text.py`, `scripts/commit_rows.py`, `scripts/report_ops.py`, `scripts/groups_ops.py`
- `scripts/temper-help.txt` (new)
- `scripts/selftest/capture-cli.sh` (new), `scripts/selftest/make-view-fixtures.sh`
- `scripts/selftest/temper-cases-32.sh`, `scripts/selftest/test-temper.sh`
- `scripts/selftest/temper-cases-2.sh`, `temper-cases-3.sh`, `temper-cases-4.sh`, `temper-cases-5.sh`,
  `temper-cases-6.sh`, `temper-cases-9.sh`, `temper-cases-13.sh`, `case-helpers-5.sh` (lists of files only)
- `.claude/CLAUDE.md`, `CONTRIBUTING.md`, `docs/plans/one-go/PROGRESS.md`

**Tests first:**

1. The capture, a tool and not a case: `scripts/selftest/capture-cli.sh OUT_DIR`. It runs the fixture generator
   with `TEMPER_CAPTURE_DIR` set. With that variable set, `snap` of `make-view-fixtures.sh` (`:94`) also copies the
   project folder, and in the copy runs a fixed list of calls and writes `<OUT_DIR>/<state>.txt`: for each call the
   call, its exit code, its standard output and its error output, with the replacements `snap` already makes
   (plugin folder, project folder, work folder, HEAD, the text after `its last commit is`, times, the run id), and
   at the end the name and the content of every file under `.temper` of the copy. The calls, in this order:
   `next --json`, `status`, `report`, `schedule`, `panel plan`, `model --all`, `state get next_stage`,
   `evidence list --stage build`, `gate intent`, `gate plan`, `gate design`, `gate build`, `gate review`,
   `gate check`, `gate commit`, `status`, `report`, `go`, `next --json`, then one writing call for each moved writer
   that the generator's own run does not reach (take the flags from `scripts/temper --help`). Run it at the base
   before any move and keep the folder outside the repository. Prototyped on 2026-11-16 with 21 calls: 43 states,
   1.4 MB, about 6.5 minutes on a shared 4 CPU machine; the generator's own output did not change; two runs differed
   only in the one commit id that the `its last commit is` replacement covers.
2. `scripts/selftest/temper-cases-32.sh`, case `room: scripts/temper leaves 40,000 bytes free`. `wc -c` of the
   file is at most 222,144. Fails until the last step. This case lives until WP05. WP05 removes it in the commit
   that puts `cli_bytes` into `scripts/caps.json` with `final` 222144 and `now` the measure. From then on a
   package may use the room, and `python3 scripts/check_caps.py --final` holds the line at the end.
3. Same file, case `room: the CLI holds at most one Python heredoc`. `grep -c "<<'PY'" scripts/temper` prints at
   most 1 (the metrics block, which WP30 deletes: the count is then 0). Fails today (19).
4. Same file, case `room: the new modules run isolated`. Every line of `scripts/temper` that starts one of the seven
   new modules starts it as `python3 -I`, and none of the seven holds `sys.path` or a star import.
5. Case 5 of WP01 (`no script reads a name it does not define`) now reads the seven new modules too, with no edit.

**Mechanism:**

1. **The form of a move.** A block becomes one function in a module and one word of that module's `main`. The
   line left in `scripts/temper` is `python3 -I "$SCRIPTS_DIR/<module>.py" <word> <the same arguments>`, the form
   `scripts/temper:3746` already uses for `findings.py`. The function gets the old `sys.argv[1:]` as its
   parameters, in the same order. A module that needs a sibling loads it by its full path, as the groups writer
   does (`scripts/temper:2221-2224`); nothing is put on `sys.path`. Nothing runs at import (unlike
   `scripts/task_ops.py:324`): end each module with the `__main__` guard, as `scripts/findings.py:142` does.
2. **Wave 1, first: the 18 quoted heredocs** (16,782 bytes, about 15,100 net). Their text is plain Python: move it
   verbatim.

   | Lines | Bytes | Function in `scripts/temper` | Target module |
   |---|---|---|---|
   | `:790-814` | 989 | `_state_migrate_legacy` | `state_ops.py` |
   | `:998-1033` | 1,383 | `_state_next` | `state_ops.py` |
   | `:1056-1088` | 1,066 | `_redo_from` | `state_ops.py` |
   | `:1378-1413` | 1,439 | `_archive_ledger` | `state_ops.py` |
   | `:1474-1490` | 668 | `cmd_state_redo` | `state_ops.py` |
   | `:1636-1659` | 1,042 | `cmd_evidence_resolve` | `ledger_ops.py` |
   | `:1686-1709` | 1,066 | `cmd_evidence_accept` | `ledger_ops.py` |
   | `:2111-2123` | 462 | `_unfenced_scenarios` | `spec_text.py` |
   | `:2127-2150` | 745 | `_cross_repo_recorded` | `spec_text.py` |
   | `:2220-2243` | 751 | `_groups_mutate` | `groups_ops.py` |
   | `:2327-2335` | 240 | `cmd_group_start` | `groups_ops.py` |
   | `:2850-2867` | 650 | `_task_box` | `spec_text.py` |
   | `:3658-3682` | 957 | `gate_build` | `ledger_ops.py` |
   | `:3765-3809` | 1,852 | `_review_code` | `state_ops.py` |
   | `:4014-4026` | 542 | `_glob_touch_match` | `commit_rows.py` |
   | `:4085-4094` | 367 | `gate_commit` | `ledger_ops.py` |
   | `:4446-4471` | 1,072 | `cmd_intent` | `spec_text.py` |
   | `:4474-4504` | 1,491 | `cmd_intent` | `spec_text.py` |

3. **Wave 2: the 20 blocks of 400 bytes or more written as `python3 -I -c "..."`** (14,678 bytes, about 12,300
   net). Their text sits in bash double quotes: undo the quoting when it moves (step 5).

   | Lines | Bytes | Function in `scripts/temper` | Target module |
   |---|---|---|---|
   | `:743-776` | 1,490 | `cmd_state_init` | `state_ops.py` |
   | `:4161-4183` | 1,274 | `gate_commit` (blast radius) | `commit_rows.py` |
   | `:4712-4741` | 1,250 | `cmd_report` | `report_ops.py` |
   | `:951-976` | 1,033 | `_tier_lines` | `spec_text.py` |
   | `:4742-4758` | 951 | `cmd_report` | `report_ops.py` |
   | `:1563-1577` | 827 | `cmd_evidence_add` | `ledger_ops.py` |
   | `:1597-1613` | 773 | `cmd_evidence_list` | `ledger_ops.py` |
   | `:461-489` | 748 | `_json_set_path` | `json_ops.py` |
   | `:2164-2173` | 620 | `_plan_digest` | `spec_text.py` |
   | `:293-312` | 614 | `_json_get_path` | `json_ops.py` |
   | `:3272-3277` | 588 | `_task_gate_body` | `ledger_ops.py` |
   | `:3987-4000` | 582 | `_override_covers` | `commit_rows.py` |
   | `:1316-1326` | 541 | `_groups_reset` | `groups_ops.py` |
   | `:1754-1762` | 541 | `cmd_evidence_run` | `ledger_ops.py` |
   | `:4380-4391` | 507 | `cmd_status` | `report_ops.py` |
   | `:3449-3453` | 499 | `cmd_task_confirm` | `ledger_ops.py` |
   | `:1985-2001` | 494 | `_intent_uncovered_scenarios` | `spec_text.py` |
   | `:1146-1164` | 468 | `cmd_state_advance` | `state_ops.py` |
   | `:1190-1207` | 452 | `cmd_state_advance` | `state_ops.py` |
   | `:2673-2682` | 426 | `_group_reopen_body` | `groups_ops.py` |

4. **Housekeeping that frees bytes with no code move** (about 9,900 net). The help text (`scripts/temper:5052-5104`,
   4,473 bytes) goes to `scripts/temper-help.txt` and the case prints it with `cat`. The two functions nothing
   calls go: `_setup_calls` (`:4540-4558`, 1,354 bytes) and `_excludes_current` (`:636-643`, 437 bytes), whose live
   twin is `setup_calls` at `scripts/cli_ctx.py:106`. A bash comment that sits directly above a moved block and
   describes it moves into the module as its docstring (about 1,600 bytes at 10 blocks). The 30 rule lines of
   dashes (2,340 bytes) shrink to `# ---`.
5. **Undoing the quoting, for wave 2 and wave 3.** In a `-c "..."` block bash has already turned `\\` into `\`,
   `\"` into `"` and `\$` into `$` before Python reads it, and has put in every `$name` and `$(...)`. Write the
   module text as Python saw it. A shell value that was spliced into the text becomes one more argument. Example:
   the patterns at `scripts/temper:4171` and `:4174` read `\\S+` and `\\.` in the bash file and must read `\S+` and
   `\.` in the module.
6. **Wave 3, all of it, and step 7 after it, whatever the target says:** the 34 smaller `-c` blocks, largest
   first (8,082 bytes, about 4,100 net). The later packages add about 10 KB of dispatch lines, flags and rows to
   the bash file. The estimate after waves 1 and 2 and step 4 is about 37,300 net against the 38,360 needed; with
   all of wave 3 and the reserve of step 7 the most this package can free is about 45 KB. Write the bytes freed
   into PROGRESS.md. Put the hot helpers (`_json_read` `:278-285`, `_json_append` `:498-512`, `_jget`
   `:2876-2880`, `_req` `:2006-2009`, the `_ev_last_*` readers `:1906-1939`) into `json_ops.py` and `ledger_ops.py`
   and keep `json_ops.py` small: every call compiles its whole module.
7. **The reserve, with more risk, taken too (step 6):** the 16 Python bodies that callers pass to
   `_groups_mutate` as text (6,394 bytes, first at `scripts/temper:2420-2434`, largest at `:2761-2779`) become
   named functions of `groups_ops.py`. Take it after wave 3, as a commit of its own with the gate of step 8, and
   say in PROGRESS.md what it freed.
8. **Order of work and the gate between waves.** After each wave: `bash scripts/verify.sh quick`, then the fast
   tier (`run-selftest.sh --fast`), then one commit with `(wp02)` in its subject, pushed when it is made
   (`docs/plans/one-go/session-mechanics.md` section 6). After the last wave and the reserve of step 7: the
   capture again and `diff -r <before> <after>`, then `bash scripts/verify.sh full`. The last of these commits is the
   package commit; after it comes the small progress commit, and one push for both
   (`docs/plans/one-go/README.md` section 4).
9. **The throwaway plugins of the suite.** Eight places copy five named files into a scratch plugin and run `init`,
   `state init`, the installer or the commit hook there: `scripts/selftest/test-temper.sh:216`,
   `temper-cases-2.sh:1094`, `temper-cases-3.sh:94`, `:394`, `:565`, `:943`, `temper-cases-4.sh:92`, `:272`. Those
   paths now need the new modules. Put the list of the CLI's files into one function in `test-temper.sh` and use it
   at the eight places, by name, with no wildcard.
10. **Keep the reach of the source greps.** Add the seven modules to the file lists of the cases that prove a text
    is absent from the CLI: `temper-cases-2.sh:1086` and `:1105`, `temper-cases-5.sh:1574`, `temper-cases-6.sh:269`
    and `:273`, `temper-cases-9.sh:571`, `temper-cases-13.sh:28`. After an edit of `temper-cases-5.sh` regenerate
    `case-helpers-5.sh` (the drift case of `temper-cases-31.sh:34-35`).

**Removed:** the 72 Python blocks of waves 1 to 3 from `scripts/temper`, and the 16 bodies of step 7 as text;
the help heredoc; `_setup_calls` and `_excludes_current`; 30 long rule lines. Nothing a run can reach is removed.

**Documents in the same change.** `.claude/CLAUDE.md:53` and `:55-56`: the rule becomes "gate logic lives in the CLI
(the script and its Python modules), never in a prompt", and a change of gate mechanics is an edit of the CLI or of
its module plus a case, as section 7 of `docs/plans/two-approval-run.md` asks. `CONTRIBUTING.md:40` names the
modules. One line in PROGRESS.md with the bytes before and after.

**Done when:**

- `wc -c scripts/temper` prints at most 222,144.
- `bash scripts/verify.sh full` ends with `verify full: PASS`, with the selftest total equal to the one WP01
  recorded plus the cases of this package.
- `diff -r` of the capture folders made before the first move and after the last prints nothing, apart from
  lines of a Python traceback that name a file and a line (replace those in the capture by fixed text).
- `git diff --exit-code scripts/selftest/view-fixtures.ts scripts/selftest/view-fixtures-2.ts` after a regeneration
  prints nothing.
- `TEMPER_E2E_TRACE_DIR=<dir> bash scripts/verify.sh full`: the folder the closing `full` of WP01 wrote, and one
  more at the end, are two trace folders that `diff -r` finds equal.
- `bash scripts/validate-directory.sh` and `python3 -I scripts/selftest/check-names.py` over the scripts pass.

**Traps:**

- **Not in phase 1:** no rename of an option, a label, a row, a command or a state key; no change of any text the
  CLI prints; no merge of a rule that exists in bash and in Python (the pairs of
  `docs/plans/one-go/evidence/cli-core.md` section 4.2); no single process CLI; no move of the lock (`:337-352`,
  `:364-382`, `:429-431` stay in bash) or of the refusals in front of `main`; no deletion of dormant machinery (the
  metrics block `:4847-4875` stays for WP30); no fix of a defect found on the way (write it into PROGRESS.md).
- The size limit is 262,144 bytes and the file starts 1,640 below it: remove before you add. A wave that adds a
  call line before it deletes the block can fail `quality-check.sh` in between.
- A heredoc block reads its program from standard input, a `-c` block does not. Some `-c` blocks read data from a
  pipe (`:4161`, `:2876`, `:2938`): after the move standard input is still theirs; do not add a heredoc there.
- `python3 -I` puts neither the script's folder nor the current folder on the path and ignores `PYTHON*`
  variables. Keep `-I`; a move to `-E -s` would change what a hostile project folder can make the CLI load.
- Tests read the text of `scripts/temper`. These must stay in the bash file as they are: the functions
  `_git_id_args` (`temper-cases-1.sh:1052`) and `_spec_dir_ok` (`temper-cases-3.sh:153`), each from its `name() {`
  line to a line that is exactly `}`; the lines `STAGE_SEQ_TEMPER=` and `STAGE_SEQ_FIX=` (`temper-cases-2.sh:809`,
  `temper-cases-18.sh:179`); `TASK_BRIEF_MAX_BYTES=` at a line start (`temper-cases-5.sh:1170`); the header comment
  lines `#   temper status`, `schedule`, `group`, `task`, `integrate` and `usage` (`temper-cases-2.sh:801`,
  `temper-cases-5.sh:1102`, `:1164`).
- A moved block is now a Python file for the directory rules, which read Python more closely than Python inside
  bash: no glob call, no join with the parent folder, no path with a folder named `hooks`, `tests`, `mod`, `core`
  or `ui`, no word joined from quoted pieces (`scripts/validate-directory.sh:17-38`).
- The view is rewritten after almost every command (`scripts/temper:5108-5117`); a module that fails to start makes
  a command fail, but a failed view write is silent (`:4652-4656`). Trust the capture and the selftest, not the
  absence of an error.
- An uncaught error in a moved block prints a traceback with a new file name and line. That is the one allowed
  difference in error output; an exit code never changes.
- Do not touch `scripts/go.py`, `scripts/cli_ctx.py`, `scripts/flow.py` or anything under `scripts/guards` here.
  The installed commit hook calls the CLI by its path and needs no change; WP03 owns the flow.
- The capture runs `gate plan`, whose preflight runs the fixture's `npm test` in a scratch worktree. It gave the
  same text on two runs of one machine; compare only captures made on the same machine.

**Size:** L.

## WP03 Split `scripts/flow.py` into modules, behaviour unchanged

**Goal:** `scripts/flow.py` becomes a facade of at most 32,768 bytes over seven modules, none over 65,536 bytes, and
`temper next --json`, `.temper/view.json` and every other output are byte equal on every fixture state and on every
end to end trace.

**Depends on:** WP01, WP02 (it uses the capture of WP02 and the trace dump of WP01).

**Lane:** flow core.

**Touches:**

- `scripts/flow.py`
- new: `scripts/flow_base.py`, `scripts/flow_run.py`, `scripts/flow_ask.py`, `scripts/flow_work.py`,
  `scripts/flow_build.py`, `scripts/flow_commit.py`, `scripts/flow_view.py`
- `scripts/selftest/case-helpers.sh`, `scripts/selftest/run-selftest.sh`, `scripts/selftest/temper-cases-32.sh`
- `scripts/selftest/temper-cases-2.sh`, `temper-cases-8.sh`, `temper-cases-10.sh`, `temper-cases-13.sh`,
  `temper-cases-15.sh`, `temper-cases-18.sh`, `temper-cases-28.sh` (where they read the text of `flow.py`)
- `.claude/CLAUDE.md`, `CONTRIBUTING.md`, `docs/flow.md`, `docs/plans/one-go/PROGRESS.md`

**Tests first:** in `scripts/selftest/temper-cases-32.sh`.

1. `room: flow.py is a facade and no flow module is large`. `flow.py` is at most 32,768 bytes and each
   `flow_*.py` at most 65,536. Fails today (205,631).
2. `flow: the names other code reads are still on the module`. After `import flow` these exist: `Run`, `Builder`,
   `MOVES`, `SEQ`, `VERSION`, `view`, `write_view`, `scoped_notes`, `same_failure`, `open_concerns`,
   `concern_blocks`, `plan_files`, `advance_ok`, `design_accept`, `changed_files`, `run_next`, `run_view`; and
   `flow.Builder` has `opt`, `ADHOC_STAGES`, `report_steps` and `review_notes`. Passes today; it guards the split.
3. `flow: the modules import one way`. No `flow_*.py` imports the module `flow` itself (neither `import flow` at a
   line end nor `from flow import`); `flow_base.py` imports no `flow_` module; no flow file holds a star import or
   `sys.path`.
4. `flow: each word of flow.py still answers`. In a scratch folder with no run, the word `plan-files` with an empty
   folder prints `[]` and exits 0, `advance-ok intent_complete plan` exits 1 with the text `no active run`, and a
   call with no word exits 2. Passes today (checked at `10e965a`).
5. Case 5 of WP01 (`no script reads a name it does not define`) covers the new modules with no edit. It is the
   main guard: a name left behind in a moved method fails only when its branch runs.

**Mechanism:**

1. **Before the first edit**, at the base of this package: make the capture (`scripts/selftest/capture-cli.sh`) and
   the traces (the folder that `TEMPER_E2E_TRACE_DIR` named in the last `verify.sh full` of WP02 serves), and keep
   both outside the repository.
2. **The modules.** Lines are of `scripts/flow.py` at `10e965a`. Method bodies and function bodies move verbatim;
   only import lines and class headers are new.

   | Module | Holds | From lines | About |
   |---|---|---|---|
   | `flow_base.py` | the tables and headers (`VERSION` to `MOVES`), `loop_at`, `read_json`, `read_text`, `scoped_notes`, `git`; `CARRY`, `blocking_asks`, `advance_ok`, `plan_files`, `path_tokens`, `same_failure`, `goes_on`, `short_model`, `on_model`, `criteria`; the concern readers (`CONCERN_STRUCT`, `concern_blocks`, `open_concerns`, `design_accept`) | `:37-108`, `:2485-2595`, `:2619-2627`, `:2985-3054` | 15 KB |
   | `flow_run.py` | `class Run`; `changed_files`, `project_facts` | `:110-427`, `:2899-2983` | 22 KB |
   | `flow_ask.py` | `class AskPart`: the option and question makers (`c` to `leave_plan`), `ask`, and the question helpers from `measurement_gap` to `walked` | `:435-1117` | 54 KB |
   | `flow_work.py` | `class WorkPart`: `agent`, `armed_text`, `policy_move`, `setup_offer` to `fresh_work`, `stage_work`, the acceptance methods to `cli_check` | `:1119-1556` | 32 KB |
   | `flow_build.py` | `class BuildPart`: `chain_of` to `parked` | `:1558-2133` | 43 KB |
   | `flow_commit.py` | `class CommitPart`: `report_steps` to `context_question` | `:2135-2329` | 15 KB |
   | `flow_view.py` | `check_markers`; `PERSON_ROWS` to `drift_info`; `AGENTS_NAMED`, `named_before`, `write_named`, `write_view` | `:2597-2617`, `:2633-2897` | 16 KB |
   | `flow.py` | the docstring; `class Builder(AskPart, WorkPart, BuildPart, CommitPart)` with `__init__`, `next`, `add_note`, `core_next`; `main`, `run_next`, `run_view`; the names of test 2 imported by name | `:1-13`, `:430-433`, `:2331-2484`, `:3056-3118` | 14 KB |

3. **The import structure.** `flow_base` imports the standard library and the helper modules its functions use
   (`tasks_md`, `shlex` and so on). An import that sits inside a function stays inside it (`acceptance` at
   `:1545`, `:2623` and `:2641`).
   `flow_run`, the four part modules and `flow_view` import from `flow_base` by name. No module imports `flow`, and
   the part modules import neither each other nor `flow_run`. `flow.py` imports all seven and is the only file
   that builds a `Builder`. Each module carries on the sibling imports its own code needs from `flow.py:24-35`
   (`adhoc_ops`, `check_run`, `config_yaml`, `decisions`, `doctor`, `fresh_review`, `intent_parse`, `plan_ops`,
   `run_env`, `tasks_md`, `finding_state`, `loop_step`). Let the name check tell which module needs which.
4. **Why parts of one class work.** No method names the class: the only uses of `Builder(` and `Run(` are in
   `main`, `run_next` and `run_view` (`flow.py:3061`, `:3097-3110`). Every call between methods goes through
   `self`, so a method of one part finds a method of another on the finished class. The class attributes move with
   their region: `ADHOC_STAGES` and `ADHOC_OPTION_STAGES` (`:900`, `:903`) to `AskPart`, `ACC_LOCK` and
   `ACC_REASONS` (`:1387`, `:1443`) to `WorkPart`; the static methods (`:879`, `:1422`, `:1558`, `:1951`, `:2288`)
   keep their decorator. Two names exist as a method and as a module function, `criteria` (`:1540` and `:2619`) and
   `open_concerns` (`:238` and `:3027`): inside a method the bare name is the module function, so import both
   functions from `flow_base` where the bare call is.
5. **Callers that must keep working, unchanged.** `scripts/temper` starts `flow.py` with the words `advance-ok`,
   `plan-files` and `design-accept` (`scripts/temper:1134`, `:1141`, `:1180`, `:1188`); `scripts/cli_ctx.py:149-162`
   imports `flow` and calls `run_view` and `run_next`; `scripts/answer_ops.py:107` and `scripts/panel.py:181` call
   `flow.concern_blocks`; `scripts/drift.py:60` calls `flow.plan_files`; `scripts/go.py:88` runs
   `temper next --json` as a process and imports nothing. All of them start Python without `-I`, with the scripts
   folder first on the path, which is how the siblings find each other.
6. **Tests that read the text of `flow.py`.** Add to `scripts/selftest/case-helpers.sh` one function that prints
   the text of `flow.py` and of the seven modules, from one list of names, and read through it at:
   `temper-cases-10.sh:92-97` (no instruction in a `say` string), `temper-cases-18.sh:48-55` (every move written is
   in `MOVES`), `temper-cases-8.sh:388`, `temper-cases-13.sh:28` and `:38`, `temper-cases-15.sh:556`,
   `temper-cases-2.sh:1086`. `temper-cases-28.sh:26` cuts the text from `def policy_move` to `def setup_offer`:
   keep the two methods adjacent and in that order (`flow.py:1144`, `:1183`) and point the case at `flow_work.py`.
   Each assertion keeps its expected value.
7. **The runner's map.** In `scripts/selftest/run-selftest.sh:43` add the pattern `scripts/flow_*.py` beside
   `scripts/flow.py`.
8. **Proof, in this order:** `bash scripts/verify.sh quick`; the fast tier; regenerate both fixture files and see
   no difference; the capture again and `diff -r`; the traces again and `diff -r`; `bash scripts/verify.sh full`.

**Removed:** nothing a run can reach. `scripts/flow.py` loses about 190 KB to the seven modules.

**Documents in the same change.** `.claude/CLAUDE.md:27` and `:57` (what comes next is `scripts/flow.py` and its
`flow_*.py` modules); `CONTRIBUTING.md:40` and `:90`; `docs/flow.md:6`; one line in PROGRESS.md with the bytes of each
flow file.

**Done when:**

- `wc -c scripts/flow.py scripts/flow_*.py` shows the facade under 32,768 and no module over 65,536.
- `bash scripts/selftest/make-view-fixtures.sh | cmp - scripts/selftest/view-fixtures.ts` and the same with `extra`
  and `view-fixtures-2.ts` print nothing; `git status` shows no fixture change.
- `diff -r` of the capture before and after prints nothing: `next --json` is byte equal on all 43 states.
- `diff -r` of the end to end traces before and after prints nothing, for 23 scenarios in three modes.
- `bash scripts/verify.sh full` ends with `verify full: PASS` and the selftest total is the recorded one plus the
  cases of this package.

**Traps:**

- **Not in phase 1:** no rename of an option or a label, no ids (WP04), no change of the order of the checks in
  `core_next` (`flow.py:2360-2482`; its order is the precedence), no question registry (left to WP04, which puts
  `QUESTIONS` and `OPTION_IDS` into `scripts/flow_base.py`; `NEEDS` is left to WP16), no change of `VERSION`
  (`:37`), no cleaning of comments, no merge with the bash twins of a rule. A defect seen on the way goes into
  PROGRESS.md for WP08.
- Python reports a missing name only when the line runs. `py_compile` and a green fast tier do not prove the
  split; the name check of WP01 does, together with the traces. Run it after every moved region.
- Imports by name copy a value once. That is safe here: no flow file has a `global` statement and no test assigns
  to a name of the module. Do not start to patch `flow.TEMPER` or the tables from a test.
- The usage text of `flow.py` is its docstring (`:3075`), so the docstring stays in `flow.py`.
- Folder names: the directory rules refuse a script that names a path with a folder called `core`, `ui`, `mod`,
  `tests` or `hooks`. Keep the modules flat in `scripts`, with the names above; do not make a package folder.
- `flow.py` is 56,513 bytes below the limit today, so nothing forces an order; still move one region, run the name
  check and case files 8, 10, 12, 13 and 18, and only then move the next.
- The throwaway plugins of the suite copy `flow.py` alone (WP02 step 9). Nothing there imports it with success
  today, because its sibling imports are missing there too; leave those copies as they are.
- The mod does not read these files; no table of the mod and no reviewed call changes. If a fixture differs after
  the split, the split changed behaviour: find the cause, never regenerate to make the case pass.
- The line of test 1 stands for the whole build, and `flow_ask.py` starts at 54 KB of moved code under a line of
  65,536 bytes. When a later package brings a flow module to its line, that package first splits the module in
  a commit of its own (a move with no change, proven by the fixture compare and the name check), adds the new
  file to `flow_files` of `scripts/caps.json` and one line to `contracts.md` section 1. The line is never raised.

**Size:** M.
