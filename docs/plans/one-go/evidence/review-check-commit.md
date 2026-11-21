# After Build: Review, Check, Commit, Pipeline, and the fix flow

Subsystem map of Temper at the head of PR #115 (branch `pr115`, 9.8.5), read against the owner's goal: fewer seconds,
dollars, questions, agent launches, loops between stages, and concepts.

All paths are relative to `/home/user/temper`. Line numbers are those of the PR head.

**How each claim is marked**

- `[code]` read in the code at the cited lines.
- `[run]` measured by running it in a scratch copy (the method is in section 0).
- `[doc]` only a claim in a doc or a brief (a model is told to do it; no code does it or checks it).
- `[inf]` inferred from the code; not run.

---

## 0. Method and limits

- Read every file named in the task, plus `scripts/run_env.py`, `scripts/runs.py`, `scripts/loop_step.py`,
  `scripts/scenario_ops.py`, `scripts/go.py`, the relevant parts of `scripts/task_ops.py`, `agents/build.md`,
  `commands/temper.md`, `hooks/temper-mod/core/rules.ts` (stage write rules), `docs/evidence/bench-2026-11.md` and
  `docs/evidence/haiku-sonnet-task-agents.md`.
- **Questions and launches** were produced by calling `flow.Builder(Run).next()` (the function behind `temper next`,
  `scripts/flow.py:3088-3095`) with run data held in memory, on a clone at `pr115` and on a worktree at `origin/main`.
  Nothing was written into a `.temper` folder by hand. (This session's Temper mod refused a Bash call that wrote
  `.temper/gates.json` by hand, so I did not fake a run on disk.)
- **Check's commands** were measured by running `scripts/check_run.py run` on a throwaway Python project whose suite
  wrapper logs every invocation.
- **Not measured:** real agent time or dollars for any stage (I launched no agent), Pipeline, pull requests, a Maven
  project. Costs quoted are from the two evidence docs.

---

## 1. The main findings

1. **Review and Check already run at the same time, but their gates, questions and repairs are strictly serial.**
   The CLI starts Check's whole run in the background when the Review agent is launched (`temper check ahead`,
   `scripts/flow.py:1375-1378`, `scripts/temper:4948-4956`) `[code][run]`. The person still answers the Review question
   before Check's result is shown, and a Check failure the CLI already knows is not in the Review question `[run]`.
2. **Repairing one finding costs a loop through three stages.** The only recommended repair is "Loop back to Build":
   a new fix agent, the Integration suite again, the Build question, a second Review agent that reviews the whole diff
   again, Check's whole run again (`scripts/flow.py:588-593, 1655-1672`, `scripts/temper:1269-1295, 1876-1896`)
   `[code][run]`. Measured: $0.40 to $0.50 for one such round (`docs/evidence/bench-2026-11.md:272-273`); on 9.8.4, 7 of
   18 measured feature runs had two or more Review rounds and 16 of 18 had at least one Build fix pass
   (`docs/evidence/haiku-sonnet-task-agents.md:28-47, 79-80`).
3. **PR #115 makes that loop more frequent.** `review.block-on` now defaults to critical and high (was critical),
   and any open finding at medium or above makes "Loop back to Build" the recommended answer; on `origin/main` the same
   state recommended "Continue to Check" (`scripts/temper:3814`, `scripts/flow.py:420, 779-787`;
   `git show origin/main:scripts/temper` line 3824) `[code][run]`.
4. **PR #115 has a regression at exactly that question:** with one open medium finding, "More options" leads to a
   question that holds only "More options" and "Make a small change". "Accept a finding", "Grill Me", "Teach Me" and
   "Save for later" cannot be reached (`scripts/flow.py:925-947`) `[run]`.
5. **The same code is tested again and again.** On the tree Build leaves, the full suite runs at the group gate, at
   `temper integrate`, at Check (with coverage), and up to 40 more times for the mutation score; each scenario's `Test:`
   command runs at the group gate, at integrate and at Check. The reuse added by this PR covers two call sites only and
   never Check (`scripts/task_ops.py:464, 488`; `scripts/check_run.py:671, 693, 720`) `[code][run]`.
6. **Two of Check's own measurements are unsound.** The mutation score changed between identical runs (50.0%, 75.0%,
   80.0% in 12 runs of one tree; the threshold is 70) `[run]`; a fix's "regression proof" passed with no fix at all
   when the suite could not start in the bare worktree `[run]`.
7. **Much of the Review and Check text describes things no code does:** review memory, OCR, the confidence
   threshold, lint, type check, security scan, compile, environment check. With the CLI running Check (the normal
   case), none of Check's levels 0, 1, 3, 4.75 to 7 run at all `[code]`.
8. **`/temper:fix` is lean because it has one investigator, one implementer in the project folder and four
   one-click questions,** not because its Review and Check are cheaper. It lacks even the parallel Check
   (`scripts/flow.py:1375`) `[code][run]`.

---

## 2. Review

### 2.1 What the agent is

| Fact | Value | Source |
|---|---|---|
| Brief | `agents/review.md` (93 lines, 6,360 bytes) | `[code]` |
| Model, effort | `sonnet`, `high` | `agents/review.md:4-5` `[code]` |
| Context | clean: the changed files and `intent.md`; nothing from the conversation | `agents/review.md:8-11` `[doc]` |
| Must read first | `reference/review.md` (287 lines, 17,159 bytes), "Follow it exactly" | `agents/review.md:20-22` `[doc]` |
| Also told to load | the enabled packs' `rules.md`, `.temper/review-memory.json`, `.claude/temper.config`, `build-context.json`, `REVIEW.md` | `reference/review.md:28-42` `[doc]` |
| Fixed instruction load before any project file | about 33 KB: brief 6.4 KB + reference 17.2 KB + the five default packs 9.9 KB (`quality` 784, `tdd` 3,041, `security` 1,176, `git` 555, `performance` 4,348 bytes; default list in `templates/temper.config.default:16`). Roughly 8,000 tokens at 4 bytes a token | `wc -c` `[run]`; the token figure is an estimate |
| Scope of the read | every file changed since `base_sha`, each read whole ("Read the ENTIRE file (not just the diff)") | `agents/review.md:15-18`, `reference/review.md:92-93` `[doc]` |
| Launch prompt | 3 lines: brief path, spec path, plugin folder | `scripts/flow.py:1119-1136` `[run]` |
| Measured time | 30 to 45 s; 27 to 54 s across runs | `docs/evidence/bench-2026-11.md:457-459, 477` |
| Further launches it may make | review subagents for a large diff; a nested Opus agent for a finding it cannot judge; OCR, an external engine | `reference/review.md:74-81`, `agents/review.md:23-25`, `reference/review.md:44-65` `[doc]` |

Nested launches are at the agent's judgment and are not in the usage ledger (the `usage add` call is one row per
top-level agent, `scripts/flow.py:1136`) `[code]`. I could not determine how often they happen.

### 2.2 The dimensions the reference page asks for

All of this is prompt text `[doc]`; no code checks that any of it ran.

