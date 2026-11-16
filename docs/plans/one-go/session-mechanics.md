# Session mechanics for the one pass build

This file tells the build session how to work: the first ten minutes, the gate, the progress file, the commit and
push rhythm, the lanes, and how to keep going with nobody watching. It holds no package spec; those are in
`docs/plans/one-go/wp/`. The settled decisions, the method and the one build order are in the brief,
`docs/plans/one-go/README.md` (sections 3, 4 and 5); the names every package must use are in
`docs/plans/one-go/contracts.md`. Where this file and the brief differ, the brief wins.

Everything marked **[measured]** was run on 2026-11-16 by a dry run in a clone, on the machine the planning session
used: 4 CPUs, 15 GB of memory, bun 1.4.4, node 22.23.4, tsc 6.0.2, Python 3.13.18, Claude Code 2.1.325, with other
agents on the same machine (load average 1.3 to 4.5). Every second below is therefore an upper bound.
**[read]** means read in the code or in a tool's own description. **[suggestion]** means neither: judge it yourself.

## 1. The first ten minutes

The three commits the branch is made of **[measured]**:

| What | Branch on `origin` | Commit |
|---|---|---|
| The base | `main` | `7c7a1c1` (version 9.8.4) |
| Pull request 115 | `ccr-e0b10914-a7hzu0`, and the pull ref `refs/pull/115/head` | `10e965a` (version 9.8.5, 16 commits on top of `7c7a1c1`) |
| The plan and this kit | `ccr-88156f39-u643ta` | `8477375` (the plan), `65c7d42` (the evidence), then the kit commit |

The merges were rehearsed in a clone: both are clean, with no conflict, and `git diff --stat 10e965a HEAD` then
shows only files under `docs/plans` (43 files at `65c7d42`). The fetch from GitHub itself was not rehearsed.

```bash
# 1. Where am I, and is the history deep enough
git status -sb && git remote -v
git fetch origin main ccr-88156f39-u643ta && git fetch origin refs/pull/115/head
git rev-parse --short origin/main FETCH_HEAD origin/ccr-88156f39-u643ta
git cat-file -e 7c7a1c1 && git cat-file -e 10e965a || git fetch --unshallow origin

# 2. The branch
git rev-parse --abbrev-ref HEAD   # the branch this session was told to develop on; stay on it
# only when no branch was named: git checkout -b one-go origin/main
git merge --no-ff --no-edit 10e965a
git merge --no-ff --no-edit origin/ccr-88156f39-u643ta
git merge-base --is-ancestor 10e965a HEAD
ls docs/plans/one-go/README.md docs/plans/one-go/contracts.md docs/plans/one-go/done.md
git diff --stat 10e965a HEAD | tail -1

# 3. The tools
bun --version; python3 --version; node --version; claude --version; tsc --version
timeout 120 npx -y -p @anthropic-ai/claude-code@2.1.287 claude -p "hi" --plugin-dir . \
  --debug-file /tmp/mod-debug.log || true
test -f .claude-plugin/types/claude-code/index.d.ts && echo "types ready"

# 4. One minute of proof that the tree is sound
bash scripts/quality-check.sh && bash scripts/validate-docs.sh && bash scripts/check-mod-calls.sh
tsc -p tsconfig.mod.json && claude plugin validate --strict .
```

Then read the brief (`docs/plans/one-go/README.md`), `contracts.md`, `done.md` and this file, start the baseline of
WP00 in the background, and write `PROGRESS.md` while it runs. WP00 creates that file; every later package updates
it, and none creates it again (WP01 only adds its numbers).

Notes on those commands:

- Merge `10e965a` by its hash, not by the branch name. Every `file:line` in the kit is of that commit. If the
  branch of pull request 115 has moved, write the newer commits into `PROGRESS.md` under "Found on the way" and
  leave them out.
- `10e965a` is the head of pull request 115; the pull ref stays when the branch goes. That is why the fetch names
  `refs/pull/115/head` and not the branch: a fetch that names a removed branch fails as a whole, and a server
  takes no short hash in a fetch.
- A cloud session is given its branch and may push to no other. Stay on it; the merges are the same.
- If `origin/main` is no longer `7c7a1c1`, still start from `origin/main` (the pull request must merge into it)
  and note the new hash. `scripts/e2e/ab-replay.sh:9` needs `7c7a1c1` in the clone; the working copy of the
  planning session was a shallow clone (136 commits) **[measured]**, so check with `git cat-file -e` as above.
- If the session starts on a branch that already holds the kit, only the merge of `10e965a` is left. What counts is
  the result: `7c7a1c1` and `10e965a` are ancestors of `HEAD` and the kit files are there.
- The mod's types. `.claude-plugin/types/` is ignored by git (`.gitignore:58`) and only a load of the plugin writes
  it. With Claude Code 2.1.325 the load of `.github/workflows/quality.yml:116` wrote nothing, twice **[measured]**.
  With the version CI pins, run through `npx` as above, it wrote the folder in 4 seconds, and then both
  `tsc -p tsconfig.mod.json` (6.0.2, 2.8 s) and `npx -y -p typescript@5.6 tsc -p tsconfig.mod.json` (5.6.3, 3.2 s)
  passed **[measured]**. Do this once per work tree and again after a restart of the container.
