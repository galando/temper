# Session mechanics for the one pass build

This file tells the build session how to work: the first ten minutes, the gate, the progress file, the commit and
push rhythm, the lanes, and how to keep going with nobody watching. It holds no package spec; those are in
`docs/plans/one-go/wp/`. The method and the settled decisions are in `docs/plans/one-go/FRAME.md`.

Everything marked **[measured]** was run on 2026-11-16 by a dry run in a clone, on the machine the planning session
used: 4 CPUs, 15 GB of memory, bun 1.4.4, node 22.23.4, tsc 6.0.2, Python 3.13.18, Claude Code 2.1.325, with other
agents on the same machine (load average 1.3 to 4.5). Every second below is therefore an upper bound.
**[read]** means read in the code or in a tool's own description. **[suggestion]** means neither: judge it yourself.

## 1. The first ten minutes

The three commits the branch is made of **[measured]**:

| What | Branch on `origin` | Commit |
|---|---|---|
| The base | `main` | `7c7a1c1` (version 9.8.4) |
| Pull request 115 | `ccr-e0b10914-a7hzu0` | `10e965a` (version 9.8.5, 16 commits on top of `7c7a1c1`) |
| The plan and this kit | `ccr-88156f39-u643ta` | `8477375` (the plan), `65c7d42` (the evidence), then the kit commit |

The merges were rehearsed in a clone: both are clean, with no conflict, and `git diff --stat 10e965a HEAD` then
shows only files under `docs/plans` (43 files at `65c7d42`). The fetch from GitHub itself was not rehearsed.

```bash
# 1. Where am I, and is the history deep enough
git status -sb && git remote -v
git fetch origin main ccr-e0b10914-a7hzu0 ccr-88156f39-u643ta
git rev-parse --short origin/main origin/ccr-e0b10914-a7hzu0 origin/ccr-88156f39-u643ta
git cat-file -e 7c7a1c1 && git cat-file -e 10e965a || git fetch --unshallow origin

# 2. The branch: use the one this session was told to develop on; make one only if none was named
git checkout -b one-go origin/main
git merge --no-ff --no-edit 10e965a
git merge --no-ff --no-edit origin/ccr-88156f39-u643ta
git merge-base --is-ancestor 10e965a HEAD && ls docs/plans/one-go/FRAME.md docs/plans/one-go/done.md
git diff --stat 10e965a HEAD | tail -1

# 3. The tools
bun --version; python3 --version; node --version; claude --version; tsc --version
npx -y -p @anthropic-ai/claude-code@2.1.287 claude -p "hi" --plugin-dir . --debug-file /tmp/mod-debug.log
test -f .claude-plugin/types/claude-code/index.d.ts && echo "types ready"

# 4. One minute of proof that the tree is sound
bash scripts/quality-check.sh && bash scripts/validate-docs.sh && bash scripts/check-mod-calls.sh
tsc -p tsconfig.mod.json && claude plugin validate --strict .
```

Then read `FRAME.md`, `done.md` and this file, start the baseline of WP00 in the background, and write
`PROGRESS.md` while it runs.

Notes on those commands:

- Merge `10e965a` by its hash, not by the branch name. Every `file:line` in the kit is of that commit. If the
  branch of pull request 115 has moved, write the newer commits into `PROGRESS.md` under "Found on the way" and
  leave them out.
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
that finished passed. Three were stopped by the dry run's own limit of 9 minutes a command.

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
| Case file 5 alone | stopped at the limit of 540 s, not finished, no failure printed | over 540 |
| Case file 6 alone | stopped at the limit of 540 s, not finished, no failure printed | over 540 |

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
- Case files 5 and 6 are the long poles: each ran for more than 9 minutes and was stopped. An earlier reader saw
  the same (`docs/plans/one-go/evidence/dev-efficiency.md` section 1.1). So the whole parallel selftest was not
  measured to its end here. From the parts it is 12 to 15 minutes on this machine: an estimate, not a measurement.
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
- The bench. It is never part of CI and needs a model credential (section 9).

## 3. The gate: `scripts/verify.sh`

The script is written by WP01, and its table of steps is in `docs/plans/one-go/wp/phase-1-speed-and-room.md`. This
section adds the measured seconds and one correction. Until WP01 is done, WP00 runs the commands of `full` by hand.

`quick [REV]`, at the end of every package. The target is under 180 seconds.