| Step | What | Lines |
|---|---|---|
| 1 | Gather context: diff stat, config, pack rules, review memory, intent, `REVIEW.md`, the OCR probe | `reference/review.md:26-65` |
| 1.5 | Classify each hunk (change type, risk signals) | `:67-72` |
| 2 | Review, in subagents when the diff is large. Categories: logic, security, performance, quality, standards, architecture, test gap. Each finding: severity, confidence 0.0 to 1.0, file:line, description, suggestion. Performance severity floors; security (semgrep MCP first, else by reading), which bypasses the confidence filter; seven "AI code" patterns | `:74-135` |
| 3 | Intent and test validation: (a) each scenario has a test that passes, (b) each criterion's `Validate:`, (c) test quality STRONG / WEAK / TRIVIAL, (d) does it solve the Problem, (e) uncovered branches, (f) a live mutation spot check on up to 3 files | `:137-164` |
| 3.5 | "Deep doubt": attack every claim of the diff, up to 3 cycles | `:166-173` |
| 3.55 | Stale `CLAUDE.md` lines | `:175-179` |
| 3.6 | Cross-file pattern drift (MEDIUM, confidence 0.6) | `:181-187` |
| 3.7 | API contract diff per endpoint | `:189-196` |
| 3.8 | Architecture depth: not the agent's; an option of the Review question that the orchestrator runs | `:198-202`, `scripts/flow.py:769-770` |
| 4 | Confidence filter: below `review.confidence-threshold` (0.7) a finding is dropped; review memory suppresses or downgrades | `:204-210` |
| after | `review-context.json`, `metrics.json`, `review-memory.json` | `:227-237, 260-282` |

Problems inside the text itself:

- Step 3.6 produces findings at confidence 0.6 and Step 4 drops everything below 0.7, so a pattern-drift finding is
  always dropped at the default (`reference/review.md:185, 207-208`) `[inf]`.
- Step 3f tells the reviewer to change a source file and run tests (`:160-164`), while the brief says "You do not
  change code at Review" and the mod refuses any write outside the spec folder at Review (`agents/review.md:30-31`,
  `hooks/temper-mod/core/rules.ts:277-283`) `[code]`. The CLI now measures a mutation score itself
  (`scripts/check_run.py:358-398`).
- Step 3a (each scenario has a passing test) repeats what the CLI records at integrate and at Check
  (`scripts/scenario_ops.py:133-152`, `scripts/check_run.py:715-722`) `[code]`.

### 2.3 Confidence, review memory, OCR: what is real

| Mechanism | What the docs say | What the code does |
|---|---|---|
| Confidence score | filter findings below 0.7 (`reference/review.md:204-210`) | `--confidence` is stored on the evidence row; the gate never reads it (`scripts/temper:3812-3860`); `review.confidence-threshold` is read by no script and no mod file (grep) `[code]` |
| Review memory | one store that promotes and suppresses patterns (`reference/review.md:260-282`) | no script and no mod file reads or writes `review-memory.json` (grep). This repo's own file has `"patterns": {}` and was last changed in commit ab11249. The agent returns before the person accepts or dismisses anything, so it cannot know the outcome it is told to record `[code][inf]` |
| OCR | off by default; `tools.ocr.mode` (`reference/review.md:44-65`) | `tools.ocr.*` and `tools.mode` are read by no script (grep) `[code]` |
| `(auto-fix)` mark | the reviewer marks a finding the fix pass can fix mechanically and "never applies it" (`agents/review.md:78-79`) | nothing parses the mark (grep); `auto_fixed` survives only as a metric field (`reference/review.md:233, 263`) `[code]` |

### 2.4 Output

- Evidence rows in `.temper/evidence/review.json`: one per finding (`--claim '<file>:<line> <one line>' --severity
  --confidence --label`) and a `review completed` row (`agents/review.md:35-52`) `[doc]`.
- One 76-column panel the model draws; the orchestrator prints it verbatim (`agents/review.md:70-93`) `[doc]`. For
  Plan, Design, RCA and Build tasks the CLI now draws the panel instead (`scripts/flow.py:1379-1381`,
  `agents/rca.md:41-44`); a Build task agent spent about a minute of three drawing its box
  (`docs/evidence/bench-2026-11.md:459-460`).
- `review-context.json`: counts and verdicts only. Its schema has no field for a finding's description or suggested
  fix (`reference/review.md:229-237`) `[doc]`.

### 2.5 The gate rows and what blocks

`gate_review`, `scripts/temper:3812-3860` `[code]`:

| Row | Passes when |
|---|---|
| `no blocking findings` | no finding at a severity in `review.block-on` is open. Default `critical,high` (`scripts/temper:3814`). Resolved and accepted findings do not count; contested and escalated ones still do (`scripts/findings.py:27-37, 112-117`) |
| `review completed` | the latest `review completed` row has exit 0 (`scripts/temper:3840-3846`) |
| `no code changed at Review` | no tracked file outside `.temper` and `.claude` differs from the snapshot taken when the run entered Review, and HEAD did not move (`scripts/temper:3763-3810, 3847-3857`; snapshot at `:1037`, `:1469`, `:4618-4622`) |

The Review question, as the CLI builds it at PR head `[run]`:

| State | Question | Recommended |
|---|---|---|
| PASS, no finding | "Review: the check passed. Continue to Check?" | Continue to Check |
| PASS, an open finding at medium or above | "Review: the check passed, open findings: 1 medium. Loop back to Build to repair them?" | Loop back to Build |
| FAIL, a high or critical finding | "Review: the check failed (…), open findings: 1 high. Loop back to Build?" | Loop back to Build |
| FAIL, only the completion row missing | "Run Review again" | Run Review again (`scripts/flow.py:793-798`) |

Every "Loop back", "Override", "Accept finding N" and "Make a small change" option carries a second dialog, "What is
the reason?" (`scripts/flow.py:475-480`, `commands/temper.md:150-153`). For "Loop back" that dialog has one real
option, "The check found a real problem", and "Cancel" (`scripts/flow.py:586, 591-593`) `[run]`.

### 2.6 How a finding gets fixed

| Way | Who changes the code | Context | Review after it | Source |
|---|---|---|---|---|
| **Loop back to Build** (the recommended way) | Build's fix pass: `agents/build.md`, a new `sonnet` agent | clean; reads `tasks.md`, `intent.md`, `reference/build.md` (22 KB of brief and reference), and the finding as one line cut to 200 characters | a full new Review agent, same brief, whole diff since `base_sha`, plus two lines naming the earlier finding | `scripts/flow.py:1248-1262, 1655-1672, 1340-1347`; `agents/build.md:7-25` `[code][run]` |
| **Make a small change** (under "More options") | the main conversation, in an ad-hoc window | the conversation's own | a Review agent told "review only {files}", then the gate | `scripts/flow.py:905-913, 954-965`, `scripts/adhoc_ops.py:100-111` `[code]` |
| **Accept a finding** | nobody; the person keeps it with a reason | | none; the gate runs again | `scripts/flow.py:1071-1088`, `scripts/temper:1665` `[code]` |
| **Contest or escalate** | the fix pass answers instead of fixing; the finding stays open for the person | | | `scripts/findings.py:1-19`, `agents/build.md:110-113` `[code]` |
| **Override and continue** | nobody; the gate is skipped with a reason | | none | `scripts/flow.py:595-598` `[code]` |