- That `claude -p "hi"` got an answer from a model **[measured]**. It is one short request on the session's own
  access. No key was set for it.
- `gh` is installed (2.89.0) but `gh auth status` said the token in `GH_TOKEN` is invalid **[measured]**. Use the
  GitHub tools of the session for the pull request and for CI results, and check `gh auth status` before any `gh`.
- The shell of the planning session exported `BUN_OPTIONS=--smol` **[measured]**; the bun timings below include it.

## 2. What runs here, and how long it takes

All of these ran on the merged tree (pull request 115 plus the plan and the evidence) **[measured]**. Every command
that finished passed. One was stopped by the dry run's own limit of 9 minutes a command. Case files 5 and 6 were
timed by a later rehearsal on the same machine, idle.

| Command | Result | Seconds |
|---|---|---|
| `bash scripts/quality-check.sh` | PASS 9, FAIL 0 | 7.0 |
| `bash scripts/validate-docs.sh` | PASS 10, FAIL 0 | 0.2 |
| `bash scripts/validate-directory.sh` (also inside `quality-check.sh`) | OK | 5.2 |
| `bash scripts/validate-readme.sh`, `bash scripts/validate-plugin.sh`, `python3 scripts/validate-panels.py` | pass | under 1 together |
| `bash scripts/check-mod-calls.sh` | OK, 20 calls | 4.9 |
| `bash scripts/selftest/test-check-mod-calls.sh` | pass | 2.4 |
| `bash scripts/check-known-limits.sh` | pass | 0.1 |
| `bash scripts/selftest/test-validate-directory.sh` | pass | 23.6 |
| `claude plugin validate --strict .` (2.1.325) | Validation passed | 4.2 |
| `claude plugin test .` (2.1.325, no key set) | 1774 pass, 0 fail, 40 files | 36.4 |
| The same suite on 2.1.287 through `npx` | 1774 pass, 0 fail | 40.3 |
| `tsc -p tsconfig.mod.json`, after the types were made | no output | 2.8 |
| `bash scripts/selftest/run-selftest.sh --fast` (case files 10 to 31, 4 at a time) | PASS 837, FAIL 0 | 180.2 |
| `TEMPER_CASES_ONLY=29 bash scripts/selftest/test-temper.sh` (10 assertions) | PASS 10 | 5.3 |
| `TEMPER_CASES_ONLY=13 bash scripts/selftest/test-temper.sh` (43 assertions) | PASS 43 | 27.5 |
| `bun scripts/e2e/run.ts plain full-run` (one scenario, one mode, 70 steps) | PASS | 32.0 |
| `bash scripts/e2e/ab-replay.sh` (three replays side by side) | the table of `docs/evidence/ab-replay-9.8.5.md:26-35` | 54.4 |
| `bun scripts/e2e/run.ts plain` (23 scenarios, one mode) | stopped at the limit of 540 s: 16 scenarios passed, none failed | 540, so about 34 a scenario |
| Case file 1 alone (the slow files ran 4 at a time) | PASS 214 | 134.3 |
| Case files 2 and 3, one process | PASS 502 | 165.1 |
| Case file 4 alone | PASS 248 | 44.7 |
| Case file 7 alone | PASS 22 | 15.2 |
| Case files 8 and 9, one process | PASS 278 | 342.0 |
| Case file 5 alone | PASS 445 | 783 (idle machine) |
| Case file 6 alone, after the helper fix of WP01 | PASS 114 | 266 |

How to read the table:

- The selftest runner has four ways to run (`scripts/selftest/run-selftest.sh:6-9`). No word: every case file, as
  many at a time as there are CPUs. `--fast`: case files 10 to 31. `--slow`: the serial `test-temper.sh`, which is
  what CI runs at the head (24 to 33 minutes there, `docs/plans/one-go/evidence/dev-efficiency.md` section 1.2).
  `--changed [REV]` maps changed files to case files but always adds 10 to 31 (`:49`), so it never costs less
  than the fast tier.
- One assertion costs 0.2 to 0.6 seconds (248 in 44.7 s, 43 in 27.5 s, 10 in 5.3 s; CI, in series: 0.51 to
  0.69). A new case file with 20 assertions costs about 12 seconds alone. Use that to judge what a package adds
  to the quick gate.
- One scenario in one mode costs about 32 seconds. The suite is 23 scenarios in 3 modes (`scripts/e2e/run.ts:7-10`).
  To run one: `bun scripts/e2e/run.ts plain <name>`; in every mode with the trace compare:
  `bun scripts/e2e/run.ts all <name>`.
- Each scenario leaves a folder `/tmp/temper-e2e-<name>-XXXXXX` of about 1 MB behind
  (`scripts/e2e/world.ts:34`; more than 160 were on the machine after one day of work). **[suggestion]** Remove
  them at each phase gate, when no suite is running.
- Case file 5 is the long pole: alone it takes 783 seconds, so no parallel run ends under 13 minutes. Case file 6
  ran for more than 9 minutes at the head, as an earlier reader saw too
  (`docs/plans/one-go/evidence/dev-efficiency.md` section 1.1): it runs helpers of case file 5 again. Once WP01
  has closed those helpers it takes 266 seconds. The whole parallel selftest was not measured in one piece. From
  the parts it is 14 to 18 minutes on this machine: an estimate, not a measurement.