| Order | Step | What it proves | Seconds here |
|---|---|---|---|
| 1 | `bash scripts/validate-directory.sh` | the 13 rules of the plugin directory (`scripts/validate-directory.sh:5-40`); run it first: two commits of pull request 115 exist only to satisfy it | 5 |
| 2 | `bash scripts/quality-check.sh` | no file over 256 KiB, manifests, versions, panels (and the caps from WP05 on) | 7 |
| 3 | `validate-docs.sh`, `validate-readme.sh`, `validate-plugin.sh`, `validate-panels.py`, `check-known-limits.sh` | docs, README, plugin layout, the documented limits of the guard | 1 |
| 4 | `python3 scripts/selftest/check-names.py` (WP01) and `python3 scripts/check_done.py` (WP07) | no script reads an unknown name; every promise has its check | about 2 |
| 5 | `bash scripts/selftest/run-selftest.sh --touched REV` | the case files this package changed or added | 12 for 20 assertions |
| 6 | `bun scripts/e2e/run.ts both full-run`, when a file under `scripts` outside `scripts/selftest` changed | one whole run, with the mod and without it, and the two traces equal | about 65 |
| 7 | `bun scripts/e2e/run.ts plain default-run fix --floor scripts/e2e/floor.json` (WP05) | the counts of dialogs and launches did not move unseen | about 45 |
| 8 | `claude plugin test .` and `bash scripts/check-mod-calls.sh`, when a `.ts` or `.tsx` file changed | the mod, and its reviewed host calls | 41 |
| 9 | `tsc -p tsconfig.mod.json` | the mod and its tests against the host's types | 3 |

Added up, a package that touches scripts, the mod and two case files lands near 190 seconds on this machine under
load, and a package that touches scripts only near 150. **[suggestion]** If it passes 180 seconds, let steps 5 and
6 run side by side; they are separate processes.

`full`, at the end of every phase.

| Order | Step | What it proves | Seconds here |
|---|---|---|---|
| 1 | steps 1 to 4 of `quick` | as above | 15 |
| 2 | `bash scripts/selftest/run-selftest.sh` | every case file | 12 to 15 minutes (estimate; files 5 and 6 alone are over 9) |
| 3 | `bun scripts/e2e/run.ts all --floor scripts/e2e/floor.json`, as 4 shards side by side | 23 scenarios in 3 modes, the trace compare, the floor | 10 to 13 minutes (estimate: 39 minutes of work on 4 CPUs) |
| 4 | `claude plugin test .`, `claude plugin validate --strict .`, `check-mod-calls.sh`, `test-check-mod-calls.sh`, `tsc -p tsconfig.mod.json` | the mod's suite, its manifest, its reviewed calls, its types | 51 |
| 5 | `bash scripts/selftest/test-validate-directory.sh` | the directory rules still catch what they should | 24 |
| 6 | `bun scripts/e2e/replay.ts final` with `python3 scripts/check_floor.py --replay` (WP05) | the measured bad run, replayed | about 40 |

Added up, `full` is about 25 to 30 minutes on this machine once WP01 has made the shards. At WP00 there are no
shards: the end to end suite alone is about 39 minutes, and the baseline about 55 minutes of machine time. None of
these totals was measured in one piece; WP00 and WP01 write the real numbers into `PROGRESS.md`.

The correction to WP01's text: the whole type check does run here. Make the types with Claude Code 2.1.287 through
`npx` (section 1); the compile of the two fixture files alone is not needed as a fallback on this machine.

`final` is `full` plus the closing checks of WP07 (`check_done.py --final`, `check_caps.py --final`,
`check_floor.py --final`, `check_changed_tests.py`) and is run by WP32.

Two rules for running the gate:

- The shell tool stops a foreground command after 10 minutes at most **[read]**, and `full` takes longer. Start
  `full` as a background command with a time limit of 90 minutes, let it write its output to a file, and read the
  last line. Never start a second `full`, or a parallel selftest, while one runs: both use every CPU.
- A red gate is repaired, never bent. The gate is not edited to get green, a step is not taken out, and a failing
  check is put on `scripts/selftest/expected-fail.txt` only by WP07's rule: it was written to fail first.

## 4. The layout of `docs/plans/one-go/`

| Path | What it is | Who writes it |
|---|---|---|
| `docs/plans/two-approval-run.md` | the plan | merged in; WP31 sets its status line |
| `FRAME.md` | the method, the settled decisions, the eleven rules, the table of packages | the kit; never edited |
| `done.md` | every promise and the check that proves it; `scripts/check_done.py` reads it | the kit; WP07 corrects check names |
| `session-mechanics.md` | this file | the kit |
| `wp/phase-*.md` | the package specs, several packages a file | the kit; never edited |
| `evidence/` | 35 reports of the planning session and `prototypes/` with the diffs its verifiers made | the kit; removed by the last commit (WP32) |
| `PROGRESS.md` | the state of the build, one line a package | WP00 creates it, every package updates it |
| `changed-tests.md` | every changed or removed assertion of the base, with the reason | WP07 creates it |

The reports under `evidence/` cite scratch folders of the planning session (`understand/`, `verify/`, `work-*`).
Those folders do not exist for you. The report itself is all there is; a prototype named in a spec is under
`evidence/prototypes/`.