Three facts about the loop back:

- The loop empties the Build, Review, Check and Commit ledgers and removes their verdicts
  (`scripts/temper:1876-1896, 1041-1092`) `[code]`. The findings travel as up to 20 one-line strings of at most 300
  characters in `.temper/feedback-loops.json` (`scripts/loop_step.py:115-118`) `[code]`. The reviewer's description and
  suggested fix are not carried.
- Because the Build ledger is emptied, the Build gate again needs a failing-first test: a new RED run and a GREEN run
  after it, both run by the CLI (`scripts/temper:3633-3645`, `scripts/runs.py:40-45`). What `temper integrate` records
  after the fix does not count: `runs.py build` on a ledger holding only an Integration row and scenario rows prints
  `0 0 0` `[run]`; the self test asserts the same (`scripts/selftest/temper-cases-9.sh:487-493`). So a finding with no
  test to write first (a naming or structure finding, a weak assertion) cannot pass the Build gate by the fix alone
  `[inf]`.
- The second Review is not a recheck. The brief says to record again each finding still there
  (`agents/review.md:31-34`). The plan's fresh review has had a recheck round since 9.8.4, which reads only the earlier
  findings and the changed task blocks (`scripts/flow.py:1294-1302`, `CHANGELOG.md:97-101`); Review has none `[code]`.

One fact about the small change: nothing marks the repaired finding as resolved. `temper evidence resolve` exists
(`scripts/temper:1617`) but no brief, command page or flow step calls it (grep: only the CLI and two mod tests). The
finding stays open in the ledger, so the Review question after the change again says "open findings: 1 medium" and
again recommends the loop back `[inf]`.

---

## 3. Check

### 3.1 Who runs it

- **The CLI, with no agent,** whenever it finds a test command: `temper check run` then `temper gate check`
  (`scripts/flow.py:1359-1364`, `scripts/temper:4936-4947`) `[code][run]`. Detection: `check.commands.test`, else
  pytest or unittest, `npm test`, `go test`, `cargo test`, `mvn -q test`, gradle (`scripts/check_run.py:76-145`).
- **The CLI, then the Check agent** (`sonnet`, `agents/check.md:4`) when the intent has a criterion validated by `code`
  or `metric`: the agent only records those rows (`scripts/flow.py:1365-1373`) `[code]`. It is still told to read all
  of `reference/check.md` and "Follow it exactly" (`agents/check.md:20-22`) `[doc]`.
- **The Check agent alone** when the CLI finds no test command (`scripts/flow.py:1374-1385`) `[code]`.
- **The person**, for a criterion validated by hand: one "Confirmed" question (`scripts/flow.py:824-836`) `[code]`.

### 3.2 Every command, who runs it, and whether it repeats an earlier run on the same tree

"Same tree" means the merged feature branch that `temper integrate` left; Review writes no code, so Check sees it
unchanged.