- The end to end suite in one mode did not finish in 9 minutes either. At 34 seconds a scenario, one mode is about
  13 minutes and `all` about 39 minutes in one process (CI: 30.5 minutes). Both are estimates from 16 scenarios.

What only CI runs:

- The 10 jobs on `ubuntu-latest`, with that image's bash, git and Python. The local Python is 3.13.18.
  **[suggestion]** Read `python3 --version` in the log of the first CI run and use no syntax newer than it.
- The Official Manifest Validation job installs the newest Claude Code with no version
  (`.github/workflows/quality.yml:77`). A release of Claude Code can turn it red with no change here (commit
  `0f54e7f` was such a day). WP01 pins it.
- The Mod job on Claude Code 2.1.287 (`quality.yml:107`). It can be repeated here step by step with
  `npx -y -p @anthropic-ai/claude-code@2.1.287 claude ...` **[measured]**: the suite, the strict validation (1.2 s),
  the types and the type check all ran and passed that way.
- The serial order of `test-temper.sh` until WP01 replaces the job. Its total at the head is 2,575
  (`docs/plans/one-go/evidence/pr-tests-ci.md` section 1.1); the parallel runner counts more, because case file 6
  alone runs helpers of case file 5 again. Compare each total only with its own kind.
- The bench. It is never part of CI and needs the owner's word and a model access (section 9).

## 3. The gate: `scripts/verify.sh`

The script is written by WP01, and its table of steps is in `docs/plans/one-go/wp/phase-1-speed-and-room.md`. This
section adds the measured seconds and the steps later packages add. Until WP01 is done, WP00 runs the commands of
`full` by hand. The script has three words (`docs/plans/one-go/contracts.md` section 1): WP01 writes `quick` and
`full`, WP07 adds `final`, and WP05, WP06, WP07 and WP32 add steps. Its last line is `verify quick: PASS` or
`verify quick: FAIL`, and the same for `full` and `final`.

`quick [REV]`, at the end of every package. The target is about 3 minutes.

| Order | Step | What it proves | Seconds here |
|---|---|---|---|
| 1 | `bash scripts/validate-directory.sh` | the 13 rules of the plugin directory (`scripts/validate-directory.sh:5-40`); run it first: two commits of pull request 115 exist only to satisfy it | 5 |
| 2 | `bash scripts/quality-check.sh` | no file over 256 KiB, manifests, versions, panels (and the caps from WP05 on) | 7 |
| 3 | `validate-docs.sh`, `validate-readme.sh`, `validate-plugin.sh`, `validate-panels.py`, `check-known-limits.sh` | docs, README, plugin layout, the documented limits of the guard | 1 |
| 4 | `python3 scripts/selftest/check-names.py` (WP01), `bun scripts/e2e/xfail.ts --check` (WP06) and `python3 scripts/check_done.py` (WP07) | no script reads an unknown name; the expected to fail rule decides as it should; every promise has its check, and the count of expected failures is printed | about 2 |
| 5 | `bash scripts/selftest/run-selftest.sh --touched REV` | the case files this package changed or added | 12 for 20 assertions |
| 5b | both fixture compares (the output of `bash scripts/selftest/make-view-fixtures.sh` piped into `cmp - scripts/selftest/view-fixtures.ts`, and the same with `extra` and `view-fixtures-2.ts`), when a file under `scripts` outside `scripts/selftest` changed | the fixtures the mod's tests read are what the CLI writes now | about 40 (29 measured for the first) |
| 6 | `bun scripts/e2e/run.ts both full-run`, when a file under `scripts` outside `scripts/selftest` changed | one whole run, with the mod and without it, and the two traces equal | about 65 |
| 7 | `bun scripts/e2e/run.ts plain default-run fix --floor scripts/e2e/floor.json` (WP05) | the counts of dialogs and launches did not move unseen | about 45 |
| 8 | `claude plugin test .` and `bash scripts/check-mod-calls.sh`, when a `.ts` or `.tsx` file changed | the mod, and its reviewed host calls | 41 |
| 9 | `tsc -p tsconfig.mod.json` (WP01 runs it as `npx -p typescript@5.6 tsc -p tsconfig.mod.json`) | the mod and its tests against the host's types | 3 |

Added up, a package that touches scripts, the mod and two case files lands near 230 seconds on this machine under
load, and a package that touches scripts only near 190. **[suggestion]** Let steps 5, 5b and 6 run side by side;
they are separate processes, and `quick` then stays near 3 minutes.

`full`, at the end of every phase, and once more after WP13 and after WP30, as the table of
`docs/plans/one-go/README.md` section 5 says.