If a spec is wrong (a line moved, a function is named differently, a step cannot work), do not edit the spec.
Write one line under "Found on the way" in `PROGRESS.md`, do what the goal of the package asks, and go on.

## 5. `PROGRESS.md`, exactly

```markdown
# Progress of the one pass build

- Branch: `one-go`
- Pull request: 123 (draft)
- Base: `7c7a1c1` (main), `10e965a` (pull request 115), `65c7d42` (plan and kit)
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

## Phase gates

| Phase | Commit | Date | Result of `full` | Seconds | Expected to fail |
|---|---|---|---|---|---|
| 1 | `2b3c4d5` | 2026-11-17 | PASS | 1980 | 0 |

## Blockers

1. WP09: what blocks it, what was tried, which packages wait for it.

## Found on the way

- 2026-11-17 WP04: a fixture view has two recommended options; asserted the views that hold.
```

The rules of the file:

- The table "Packages" has one line for each of WP00 to WP32 from the first commit on, in the order of the build.
  Nothing else in the file is read by the resume rule.
- **State** is one of four words. `todo`: not started. `doing`: started; the note says what is done and what is
  left, and it is rewritten whenever that changes. `done`: the quick gate was green on the commit named in the
  line. `blocked`: a true blocker; the number of its entry under "Blockers" is in the note.
- **Commit** is the short hash of the package's own commit, in a code span; empty until the package is done.
  A package with several commits names its last one. WP32 alone names the commit before its last (its spec
  says why).
- **Date** is the day (UTC) the state last changed.
- **Note** is one sentence, with no line break and no vertical bar.
- "Phase gates" gets one line for every `full` that ended a phase, red ones included.
- "Found on the way" takes what the pull request text must tell the owner: a spec that was wrong, a defect found
  and not fixed, a cap that cannot be met with its measured number, a check name that changed in CI.
- No markdown link anywhere in the file: `scripts/validate-docs.sh` (rule 2, `:74-81`) follows every link under
  `docs`.

## 6. The rhythm of a package

1. Mark the line `doing`. This needs no commit of its own.
2. Read the spec. Write the tests of "Tests first" and see each one fail for the reason of its promise.
3. Make the change. Run the narrow check often: one case file
   (`TEMPER_CASES_ONLY=N bash scripts/selftest/test-temper.sh`), one scenario
   (`bun scripts/e2e/run.ts plain <name>`).
4. `bash scripts/verify.sh quick`. Red: repair and run it again.
5. The package commit: the work, its tests and its documents in one commit. The subject follows the style of the
   repository and carries the id in the scope, for example `feat(wp11): the approval runs to the commit`. Add files
   by name; `git add -A` is for a tree you have just read with `git status --short`.
6. The progress commit: set the line to `done` with the hash of step 5, the date and a note; commit only
   `PROGRESS.md` as `docs(progress): WP11 done`. A commit cannot name its own hash, which is why the line is a
   second, small commit.
7. One push for both: `git push -u origin <branch>`. **[suggestion]** If the push fails on the network, try again
   after 2, 4, 8 and 16 seconds, then write it under "Found on the way" and go on; the next package pushes all.
8. At the end of a phase: `bash scripts/verify.sh full` in the background, one line under "Phase gates", and the
   pull request text updated (section 7). While it runs, read the specs of the next phase and write its tests, but
   start no suite. A red `full` is repaired before any package of the next phase is committed.

No commit hook is installed in a fresh clone of this repository **[measured]**: nothing but the gate stands between
a red tree and a commit, so step 4 is never left out. Do not start a Temper run on the repository itself during the
build. The CLI allows it for this one folder (`scripts/temper:191-198`), but its run state would sit in the tree you
are changing. **[suggestion]**

## 7. The draft pull request

- Open it when WP00 is pushed: base `main`, head the build branch, as a draft, with the GitHub tool of the session
  (`create_pull_request` with `draft: true`). Not tried by the dry run.
- Title: `Temper 10.0.0: a run that asks twice`. It does not change.
- The text, from the first day: what the pull request will hold (one paragraph from the plan), the line
  `Supersedes pull request 115, whose commits are inside this one`, the table "Packages" of `PROGRESS.md` cut to id
  and state, the last line of "Phase gates", and the lists "Blockers" and "Found on the way". Update it at every
  phase gate with `update_pull_request`. WP32 writes the final text.
- CI runs on every push to the pull request (`.github/workflows/quality.yml:6-7`), draft or not. At the head no run
  is cancelled by a newer push: until WP01 is in, each push costs one whole run of 30 to 60 minutes
  (`docs/plans/one-go/evidence/dev-efficiency.md` section 1.2). That is one more reason to do WP01 first.
- Never mark it ready, never merge it, never close pull request 115, never push a tag: a tag `v*` starts the
  release workflow (`.github/workflows/release.yml:3-6`). Those four are the owner's.

