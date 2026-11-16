# PR #115 (9.8.5): tests and CI state

Reader: planners of the Temper restructuring. Scope: the tests and the CI of galando/temper pull request 115.
All local runs were made in scratch clones under
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-pr-tests-ci/`
(`repo` = local branch pr115, `repo-gh` = the real PR head, `repo-main` = origin/main), between 21:54 and 22:31 UTC on
2026-11-15, on a 4 core container that 16 other agents shared (load average 1.4 to 6.2). Local seconds are therefore
upper bounds, not benchmarks. Nothing was written in `/home/user/temper`.

Confidence labels: **[code]** read or executed in code, **[CI]** read from GitHub Actions, **[measured]** a run I made,
**[doc]** only a claim in a doc or commit message, **[inferred]** my reasoning.

---

## 0. The three findings that matter most

1. **The local working tree is not the PR head.** `/home/user/temper` (branch pr115) is at `9a01eff`. GitHub's PR head is
   `10e965a`, three commits later (16 commits, 64 files, +4662 −288). The three missing commits hold the A/B replay
   (`scripts/e2e/replay.ts`, `scripts/e2e/ab-replay.sh`, `docs/evidence/ab-replay-9.8.5.md`), three bug fixes in
   `scripts/flow.py` and `scripts/gate_rows.py`, and the fix of the two e2e scenarios 9.8.5 broke. At `9a01eff` the e2e
   job does not pass: `FAIL maven [plain]: the run did not end in time` after 21 minutes, then the job is killed at its
   60 minute limit (run #314) **[CI]**. Any planner reading the local tree reads a tree whose own end to end suite is red.
2. **CI is green at the real head, and only there.** All 10 check runs of `10e965a` succeeded (run #317, finished
   21:55:58 UTC) **[CI]**. Of the 14 CI runs of this PR, 4 passed, 7 failed and 3 were cancelled. The end to end job was
   red on four pushes in a row (18:22 to 21:25 UTC, 3 h 02 min from the breaking push to its fix) and each of those runs took
   60 minutes to say so.
3. **What 9.8.5 adds is tested mostly below the CLI and not at all end to end in CI.** No CI e2e scenario has a setup
   block, a failing preflight, the run policy, the environment agent, a plan patch or an ENV task verdict (0 hits in
   `scripts/e2e/scenarios.ts` and `pyjokes.ts`) **[code]**. The only end to end exercise is the replay, which is not in
   CI, runs without the mod (`replay.ts:279`: `new World('plain', …)`), on fake `mvn`, `java` and Postgres programs.
   The environment agent is never executed anywhere (`replay.ts:273`: `'temper:temper-env': () => undefined`).

---

## 1. CI state of PR #115

### 1.1 Check runs at the PR head `10e965a` (workflow run #317, id 43763595180) [CI]

| Job (`.github/workflows/quality.yml`) | Result | Started | Completed | Duration |
|---|---|---|---|---|
| temper CLI Unit Tests (`:19-24`, `bash scripts/selftest/test-temper.sh`, serial) | success, `PASS: 2575  FAIL: 0` | 21:25:21 | 21:50:06 | **24 min 45 s** |
| End to end (plain, mod, driver) (`:87-96`, `bun scripts/e2e/run.ts all`, `timeout-minutes: 60`) | success, `e2e: all passed` | 21:25:21 | 21:55:58 | **30 min 37 s** |
| Mod (Claude Code 2.1.287) (`:99-125`) | success, `1774 pass, 0 fail, 40 files, 41.35 s`; tsc 5.6 clean; `OK: 20 calls`; known limits `PASS: 20` | 21:25:22 | 21:26:23 | 61 s |
| Directory Readiness | success | 21:25:22 | 21:25:47 | 25 s |
| Official Manifest Validation | success | 21:25:21 | 21:25:36 | 15 s |
| Quality Checks | success | 21:25:22 | 21:25:34 | 12 s |
| Documentation Validation | success | 21:25:21 | 21:25:29 | 8 s |
| Plugin Structure | success | 21:25:21 | 21:25:27 | 6 s |
| Stage Panel Validation | success | 21:25:22 | 21:25:27 | 5 s |
| README Validation | success | 21:25:21 | 21:25:24 | 3 s |

No job failed at the head, so there is no failing case to report there. The e2e log shows 23 scenarios, each `PASS` in
`plain`, `mod` and `driver`, plus 23 lines `the flow is identical with the mod and without it` (69 runs, 23 comparisons).
Per scenario the three modes take 26 s (`fix`) to 162 s (`pyjokes-full`); most take 72 to 97 s.

Two stderr lines in the passing unit test log are noise: `temper-cases-11.sh: line 278:
docs/guide.md: No such file or directory` and `make: *** No rule to make target 'test'. Stop.` **[CI]**.

The PR is still a **draft** (`draft: true`); `mergeable_state` read `unstable` while the e2e job was running.

### 1.2 The same two jobs across the PR, and on main [CI]

| Run | Commit | Unit tests step | Unit result | e2e step | e2e result |
|---|---|---|---|---|---|
| #303 (main) | `7c7a1c1` (9.8.4) | 24 min 50 s | `PASS: 2444  FAIL: 0` | 29 min 31 s | success |
| #312 | `feb6df1` | 23 min 30 s | success | 34 min 24 s | success |
| #314 | `9a01eff` (the local tree) | 33 min 06 s | success | 60 min 09 s | **cancelled at the limit** |
| #315 | `573bb66` | 31 min 35 s | success | 60 min 09 s | **cancelled at the limit** |
| #317 | `10e965a` (PR head) | 24 min 45 s | `PASS: 2575  FAIL: 0` | 30 min 30 s | success |

The unit job varies from 23.5 to 33 minutes on the same kind of runner, so runner noise (about ±5 minutes) is larger
than anything the PR adds. The PR adds 131 assertions in CI (2444 to 2575, +5.4%) and no e2e scenario (23 on main, 23
at the head, `scripts/e2e/run.ts:7`).

### 1.3 All 14 runs of the PR [CI]

| # | Commit | Conclusion | Run time | What failed |
|---|---|---|---|---|
| 304 | `7859742` | failure | 30 min 52 s | not read. The next commit's message says the build-task brief was over its size limit **[doc]** |
| 305 | `c0c9c7e` | failure | 25 min 25 s | not read (same tree plus an ADR) |
| 306 | `a9068b7` | success | 29 min 50 s | |
| 307 | `bd565eb` | success | 31 min 37 s | |
| 308 | `339d3c4` | failure | 31 min 08 s | 3 jobs. Unit: `PASS: 2519  FAIL: 1`: "the CLI and its Python files expand no home folder and read no transcript … expected '0\|no', got '1\|no'". Quality Checks and Directory Readiness: "a script lists a folder by a wildcard after a variable", `scripts/doctor.py:94, 106, 112` |
| 309 | `5c42b58` | failure | 27 min 21 s | not read (pushed 3 minutes after #308, before its result) |
| 310 | `69aad39` | failure | 32 min 13 s | 3 jobs. Unit: `PASS: 2532  FAIL: 2`: the home folder case again, and "9.8.5 S8: after an empty fix, Loop back to Plan is recommended and first … expected 'Loop back to Plan (Recommended)\|True\|False', got 'Change the group's command (Recommended)\|True\|False'". The two directory jobs: the same `doctor.py` lines |
| 311 | `28fff04` | failure | 31 min 08 s | Unit: `PASS: 2533  FAIL: 1`: the S8 case above |
| 312 | `feb6df1` | success | 34 min 33 s | |
| 313 | `30d94ac` | cancelled | 60 min 18 s | **[inferred]** the e2e job at its 60 minute limit (this commit introduced Q3 and Q4, which the e2e scripts did not follow) |
| 314 | `9a01eff` | cancelled | 60 min 17 s | e2e: 14 scenarios pass by 19:51:13, then `FAIL maven [plain]: the run did not end in time` at 20:12:26 (21 min 13 s in one scenario and one mode), then killed at 60 min. The trace shows `task start 1` / `task gate 1 --model claude-haiku-5-5` / `--model sonnet` repeating |
| 315 | `573bb66` | failure | 60 min 18 s | e2e cancelled at 60 min. Quality Checks and Directory Readiness: "a script goes up a folder after a variable", `scripts/e2e/ab-replay.sh:8: ROOT="$(cd "$HERE/../.." && pwd)"` (`PASS: 76  FAIL: 1`) |
| 316 | `c417166` | cancelled | 60 min 17 s | **[inferred]** e2e at its limit |
| 317 | `10e965a` | success | 30 min 39 s | |

Sum of the 14 run times: about 546 minutes (9.1 hours) of CI wall time for one PR. Commits were pushed one by one,
three minutes apart (#307 to #310 at 14:37, 14:40, 14:43 and 14:46), while a run needs about 30 minutes to answer.
The directory rule that #308 broke was visible 22 seconds after its push (Directory Readiness failed at 14:40:46) and
was repaired only in `28fff04` at 15:12, two pushes later **[CI timestamps]**.

Why a broken scenario costs an hour: `scripts/e2e/loop.ts:163` gives the loop 400 steps and `:212` throws only after
them; each step is several CLI calls of 0.1 to 0.5 s, so one scenario that loops takes about 21 minutes per mode, three
modes exceed the job limit, and the job is killed without a result line for the scenarios after it.

---

## 2. Local runs of the PR's new and changed selftest case files

Method: exactly what `scripts/selftest/run-selftest.sh:56` does for one file,
`TEMPER_CASES_ONLY="<N>" bash scripts/selftest/test-temper.sh`, one file after another, each under `timeout 520`.
Every such process adds 3 "selftest safety" assertions of its own (`test-temper.sh:268-271`), so "own" below is PASS − 3.

### 2.1 At local pr115 (`9a01eff`) [measured]

| File | What it covers | PASS | FAIL | own | seconds |
|---|---|---|---|---|---|
| 21 | Maven filtered verify row (`gate_rows.py`) | 13 | 0 | 10 | 1.1 |
| 22 | preflight (`preflight.py`) | 17 | 0 | 14 | 6.9 |
| 23 | setup block (`run_env.py`), prompts, `temper doctor` | 16 | 0 | 13 | 3.2 |
| 24 | ENV verdict at the task gate | 10 | 0 | 7 | 15.5 |
| 25 | Design decisions reach tasks, High blocks, integrate reruns | 14 | 0 | 11 | 10.3 |
| 26 | failure text, empty fix, SETUP at Check, four options | 14 | 0 | 11 | 9.9 |
| 27 | `doctor --propose`, CI facts, `--candidate`, env agent launch | 24 | 0 | 21 | 6.9 |
| 28 | run policy (`autonomy.policy: decide`) | 12 | 0 | 9 | 19.5 |
| 29 | `temper plan patch` | 10 | 0 | 7 | 4.4 |
| 30 | PERSON label, Interfaces by shape, RED before code, ask_note | 12 | 0 | 9 | 26.5 |
| 31 | claimed runs, `evidence void`, helper drift | 14 | 0 | 11 | 2.9 |
| **21 to 31** | **the 11 new files** | **156** | **0** | **123** | **107.1** |
| 17 | changed in place (lock) | 85 | 0 | 82 | 45.1 |
| 11 | +3 cases (Maven after `cd`) | 111 | 0 | 108 | 58.5 |
| 8 with 9 | changed in place (override, fix pass) | 278 | 0 | 275 | 289.0 |
| 6 | now runs alone (sources `case-helpers-5.sh`) | **no result** | | | **> 520 (timeout)** |
| 5 | changed in place (lock) | **no result** | | | **> 520 (timeout)** |

Files 5 and 6 did not finish. Rerun alone with a timestamped trace and a 535 s limit, two at a time:

| File | Reached in 535 s | FAIL lines printed | CLI calls made | Wall per CLI call |
|---|---|---|---|---|
| 5 | line 1451 of 1624 (89%), the case "M3 reopen: the worktree is clean and both tasks are pending" | 0 | 1,259 | 0.42 s |
| 6 | line 311 of 527 (59%; 65 of its 111 assertion call sites), the case "F3: with G2 depending on G1 the dependency row passes" | 0 | 1,116 | 0.48 s |

So on this machine file 5 alone needs about 10 minutes and file 6 alone about 15 minutes **[inferred by extrapolation]**.
CI proves both pass at the head (they are inside the serial `PASS: 2575  FAIL: 0`).

### 2.2 At the real PR head `10e965a`, the two case files the last three commits changed [measured]

| File | PASS | FAIL | own | seconds |
|---|---|---|---|---|
| 21 (+3 cases: the two Maven rows agree) | 16 | 0 | 13 | 2.9 |
| 26 (+2 cases: the same failure with a grown count) | 16 | 0 | 13 | 12.5 |

### 2.3 Baseline at origin/main `7c7a1c1`, same method [measured]

| File | PASS | seconds on main | seconds on pr115 |
|---|---|---|---|
| 17 | 85 | 46.7 | 45.1 |
| 11 | 108 | 56.9 | 58.5 |
| 8 with 9 | 278 | 281.6 | 289.0 |

No measurable time added to the changed files.

### 2.4 The rest of the suite at pr115, for the whole picture [measured]

| File | PASS | s | File | PASS | s | File | PASS | s |
|---|---|---|---|---|---|---|---|---|
| 1 | 214 | 131.4 | 10 | 41 | 16.8 | 16 | 60 | 27.2 |
| 2 with 3 | 502 | 149.1 | 12 | 40 | 17.3 | 18 | 41 | 44.2 |
| 4 | 248 | 38.0 | 13 | 43 | 23.5 | 19 | 31 | 4.6 |
| 7 | 22 | 13.1 | 14 | 67 | 66.0 | 20 | 60 | 50.8 |
| | | | 15 | 97 | 95.4 | | | |

Total of the 27 processes that finished (29 of 31 case files): **2,096 PASS, 0 FAIL**, 1,176 s summed. Files 5 and 6
add an estimated 1,500 s here. Two files of 31 are therefore more than half of the suite's time **[inferred]**.
`run-selftest.sh:7` calls the `--fast` tier (files 10 to 31) "a minute or two"; summed serially it was 556 s here.

### 2.5 Other suites at the PR head, run in the scratch clone [measured]

| Command | Result | seconds |
|---|---|---|
| `claude plugin test .` (Claude Code 2.1.325) | 1774 pass, 0 fail, 40 files | 52 |
| `bash scripts/quality-check.sh` | All checks passed | 5.2 |
| `bash scripts/validate-directory.sh` | OK | 4.3 |
| `bash scripts/check-mod-calls.sh` | OK: 20 calls | 5.7 |
| `bash scripts/selftest/test-check-mod-calls.sh` | PASS: 24 FAIL: 0 | 3.9 |
| `bash scripts/check-known-limits.sh` | PASS: 20 FAIL: 0 | 0.1 |
| `bash scripts/validate-plugin.sh` | PASS: 31 FAIL: 0 | 0.5 |
| `bash scripts/validate-docs.sh` | PASS: 10 FAIL: 0 | 0.2 |
| `python3 scripts/validate-panels.py` | PASS | 0.1 |
| `bash scripts/e2e/ab-replay.sh` | the table of the PR body, exactly (see 3) | 69 |

`tsc -p tsconfig.mod.json` could not run locally: `.claude-plugin/types/` exists only after a signed in load of the
plugin. CI ran it clean.

---

## 3. The PR body's claims, checked

### "How I know it works"

| Claim | Verdict | Evidence |
|---|---|---|
| "Whole selftest: 2879 pass, 0 fail." | **0 fail holds; 2879 does not reproduce.** | CI at the head counts `PASS: 2575  FAIL: 0` (serial). The parallel runner would report 2659: it sums each process's line (`run-selftest.sh:66-75`) and each of its 29 processes repeats the 3 safety assertions (+84). The remaining 220 I could not explain: my per-file counts match the commit messages' own rerun figures ("8, 9 and 28 rerun: 287 pass" = 275 + 9 + 3; "26 and 27 rerun: 35 pass" = 11 + 21 + 3), so the environment is not the cause. |
| "The mod's suite: 1774 pass, 0 fail." | **Holds.** | CI (2.1.287): `1774 pass 0 fail`, 41.35 s. Mine (2.1.325): the same, 52 s. |
| "All 23 e2e scenarios pass, each with the mod and without it, and the flow is identical both ways." | **Holds at `10e965a` only.** | CI run #317. It was false for the four pushes before it (#313 to #316), and is false for the local tree `9a01eff`. |
| "`check-mod-calls.sh`, `quality-check.sh` and `validate-directory.sh` pass." | **Holds.** | CI at the head and my runs. `validate-directory.sh` failed on #308, #310 and #315 and was repaired each time. |

### "Proof: the measured run, replayed"

| Claim | Verdict | Evidence |
|---|---|---|
| The table (defect in commit yes / no / no; questions 8 / 8 / 4; repairs by hand 2 / 0 / 0; launches 10 / 7 / 7; minutes 191 / 92 / 92) | **Reproduces exactly** | `bash scripts/e2e/ab-replay.sh` in `repo-gh`, 69 s. It also prints what the body leaves out: build tool runs 30 / 36 / 36, and CLI seconds with instant fake tools 68 / 54 / 55 with the three replays running at once (31 to 32 s for the 9.8.5 replay running alone, in my `mod` mode run). |
| "agent minutes" | **Not a measurement.** | `replay.ts:192-196`: launches times fixed constants (Plan 12, Build task 25, Build fix 40, Review 3, Intent 1, Acceptance 8). 191 = 1 + 2×12 + 8 + 3×25 + 2×40 + 3; 92 = 1 + 12 + 8 + 25 + 40 + 2×3. The mock project has one Build task launch; the real run had 12 tasks. The body says "estimate"; the bold 92 reads like a result. |
| "The real CLI of each version runs" | Holds | `ab-replay.sh:13-17`, `world.ts:16-17` (`TEMPER_E2E_ROOT`). |
| "questions to the person 8 / 8" | Holds, and is the honest headline: **with default settings 9.8.5 asks as many questions as 9.8.4.** Fewer questions need the opt-in key `autonomy.policy: decide`. | replay output |
| Not said in the body | The replay runs in `plain` mode only (`replay.ts:279`). I ran it in `mod` mode in the scratch clone (one word changed in a copy): shipped, 8 questions, and 4 with the policy, no repair by hand. So the mod's rule engine does not refuse the 9.8.5 flow, but nothing in the repo checks that. The `driver` mode was not tried. | **[measured]** |

### "What is left, stated plainly"

| Claim | Verdict | Evidence |
|---|---|---|
| "A stub is allowed by default; `build.red-before-code: true` forbids stubs" | Holds | `temper-cases-30.sh:38-46`, both cases pass |
| "What no source can make (a licence, a secret, a VPN, a toolchain …) is named in plain words" | **A prompt instruction, not a tested behaviour** | Only in `agents/env.md:49`. 0 mentions in any test. |
| "The local type check could not run in this container; CI runs `tsc` on every push" | Holds | CI Mod job, step "Type check the mod" |
| "The replay's agents are scripted, and agent minutes are an estimate" | Holds | above |
| Not listed as left | no CI e2e for any 9.8.5 behaviour; the env agent never executed; no real Maven anywhere; the old suite runs with the strict evidence default switched off; non Maven stacks (see 4) | |

---

## 4. Test design of the PR

### 4.1 How the new behaviours are tested [code]

My classification of the 128 new assertions in files 21 to 31 at the head (read one by one; ±3):

| Mechanism | Count | Share | Examples |
|---|---|---|---|
| The real CLI entry point (`"$TEMPER" …`, mostly `temper next --json` through `nx`, `case-helpers.sh:16`) | 73 | 57% | 24, 25, 27, 28, 29, 30 |
| A Python module called directly, past the CLI | 49 | 38% | all 13 of file 21 (`gate_rows.py plan-rows`, `:5`), all 14 of file 22 (`preflight.py row`, `:9`), `run_env` by import (23), `runs.py` with the mode passed by hand (31) |
| `grep` of a template, brief or source file | 6 | 5% | `temper-cases-28.sh:26` greps `flow.py` for the word override |

Three things qualify the 57%:

- **The state is hand written.** A question is tested by writing `.temper/gates.json` (`gpass`, `gfail`:
  `case-helpers.sh:32-56`), `.temper/groups.json` or `.temper/preflight.json` with `printf`, then asking `temper next`
  what it would do. That checks the decision table of `flow.py`, one step at a time. It never checks that the CLI itself
  can reach that state, or what happens after the step. Example: every policy case (`temper-cases-28.sh:11-43`) asserts
  the first call of one `temper next`; none carries an armed run from Review through a loop back to a commit.
- **The headline feature never passes through `temper` in the selftest.** No case in 21 to 31 calls `temper gate plan`
  with a failing preflight or `temper plan preflight`; the wiring at `scripts/temper:3600` and `:4568-4570` is run only
  by the e2e happy paths and by the replay.
- **Every tool is a fake.** `fakebin/mvn` (`temper-cases-22.sh:15-29`), `faketest` (`24:27`), `fakepg/pg_lsclusters`,
  `pg_isready`, `pg_ctlcluster` (`27:9, 23-25`), `fakedock/docker` (`27:62`). The texts the fakes print are the texts the
  classifier's patterns were written for.

### 4.2 What is not tested

| Gap | Evidence | Why it matters for the goal |
|---|---|---|
| **The environment agent** (`agents/env.md`, sonnet, tools Read, Glob, Grep, Bash, Write) is never run, by a model or by a script | `temper-cases-27.sh:114-131` asserts that `temper next` launches it and that `doctor --candidate` accepts or refuses a hand written file; `replay.ts:273` is a no-op | The third source of the setup block, and the only one for a project no rule fits, is unproven. It is also a new agent launch and a new question. |
| **A non Maven stack** | I fed `preflight.classify` 14 failure texts **[measured; the texts are my own approximations of each tool's message]**. Classified as an environment fault: the Maven enforcer JDK range, and two texts with the literal words "Connection refused". Classified **"needs new code", which passes the row** (`preflight.py:224`): npm unsupported engine, Node `ECONNREFUSED`, Python `ModuleNotFoundError`, `No module named pytest`, Go toolchain too old, rustc too old, Docker daemon not running, npm missing script, Gradle and JDK mismatch, Ruby version, .NET SDK. The patterns are `preflight.py:34-37` and `:73-96`. | The preflight finds the faults of the one run it was written from. On any other stack the same class of fault still reaches Build. |
| `doctor --propose` rules without a case | 0 mentions in files 21 to 31 of `.nvmrc`, GitLab CI, `setup-node`, `mysql`, `gradlew`, all of which `scripts/doctor.py` handles; Gradle, `.tool-versions`, Compose and a venv share one assertion (`27:64`) | 530 new lines, tested on the Maven and Postgres path |
| **A real Maven** | `temper-cases-13.sh:41-45`: with Maven present the "real Maven case" is `assert_eq … "yes" "yes"`; without it the case prints SKIP (CI prints the SKIP) | The PR exists because of a Maven run; no test runs Maven |
| **The policy on a whole run** | selftest: single steps; CI e2e: none; replay: yes, `plain` mode, not in CI | The one feature that lowers the question count is the least proven |
| **The mod with the new questions** | 0 hits in `view-fixtures.ts`, `view-fixtures-2.ts`, `tests/mod` and `hooks/temper-mod` for "Check it again", "Add the proposed setup block", "Let an agent find the setup", "Change the group's command", "Repair the environment", "Note from Claude". The mod tests gained 11 lines: 8 `git push` cases (`tests/mod/session.test.ts`) and `plan patch` as a person only call (`tests/mod/v975.test.ts`) | The mod's drawing and driver were not shown any 9.8.5 question |
| **Who may write the setup block** | `hooks/temper-mod/core/rules.ts:476-496` lists the person only calls; `doctor --propose --write`, `doctor --candidate … --write`, `evidence void`, `state set env_agent` and `state set ask_note` are not in it, and no mod test names them | "One click for the person" is a property of the question, not of the guard. The block's `run:` line is shell that every later CLI command runs. Not tested either way. |
| **The strict evidence default under the old suite** | `test-temper.sh:77-78` puts `evidence: claimed-runs: count` into the shared fixture: "the cases simulate runs with evidence add". The default a user gets (`ignore`, `scripts/temper:3634, 3869`) is tested by `temper-cases-31.sh` through `runs.py` with the mode given on the command line (`:8-18`), and by the e2e scenarios | About 2,400 older assertions run in a mode no new user has; the switch from config to gate verdict has no selftest case |
| **A live model** | `scripts/e2e/run.ts:1` and `live-smoke.sh:27` keep it off; `docs/evidence/` has nothing live for 9.8.5 | Four briefs changed (`agents/build.md`, `build-task.md`, `fix.md`, `plan.md`) and one is new; the measured costs in `bench-2026-11.md` are from before |

### 4.3 `case-helpers-5.sh` and `make-helpers-5.sh` [code]

- `make-helpers-5.sh` (31 lines) copies every top level function and seven constants out of `temper-cases-5.sh` into
  `case-helpers-5.sh`. Of its 951 lines, 949 are verbatim lines of `temper-cases-5.sh`.
- Purpose: `temper-cases-6.sh:11` sources it when case 5 has not run, so the parallel runner no longer pairs 5 and 6
  (`run-selftest.sh:35`). That lowers the parallel runner's longest process from 5 plus 6 (about 25 minutes here) to 6
  alone (about 15 minutes here) **[inferred]**.
- Of the 46 functions copied, file 6 needs 20 (181 lines) by a name based closure; 768 lines are functions it never
  calls **[inferred from static analysis]**.
- A new upkeep rule comes with it: after any edit of a helper in `temper-cases-5.sh`, regenerate, or
  `temper-cases-31.sh:34-35` fails. `.claude/CLAUDE.md` does not mention it (it names only `make-view-fixtures.sh`).
- Two comments now contradict the code: `run-selftest.sh:33` ("2 with 3, 5 with 6, 8 with 9") and `test-temper.sh:227`
  ("Files 3, 6 and 9 go on from 2, 5 and 8"). A third stale comment from the same PR: `scripts/temper:326-327` still
  says a held lock "is written past with a WARN (fail open)" after 60 s; the code at `:422-440` fails with exit 75 after
  120 s.
- The simpler design is one helper file that both case files source, with no generator and no drift case.

### 4.4 View fixtures [code]

`scripts/selftest/view-fixtures.ts` is generated from the real CLI by `make-view-fixtures.sh` (330 lines) and compared
by a selftest case; the mod's tests read it. The PR changes 48 lines in and 94 out, all for two effects: the Review
question now names the open findings, and questions keep four options with the rest under "More options". No fixture
was added for any new question. The two fixture files are 15,869 generated lines in the repository.

---

## 5. Test weight of the PR

### 5.1 Lines (PR head against the merge base, `git diff --numstat origin/main...10e965a`) [measured]

| Kind | Files | Added | Removed |
|---|---|---|---|
| Product: CLI (`scripts/temper`, `scripts/*.py`) | 16 | 1,899 | 139 |
| Product: mod (`hooks/temper-mod`) | 2 | 18 | 1 |
| Product: prompts (`agents/`, `commands/`, `reference/`) | 9 | 109 | 16 |
| Product: config and manifest | 2 | 28 | 3 |
| **Product total** | **29** | **2,054** | **159** |
| Test, hand written: selftest | 19 | 763 | 23 |
| Test, hand written: e2e and replay | 5 | 448 | 8 |
| Test, hand written: mod tests | 2 | 11 | 0 |
| **Hand written test total** | **26** | **1,222** | **31** |
| Test, generated: `case-helpers-5.sh` | 1 | 950 | 0 |
| Test, generated: `view-fixtures.ts` | 1 | 48 | 94 |
| Docs (`docs/`, CHANGELOG, README, CLAUDE.md) | 7 | 388 | 4 |
| **All** | **64** | **4,662** | **288** |

- Hand written test lines per product line added: **0.59** (1,222 / 2,054). With the generated files: 1.08.
- Selftest lines per CLI line added: **0.40** (763 / 1,899). The code base before the PR: 0.82 (12,851 hand written
  selftest lines for 15,724 CLI lines on main).
- Assertions: +131 in CI for 1,899 added CLI lines, one per 14.5 lines. Before the PR: one per 6.4 lines
  (2,444 for 15,724). The new code is tested at less than half the density of the old.
- The CLI grows 11% (15,724 to 17,484 lines) and gains 5 Python files (`doctor.py` 530, `preflight.py` 255,
  `plan_patch.py` 144, `decisions.py` 123, `runs.py` 97).

### 5.2 Time

| Measure | Value | Basis |
|---|---|---|
| Serial time of the 11 new case files | about 107 s here (112 s at the head) | 2.1, 2.2 **[measured]** |
| Time added to changed files 8 with 9, 11, 17 | none measurable | 2.3 **[measured]** |
| CI unit job | 24 min 50 s on main, 24 min 45 s at the head; 23.5 to 33 min in between | 1.2 **[CI]** |
| CI e2e job | 29 min 31 s on main, 30 min 30 s at the head | 1.2 **[CI]** |
| CI answer time per push | about 30 minutes when green, 60 when an e2e scenario loops | 1.3 **[CI]** |
| CI wall time this PR used | about 546 minutes in 14 runs | 1.3 **[CI]** |

The PR's own test weight is small. The cost is the suite it joins: a 25 minute serial unit job, a 30 minute e2e job,
and no early stop.

---

## 6. Avoidable cost found here

| # | What | Where | Kind | Size |
|---|---|---|---|---|
| 1 | The unit suite runs serially in CI although a parallel runner exists | `quality.yml:24` | time | 24 min 45 s per push; the parallel runner is bounded by its longest file |
| 2 | Two case files are more than half the suite | `temper-cases-5.sh` (1,624 lines), `temper-cases-6.sh` (527 lines) | time | each over 520 s alone here; about 2,300 CLI calls in 535 s of the two |
| 3 | e2e runs 23 scenarios times 3 modes in one job, one after another | `quality.yml:96`, `run.ts:14-33` | time | 30 min per push |
| 4 | A looping scenario burns 21 minutes per mode before it fails, then the job limit hides the rest | `loop.ts:163, 212`; `quality.yml:89` | time, reliability | 4 runs of 60 min; 3 h 02 min from break to fix |
| 5 | Pushes without a local e2e run | commits `30d94ac` to `c417166` | loops | 4 red pushes |
| 6 | A generated 950 line copy of helpers, with its generator and its drift case | `case-helpers-5.sh`, `make-helpers-5.sh`, `temper-cases-31.sh:34-35` | complexity | 950 lines, one more regenerate rule |
| 7 | The old suite pinned to the retired evidence mode | `test-temper.sh:77-78` | reliability, complexity | about 2,400 assertions; keeps the knob `evidence.claimed-runs` alive |
| 8 | Two totals for one suite | `run-selftest.sh:66-75` against `test-temper.sh:275` | reliability | +84 in the parallel total; the PR body's figure is 304 above CI's |
| 9 | The preflight classifier is a list of texts from one run | `preflight.py:34-37, 73-115` | reliability | 11 of 14 non Maven probes pass as "needs new code" |
| 10 | The proof of "asks less" is a script outside CI, in one mode | `replay.ts`, `ab-replay.sh` | reliability | 393 + 43 lines that no check run executes |
| 11 | Directory rules found only by CI | #308, #310, #315 | loops | 3 red runs; `validate-directory.sh` takes 4.3 s locally |

---

## 7. Verdict: what must be true before this PR is merged

Already true:

1. Every check run is green on the head commit `10e965a` (run #317). **[CI]**
2. Unit tests `PASS: 2575  FAIL: 0`; mod tests 1774 pass; 23 e2e scenarios pass in 3 modes with identical flows;
   the validators pass. **[CI and measured]**

Must be made true (small, mechanical):

3. The branch that is merged is `10e965a`, not the local `9a01eff`. Bring the local branch up to the head before anyone
   plans from it or builds on it.
4. The PR leaves draft.
5. The PR body states the suite count CI shows (2575) or says how 2879 was counted.
6. The three stale comments are corrected (`run-selftest.sh:33`, `test-temper.sh:227`, `scripts/temper:326-327`), since
   each now tells the reader the opposite of the code.

Should be true before the release is called proven (each is a gap the PR's own text does not name):

7. One CI e2e scenario per headline behaviour, in all three modes: a preflight environment fault repaired by the one
   click setup block, an armed run under `autonomy.policy: decide` through a loop back to the commit, a plan patch, an
   ENV task verdict. The replay already scripts the first two; it passed in `mod` mode when I ran it.
8. The environment agent is executed at least once (a scripted agent in e2e that writes `setup-proposal.yaml`, and one
   live run on a project that is not Maven).
9. The preflight is tried on a second stack before it is described as general ("Temper finds it for any project" in
   the PR body). Today it is proven for the Maven enforcer and "Connection refused".
10. The shared fixture drops `evidence.claimed-runs: count`, or the PR says that the old suite does not run on the new
    default.

My reading for the planners: as a repair of the two failed runs inside today's architecture, this PR is mergeable at
its head. As evidence for the owner's goal it shows less than its title: with default settings the question count is
unchanged (8 and 8), the agent minutes are arithmetic on launch counts, the mechanism is fitted to one stack, and it
adds 1,760 net lines of CLI, 5 modules, one agent, new questions, 6 new config keys or blocks (`setup:`,
`plan.preflight-timeout`, `plan.preflight-skip`, `autonomy.policy`, `evidence.claimed-runs`, `build.red-before-code`;
none of them is in `scripts/temper`, `flow.py` or the template on main) and one changed default (`review.block-on` now
includes `high`) to a system whose stated problem is weight.