| Order | Step | What it proves | Seconds here |
|---|---|---|---|
| 1 | steps 1 to 4 of `quick` | as above | 15 |
| 2 | `bash scripts/selftest/run-selftest.sh` | every case file | 14 to 18 minutes (estimate; case file 5 alone is 13) |
| 3 | `bun scripts/e2e/run.ts all --floor scripts/e2e/floor.json`, as 4 shards side by side | 23 scenarios in 3 modes, the trace compare, the floor | 10 to 13 minutes (estimate: 39 minutes of work on 4 CPUs) |
| 4 | `claude plugin test .`, `claude plugin validate --strict .`, `check-mod-calls.sh`, `test-check-mod-calls.sh`, `tsc -p tsconfig.mod.json` | the mod's suite, its manifest, its reviewed calls, its types | 51 |
| 5 | `bash scripts/selftest/test-validate-directory.sh` | the directory rules still catch what they should | 24 |
| 6 | `bun scripts/e2e/replay.ts final` with `python3 scripts/check_floor.py --replay`, and `bash scripts/e2e/ab-replay.sh 10e965a` (about 55 s); WP05 adds both. The base column of the second must equal the numbers of 9.8.5 that WP05 recorded (the entry `replay_base` of `scripts/e2e/floor.json`); from WP08 on a package can move it | the measured bad run, replayed; the harness still drives the CLI of 9.8.5 to the same numbers | about 95 |

Added up, `full` is about 30 minutes on this machine once WP01 has made the shards, and it grows toward 45 as the
end to end suite goes from 23 to about 55 scenarios during the build. At WP00 there are no shards: the end to end
suite alone is about 39 minutes, and the baseline about 55 minutes of machine time. None of these totals was
measured in one piece; WP00 and WP01 write the real numbers into `PROGRESS.md`.

On the type check, as WP01's text now says too: the whole type check does run here. Make the types with Claude Code
2.1.287 through `npx` (section 1); the compile of the two fixture files alone is not needed as a fallback on this
machine.

`final` is `full` plus the closing checks of WP07 (`check_done.py --final`, `check_caps.py --final`,
`check_floor.py --final`, `check_changed_tests.py`, and the bench block: the scorecard file inside the lines of part
H of `done.md`, or the line `OPEN: the bench gate (needs the owner's word and a model access)`), plus the one
thing WP32 adds: in `final` the replay against 9.8.5, `bash scripts/e2e/ab-replay.sh 10e965a`, also fails when
this tree is worse than the base. That compare is in `final` and in no other mode: in `full` the call carries
`--base-only`. `final` is run by WP32.

Two rules for running the gate:

- The shell tool stops a foreground command after 10 minutes at most **[read]**, and `full` takes longer. Start
  `full` as a background command with a time limit of 90 minutes, let it write its output to a file, and read the
  last line (`verify full: PASS` or `verify full: FAIL`). Never start a second `full`, or a parallel selftest,
  while one runs: both use every CPU. `quick` after an edit of case file 5 is a background command too: that
  file alone takes 13 minutes (`docs/plans/one-go/contracts.md` section 10).
- A red gate is repaired, never bent. The gate is not edited to get green, a step is not taken out, and a failing
  check is put on `scripts/selftest/expected-fail.txt` only by WP07's rule: it was written to fail first.

## 4. The layout of `docs/plans/one-go/`

| Path | What it is | Who writes it |
|---|---|---|
| `docs/plans/two-approval-run.md` | the plan | merged in; WP31 sets its status line |
| `README.md` | the brief: the settled decisions, the method, the one build order, the eleven rules | the kit; never edited |
| `session-mechanics.md` | this file: the first ten minutes, the gate script, `PROGRESS.md`, the rhythm, the resume rule | the kit |
| `contracts.md` | the names every package must use, each with the package that creates it | the kit; no line of it is changed, and a package that needs a new shared name adds one line, as the page says |
| `done.md` | every promise and the check that proves it; `scripts/check_done.py` reads it | the kit; WP07 corrects check names, and nothing else in it is edited |
| `pr-115-fixes.md` | the decision for each defect of pull request #115 | the kit; never edited |
| `wp/phase-*.md` | the specs of the work packages WP00 to WP32, several packages a file | the kit; never edited |
| `evidence/` | the reports and prototypes the specs cite: 35 reports of the planning session and `prototypes/` with the diffs its verifiers made | the kit; removed by the last commit (WP32) |
| `PROGRESS.md` | the state of the build, one line a package | WP00 creates it, every later package updates it |
| `changed-tests.md` | every changed or removed assertion of the base, with the reason | WP07 creates it |

The reports under `evidence/` cite scratch folders of the planning session (`understand/`, `verify/`, `work-*`).
Those folders do not exist for you. The report itself is all there is; a prototype named in a spec is under
`evidence/prototypes/`.

If a spec is wrong (a line moved, a function is named differently, a step cannot work), do not edit the spec.
Find the function by its name; if a mechanism cannot work as written, choose the smallest change that still makes
the checks of the package pass (`docs/plans/one-go/README.md` section 4). Write one line under "Found on the way"
in `PROGRESS.md`, do what the goal of the package asks, and go on. Where a spec and `contracts.md` differ on a
name, `contracts.md` wins; where a spec and `done.md` differ on what must hold, `done.md` wins.

## 5. `PROGRESS.md`, exactly