## 8. Lanes, subagents and workflows on 4 CPUs

What is known: the machine has 4 CPUs; the fast tier alone keeps 3 to 4 of them busy for 3 minutes; `full` keeps
all of them busy for its whole time. The planning session reports that a workflow runs 2 agents at a time and that
two workflows can run side by side; the dry run did not measure that.

- **One serial lane for the flow core.** Every package whose Lane is `flow core` runs here, one after another, in
  the main work tree. Its files are the flow modules, `scripts/temper`, `scripts/go.py`, the view and the fixtures.
  Two packages never edit them at the same time, in any work tree.
- **Side lanes in work trees.** A package whose Lane is `side` may run beside the serial lane:
  `git worktree add ../wp28 -b wp28 HEAD`, the agent works and commits there, the conductor merges with
  `git merge --no-ff wp28` in the main work tree, runs `quick`, pushes, and removes the work tree. The side branch
  is never pushed. Each work tree needs its own types folder (section 1).
- **A side lane is lost by a restart.** Work trees outside the repository folder and unpushed branches do not
  survive a new container. Keep side packages small, and merge and push each as soon as its `quick` is green.
- **At most 3 agents that run suites at one time** **[suggestion]**: the serial lane and one side workflow of two.
  With two lanes active, run the selftest with `TEMPER_SELFTEST_JOBS=2` (`scripts/selftest/run-selftest.sh:17`).
- **`full` runs alone.** Start it when the lanes are between packages. While it runs, agents may read and write
  files but start no suite.
- **Who does what** **[suggestion]**. The conductor (the main session) holds `PROGRESS.md`, the merges, the pushes
  and the gate. It gives a package to a subagent with: the absolute path of the work tree, the spec file and the
  heading, the list of section 10, and the order to end with the last line of `quick`, the files changed and
  anything for "Found on the way". A subagent never pushes and never edits `PROGRESS.md`.
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
SDK can use that access for a round was not tried, and it is not a credential the owner gave for the bench.

What a round costs (`docs/plans/one-go/done.md`, note 1, from round M1 of
`docs/plans/one-go/evidence/v-targets-scorecard.md` section 4): the round before, on `10e965a` with plain Claude
Code beside it, is 36 runs, 40 to 50 dollars and 3 to 4 hours; the round after, on the result, is 18 runs, about 30
dollars and 2.7 hours. Together about 80 dollars and 6 hours, one run at a time.

What the owner would have to give, before the session starts: a key for the model API, saved for the session's
environment and never typed into the conversation, and the word that about 80 dollars and 6 hours may be spent.

The rule for the build session: a credential exists when the owner's first message says the bench may run and on
what access, or when `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` is set in the environment. Then WP32 runs the
round. Otherwise it does not ask: it leaves part H of `done.md` open and says so in the pull request text. It never
asks for a key in the conversation, and it never writes one into a file.

## 10. Never

- Never skip, disable, delete or weaken a test or a gate step to get green. Never add `.skip`, `.only` or `.todo`.
- Never put a check on the expected to fail list that passed before, and never take one off except in the commit
  that makes it pass.
- Never raise a `final` of `scripts/caps.json` or `scripts/e2e/floor.json`, and never take a stop out of
  `scripts/stops.json`.
- Never force push, never amend or rebase a pushed commit, never commit with `--no-verify`.
- Never push to another branch, never push a tag, never merge or mark ready the pull request, never close 115.
- Never wait for CI. Push and go on; read its result when it is there (section 11).
- Never ask the owner. A true blocker goes under "Blockers" and the next package that does not depend on it starts.
- Never edit `FRAME.md`, `done.md` (but for a check name, as WP07 says) or a spec.
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
   way" and go on; do not push empty commits to run CI again.
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

1. `git fetch origin` and `git status -sb`. Local commits ahead of `origin`: push them. `origin` ahead: take it with
   `git pull --ff-only`. There is only ever one session on the branch.
2. Read the table "Packages" of `PROGRESS.md`.
3. The work tree has changes: they belong to the line that says `doing`. Keep them, read `git diff --stat` and the
   note, and go on with that package. Never throw uncommitted work away unread.
4. The newest commit is a package commit with no progress commit after it (its subject carries `(wpNN)` and the
   line still says `doing`): run `quick`. Green: write the line, commit, push. Red: the package goes on.
5. `git worktree list`, then `git worktree prune`. A side lane whose work tree is gone starts again from its spec.
6. Make the types folder again (section 1). Nothing in the background survived: a `full` that was running is
   started again.
7. Take the first line, in the order of the table, that is not `done` and whose "Depends on" packages are all
   `done`. A `blocked` line is skipped until its blocker is gone. When no such line is left, the build is at WP32
   or it is over.
8. Make sure one hourly check is pending (section 12).