| # | Command | Run by | Code | Repeats an earlier run on the same tree? |
|---|---|---|---|---|
| 1 | The suite, with coverage on in the same run when the stack allows (`cov["run"]`, else `det["test"]`) | CLI | `scripts/check_run.py:691-699` | **Yes.** `temper integrate` ran the plan's Integration command on this tree (`scripts/temper:3405-3418`), and the group gate ran the group's Validate command on the group branch before the merge (`scripts/temper:2496`). Check's run is never reused, and its command text differs (the coverage form) |
| 2 | The coverage report (`coverage json`, `go tool cover`) | CLI | `:695-697` | No |
| 3 | Each scenario's `Test:` command | CLI | `:715-722` | **Yes.** integrate ran every one on this tree and recorded a row each (`scripts/temper:3421-3423`, `scripts/scenario_ops.py:133-152`); the group gate ran the group's (`scripts/temper:2505`). `[run]`: 2 scenarios, 2 more runs at Check |
| 4 | The locked acceptance tests (the lock's command) | CLI | `:656-674, 723-731` | **No, and that is the problem:** this is the first time they run against the built code. The lock only checks that the command can start (`:471-483, 509-513`). Builders are told the tests "must pass at integration" (`scripts/flow.py:1436-1441`), but integrate does not run them |
| 5 | Mutation score: one planted bug at a time in the lines changed since `base_sha`; each mutant runs the **full** test command in a temporary copy of the project. At most 40 mutants, a 300 s budget checked before each mutant | CLI | `:41-42, 358-398, 732-740` | No earlier run. `[run]`: 13 changed source lines gave 20 mutants, so 21 suite runs for one Check |
| 6 | Regression proof (fix runs): the full test command in a new git worktree at `base_sha`, with the changed tests copied in; a non-zero exit is the proof | CLI | `:402-427, 741-745` | Partly: the Fix agent's RED run, which the CLI ran, already showed the test failing before the fix (`agents/fix.md:24-31`) |
| 7 | Setup fault detection: a pattern on the output of 1 and 4 | CLI | `:177-186, 700-703, 728-731` (new in this PR) | No command |
| 8 | Evidence for `code` and `metric` criteria | Check agent | `scripts/flow.py:1365-1373` | |
| 9 | Compile or build, integration tests, test-gap analysis, API diff, performance baseline, lint, type check, dependency and SAST scan, the environment check, config suggestions, debt metrics (levels 0, 1, 3, 4.75 to 7 and Step 3 of `reference/check.md:34-129`) | **only** the Check agent, so only when the CLI found no test command | `reference/check.md` `[doc]` | Never run in the normal path `[code]` |

Notes on the table:

- Row 9: `check.commands.lint`, `check.commands.typecheck`, `check.environment`, `check.live-scenarios` and
  `debt-tracking` are read by no script (grep), though the config template documents the first three
  (`templates/temper.config.default:35-45`) `[code]`. The Check panel still has `Compile`, `Lint` and `Security` cells
  (`agents/check.md:88-89`).
- Row 5, the copy: `shutil.copytree` leaves out `.git`, `__pycache__`, `.temper`, `.claude` and `node_modules` only
  (`scripts/check_run.py:377`); a `target/`, `dist/` or `.venv/` inside the project is copied for every Check `[code]`.
- Row 1 on Maven, Gradle and Rust: `detect` returns no coverage command (`scripts/check_run.py:138-144`), so the first
  Check records "coverage tool missing" and the gate fails on coverage until the user sets
  `check.commands.coverage` `[code]`. `reference/check.md:184-188` says Check "never runs a second full Maven pass";
  the detected command is `mvn -q test`, which is exactly that `[doc vs code]`.

### 3.3 The gate rows

`gate_check`, `scripts/temper:3862-3972` `[code]`:

| Row | Fails when |
|---|---|
| `tests pass` | the latest run of any test command failed, or none passed; only runs the CLI ran or the person confirmed count (`:3869-3879`, `scripts/runs.py:48-56`) |
| `scenarios traced to tests` | a scenario of `intent.md` has no passing row (`:3880-3903`) |
| `coverage >= threshold` | no value, or below `check.coverage-threshold` (80) (`:3904-3914`) |
| `mutation score >= threshold` | a measured score below `check.mutation-threshold` (70); "not measured" passes (`:3918-3931`) |
| `acceptance tests written before Build` | the locked tests fail, were changed, or are reopened (`:3933-3945`) |
| `regression proof` (fix runs) | the changed tests pass on the old code too (`:3947-3957`) |
| `acceptance evidence` | a criterion has no supported passing row (`:3958-3969`) |

The Check question `[run]` (`scripts/flow.py:813-875`):

| State | Recommended |
|---|---|
| PASS | Commit. Also: Loop back to Build, Commit and open PR, (stacked PRs with two or more groups), Review config suggestions |
| a `manual` criterion open | Confirmed |
| a setup fault (new in this PR) | Repair the environment and run again; a loop back is never recommended |
| only a missing measurement | Run Check again |
| only the acceptance tests fail | a triage agent runs first (`sonnet`, `scripts/flow.py:1465-1485`), then Loop back to Build or Correct the acceptance test |
| anything else, including coverage below 80 and mutation below 70 | Loop back to Build |

### 3.4 Check while Review reads (exists since 9.8.0)

- When the Review agent of a `/temper` run is launched and the CLI can run Check, its `before` call is
  `temper check ahead` (`scripts/flow.py:1375-1378`) `[run]`. That starts `check_run.py ahead` with `nohup` in the
  background (`scripts/temper:4948-4956`): the whole of 3.2 rows 1 to 5 `[code]`.
- `check run` first calls `adopt`: it waits for the background run, then adds its rows when the tree digest is the one
  the run measured (HEAD plus the content of every changed or untracked file outside `.temper` and `.claude`), else it
  runs everything again (`scripts/check_run.py:757-829, 856-859`) `[code]`.
- **Not started for:** fix runs (`r.command == "temper"`, `scripts/flow.py:1375`) `[run]`; the narrow Review after a
  small change (`:954-965`); a project where the Check agent runs.
- **Wasted when the person loops back from Review:** the run measured the tree before the fix and is thrown away; the
  next Review starts another `[code]`.
- **A hazard** `[inf]`: the Review agent is told to run tests itself and to mutate a file and restore it
  (`agents/review.md:57`, `reference/review.md:142, 160-164`) while the background suite runs in the same folder. The
  digest is compared only at the start and the end (`scripts/check_run.py:788, 797`), so a probe made and restored in
  between is not seen, and rows from a suite that ran on probed code would be adopted. Two test processes in one
  `target/` or on one `.coverage` file can also collide.

### 3.5 The reuse of a passing check (new in this PR): what it covers and misses

`run_env.run_cached`, `scripts/run_env.py:121-180` `[code]`. A pass is kept under a key of `HEAD^{tree}`, the command
and the `setup:` block, in `temper-results.json` in the git common folder (200 entries at most). Only a pass is kept.
A work tree with any uncommitted or untracked path outside `.temper/` and `.claude/worktrees/` has no key.

| | |
|---|---|
| **Covers** | a group's Validate command (`scripts/task_ops.py:459-464`) and the Integration suite (`:483-488`): the same command on the same tree, for example a group gate run again, `integrate` run again on an unchanged HEAD, or a one-group plan whose Validate and Integration commands are the same string |
| **Misses: Check's suite** | `check_run.run` calls `run_cmd` (`scripts/check_run.py:693`). Its command is the coverage form, so the key would differ anyway. `[run]`: `bash run_suite.sh` and `bash run_suite.sh cov` are separate keys |
| **Misses: scenario `Test:` commands** | at integrate (`scripts/scenario_ops.py:145`) and at Check (`scripts/check_run.py:720`) |
| **Misses: the acceptance command, the mutants, the regression proof, the plan preflight** | `scripts/check_run.py:671, 386, 421`, `scripts/preflight.py:202` |
| **Misses: any project that does not git-ignore its test byproducts** | `[run]`: on a Python project with no `.gitignore`, the first run left `__pycache__` files, the key became `None`, and the second identical call ran again (2 calls, 2 runs). With `__pycache__/` ignored, 4 calls gave 2 runs |
| **Misses: a `/temper:fix` run** | the Fix agent does not commit, so the tree is dirty through Review and Check (`commands/fix.md:82-86`) `[inf]` |

There are now two notions of "the same tree" in the CLI: `tree_digest` (content of dirty files included,
`scripts/check_run.py:757-772`) and `result_key` (clean trees only, `scripts/run_env.py:133-141`).

### 3.6 Two unsound measurements

- **The mutation score is not deterministic on a fast Python suite** `[run]`. Twelve runs of `check_run.py run` on
  one unchanged tree: 75.0% ten times, 50.0% once, 80.0% once; over all 19 runs I made, 50.0% three times. With
  `PYTHONDONTWRITEBYTECODE=1` in the test command: 75.0% twelve times of twelve. The likely cause `[inf]`: mutants are
  written into the same file within one second, and Python reuses a `.pyc` whose recorded source time (whole seconds)
  and size match. The threshold is 70, so the same code passes or fails the Check gate by chance, and a failure
  recommends a loop back to Build.
- **The mutation step can spend two full suite runs and measure nothing** `[run]`. The budget is tested before each
  mutant and fewer than 3 mutants is "not measured" (`scripts/check_run.py:381, 395-397`). With a 1 s suite and a 2 s
  budget: "not measured (only 2 mutant(s) ran in the time budget)", 3 suite runs in all. At the default 300 s budget
  that is any suite slower than about 150 s `[inf]`.
- **The regression proof passes when the old code cannot be tested at all** `[run]`. `regression` treats any non-zero
  exit in the bare worktree as proof (`scripts/check_run.py:421-427`). With base equal to HEAD (no fix), a new test
  that always passes, and a test command that needs an untracked folder, the row read "the new or changed tests … fail
  on the code before the fix and pass with it". A project whose tests need `node_modules`, a virtual environment in
  the project or build output gets this false pass `[inf]`.

---

## 4. Commit gate, commit steps, report, pull requests, Pipeline

### 4.1 The commit gate rows

`gate_commit`, `scripts/temper:4033-4227` `[code]`. Measured CLI time on a small project: 1.0 s (38 Python starts);
`gate review` 0.5 s, `gate check` 0.7 s, `temper next --json` 0.2 s `[run]`. The CLI itself is not a cost.

| Row | Rule | Lines |
|---|---|---|
| `artifact-only commit` | every staged file is under `.temper/specs/`: pass, nothing else checked | `:4042-4053` |
| `active run` | no run state: pass | `:4059-4064` |
| `build checkpoint commit` | while the run is at Build on its own branch with the earlier gates satisfied: the last GREEN test run decides | `:4072-4110` |
| `<stage> gate`, one per stage | `plan build review check` (plus `intent`, `design` when their file exists); a fix run: `build review check`. PASS, or the person's override | `:4116-4144` |
| `blast radius` (scope) | every changed file is one `tasks.md` declares, a test, the spec folder, Temper's state, or one the person allowed | `:4145-4190` |
| `blast radius` (count) and `park-on-touch paths` | unattended runs only | `:4191-4224` |

The gate asks only that each stage has a PASS or an override. It does not ask in which order they were reached or on
which tree `[code]`.

### 4.2 What Commit costs

| Step | What happens | Questions | Agent launches | Session turns without the mod | Source |
|---|---|---|---|---|---|
| The decision | the Check question: Commit, Commit and open PR, Commit and open stacked PRs | 1 (it is the Check question) | 0 | | `scripts/flow.py:813-821, 887-897` `[run]` |
| `gate commit` | CLI | 0 | 0 | 0 (`temper go` runs it) | `scripts/flow.py:2224-2226`, `scripts/go.py:95-97` |
| Report | `temper intent complete`, `temper spec deviations`, `temper report --end`; then the session copies the printed report into its reply | 0 | 0 | 1 | `scripts/flow.py:2135-2147, 2245-2246` `[run]` |
| Report page | `temper report --html` | 0 (asked before 9.8.0) | 0 | 0 | `scripts/flow.py:2237-2241` |
| Record commit | `temper state archive`, `temper spec commit '<message>' -- <files>`, `temper state clear`; the CLI drafts the message | 0 | 0 | 1 | `scripts/flow.py:2176-2220`, `scripts/spec_ops.py:42-67` `[run]` |
| A failed commit gate | "Add to plan", "Override and commit", "Loop back to Fix" | 1 or more | 0 | | `scripts/flow.py:2247-2277` |
| An armed run | parks before the commit; the person is asked "Commit?" | 1 | 0 | | `scripts/flow.py:2227-2231, 2242-2244` |

With the mod the driver makes these calls with no model turn; it carried 7 of 8 measured runs with no main session
turn (`docs/evidence/bench-2026-11.md:437`). The time outside the agents in a whole run (loop, CLI calls, the person's
answers) was 42 to 103 s for a feature with the mod and 183 to 206 s without it (`:482-484`); the share that is Commit
was not broken out.

`commands/temper.md:102-104` still says that after the report `next` "asks whether to write the report as an HTML page
too". The code stopped asking in 9.8.0 (`scripts/flow.py:2237-2241`) `[doc vs code]`.

### 4.3 Pull requests

- Only on "Commit and open PR" or "Commit and open stacked PRs", never for an armed run or a fix run
  (`scripts/flow.py:887-897`, `reference/pr.md:3-7`).
- The orchestrator (a model, or the conversation the driver hands to) follows `reference/pr.md`: capture four facts,
  check `gh`, write the body (the Problem sentences, the criteria, the diff stat, the report), `git push -u`,
  `gh pr create --draft` (`reference/pr.md:9-42`) `[doc]`. The body is composed by a model.
- Stacked: one more question to confirm the parts (`reference/pr.md:46-49`); `scripts/pr_parts.py:66-88` cuts the
  parts at the group merge commits with no model `[code]`.
- Cost in seconds or dollars: not measured anywhere I found.

### 4.4 The Pipeline stage

- Runs only after a Commit that opened a pull request, unless `phases.pipeline: false`
  (`scripts/flow.py:228-236, 2215-2217`).
- One agent launch per reading: `sonnet`, effort `medium` (`agents/pipeline.md:4-5`). It reads `gh pr checks` and the
  failed logs and writes `pipeline-context.json` (`:16-21`).
- **While the checks still run it writes no file** (`agents/pipeline.md:17`), the gate row `pipeline result` fails
  (`scripts/gate_rows.py:203-221`), and the person is asked "Run Pipeline again?" (`scripts/flow.py:1020-1023`). So
  each poll of a running CI costs one agent launch and one question `[code]`. Nothing waits or polls without a model.
- Green: "End the run?" (1 question). Red: "Apply the fix and push?"; the orchestrator applies the listed changes in an
  ad-hoc window, commits, pushes, and the stage runs again, at most `loops.max-per-type` (2) rounds
  (`scripts/flow.py:1024-1037`, `reference/pipeline.md:25-36`).
- Cost: not measured (the benchmark never pushes).

---

## 5. The loops back to Build

### 5.1 Triggers

| From | Trigger | Recommended? | Source |
|---|---|---|---|
| Review, gate FAIL | an open critical or high finding (default) | yes | `scripts/flow.py:792-808` |
| Review, gate PASS | an open finding at medium or above (new in this PR) | yes | `scripts/flow.py:779-787` |
| Review, gate PASS | only low findings | offered | `:783-784` |
| Check, gate FAIL | failing tests, an untraced or failing scenario, coverage below 80, mutation below 70, a missing criterion row | yes | `scripts/flow.py:874-875` |
| Check, acceptance tests fail | after the triage agent, unless it says the test is wrong | yes or offered | `:864-873, 1487-1511` |
| Check, gate PASS | none; the person's choice | offered | `:817` |
| Commit of a fix run | the check gate failed | yes ("Loop back to Fix") | `:2266-2268` |
| An armed run under `autonomy.policy: decide` (new in this PR) | the same rules, taken with no question, until the budget is spent, then it parks | automatic | `scripts/flow.py:1144-1181` |

Budget: 2 per pair by default (`loops.max-per-type`; Check to Build takes `fix.max-loops` when set), counted
separately for Review to Build and Check to Build, so up to 4 loops back to Build in one run
(`scripts/loop_step.py:20-32`) `[code]`.

### 5.2 What a loop back does

1. `temper state loop <from> build --reason …` counts the step, stores the open findings or failed rows of `<from>`
   only, and empties the ledgers of Build, Review, Check and Commit (`scripts/temper:1222-1262, 1876-1896`,
   `scripts/loop_step.py:56-123`).
2. The verdicts and overrides of Build and every later stage go (`scripts/temper:1041-1092`).
3. `temper next` launches the fix pass: `temper:temper-build`, `sonnet`, with "Feedback re-entry: {reason}" and the
   findings (`scripts/flow.py:1655-1672`) `[run]`. The brief is `agents/build.md` (10.7 KB) and it must read
   `reference/build.md` (11.3 KB). It makes a failing test, then the fix, records both with `temper evidence run`,
   and commits (`agents/build.md:21-25, 52-76`).
4. Its `after` calls: `temper integrate` (the Integration suite runs again because HEAD moved, then every scenario's
   `Test:` command, `scripts/temper:3316-3331`) and `temper gate build` `[run]`.
5. The Build question: "Build: the check passed. Continue to Review?" `[run]`.
6. Review again in full, with `check ahead` again; the Review question; Check (adopted); the Check question.

### 5.3 Count: one medium finding at Review, from the finding to the next clean Review

Interactive run, PR head, default config, one group, the CLI runs Check. Built from the harness output `[run]` and the
code above.

| # | Step | Agent launches | Dialogs put to the person | Full-suite runs | Scenario command sets |
|---|---|---|---|---|---|
| 0 | (Review 1 found the finding; its background Check ran) | (1, the baseline) | | 1 + up to 40 mutants, **thrown away** | 1, thrown away |
| 1 | Review question, "Loop back to Build (Recommended)" | | 1 | | |
| 2 | "Loop back to Build (Recommended). What is the reason?" | | 1 | | |
| 3 | Fix pass | **1** (`sonnet`) | | scoped RED and GREEN only | |
| 4 | `temper integrate` | | | 1 | 1 |
| 5 | Build question, "Continue to Review?" | | 1 | | |
| 6 | Review 2, whole diff | **1** (`sonnet`, high) | | 1 + up to 40 mutants (background) | 1 |
| 7 | Review question, "Continue to Check?" | | 1 | | |
| | **Total for the repair** | **2 launches** | **4 dialogs** | **2 + up to 40 mutant runs, plus 1 + up to 40 thrown away** | **2, plus 1 thrown away** |

- The Check question follows as it would have anyway.
- Measured dollars for this round: $0.40 to $0.50 (`docs/evidence/bench-2026-11.md:272-273`). Review alone is 27 to
  54 s (`:477`); the fix pass's own time was not broken out.
- If Review 2 raises another finding at medium or above (a fresh reader of the whole diff can), the same round runs
  once more, then the budget is spent `[inf]`.
- Under `autonomy.policy: decide` the launches are the same and the dialogs are 0 (`scripts/flow.py:1166-1172`).
- A loop back from Check costs the same 2 launches and 4 dialogs plus the Check question, although Review had
  already passed everything but the lines the fix touches `[code]`.
- For comparison, "Make a small change": the Review question, "More options", "Make a small change", its reason
  dialog (and one line asking what to change), the conversation's edit, 1 narrow Review launch, the Review question
  again. 4 to 5 dialogs, 1 launch, no Build question, no integrate; and the finding stays open (2.6).

### 5.4 How often, measured

`docs/evidence/haiku-sonnet-task-agents.md:28-47` (Temper 9.8.4, 18 runs of three large feature tasks):

- Review rounds: 26 in 18 runs (1.44 a run); 7 of 18 runs had 2 or 3.
- Build fix passes: 28 in 18 runs (1.56 a run); 16 of 18 runs had at least one. Most were not followed by another
  Review round, so they came from Build's own gate; the doc does not say which trigger, and I did not determine it.
- Questions to the person: 8 to 26 a run.
- One task, three runs on the same arm (`:39-41`): 1 fix pass and 1 Review cost $3.32 and $2.96 (923 s and 874 s, 13
  and 12 questions); 6 fix passes and 3 Reviews cost $5.43 (1534 s, 26 questions). That is one run; read it as an
  order of magnitude: about $0.45, 130 s and 2.7 questions per extra fix pass `[inf]`.
- Before 9.8.0's fixes, three runs that looped at Check on a locked acceptance test cost $38.24, $26.91 and $23.19
  against about $3 (`docs/evidence/bench-2026-11.md:158-170`).

That was with Review blocking on critical only. PR #115 blocks on high and recommends the loop for medium `[code]`;
there is no measurement of the loop rate at 9.8.5.

---

## 6. Could Review and Check run together, and could a finding be repaired in the stage?

### 6.1 Running together

The work already does (3.4). What is still serial:

| Still serial | Where |
|---|---|
| A stage is left only for the next stage of the sequence, once its own check passed | `advance_ok`, `scripts/flow.py:2510-2535`; `SEQ`, `:48-49` |
| Check's verdict is computed only after the Review question is answered | `scripts/flow.py:1359-1364` runs at stage `check` |
| The Review question does not show Check's result, and a loop back carries only the ledger of the stage it leaves | `scripts/temper:1257`, `scripts/loop_step.py:83-118` |
| Two questions in a row when both passed: "Continue to Check?" then "Commit?" | `[run]` |
| Loop budgets are per pair | `scripts/loop_step.py:20-32` |

Nothing in the commit gate needs the order: it checks that build, review and check each hold a PASS or an override
(`scripts/temper:4116-4144`) `[code]`. One gate over both ledgers, one question, and one repair carrying both sets of
findings fits the commit gate as it is.

### 6.2 Repair in the stage, with a narrow recheck

Pieces that exist:

- The ad-hoc window: a change at Review with no loop, then a Review agent told to review only the changed files
  (`scripts/adhoc_ops.py:83-145`, `scripts/flow.py:954-965`).
- `temper evidence resolve --fixed-by` marks a finding fixed and keeps the row (`scripts/temper:1617`).
- The CLI already knows which files changed since Review started (`_review_code compare`, `scripts/temper:3763-3810`).
- A recheck round with only the earlier findings and the changed parts exists for the plan review
  (`scripts/flow.py:1294-1302`).

What assumes the opposite today:

| Assumption | Where | What it protects |
|---|---|---|
| Review writes no code | brief `agents/review.md:30-31`; gate row `scripts/temper:3847-3857`; mod rule `hooks/temper-mod/core/rules.ts:277-283` | the code committed is the code reviewed; a fix is tested first |
| Check writes no code | `rules.ts:284-291` | the same |
| Commit writes only the spec folder | `rules.ts:315-323` | the same |
| A fix is made by a Build agent at the Build stage, with RED then GREEN | `scripts/temper:3633-3645`; the gate row's own text, `:3855` | test-first |
| A loop back removes every later verdict and ledger | `scripts/temper:1041-1092, 1876-1896` | no stale verdict survives a code change |
| A second Review is a whole Review | `agents/review.md:31-34` | nothing; it is how the loop was built |
| A verdict is not tied to a tree | gate rows hold no digest (`scripts/temper:1834`); only `adopt` compares one (`scripts/check_run.py:819`) | so the order and the write bans stand in for it |

The last row is the root. "What is committed is what was reviewed and checked" is kept by forbidding writes and by
wiping everything after a change, not by recording what each verdict judged. If each verdict recorded the tree digest
it judged, and the commit gate asked that the review and check verdicts be of the tree being committed (or of a tree
whose difference was rechecked), then the order would be free, a repair could happen in place, and only the difference
would need a second look `[inf]`.

The reviewer cannot be the one who judges its own fix; the independent judges that remain after a repair are the
CLI's checks on the new tree and a recheck of the difference by a reader that did not write it.

---

## 7. `/temper:fix`

### 7.1 Launches, questions, cost

Sequence `rca, fix, review, check, commit` (`scripts/flow.py:49`). Harness output `[run]`:

| Step | Launch | Question | Source |
|---|---|---|---|
| RCA | 1: `temper:temper-rca`, `opus`, effort high. First runs `temper brief --stdin` (no model), writes plain fields into `rca.md`; the CLI draws the panel | "RCA: the root cause is in …/rca.md. Proceed to Fix?" | `commands/fix.md:33-65`, `agents/rca.md:4-5, 14-18, 41-71`, `scripts/flow.py:616-619` |
| Fix | 1: `temper:temper-fix`, `sonnet`. Regression test RED, fix GREEN, both with `temper evidence run`; then `gate build` | "Fix: the check passed. Continue to Review?" | `agents/fix.md:20-31`, `scripts/flow.py:743-752` |
| Review | 1: `temper:temper-review`, `sonnet` high, with a "Fix mode" line. **No `check ahead`** | "Review: the check passed. Continue to Check?" | `scripts/flow.py:1319-1322, 1375` |
| Check | 0: the CLI: suite with coverage, mutation, regression proof | "Check: the check passed. Commit?" | `scripts/flow.py:1359-1364`, `scripts/check_run.py:741-745` |
| Commit | 0; the CLI drafts the message from `rca.md` | none | `scripts/flow.py:2153-2174, 2192-2194` |

**3 launches, 4 questions, each with a recommended "go on".** No pull request, no Pipeline.

Measured (`docs/evidence/bench-2026-11.md`): with the mod $0.45 to $0.50 and 88 to 110 s a bug run (`:437-438`);
without the mod $0.81 to $0.84 and 147 to 177 s (`:427-428`); vanilla $0.36 to $0.37 and 46 to 48 s (`:427-428`); so
1.25 to 1.35 times vanilla's cost and 1.9 to 2.4 times its time (`:451`). The root cause agent alone: $0.23 to $0.34,
33 to 61 s, 5 to 7 turns (`:387-388`). One run handed back and cost $1.27 and 290 s: the suite failed at Check after
Fix, the person looped back, and the Fix agent could not pass with its locked regression test (`:441-445`).

### 7.2 Why it is lean

| Property of the fix flow | The feature flow's counterpart |
|---|---|
| One agent investigates and writes a short file of plain fields; the CLI draws the panel (`agents/rca.md:41-71`) | Intent, Plan and often Design: three agents, two on Opus, 45% to 83% of a run's cost |
| No gate on the RCA; the person's one click is the check (`agents/rca.md:29`) | the intent gate, the plan gate with fresh reviewers, the design gate |
| One implementer works in the project folder, on the branch | groups, worktrees, a task agent per chain, task gates, group gates, a merge, integrate |
| The Build gate is one RED then GREEN pair run by the CLI (`scripts/temper:3633-3645`; no `tasks.md` rows) | the same plus tasks, criteria, integration |
| No acceptance writer, no acceptance lock | one more agent before Build, and a lock that can fail late at Check |
| The proof of the fix is mechanical (RED, GREEN) | the same idea, spread over tasks |
| 4 one-click questions | 8 to 26 (`docs/evidence/haiku-sonnet-task-agents.md:28-47`) |

### 7.3 What it still wastes

- Two of its four questions decide nothing when the gate passed ("Continue to Review?", "Continue to Check?").
- Check waits for Review; nothing runs ahead (`scripts/flow.py:1375`).
- The full suite first runs at Check, after Review. The Fix agent's gate needs only the regression test's RED and
  GREEN; "all existing tests still pass" is prose (`reference/fix.md:91`). A broken suite is found after the Review
  launch, and the loop back to Fix repeats Fix, Review and Check. The run that handed back did exactly this
  (`docs/evidence/bench-2026-11.md:441-445`).
- Review reads the feature review's 17 KB reference page, most of which is about an intent a fix does not have.
- The regression proof repeats the RED run with a whole suite in a bare worktree, and can pass falsely (3.6).

### 7.4 What the feature flow could take from it

- One writer of a plain-field file and a panel the CLI draws, for every stage's output, Review included.
- One implementer in the project folder when the plan has one group.
- A gate that is a small mechanical proof the CLI ran, with the person's single click as the judgment.
- Fewer stages between the request and the code for a request that is already clear: the benchmark's clear tasks are
  where vanilla is as correct at a fifth of the cost.

---

## 8. Where the time, tokens, questions and loops go (this subsystem)

| # | Waste | Where | Kind | Size, and its basis |
|---|---|---|---|---|
| 1 | A finding is repaired by a three-stage loop: fix agent, Build question, full Review, Check again | `scripts/flow.py:588-593, 1655-1672`; `scripts/temper:1269-1295` | loops | 2 launches, 4 dialogs, $0.40 to $0.50 a round (bench:272-273); 7 of 18 runs had it at 9.8.4 |
| 2 | The second Review reads the whole diff again with the whole method | `agents/review.md:31-34` | tokens | one full Review, 27 to 54 s (bench:477), each round |
| 3 | Medium findings now recommend that loop | `scripts/flow.py:779-787` | loops | not measured at 9.8.5; raises the 7-of-18 rate |
| 4 | The fixer gets a finding as one line; description and suggestion are dropped | `scripts/loop_step.py:115`, `scripts/flow.py:1258-1262`, `reference/review.md:229-237` | tokens | the fix agent derives the fix again |
| 5 | Every loop back needs a new failing-first test, whatever the finding | `scripts/temper:1876-1896, 3633-3645` | loops | `[run]` `runs.py` prints `0 0 0`; a finding with no test to write cannot pass Build |
| 6 | Questions that decide nothing: "Continue to Review?", "Continue to Check?" when the check passed | `scripts/flow.py:749-752, 784` | questions | 2 a clean feature run, 2 a fix run, 1 more per loop |
| 7 | A reason dialog with one real option | `scripts/flow.py:475-480, 586` | questions | 1 per loop back |
| 8 | The suite and each scenario command run again on the same tree | `scripts/temper:2496, 3408, 3422`; `scripts/check_run.py:693, 720` | time | 3 suite runs and 3 scenario sets on one tree; a source run ran 11,600 tests about eight times (`scripts/run_env.py:122`) |
| 9 | Mutation: a full suite per mutant, up to 40 | `scripts/check_run.py:358-398` | time | `[run]` 20 mutants for 13 changed lines; up to 300 s plus one mutant |
| 10 | Mutation on a slow suite measures nothing | `scripts/check_run.py:381, 395-397` | time | `[run]` 2 suite runs for "not measured" |
| 11 | The mutation score is not stable | `scripts/check_run.py:380-392` | reliability | `[run]` 50.0%, 75.0%, 80.0% on one tree; threshold 70 |
| 12 | The first background Check is thrown away on any loop back | `scripts/check_run.py:805-829` | time | one whole Check run per loop |
| 13 | The locked acceptance tests first meet the code at Check | `scripts/check_run.py:656-674` | loops | three runs at $23 to $38 before the 9.8.0 fixes (bench:158-170) |
| 14 | A failed Check is not shown at the Review question | `scripts/flow.py:767-808` | loops | a second loop that one fix pass could have covered |
| 15 | The reuse of a pass covers 2 call sites | `scripts/task_ops.py:464, 488` | time | `[run]`; never Check, never a tree with untracked byproducts |
| 16 | The Review reference page: 17 KB, with steps no code checks and several that conflict or are dead | `reference/review.md` | tokens, complexity | about 8,000 tokens of instructions a Review launch (estimate) |
| 17 | The Review panel is drawn by the model | `agents/review.md:70-93` | time, tokens | a Build task agent spent about a minute on its box (bench:459-460); Review's share not measured |
| 18 | `reference/check.md`: 195 lines for an agent that normally does not run; its levels never run | `reference/check.md:34-129` | complexity | 12 levels described, 5 commands run |
| 19 | Pipeline polls CI with an agent and a question each time | `agents/pipeline.md:17`, `scripts/flow.py:1020-1023` | time, questions | 1 launch and 1 question per poll; not measured |
| 20 | "More options" loses four options | `scripts/flow.py:938-947` | reliability | `[run]`; new in this PR |
| 21 | A finding fixed by a small change stays open | no caller of `evidence resolve` | reliability | the question recommends the loop again |
| 22 | The regression proof can pass falsely, and costs a suite run | `scripts/check_run.py:402-427` | reliability, time | `[run]` |
| 23 | Options on the Review and Check questions | `scripts/flow.py:767-875` | complexity | 11 labels at Review, 16 at Check across their states |
| 24 | Knobs that do nothing | grep | complexity | `review.confidence-threshold`, `tools.ocr.*`, `tools.mode`, `check.commands.lint`, `check.commands.typecheck`, `check.environment`, `check.live-scenarios`, `debt-tracking` |

---

## 9. Where a doc and the code disagree

| Doc says | Code does |
|---|---|
| `agents/review.md:27`: `review.block-on` "default: `critical`" | `critical,high` (`scripts/temper:3814`, `scripts/flow.py:420`); `reference/review.md:28` was updated in this PR, the brief was not |
| `reference/review.md:160-164`: mutate a file and restore it | Review writes no code (`agents/review.md:30-31`); the mod refuses it (`rules.ts:277-283`) |
| `reference/review.md:204-210, 260-282`: confidence filter and review memory | no code reads either |
| `reference/review.md:241`: "write them to `review-context.json`" | the schema above it has no field for findings (`:229-237`) |
| `reference/check.md:34-53`: twelve validation levels | the CLI runs the suite with coverage, scenario commands, acceptance, mutation, regression (`scripts/check_run.py:678-750`) |
| `reference/check.md:21-24`, `templates/temper.config.default:41-45`: `check.commands.lint`, `typecheck` | read by nothing |
| `reference/check.md:184-188`: Check never runs a second full Maven pass | Maven is detected as `mvn -q test` with no coverage (`scripts/check_run.py:140-141`) |
| `commands/temper.md:102-104`: `next` asks whether to write the HTML report | it writes it without asking (`scripts/flow.py:2237-2241`) |
| `scripts/temper` help, `:5097`: `temper check run|detect` | `ahead` exists too (`:4948`) |
| `scripts/flow.py:1436-1441`: the acceptance tests "must pass at integration" | integrate does not run them |

---

## 10. Changes I would make, most valuable first

1. **Repair in place, recheck only the difference.** In the stage where the finding was made, launch the fix agent
   with the whole finding (description and suggestion), let the CLI mark the finding resolved by the fixing commit,
   run the CLI's checks on the new tree, and launch a recheck that reads only the diff since the reviewed tree and the
   list of findings, as the plan review's recheck does. No Build question, no second whole Review.
2. **One gate and one question for Review and Check.** Start both when Build passes (in fix runs too), compute both
   verdicts, ask once. Drop the questions that decide nothing and the one-option reason dialog; keep reasons for
   overrides and accepted findings.
3. **Tie every verdict and every kept pass to a tree digest, through one runner.** One notion of "same tree"; Check's
   suite, the scenario commands and the acceptance command reuse a pass on that tree; the commit gate asks that the
   review and check verdicts be of the tree committed. This is what makes 1 and 2 safe.
4. **Run the mechanical checks when Build ends, before any Review launch:** the suite once with coverage, the
   scenario commands once, the locked acceptance tests. In a fix run, the suite right after the Fix agent.
5. **Make the mutation gate sound and bounded:** no stale bytecode, the tests of the changed files instead of the
   whole suite, skip when three mutants cannot fit the budget, and report survivors as findings for the in-place repair
   instead of failing the stage.
6. **Cut Review to what is used:** a short brief, findings written as structured rows the CLI draws the panel from;
   remove review memory, OCR, the confidence threshold, the mutation spot check, the scenario pass check and the
   metrics writes, or implement them in the CLI.
7. **Before merging PR #115:** fix "More options" at the Review question, the brief's stale default, and the finding
   that stays open after a small change; decide whether medium findings should recommend a loop while the loop is
   this expensive.
8. **Pipeline and the commit tail:** the CLI polls the checks; an agent runs only on a red result; the report, the
   page and the record commit are one CLI call.

---

## 11. What any redesign must keep

- The person decides only in a question dialog; the mod adds no deciding button (`.claude/CLAUDE.md`, "Known
  mistakes"; ADR 0012, ADR 0013).
- A gate verdict is computed by `scripts/temper` from the evidence ledger, never asserted by a model
  (`.claude/CLAUDE.md`, "The deterministic spine").
- A test run counts only when the CLI ran it or the person confirmed it (`scripts/runs.py:7-12, 30-33`).
- `git commit` is refused while a gate is FAIL and not overridden: build, review and check each need PASS or the
  person's override (`scripts/temper:4116-4144`); hooks fail open except on their one detected violation
  (`.claude/CLAUDE.md`).
- The code committed is the code Review and Check judged (today by write bans, `rules.ts:277-291, 315-323`, and the
  gate row `scripts/temper:3847-3857`).
- A fix is test-first, RED then GREEN (`scripts/temper:3633-3645`, `agents/build.md:21-25`).
- Only the person accepts or overrides a finding, with a reason that stays in the ledger and the report; a reviewer
  never accepts or contests its own finding; the ledger is never cleared to pass a gate (`agents/review.md:42-44`,
  `reference/review.md:258`, `scripts/findings.py:14-19`).
- Locked acceptance tests and a fix's regression test are not edited by the builder; only the person reopens a lock
  (`scripts/check_run.py:516-520`, `agents/fix.md:34-38`).
- Loops are bounded, and the same failure is not recommended again (`scripts/loop_step.py:20-32`,
  `scripts/flow.py:753-763, 853-863`).
- Temper pushes and calls `gh` only by `reference/pr.md`, on the person's choice; every pull request is a draft; never
  `gh pr ready`; an armed run and a fix run never push (ADR 0015, points 1, 2, 5).
- The Pipeline agent never pushes or commits; a CI log is untrusted text (ADR 0014, point 2;
  `agents/pipeline.md:25-28`).
- Changed files stay within the plan, tests, the spec folder, or what the person allowed
  (`scripts/temper:4145-4190`).
- No credential-named variable reaches a test command (`scripts/run_env.py:33-53`).
- Four options a question at most (`scripts/flow.py:492-498`).
- Stage logic lives in the stage's brief and in `scripts/flow.py`, never in `commands/temper.md` or `commands/fix.md`
  (`.claude/CLAUDE.md`).

---

## 12. What I could not determine

- The time and cost of a Build fix pass by itself; the evidence gives only fix plus second Review.
- How often Review raises a finding at medium or above on 9.8.5, and so how often the new default loops.
- What triggered the 20 or more fix passes at 9.8.4 that were not followed by another Review.
- Check's wall time on a real project. The benchmark suites run in about a second.
- How often the Review agent launches subagents, a nested Opus agent, or runs tests itself.
- Whether the collision between the reviewer's own test runs and the background Check has happened in a run.
- Any cost of pull requests or Pipeline.
- Why fix runs are left out of `check ahead`.
- Whether the mod's driver starts `check ahead` as the conversation does. It runs an agent's `before` calls
  (`hooks/temper-mod/core/driver.ts:401-409`); I did not run it.