```markdown
# Progress of the one pass build

- Branch: `one-go`
- Pull request: 123 (draft)
- Base: `7c7a1c1` (main), `10e965a` (pull request 115), `<tip of ccr-88156f39-u643ta>` (plan and kit)
- Watch: one check is scheduled; the next is due 2026-11-17 14:00 UTC

## Baseline

| Check | Result | Seconds |
|---|---|---|
| selftest, parallel | PASS 2879, FAIL 0 | 1140 |

## Packages

| Id | State | Commit | Date | Note |
|---|---|---|---|---|
| WP00 | done | `1a2b3c4` | 2026-11-17 | baseline green; pull request opened |
| WP01 | doing | | 2026-11-17 | tests written; fixtures regenerated; workflow left |
| WP02 | todo | | | |
| WP09 | blocked | | 2026-11-18 | see Blockers 1 |
| WP10 | todo | | | |
| WP18 | todo | | | |
| WP14 | todo | | | |
| WP11 | todo | | | |

## Phase gates

| Phase | Commit | Date | Result of `full` | Seconds | Expected to fail |
|---|---|---|---|---|---|
| 1 | `2b3c4d5` | 2026-11-17 | PASS | 1980 | 0 |

## Blockers

1. WP09: what blocks it, what was tried, which packages wait for it.

## Found on the way

- 2026-11-17 WP04: a fixture view has two recommended options; asserted the views that hold.

## Follow ups of pull request 115

- [ ] U1 (WP25): a plan patch keeps the marks of a failed fix.
- [x] U19 (WP08): three run files are not in the exclude list and outlive the run.
```

The example shows a few lines of each table; the real table "Packages" has all 33. The rules of the file:

- WP00 creates the file. The table "Packages" has one line for each of WP00 to WP32 from the first commit on, in
  the build order of `docs/plans/one-go/README.md` section 5, which is not the order of the numbers: WP00, WP01,
  WP02, WP03, WP04, WP05, WP06, WP07, WP08, WP09, WP10, WP18, WP14, WP11, WP12, WP13, WP15, WP16, WP17, WP19, WP20,
  WP21, WP22, WP23, WP24, WP25, WP26, WP27, WP28, WP29, WP30, WP31, WP32. Nothing else in the file is read by the
  resume rule.
- **State** is one of four words. `todo`: not started. `doing`: started; the note says what is done and what is
  left, and it is rewritten whenever that changes. `done`: the quick gate was green on the commit named in the
  line. `blocked`: a true blocker; the number of its entry under "Blockers" is in the note.
- **Commit** is the short hash of the package's own commit, in a code span; empty until the package is done.
  A package with several commits names its last one. WP32 alone names the commit before its last (its spec
  says why).
- **Date** is the day (UTC) the state last changed.
- **Note** is one sentence, with no line break and no vertical bar.
- "Phase gates" gets one line for every `full` that ended a phase, red ones included, and for the two more after
  WP13 and after WP30.
- "Found on the way" takes what the pull request text must tell the owner: a spec that was wrong, a defect found
  and not fixed, a cap that cannot be met with its measured number, a check name that changed in CI, a wish the
  brief leaves out (`docs/plans/one-go/README.md` section 9) and an item for the owner (its section 10). A row of
  `done.md` whose package the build order moved is not noted: its last column already names the package
  (`docs/plans/one-go/contracts.md` section 13).
- "Follow ups of pull request 115" is not there before WP08: that package adds the section, one line for each
  point of `docs/plans/one-go/pr-115-fixes.md` section 3 with the package that takes it. The package that closes a
  point ticks its line, a point the build drops is marked dropped, and WP32 reads the list in its first step.
- No markdown link anywhere in the file: `scripts/validate-docs.sh` (rule 2, `:74-81`) follows every link under
  `docs`.

## 6. The rhythm of a package

1. Mark the line `doing`, and commit and push that one line (`docs(progress): WP11 doing`).
2. Read the spec. Write the tests of "Tests first" and see each one fail for the reason of its promise.
3. Make the change. Run the narrow check often: one case file
   (`TEMPER_CASES_ONLY=N bash scripts/selftest/test-temper.sh`), one scenario
   (`bun scripts/e2e/run.ts plain <name>`).
   - 3a. Checkpoint. In a package of size L, and every two hours at the latest, commit what stands as
     `wip(wp11): <what is done>` with the note of the line rewritten, and push. A checkpoint needs
     `bash scripts/validate-directory.sh` and `bash scripts/quality-check.sh` green and nothing else; CI on a
     checkpoint is not read. Each commit of a package of several commits (WP02 a wave, WP08 a defect) is pushed
     when it is made.
4. `bash scripts/verify.sh quick`. Red: repair and run it again.
   - 4a. From WP08 on, in the serial lane: after the green `quick` start
     `TEMPER_SELFTEST_JOBS=3 bash scripts/selftest/run-selftest.sh` in the background and read the next spec while
     it runs (about 15 minutes). The progress commit waits for its `FAIL: 0`. A case of the base that it shows red
     is repaired in this package, or, when the package changed that behaviour on purpose, rewritten and listed in
     `changed-tests.md` in this package. It is never left for the phase gate.
5. The package commit: the work, its tests and its documents in one commit. The subject follows the style of the
   repository and carries the id in the scope, for example `feat(wp11): the approval runs to the commit`. Add files
   by name; `git add -A` is for a tree you have just read with `git status --short`. Where a spec splits its work
   over several commits (WP02 a wave, WP08 a defect), each follows a green `quick` and carries the id; the last
   one is the package commit, and the progress commit comes once, after it.
6. The progress commit: set the line to `done` with the hash of step 5, the date and a note; commit only
   `PROGRESS.md` as `docs(progress): WP11 done`. A commit cannot name its own hash, which is why the line is a
   second, small commit.
7. One push for both: `git push -u origin <branch>`. **[suggestion]** If the push fails on the network, try again
   after 2, 4, 8 and 16 seconds, then write it under "Found on the way" and go on; the next package pushes all.
8. At the end of a phase: `bash scripts/verify.sh full` in the background, one line under "Phase gates", and the
   pull request text updated (section 7). While it runs, read the specs of the next phase and write its tests, but
   start no suite. A red `full` is repaired before any package of the next phase is committed. Then the review of
   the phase (`docs/plans/one-go/README.md` section 4): agents that did not write it read the whole diff of the
   phase against the specs and the eleven rules of the brief's section 6, and what they find is fixed before the
   next phase.

This is the rhythm of `docs/plans/one-go/README.md` section 4: two commits and one push end every package, with
pushed checkpoints between them. WP00 and WP32 say in their specs where they differ.

No commit hook is installed in a fresh clone of this repository **[measured]**: nothing but the gate stands between
a red tree and a commit, so step 4 is never left out. Do not start a Temper run on the repository itself during the
build: that is a rule of the brief (`docs/plans/one-go/README.md` section 4). The CLI allows it for this one folder
(`scripts/temper:191-198`), but its run state would sit in the tree you are changing, and the run you are
rebuilding would stop you at every gate.

## 7. The draft pull request

- Open it when WP00 is pushed: base `main`, head the build branch, as a draft, with the GitHub tool of the session
  (`create_pull_request` with `draft: true`). Not tried by the dry run.
- Title: `Temper 10.0.0: a run that asks twice`. It does not change.
- The text, from the first day: what the pull request will hold (one paragraph from the plan), the line
  `Supersedes pull requests 115 and 116, whose commits are inside this one` (pull request 116 is the plan and this
  kit, branch `ccr-88156f39-u643ta`; `docs/plans/one-go/README.md` section 8), the table "Packages" of
  `PROGRESS.md` cut to id and state, the last line of "Phase gates", and the lists "Blockers" and "Found on the
  way". Update it at every phase gate with
  `update_pull_request`. WP32 writes the final text, with the parts the brief's section 8 names.
- CI runs on every push to the pull request (`.github/workflows/quality.yml:6-7`), draft or not. At the head no run
  is cancelled by a newer push: until WP01 is in, each push costs one whole run of 30 to 60 minutes
  (`docs/plans/one-go/evidence/dev-efficiency.md` section 1.2). That is one more reason to do WP01 first.
- Never mark it ready, never merge it, never close pull request 115 or 116, never push a tag: a tag `v*` starts
  the release workflow (`.github/workflows/release.yml:3-6`). Those four are the owner's
  (`docs/plans/one-go/README.md` section 10).

## 8. Lanes, subagents and workflows on 4 CPUs

What is known: the machine has 4 CPUs; the fast tier alone keeps 3 to 4 of them busy for 3 minutes; `full` keeps
all of them busy for its whole time. The planning session reports that a workflow runs 2 agents at a time and that
two workflows can run side by side; the dry run did not measure that.

- **One serial lane for the flow core.** Every package that the second table of `docs/plans/one-go/README.md`
  section 5 marks serial runs here, one after another, in the main work tree. That is every package but WP06 and
  WP07, and the merges of those two are serial too; the table decides, whatever the Lane of a spec says. Its files
  are the flow modules, `scripts/temper`, `scripts/go.py`, the view and the fixtures. Two packages never edit them
  at the same time, in any work tree.
- **Side lanes in work trees.** What may run beside the serial lane is the list of that section: the five new
  files of WP06 while WP05 is built, the new files of WP07 while WP06 is built, the new selftest case file of the
  next package (`docs/plans/one-go/contracts.md` section 10 reserves its number), the pages of WP31 after its
  steps 1 to 3, and the reviewers. The way: `git worktree add ../wp06 -b wp06 HEAD`, the agent works and commits
  there, the conductor merges with `git merge --no-ff wp06` in the main work tree once the package before it is
  done, runs `quick`, pushes, and removes the work tree. The side branch is never pushed. Each work tree needs its
  own types folder (section 1).
- **A side lane is lost by a restart.** Work trees outside the repository folder and unpushed branches do not
  survive a new container. Keep side packages small, and merge and push each as soon as its `quick` is green.
- **At most 3 agents that run suites at one time** **[suggestion]**: the serial lane and one side workflow of two.
  With two lanes active, run the selftest with `TEMPER_SELFTEST_JOBS=2` (`scripts/selftest/run-selftest.sh:17`).
- **`full` runs alone.** Start it when the lanes are between packages. While it runs, agents may read and write
  files but start no suite.
- **Who does what** **[suggestion]**. The conductor (the main session) holds `PROGRESS.md`, the merges, the pushes
  and the gate. It gives a package to a subagent with: the absolute path of the work tree, the spec file and the
  heading, `docs/plans/one-go/contracts.md` for the names, the list of section 10, the rows of the package under
  "Rows by package" of `done.md`, with its note 8, and the order to end with the last line of `quick`, the files
  changed and anything for "Found on the way". A subagent never pushes and never
  edits `PROGRESS.md`. Which model an agent runs on is section 7 of `docs/plans/one-go/README.md`.
- **Tests by another hand** **[suggestion]**. Where the size allows, let one agent write the tests of "Tests first"
  from the spec and another make the change. The reviewer of a package is never the agent that wrote it.
- The selftest and the scenarios work in folders of their own under `/tmp` (`scripts/selftest/test-temper.sh:18`,
  `scripts/e2e/world.ts:34`), so two work trees can run them at once without touching each other.

## 9. The bench

What a round needs **[read]**: node and `cd bench && npm install` (one package, `@anthropic-ai/claude-agent-sdk`
0.3.318, `bench/package.json`); Python 3 for the grading; a model credential in the environment, which
`bench/run.mjs:158` hands to the Agent SDK as it is; the network hosts of the npm registry and of the model API. It
runs every arm with permissions bypassed in a scratch folder (`bench/run.mjs:154-155`) and writes its results under
`~/temper-bench-results` or `$TEMPER_BENCH_RESULTS`, outside the plugin folder (`bench/run.mjs:36`). Runs go one at
a time, a graded run is not run again (`bench/run-all.sh:13`), so a round that was cut off goes on where it stopped
as long as the results folder is still there.

What the dry run found on its machine **[measured]**, by names only: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`
and `CLAUDE_CODE_OAUTH_TOKEN` are not set; there is no `~/.claude/.credentials.json`; `ant` is not installed;
`bench/node_modules` is not there. `ANTHROPIC_BASE_URL` and `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` are set, and a
nested `claude -p` did answer, so a child process can reach a model on the session's own access. Whether the Agent
SDK can use that access for a round was not tried, and it is the owner's to allow, never the session's to take.

What a round costs (`docs/plans/one-go/done.md`, note 1, from round M1 of
`docs/plans/one-go/evidence/v-targets-scorecard.md` section 4): the round before, on `10e965a` with plain Claude
Code beside it, is 36 runs, 40 to 50 dollars and 3 to 4 hours; the round after, on the result, is 18 runs, about 30
dollars and 2.7 hours. Together about 80 dollars and 6 hours. The model test of WP32 (the same tasks once more,
with the planner on Sonnet below risk H) is 18 runs more, about 30 to 45 dollars and 3 to 5 hours. All three: about
110 to 125 dollars and 9 to 11 hours, one run at a time.

What the owner gives is one sentence in the first message of the session: that the bench may run, and on what
access (a key in the environment, or this session's own model access). That sentence is also the word that the
money and the hours above may be spent.

The rule for the build session: the bench runs when the owner's first message says it may, on the access that
message names. "This session's own model access" is allowed only when the message says so. A key that is set in
the environment with no such sentence is not that word. If the Agent SDK cannot use the access the message names,
write one line under "Blockers" and leave part H of `done.md` open. With no such sentence the session does not
ask: it leaves part H open and says so in the pull request text. Never ask for a key in the conversation, and
never write one into a file. What WP32 runs, and in what order, is the bench block of its spec
(`docs/plans/one-go/wp/phase-0-and-9-setup-and-final.md`).

## 10. Never

- Never skip, disable, delete or weaken a test or a gate step to get green. Never add `.skip`, `.only` or `.todo`.
- Never put a check on the expected to fail list that passed before, and never take one off except in the commit
  that makes it pass (after `wip` checkpoints: in the package commit at the latest).
- Never raise a `final` of `scripts/caps.json` or `scripts/e2e/floor.json`, and never take a stop out of
  `scripts/stops.json` without a decision record.
- Never force push, never amend or rebase a pushed commit, never commit with `--no-verify`.
- Never push to another branch, never push a tag, never merge or mark ready the pull request, never close 115 or
  116.
- Never wait for CI. Push and go on; read its result when it is there (section 11).
- Never stop to ask the owner. A true blocker goes under "Blockers" in one line, is said once in the reply, and the
  next package that does not depend on it starts. The brief names the only two (`docs/plans/one-go/README.md`
  section 4): the word that the bench may run, with the access it runs on, and anything a host refuses.
- Never edit `README.md`, `contracts.md`, `done.md` (but for a check name, as WP07 says) or a spec. These are the
  files of `docs/plans/one-go/`: its `README.md` is the brief, not the README of the repository, which WP31
  rewrites. The one thing a package does to `contracts.md` is what that page itself allows: it adds the line of a
  new shared name, in its own commit, and changes no line that is there.
- Never run `/temper:temper` on this repository during the build (`docs/plans/one-go/README.md` section 4).
- Never build what the brief leaves out (its section 9), also when a review asks for it.
- Never copy kit files by hand, and never commit `.claude-plugin/types/`, a results folder of the bench or a key.
- Never run two suites that each use every CPU at once.

## 11. When CI is red

The session does not wait for CI, but it reads it: at the start of every package, and whenever a pull request event
arrives. **[suggestion]** Subscribe the session to the pull request's activity once, so that a finished run arrives
as an event; otherwise read the check runs of the last pushed commit with the GitHub tool.

1. Read which job failed and fetch its log (`get_job_logs`).
2. Run the same command here. The table is of the head; WP01 renames the two long jobs and adds shards.

   | Job (`quality.yml`) | The command here |
   |---|---|
   | Quality Checks (`:10`) | `bash scripts/quality-check.sh` |
   | temper CLI Unit Tests (`:18`) | the case file the log names: `TEMPER_CASES_ONLY=N bash scripts/selftest/test-temper.sh` |
   | README Validation (`:26`) | `bash scripts/validate-readme.sh` |
   | Directory Readiness (`:34`) | `bash scripts/selftest/test-validate-directory.sh && bash scripts/validate-directory.sh` |
   | Documentation Validation (`:44`) | `bash scripts/validate-docs.sh` |
   | Plugin Structure (`:52`) | `bash scripts/validate-plugin.sh` |
   | Stage Panel Validation (`:60`) | `python3 scripts/validate-panels.py` |
   | Official Manifest Validation (`:68`) | `claude plugin validate --strict .` (CI: the newest Claude Code) |
   | End to end (`:81`) | the scenario the log names: `bun scripts/e2e/run.ts all <name>` |
   | Mod (`:98`) | the steps of `:108-125`, with `npx -y -p @anthropic-ai/claude-code@2.1.287 claude` for `claude` |

3. It fails here too: the gate has a hole. Fix the fault test first, add the missing step to `scripts/verify.sh`
   if a step was missing, and commit it as its own commit (`fix(ci): ...`) before the next package commit.
4. It passes here: the cause is the difference between the two machines (the version of Claude Code, of Python, of
   bash; a time limit; the serial order). Read the log again for that. Repeat the job's own version here where
   that is possible (`npx` for Claude Code and TypeScript). If it cannot be repeated, write it under "Found on the
   way" and go on; do not push empty commits to run CI again. A job gets one rerun at most
   (`docs/plans/one-go/README.md` section 4).
5. A run that was cancelled by a newer push (after WP01) is not red. Look only at the newest run.
6. Red CI never stops the next package, except when the failing job is the gate of the phase just ended: then the
   repair comes first.

## 12. Keeping on with nobody watching

- Work in long turns. End a turn only when a background command must finish and nothing else can be done.
- Keep exactly one scheduled check pending, one hour ahead. In a cloud session the tool is `send_later` with
  `delay_minutes: 60` (elsewhere: whatever timed message the session has). By its own description the message
  waits for a running turn to end and survives a restart of the container **[read]**. The message:

  ```
  One pass build, hourly check. If a workflow, a subagent or a background command of this session is still
  running, do nothing but schedule this check again in 60 minutes. Otherwise follow the resume rule of
  docs/plans/one-go/session-mechanics.md section 13 and go on. Then schedule this check again.
  ```

- Write the due time of the pending check into the head of `PROGRESS.md` (the line "Watch"), so that a restarted
  session knows whether one is pending. When the build is done (WP32 pushed), schedule no further check.
- When a background `full` finishes, the session is told; do not poll it in a loop.

## 13. The resume rule after a restart

A session that finds finished packages in `docs/plans/one-go/PROGRESS.md` is a restarted session
(`docs/plans/one-go/README.md` section 2): it never starts over, it does not create the file again, and it goes on
from the first package that is not done.

1. `git fetch origin` and `git status -sb`. Local commits ahead of `origin`: push them. `origin` ahead: take it with
   `git pull --ff-only`. There is only ever one session on the branch.
2. Read the table "Packages" of `PROGRESS.md`.
3. The work tree has changes: they belong to the line that says `doing`. Keep them, read `git diff --stat` and the
   note, and go on with that package. Never throw uncommitted work away unread.
4. The newest commit is a package commit with no progress commit after it (its subject does not start with `wip`,
   carries `(wpNN)`, and the line does not say `done`): run `quick`. Green: write the line, commit, push. Red: the
   package goes on. A `wip` commit is never a package commit: the package goes on from the note of its line. A
   package of several commits (WP02 a wave, WP08 a defect) goes on too while the note of its line or its "Done
   when" says work is left: only its last commit is the package commit.
5. `git worktree list`, then `git worktree prune`. A side lane whose work tree is gone starts again from its spec.
6. Make the types folder again (section 1). Nothing in the background survived: a `full` that was running is
   started again.
   - 6a. What was kept outside the repository is gone (the capture and the traces of WP02 and WP03). Make a base
     again from a work tree of the package commit of the line above:
     `git worktree add --detach ../base <hash>`.
7. Take the first line, in the order of the table (the build order of `docs/plans/one-go/README.md` section 5),
   that is not `done` and whose "Depends on" packages, as the second table of that section lists them, are all
   `done`. A `blocked` line is skipped until its blocker is gone. When no such line is left, the build is at WP32
   or it is over. Never start over: a line that says `done` stays done.
8. Make sure one hourly check is pending (section 12).
