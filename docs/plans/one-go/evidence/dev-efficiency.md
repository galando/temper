# Dev efficiency: the cost of changing Temper itself

One of the 17 readers. Subject: what one behaviour change to Temper costs (files, minutes, loop backs), why, and what would make it cheap.
Tree read: `/home/user/temper`, branch `pr115`, commit `9a01eff` (clean). Everything was run in a scratch clone of that commit.

Tags on each claim: **[M]** measured by me, **[V]** verified in code, **[D]** claim in a doc or commit message only, **[I]** inferred.
Paths are relative to `/home/user/temper` unless they start with `/`.

---

## 0. Three things the planners must know first

1. **The working tree is not the head of PR #115.** The local branch `pr115` is at `9a01eff`, which is commit 13 of the 16 commits GitHub lists for the PR. The PR head is `10e965a` (three later commits: `573bb66` an A/B replay test and three bug fixes, `c417166` a directory rule fix, `10e965a` two e2e scenarios adapted to 9.8.5). **[V]** `git rev-parse HEAD` in `/home/user/temper` = `9a01eff…`; GitHub `pull_request_read get_commits` for #115 lists 16 commits ending `10e965a`; `git cat-file -t 10e965a…` fails locally.
2. **At the local head the end to end suite is red.** `bun scripts/e2e/run.ts plain fix` fails in 3 s (`expectation failed: the regression test fails first`); `plain maven` did not finish in 100 s (I stopped it; cause not determined). In CI, the e2e job at this exact commit was cancelled at its 60 minute limit (run 314, job "End to end", 19:30:11 to 20:30:20). **[M]** The fix is in `10e965a`, per its message **[D]**.
3. **The CLI's main file is 1,640 bytes below a hard size limit.** `scripts/temper` is 260,504 bytes; `scripts/quality-check.sh:21-29` fails any tracked file over 262,144 bytes. `scripts/selftest/view-fixtures.ts` is 259,060 bytes (3,084 left); `CHANGELOG.md` is 246,956 bytes (15,188 left). **[M]** Any restructuring plan that adds code to `scripts/temper` is blocked by this before it starts.

---

## 1. The numbers

### 1.1 Local timings (scratch clone, 4 CPUs, machine shared with other agents; load average is given because it moved the results)

| What | Command | Result | Wall time | Notes |
|---|---|---|---|---|
| Self test, fast tier | `bash scripts/selftest/run-selftest.sh --fast` | PASS 832, FAIL 0 (case files 10 to 31, 4 at a time) | **145.6 s** (user 386.9 s + sys 79.7 s = 466.5 s CPU) | **[M]** load 0.06 at start, 4.5 at end. The script's header says "a minute or two" (`scripts/selftest/run-selftest.sh:7`) |
| Self test, whole, parallel | `bash scripts/selftest/run-selftest.sh` | **did not finish in 560 s** (my cap). Finished: files 1, 2+3, 4, 7, 8+9, 10 to 29, 31 = 2,084 pass, 0 fail. Unfinished: 5, 6, 30 | 560 s, then killed (user 832 s + sys 179 s CPU) | **[M]** load 1.0 to 5.8. Files 5 and 6 were both still running after 557 s and 519 s |
| Case file 5 alone | `TEMPER_CASES_ONLY=5 … test-temper.sh` (timestamp per assertion) | 395 assertions logged in 520 s, then killed (the file has 436 `assert_` lines) | >520 s | **[M]** 2 processes at once, load about 2. 35 `integrate:` assertions took 121 s; the 20 slowest gaps are 39% of the time |
| Case file 6 alone | same, `=6` | 276 assertions in 520 s, then killed; **the first 220 are case file 5's** | >520 s | **[M]** see 2.5, a generator bug |
| Validators | `bash scripts/quality-check.sh` | PASS 9, FAIL 0 | **4.9 s** | **[M]** header says "under 30 seconds" (`scripts/quality-check.sh:4`) |
| Mod tests | `claude plugin test .` (Claude Code 2.1.325) | 1774 pass, 0 fail, 40 files | 32.9 s | **[M]** |
| Directory rule tests | `bash scripts/selftest/test-validate-directory.sh` | PASS 77, FAIL 0 | 20.0 s | **[M]** |
| Directory rules | `bash scripts/validate-directory.sh` | OK | 3.8 s | **[M]** |
| Mod call list | `bash scripts/check-mod-calls.sh` | OK, 20 calls | 4.2 s | **[M]** |
| View fixtures regeneration | `bash scripts/selftest/make-view-fixtures.sh` | 34 views | 26.7 s per file, two files | **[M]** case file 8 runs it twice to compare (`scripts/selftest/temper-cases-8.sh:455-458`) |
| One e2e scenario, three modes | `bun scripts/e2e/run.ts all full-run` | 4 PASS (70, 70 and 92 steps) | 101.2 s | **[M]** about 34 s per mode |
| e2e `fix`, `maven` | `bun scripts/e2e/run.ts plain fix` / `maven` | `fix` FAIL in 3 s; `maven` no result in 100 s | | **[M]** at `9a01eff` |

Per call cost of the CLI (idle machine, a `python3` shim on PATH counting processes) **[M]**:

| Call | Wall | `python3` processes |
|---|---|---|
| `temper next --json` | 0.16 s | 2 |
| `temper go` | 0.30 s | 5 |
| `temper state advance intent_complete plan` | 0.34 s | 7 |
| `temper gate intent` (self test fixture, 18 rows) | 0.59 s | 17 |
| `temper gate plan` (self test fixture, 24 rows, no preflight, no fresh review) | 1.09 s | 42 |
| One scripted full run, plain mode (`full-run`, 70 steps) | 32 s | 737 |

So a feature run spends about 30 s in the CLI's own process starts, and the self test pays the same price per assertion: 1,481 s for 2,879 assertions in CI is 0.51 s each (run 317), 1,986 s for about 2,874 is 0.69 s (run 314). **[M]**

### 1.2 CI

One workflow gates a PR: `.github/workflows/quality.yml`, 10 jobs, all on every push and PR to `main`, no path filter, no `concurrency:` group (**[V]** `quality.yml:3-7`; the only limit is `timeout-minutes: 60` on e2e, `:89`). The other three workflows do not gate a change: `pages.yml` (deploy docs on push to main), `release-bump.yml` (manual), `release.yml` (on tag).

Jobs and step times, from the GitHub API (`actions_list list_workflow_jobs`) **[M]**:

| Job (`quality.yml` line) | What it runs | PR head `10e965a`, run 317 (success) | Local head `9a01eff`, run 314 |
|---|---|---|---|
| Quality Checks (`:10`) | `quality-check.sh` | 7 s | 4 s |
| **temper CLI Unit Tests (`:18`)** | `bash scripts/selftest/test-temper.sh`, **in series** (`:23-24`) | **24 min 41 s** | **33 min 06 s** |
| README Validation (`:26`) | `validate-readme.sh` | <1 s | <1 s |
| Directory Readiness (`:34`) | `test-validate-directory.sh`, `validate-directory.sh` | 14 s + 3 s | 21 s + 4 s |
| Documentation Validation (`:44`) | `validate-docs.sh` | <1 s | <1 s |
| Plugin Structure (`:52`) | `validate-plugin.sh` | <1 s | <1 s |
| Stage Panel Validation (`:60`) | `validate-panels.py` | <1 s | <1 s |
| Official Manifest Validation (`:68`) | `claude plugin validate --strict .` | 4 s (+5 s install) | 4 s |
| **End to end (`:81`)** | `bun scripts/e2e/run.ts all`: 23 scenarios × 3 modes, in series (`:96`, `scripts/e2e/run.ts:7-22`) | **30 min 27 s** | **cancelled at 60 min** |
| Mod (`:98`) | `claude plugin test .` 42 s, validate, types, `tsc` 4 s, call list 3 s | 61 s whole job | 48 s |
| **Whole run** | | **30 min 39 s** | 60 min 17 s |

A third data point for the unit job: 31 min 35 s at `573bb66` (run 315). The same suite took 24.7, 31.6 and 33.1 minutes on one day.
On `main`: run 303 (9.8.4) 29 min 42 s; run 281 (9.8.3) 21 min 02 s; run 265 22 min 30 s. **[M]**

**PR #115's own CI history, 14 runs** (`actions_list list_workflow_runs`, branch `ccr-e0b10914-a7hzu0`) **[M]**:

| Run | Commit | Conclusion | Wall |
|---|---|---|---|
| 304 | `7859742` | failure | 30:52 |
| 305 | `c0c9c7e` (one docs file, an ADR) | failure | 25:25 |
| 306 | `a9068b7` | success | 29:50 |
| 307 | `bd565eb` | success | 31:37 |
| 308 | `339d3c4` | failure | 31:08 |
| 309 | `5c42b58` | failure | 27:21 |
| 310 | `69aad39` | failure | 32:13 |
| 311 | `28fff04` | failure | 31:08 |
| 312 | `feb6df1` | success | 34:33 |
| 313 | `30d94ac` | cancelled | 60:18 |
| 314 | `9a01eff` | cancelled (e2e at its limit; every other job passed) | 60:17 |
| 315 | `573bb66` | failure (Quality Checks and Directory Readiness failed, e2e cancelled at its limit) | 60:18 |
| 316 | `c417166` | cancelled | 60:17 |
| 317 | `10e965a` | success | 30:39 |

4 of 14 green (29%). The runs add up to about 546 minutes of wall time for one PR. Runs 307 to 310 were four pushes inside nine minutes; with no `concurrency:` group all four ran to the end. I read the job lists of runs 314, 315 and 317 only; which job failed in 304, 305 and 308 to 311 I did not determine. The commit messages name some causes **[D]**: "The build-task brief is back under its size limit (CI failure)" (`a9068b7`), "doctor lists folders without a wildcard after a variable and reads no home folder (two repository rules)" (`28fff04`), "ab-replay.sh finds the root through git, not a .. after a variable (directory rule)" (`c417166`), "the view fixtures, fixed in this commit" (`a9068b7`), "a quoting rule, fixed here" (`30d94ac`).

### 1.3 Lines

Counted with `wc -l` at `9a01eff` **[M]**.

| Area | Lines | Files | Note |
|---|---|---|---|
| `scripts/temper` | 5,121 | 1 | bash, 260,504 bytes |
| `scripts/*.py` | 12,335 | 49 | `flow.py` alone is 3,111 lines, 205,263 bytes |
| `hooks/temper-mod` | 4,984 | 26 | TypeScript |
| `agents/*.md` | 1,252 | 13 | |
| `commands/*.md` | 1,026 | 11 | `commands/temper.md` is 215 lines, 17,042 bytes |
| `reference/*.md` | 2,511 | 15 | |
| **Product, the six areas asked for** | **27,229** | | |
| also product: `scripts/guards` 2,214 (12), `templates` 1,250 (8), `packs` 955 (15), `skills` 591 (5) | 5,010 | | product total 32,239 |
| `scripts/selftest` | 30,379 | 41 | case files 12,251; **generated** `view-fixtures*.ts` 15,869; **generated** `case-helpers-5.sh` 950; runner and helpers 1,309 |
| `scripts/e2e` | 1,977 | 9 | |
| `tests/mod` | 7,245 | 43 | |
| **Test, all** | **39,601** | | **hand written: 22,782** |
| validators `scripts/*.sh` | 2,058 | 8 | `validate-directory.sh` alone is 859 |
| `bench` | 7,727 | 233 | benchmark harness and tasks |
| `docs/**/*.md` | 7,782 | 46 | `docs/flow.md` 305, `docs/commands.md` 877, `docs/mods-plan.md` 803 |
| `CHANGELOG.md` | 3,027 | 1 | 49 version entries, 246,956 bytes |
| **Docs and changelog** | **10,809** | | |

Ratios: hand written test lines to the six product areas, 0.84 to 1. To executable product only (`scripts/temper` + `scripts/*.py` + the mod = 22,440), 1.02 to 1. Docs and changelog are 40% of the six product areas.

Inside `scripts/temper` **[M]**: 161 shell functions, 191 `python3` invocations, of which 47 are multi line `python3 -c "…"` blocks (about 1,715 lines) and 19 are heredocs (424 lines). About 2,100 of the 5,121 lines (41%) are Python written inside bash strings.

Inside `scripts/flow.py` **[M]**: 370 `if`/`elif`, 41 `self.question(` and 12 `self.with_more(` call sites, 89 `self.opt(` sites with 71 distinct option labels, 30 distinct run state keys read, 27 `"action": "work"`, 18 `"auto"` and 14 `"ask"` emission sites.

### 1.4 The shape of a commit (last 30 commits on `pr115` that are not merges)

`git log -30 --no-merges --numstat` **[M]**. Three merge commits fall in the window and are left out.

| Kind | Commits | Files touched: median (min to max) | Lines changed: median |
|---|---|---|---|
| all | 30 | **4** (1 to 21), mean 6.2 | 120 |
| `fix:` | 5 | **4** (3 to 5) | 41 |
| `feat:` | 13 | **10** (3 to 21) | 236 |
| `docs:` | 5 | 3 (1 to 3) | 68 |
| `test:` | 3 | 4 (1 to 4) | 15 |

A typical fix is: one of `scripts/flow.py` / `scripts/temper` / another `scripts/*.py`, one case file, `CHANGELOG.md`, and often one prose file. A typical feature adds a new `.py` module, a new case file, the two runner lists, `docs/flow.md`, and one to three prose files.

How often each area is in a commit, of 30:

| Area | Commits |
|---|---|
| a self test case file | 19 |
| `CHANGELOG.md` | 16 |
| a `scripts/*.py` other than `flow.py` | 15 |
| `scripts/flow.py` | 12 |
| `scripts/temper` | 12 |
| `docs/flow.md` | 9 |
| `scripts/selftest/run-selftest.sh` | 8 |
| `scripts/selftest/test-temper.sh` | 8 |
| `agents/*.md` | 6 |
| `docs/commands.md` | 5 |
| `reference/*.md`, `templates/*` | 4 each |
| mod tests | 3 |
| mod source | 2 |
| view fixtures | 1 |

What changes together most often, of 30: `scripts/*.py` + case file 14; `flow.py` + case file 12; `scripts/temper` + case file 11; `scripts/temper` + another `.py` 10; **`flow.py` + `docs/flow.md` 9 (9 of the 12 `flow.py` commits)**; `CHANGELOG.md` + case file 9; `flow.py` + another `.py` 9; `flow.py` + `scripts/temper` 8; case file + runner lists 8.

Over all 122 commits in the clone that are not merges: `CHANGELOG.md` is in 61, a case file in 58, `plugin.json` and `.claude/CLAUDE.md` in 43 each (version stamps), `scripts/temper` in 43, `README.md` in 37, `flow.py` in 31. **[M]**

PR #115 as a whole at `9a01eff`: 58 files, +4,085 −276. Product scripts 2,002 lines in 16 files; self test 1,847 lines in 21 files (950 of them the generated `case-helpers-5.sh`); docs and changelog 324 lines in 5 files; briefs, reference and templates 151 lines in 10 files; mod 19 lines; mod tests 11 lines. **[M]** `git diff --numstat origin/main...HEAD`

### 1.5 The 256 KiB wall

| File | Bytes at `origin/main` | Bytes at `9a01eff` | Headroom to 262,144 |
|---|---|---|---|
| `scripts/temper` | 258,648 | 260,504 (it was 261,663 four commits earlier) | 1,640 |
| `scripts/selftest/view-fixtures.ts` | 260,042 | 259,060 | 3,084 |
| `CHANGELOG.md` | 241,523 | 246,956 | 15,188 |
| `scripts/flow.py` | 184,605 | 205,263 | 56,881 |

**[M]** The rule is `scripts/quality-check.sh:21-29` **[V]**; its reason is the plugin directory **[D]** (`CHANGELOG.md:958-969`: "`scripts/temper` had grown to 281,652 bytes, and the directory holds a version for a reviewer when a file that is not an image is over 256 KiB").
Consequences seen in the history: `scripts/*.py` went from 44 to 49 files inside this PR **[M]**; `CHANGELOG.md:157` and `:333-334` describe moving Python blocks out "keeping the CLI under the plugin directory's 256 KiB limit" **[D]**; commit `20bfd78` is "move the grouped Build report out of the CLI, so 9.8.4 fits with the lock fix" **[V]** `git log`. The module boundaries of the 49 Python files are therefore set by byte pressure, not by subject **[I]**. The fixtures file holds 34 views at a mean of 7,619 bytes; one new 91 byte field in every view breaks the limit and forces a hand edit of the split in `make-view-fixtures.sh` (the `extra` set, `scripts/selftest/make-view-fixtures.sh:220`, `:325-329`) **[M]/[I]**. A 9.8.5 size changelog entry is 5,433 bytes and a 9.8.4 size one 9,823 bytes **[M]**, so `CHANGELOG.md` hits the wall in two or three releases.

---

## 2. What makes one behaviour change expensive

### 2.1 One new question, or one new option on a question

| # | Place | Where | Kind | What catches a miss |
|---|---|---|---|---|
| 1 | The branch that builds the question: text, labels, calls, the move | `scripts/flow.py`, inside `Builder.ask` (`:574`, 306 lines) or `group_failed` (`:1957`), `commit` (`:2222`), `policy_move` (`:1144`) … | hand, code in nested `if`s | a case file |
| 2 | The move, if new | `MOVES` set, `scripts/flow.py:58-59` (`opt()` refuses others, `:460-461`) | hand | a `ValueError` at run time |
| 3 | The CLI call the option runs | a dispatch line in `scripts/temper` (`main`, `:4981`) and, because that file is full, **a new `scripts/<name>.py`** | hand | case file |
| 4 | The mod's list of calls only the person may cause | `hooks/temper-mod/core/rules.ts:371-372` (`PERSON_WORDS`), `:476-497` (`personOnly`) | hand, a second classifier of what `flow.py` already says | a mod test, by hand |
| 5 | A mod test for 4 | `tests/mod/*.test.ts` | hand | |
| 6 | A new case file (the habit is one per feature) | `scripts/selftest/temper-cases-N.sh` | hand | |
| 7 | Register the case file, **four lists in two files** | `scripts/selftest/test-temper.sh:235-265` (one source line each); `scripts/selftest/run-selftest.sh:34` (`ALL`), `:37` (`fast`), `:49` (`changed`) | hand | nothing: a file left out is silently not run |
| 8 | Older assertions that hold the question's labels or order | 149 assertion lines in the case files use `labels` or `['label']`; 126 lines of `tests/mod` hold a label literal; e2e person scripts pick by label (`scripts/e2e/scenarios.ts:119-123`) | hand | the tests fail |
| 9 | The view fixtures, when a fixture state shows the question | `scripts/selftest/view-fixtures.ts`, `view-fixtures-2.ts` | **generated** by `make-view-fixtures.sh` (27 s each) | `temper-cases-8.sh:455-458` |
| 10 | e2e scripted agents or person, when the flow moved | `scripts/e2e/scenarios.ts`, `pyjokes.ts` | hand | the e2e job, 30 min later |
| 11 | The flow page | `docs/flow.md` (305 lines, sections named by release, `:98`, `:115`, `:132`, `:166`, `:183`, `:214`, `:224`, `:237`) | hand | nothing, except three phrase greps (below) |
| 12 | The command reference | `docs/commands.md` (877 lines), the header comment of `scripts/temper:10-33`, the `--help` text (46 command lines) | hand | one test per help line when someone writes it (commit `85636d1` "the help line documents task blocked") |
| 13 | Stage prose that names the question | `reference/<stage>.md`, `agents/<stage>.md`, `docs/mods-testing.md` (70 manual check boxes), `docs/getting-started.md` | hand | nothing |
| 14 | `CHANGELOG.md` | | hand | only the version heading is checked (`quality-check.sh:111-123`) |
| 15 | A config key, if the option has one | `templates/temper.config.default` (171 lines) and the default repeated at each read site (see 3) | hand | nothing |
| 16 | The mod's run driver, when the option's `do` or `steps` text is new prose | `hooks/temper-mod/core/driver.ts:215-216`, `:290-291` match on the CLI's wording by regex | hand | a mod test |

Worked example, **commit `69aad39`** ("temper plan patch", one new option on the failed group question): 10 files, +214 −6 **[V]** `git show --stat`: `scripts/plan_patch.py` (new, 144), `scripts/temper` (+4), `scripts/flow.py` (+16), `hooks/temper-mod/core/rules.ts` (1 line: `'patch'` in `personOnly`, now `:481`), `tests/mod/v975.test.ts` (+1), `scripts/selftest/temper-cases-29.sh` (new, 28), `scripts/selftest/test-temper.sh` (+1), `scripts/selftest/run-selftest.sh` (8), `docs/flow.md` (+10), `docs/commands.md` (+6). Its changelog lines came later in `feb6df1`. CI for it: run 310, failure, 32 minutes.

Worked example, **commit `5c42b58`** (one config key, `autonomy.policy`): 6 files: `flow.py` (+62), `templates/temper.config.default` (+3), `docs/flow.md` (+11), a new case file, and the two runner files.

### 2.2 One new gate row

| # | Place | Where | Kind |
|---|---|---|---|
| 1 | The row itself | either bash in `gate_<stage>()` of `scripts/temper` (`gate_intent :2027`, `gate_plan :3494`, `gate_build :3613`, `gate_design :3718`, `gate_review :3812`, `gate_check :3862`, `gate_commit :4033`), 33 distinct `_req "<name>"` labels; or a Python row module called from there (`gate_rows.py`, `plan_rows.py`, `fresh_review.py`, `preflight.py`, `acceptance.py`, `decisions.py` …), about 23 more names | hand; the same gate is assembled from up to six sources (`scripts/temper:3497-3601` for Plan) |
| 2 | The question that reacts to the row | `flow.py` matches rows **by name string**: `FRESH_ROWS` (`:46`), `PERSON_ROWS` (`:2626`), and literals such as `"context map reviewed"`, `"preflight"`, `"tasks agree with decisions"`, `"criteria validated"`, `"review completed"` | hand; a renamed row silently stops matching |
| 3 | What the agent must now produce | `agents/<stage>.md`, `reference/<stage>.md`, `templates/*` | hand |
| 4 | A size limit on that brief | `TASK_BRIEF_MAX_BYTES=6144` (`scripts/temper:106`) and the like | a CI failure when exceeded (`a9068b7` **[D]**) |
| 5 | The self test fixture every case starts from | `setup()` in `scripts/selftest/test-temper.sh:53-165`; this PR had to add `evidence: claimed-runs: count` there (`:77-78`) so that older cases still pass under the new rule | hand |
| 6 | The scripted runs that must now satisfy the row | `scripts/selftest/make-view-fixtures.sh` (330 lines of scripted runs), `scripts/e2e/scenarios.ts`, `pyjokes.ts` | hand; `10e965a` exists because two scenarios did not (4 CI runs lost) |
| 7 | New case file + the four lists | as 2.1 rows 6 and 7 | hand |
| 8 | View fixtures | regenerate | generated |
| 9 | `docs/flow.md`, `docs/commands.md`, `CHANGELOG.md` | | hand |

Worked example, **commit `a9068b7`** (the Design row "tasks agree with decisions", and a changed default of `review.block-on`): 12 files, +331 −117: `scripts/decisions.py` (new, 123), `scripts/answer_ops.py`, `scripts/temper` (+27), `scripts/flow.py` (+41), `agents/build-task.md`, `reference/review.md`, `templates/temper.config.default`, `docs/flow.md` (+17), `temper-cases-25.sh` (new), `test-temper.sh`, `run-selftest.sh`, `view-fixtures.ts` (142 lines regenerated). Its message records two loop backs: the brief over its byte limit and the stale fixtures. **[V]** stat, **[D]** message.

### 2.3 Generated against hand kept

| Artifact | Made by | Drift check |
|---|---|---|
| `scripts/selftest/view-fixtures.ts`, `view-fixtures-2.ts` (15,869 lines) | `make-view-fixtures.sh` | exact compare, `temper-cases-8.sh:455-458` |
| `scripts/selftest/case-helpers-5.sh` (950 lines) | `make-helpers-5.sh` | exact compare, `temper-cases-31.sh:34-35`; **the generator is wrong, see 2.5** |
| version stamps in `plugin.json`, `.claude/CLAUDE.md`, README badge, `docs/index.md`, `docs/getting-started.md`, the changelog heading | `scripts/version-bump.sh:8-18` | `quality-check.sh:111-135`, `validate-plugin.sh` |
| `.claude-plugin/types/` | loading the plugin (`quality.yml:112-117`) | `tsc` |
| **Hand kept, with a check that only says "differs"** | | |
| `plugin.json` lists of agents and commands | hand | `validate-panels.py`, `quality-check.sh:61-93` |
| the mod's `$` call list | hand (`scripts/check-mod-calls.sh:24-46`) | exact both ways |
| `docs/commands.md` names every slash command | hand | `validate-docs.sh` rule 1 (`:19`) |
| a few phrases in prose | hand | 26 assertions grep a prose file, e.g. `temper-cases-13.sh:31-32` ("commands/temper.md and docs/flow.md state the rule"), `temper-cases-25.sh:38`, `temper-cases-5.sh:1202`, `:1222` |
| **Hand kept, no check** | | |
| `docs/flow.md` body, `docs/commands.md` body, `reference/*.md`, `agents/*.md` rule text, `CHANGELOG.md` body, `docs/mods-testing.md` | | none |
| the case file lists in `run-selftest.sh` and `test-temper.sh`, and the `--changed` map (`run-selftest.sh:42-46`) | | none |
| stage tables in the mod (`hooks/temper-mod/core/stages.ts:4`, `:11-20`, `:33`), `PERSON_WORDS`, `GUARD_KEYS` (`rules.ts:335`) | | two mod tests compare the stage order (`tests/mod/guard.test.ts:233-234`) |
| config defaults at their read sites, model defaults in three places | | none |

### 2.4 The feedback loop is slow, late and often red

- **The gate is 30 to 60 minutes away.** Unit job 24.7 to 33.1 min in series; e2e 30.5 min when green, 60 min when a scenario hangs. **[M]** 1.2
- **The local "whole suite" is not runnable in a sitting.** The parallel runner did not finish in 9 min 20 s on 4 shared CPUs **[M]**; `CHANGELOG.md:803-804` says "4 at a time, about 17 minutes" for 1,988 assertions at 9.7.5 **[D]**; there are 2,874 now. `CONTRIBUTING.md:16` still tells a contributor to run the serial `test-temper.sh` **[V]**.
- **The fast tier is a release list, not a subject list.** `--fast` is "the case files the 9.7.5, 9.7.6, 9.8.0, state machine and 9.8.4 work added" (`run-selftest.sh:7`, `:37`); `--changed` maps `flow.py` to files 8, 10, 12, 13 and then always adds 10 to 31 (`:43`, `:49`). Case files are named by number and organised by release (`temper-cases-10.sh:1` "Release 9.7.5, Phase A", `-20.sh:1` "Release 9.8.4", 21 to 31 "Release 9.8.5 case file N"), and the mod's tests likewise (`audit-round4.test.ts`, `review-exploits-2.test.ts`, `security-round3.test.ts`, `v975.test.ts`, `v976.test.tsx`). To find the tests of a behaviour you grep. **[V]**
- **Case files are not independent.** 3 continues from 2 and 9 from 8 in one process (`run-selftest.sh:33-35`, `test-temper.sh:226-228`); 6 needed 5 until this PR generated a copy of 5's helpers. **[V]**
- **A hang costs an hour, four times in this PR.** The e2e loop is bounded by steps (400, `scripts/e2e/loop.ts:56`, `:164`), not by time, and the job by 60 minutes. Runs 313 to 316. **[M]**
- **House rules are found in CI.** `scripts/validate-directory.sh:5-40` has 13 rules, among them: no script names a path with a folder named `hooks` (9, 10), no wildcard after a variable (11), no `..` after a variable (12), no word joined from quoted pieces (13). `CONTRIBUTING.md:121-147` explains them. Two commits in this PR exist only to satisfy them (`28fff04`, `c417166`) **[D]**. The check takes 3.8 s locally **[M]**, so it is cheap to run before every commit; nothing does.
- **No commit of this PR ran the e2e suite before pushing** as far as the messages show: each quotes the self test count ("Whole suite: 2861 pass, 1 fail", "Mod tests: 1774 pass") and none the e2e **[D]/[I]**.
- **Release adds a manual list.** `docs/mods-testing.md:8`: "Nothing is merged or released until you have run it in your own terminal", 70 boxes **[V]** count of `- [ ]`.

### 2.5 A defect in the test tooling this PR added (measured)

`scripts/selftest/make-helpers-5.sh:13-26` copies each helper function of `temper-cases-5.sh` up to "the first line that is exactly `}`". Four helpers do not end that way (`gg_ready_g1`, `gi_int`, `gr_json`, `h5_hook`; `scripts/selftest/case-helpers-5.sh:198`, `:301`, `:423`, `:650`), so the copy runs on through the test code that follows them. **732 of the 950 lines of `case-helpers-5.sh` are top level test code of case file 5, with 214 `assert_` lines.** **[V]** `temper-cases-6.sh:11` sources that file when it runs alone, which is how the parallel runner runs it since `30d94ac` (`run-selftest.sh:35`).

Measured: case file 6 alone logged **220 assertions of case file 5 (group gate, integrate, group reopen, group report) before its own first assertion, 420 s in**; its own 56 logged assertions took the last 100 s before my cap. **[M]** So the parallel runner now runs the slowest fifth of case file 5 twice, the two longest jobs of the parallel run are both mostly the same work, and its `PASS:` total is no longer the serial total. CI is not affected (in series the helpers are already defined). `CHANGELOG.md:67-68` presents the change as a speed up **[D]**; on the evidence it made the parallel run slower.

---

## 3. The same rule in several texts

| Rule | Where it is written (all **[V]** unless marked) | The one source that could make the rest |
|---|---|---|
| The stages and their order | `scripts/temper:104`, `:116`, `:121`, `:152-153`, `:4723`; `scripts/flow.py:47-48`, `:1115`; `scripts/cli_ctx.py:21`; `scripts/output_ops.py:17`; `scripts/adhoc_ops.py:25`; `hooks/temper-mod/core/stages.ts:4`, `:33`. **Ten code sites.** Labels again in `flow.py:49-50` and `stages.ts:11-20` | one stage table (id, label, gate, agent, model, back target, small change allowed) |
| What the loop does with an action, and "a failed call stops its action, except a gate call that printed `-> FAIL`" | three implementations: `scripts/go.py:109`, `hooks/temper-mod/core/driver.ts:261` and `:432`, `scripts/e2e/loop.ts:17-24`; two texts: `commands/temper.md:131`, `docs/flow.md:68`; one test that greps the phrase: `temper-cases-13.sh:31-32` | `go.py` as the one loop; the mod and the e2e drive it instead of copying it |
| How a `{placeholder}` is quoted into a call | `driver.ts:202`, `:206`; `scripts/e2e/world.ts:141`; `commands/temper.md:105` "Filling a placeholder"; `docs/flow.md:84` | the CLI takes the answer as an argument (`temper answer <option id> --reason …`), so nobody fills a string |
| Which calls only the person may cause | implicit in `flow.py` (each option's `calls`, `MOVES` at `:58-59`); again by word in `rules.ts:371-372`, `:476-497` | a command table with a `person_only` flag; or the view names the exact calls of each option (it does) and the mod needs no word list |
| Headers and fixed option sets | `flow.py:40-45` (`Temper gate`, `Build group`, `Temper resume`, `Scope drift`, `Outside the plan:`); `rules.ts:20-21`; `hooks/temper-mod/core/runview.ts:202` (defaults) | the view carries them; the mod has no copy |
| "Four options at most" | `flow.py:494-499`, `:510`; `driver.ts:223-224`; `commands/temper.md:137`; `docs/flow.md:92`, `:210`; `docs/mods-testing.md:170` | `flow.py` only |
| Which option is recommended | a suffix in the label, edited as a string: `flow.py:761`, `:846`, `:861`, `:867`, `:869`, `:2009`, `:2031`, `:2035`, `:2109`; read back by `policy_move` to decide an unattended move (`flow.py:1967`, `endswith("(Recommended)")`); and by the e2e person (`scenarios.ts:120`) | a field `recommended: true` |
| Question and option wording | `flow.py` (71 labels); 149 self test assertion lines; 126 mod test lines; e2e scripts; `docs/mods-testing.md`; `docs/commands.md`; `reference/*.md`; `hooks/temper-mod/core/commands.ts:29`. Example: "Override and continue" is in 22 files, "Save for later" in 39 **[M]** `git grep -c` | a question registry with ids; tests and scripts select by id |
| Gate rows | `scripts/temper` `gate_*` (33 names) + row modules (about 23); `flow.py` name matches; `reference/<stage>.md` | a row registry (id, stage, check function, who can clear it) |
| Config keys and their defaults | `templates/temper.config.default`; the default written at each read site: 15 keys are read at 2 to 4 sites each, e.g. `loops.max-per-type` at 4, `plan.fresh-review-rounds` at 3 (`flow.py:249`, `scripts/temper:3599`, `:4574`); `review.block-on` has the default `critical, high` at one read site and `critical,high` at another **[M]** (a regex over the read sites); `docs/commands.md`; `reference/*.md` (a key is named in 2.4 prose files on average, over 16 keys I sampled **[M]**) | a config schema (key, type, default, one line) that makes the template, the defaults and the reference table |
| Model of each agent | `agents/*.md` frontmatter (`model:` line 4 of each); resolved twice: bash `scripts/temper:567-588` and Python `scripts/cli_ctx.py:21-74`, each holding `claude-haiku-5-5` (`scripts/temper:583`, `cli_ctx.py:22`) and the "complex or risk H builds on sonnet" rule (`scripts/temper:577`, `cli_ctx.py:24`, `:46-55`) | one resolver |
| CLI syntax | the header of `scripts/temper:10-33`, `--help` (32 top level subcommands), `docs/commands.md`; and written into prompts: 63 mentions in `agents/`, 71 in `commands/`, 95 in `reference/`, 43 in `docs/flow.md` **[M]** | `flow.py` already prints every call in full; briefs should get calls from the prompt `flow.py` builds, and help from one command table |
| The shape of `next` and `view.json` | `flow.py` (`view`, `:2783`); `docs/flow.md:25-96`, `:264-295`; the mod's readers `runview.ts` (291 lines), `view.ts` (327), `driver.ts:8-35` types; `scripts/go.py` | one schema file that makes the TypeScript types and the doc tables |
| The history of each rule | `CHANGELOG.md` (3,027 lines); release tags in comments: 93 in `flow.py`, 78 in `scripts/temper` **[M]**; 8 of 14 headings of `docs/flow.md` are named after a release; `docs/decisions/` (16 ADRs); `docs/evidence/` (8 files) | history in the changelog and ADRs only; code comments say what the code does; `docs/flow.md` by subject |

`CONTRIBUTING.md:111` says `commands/temper.md` is "about 10.5 KB"; it is 17,042 bytes **[M]**. That page is read by the model on every run, so its growth is paid in tokens each time; it is the one doc figure I checked against the tree and it is stale.

---

## 4. `scripts/temper` and `scripts/flow.py` as a maintenance problem

### 4.1 What they are

**`scripts/temper`** is one bash file: 5,121 lines, 161 functions, a `main` of 141 lines (`:4981`) that dispatches 32 subcommands. Bash does the control flow; every JSON read, write and rule is Python, either inline (`python3 -I -c "…"`, 47 multi line blocks, e.g. `scripts/temper:1146-1164` writes two keys of the state file) or in one of 41 modules it calls by path with positional arguments (`python3 -E -s "$SCRIPTS_DIR/fresh_review.py" rows "$spec_path" "$(_evidence_file plan)" "$STATE_FILE" …`, `:3599`). **[V]** Consequences:

- One CLI call is many processes: 42 for a plan gate, 737 for a scripted run. **[M]**
- A gate is assembled row by row in bash from up to six sources, each row a JSON line passed through shell variables (`scripts/temper:3496-3604`). **[V]**
- Python inside bash strings cannot be imported, linted or unit tested; the only test is to run the whole CLI in a temp project, which is why an assertion costs 0.5 to 0.7 s. **[I]** from 1.1.
- Some Python modules are scripts, not modules: `scripts/task_ops.py:324` reads `sys.argv[1]` at import, so `temper-cases-26.sh:4-9` tests one of its functions by `exec`ing a slice of its source text between two markers. **[V]**
- The CLI and the flow call each other both ways: `scripts/temper` calls `flow.py advance-ok` and `plan-files` (`:1134`, `:1141`), and `flow.py` prints `scripts/temper …` calls for the session to run. **[V]**
- The file cannot grow (1.5).

**`scripts/flow.py`** has small tables at the top: `SEQ`, `LABEL`, `GATE_OF`, `BACK_TO`, `MOVES` (`:47-59`). Everything else is code. `class Builder` runs from `:429` to `:2484` (about 2,056 lines, about 100 methods). **[V]**

- `core_next` (`:2360-2482`) is one ordered chain of special cases: small change done, environment agent requested, commit, foreign branch, RCA, acceptance fix, a note after the verdict, missing records, fresh review due, no verdict yet, armed run, policy run, and last the question. The order of the `if`s is the precedence; nothing states it but the code.
- `ask` (`:574`, 306 lines, 42 `if`/`elif`, 28 `return self.question…`) builds each question inline: the sentence, each option's label and description, the move, and the CLI calls as format strings. The Plan question alone has six variants that differ in which three options come first (`:673-689`).
- A question has no id and an option has no id: an option is `{label, description, move, calls}` (`:459-482`). The label is therefore the key for the mod's answer check (`docs/flow.md:94-96`), for the driver (`driver.ts:290` `opt.label === 'More options'`, `:291` a regex on the `do` sentence, `:215-216` regexes on step sentences), for the e2e person, for 275 test lines, and for the unattended policy (`:1967`).
- Comments carry the history ("9.8.0:", "9.8.4:", "9.8.5 (U2):"), 93 times.

**Answer: the flow is code spread over branches, not a table.** The data that is a table (5 small dicts) covers the stage order and the step back targets only.

### 4.2 The refactor that makes a new route or a removed question a small change

Four moves, each usable without the next.

1. **Give the protocol ids and types (no behaviour change).** Each question gets `id` (`plan.approve`, `group.failed`), each option `id` (`approve`, `arm`, `back`, `override`, `save`, `more`), `recommended: true|false`, and a `kind` for the two that only open another question. Steps and `do` get a `kind` instead of a sentence to match. Tests, the driver, the e2e person and `policy_move` select by id. The label stays what the person reads and what the mod compares for an answer. After this, changing a word changes one string and no test.
2. **Make three registries, as data, in one module.**
   - *Stages*: id, label, gate, agent brief, default model, back target, small change allowed. Replaces the ten lists.
   - *Gate rows*: id, stage, name, a Python check function, who may clear it (agent, person, nobody), the hint. `temper gate <stage>` becomes one loop in one process. `flow.py` refers to row ids.
   - *Questions*: id, stage, `when` (a named predicate over the run), text template, options (id, label, description, move, calls template, `when`, `recommended_when`). `ask(stage)` becomes "first question whose `when` holds, render it". `core_next` becomes an ordered list of (predicate, action builder) pairs, so the precedence is one visible list.
   - *Config*: key, type, default, one line. Read through one accessor; the template and the reference table are printed from it.
   Removing a question is then deleting one entry; a new route is one entry and one predicate. A doc generator prints the tables of `docs/flow.md` from the registries, and a test fails when the committed page differs, as the fixtures test does today.
3. **Move the CLI into one Python package; bash keeps only `exec python3 …`.** Port a subcommand at a time behind the existing self test and e2e suite (2,874 assertions, 23 scenarios), keeping `next` and `view.json` byte for byte (the fixtures compare already proves it, `temper-cases-8.sh:455-458`). Modules by subject, each far below 256 KiB. One process per call. The lock, the symlink refusals and the "refuse inside the plugin folder" checks (`scripts/temper:162-200`) are the risky part and go last.
4. **Test in process.** With the flow as functions of a run state, a flow test is "this state dict gives this action" in microseconds. Keep the bash suite as the conformance suite until parity, then shrink it to the CLI's edges (git, worktrees, locks, hooks). Target: the whole unit suite under two minutes locally, from 25 to 33 in CI now.

---

## 5. The five changes that would most cut the cost of developing Temper

| # | Change | Effect | Effort | Risk |
|---|---|---|---|---|
| 1 | **Fix the feedback loop first.** (a) Fix `make-helpers-5.sh` (or delete it and make case file 6 define what it needs) so 220 assertions stop running twice. (b) Discover case files by glob; delete the four hand lists. (c) CI: one matrix job per case file group, and one e2e job per mode (plain, mod, driver). (d) Add `concurrency: cancel-in-progress` on the PR ref and a path filter so a docs only commit skips the two long jobs. (e) Give each e2e scenario a wall time limit of a few minutes. (f) One `scripts/precheck.sh` that runs what CI runs and is cheap: quality-check 5 s, directory rules 4 s, mod tests 33 s, call list 4 s, fast tier, and the e2e scenarios whose files changed. | PR gate from 30 to 60 min to about the longest single group (my estimate 10 min; file 5 is the long pole at more than 520 s here). A hang costs minutes, not an hour. The two directory rule failures, the stale fixtures and the broken e2e scenarios of this PR would have been caught before the push. | **S** (one to two days) | Low. The matrix changes the names of required checks; parallel case files need the independence that 2+3 and 8+9 do not have yet, so keep those pairs. |
| 2 | **Ids and typed fields in `next` and `view.json`** (4.2 move 1). | A wording change stops touching 149 self test lines, 126 mod test lines and the e2e scripts. The unattended policy stops depending on a display string. The driver stops matching sentences. | **M** | Medium. It is a change of the protocol the mod guards answers with: add fields within version 1 (allowed by `docs/flow.md:21-23`), keep exact label matching for the person's answer, regenerate fixtures. |
| 3 | **One declarative spec: stages, gate rows, questions, config, commands** (4.2 move 2), with generators for the mod's tables, the config template, `--help`, and the reference tables of `docs/flow.md` and `docs/commands.md`. | One new question or row: one entry and one test, instead of 10 to 12 files. Removing a question or a stage, which the owner's goal will ask for many times, becomes a deletion. Duplication table of section 3 collapses to one source per rule. | **L** | Medium to high: `ask` and `core_next` hold years of special cases whose order matters. Do it question by question under the existing tests; the fixtures compare is the safety net. |
| 4 | **The CLI as one Python package, one process per call, tests in process** (4.2 moves 3 and 4). | Ends the 256 KiB wall as a design force. Plan gate from 42 processes to 1; a run saves about 30 s; the unit suite goes from about 25 to 33 min to a target under 2 min. Functions become importable, so tests stop `exec`ing source slices. | **L** | High if done at once (5,121 lines of bash with security checks). Lower as a strangler: `main` hands ported subcommands to Python one at a time. Needs a decision on whether the plugin directory accepts a Python entry point and the directory rules still pass. |
| 5 | **One home for each kind of text.** Reference pages printed from the spec (3). `docs/flow.md` by subject, not by release. History only in `CHANGELOG.md` and ADRs: remove release tags from code comments. Changelog entries capped (a few lines per change; the evidence goes to `docs/evidence/`), and the changelog split by major version before it hits the wall. Replace the 26 phrase greps with the generated page compare. Replace the 70 box manual list with the e2e driver mode plus a short smoke. | `docs/flow.md` stops being edited in 9 of 12 flow commits and `CHANGELOG.md` in 16 of 30. Fewer stale claims (`CONTRIBUTING.md:111`). | **M** | Low. The risk is losing explanations people use: keep ADRs and evidence untouched. |

Order: 1 now (it pays for itself inside the next PR). 2 before any change to questions. Then decide what of the product survives (other readers), **delete first**, and only then do 3 and 4 on what is left: porting 53 question sites, about 56 gate rows, 33 config keys and 32 subcommands that the simplified product will not keep is waste.

Smaller, cheap, worth doing with 1: name case files and mod tests by subject; make every case file independent (no 2 then 3, 8 then 9); one `temper gate` test helper that returns rows by id.

---

## 6. Invariants a redesign must keep

- No tracked file over 262,144 bytes: `scripts/quality-check.sh:21-29`; reason in `CHANGELOG.md:958-969` **[D]**.
- Python standard library only, no network: `scripts/temper:8`, `scripts/flow.py:12`.
- `next` (`v`) and `view.json` (`version`) are versioned; a field is added within a version, never renamed or removed without a new one: `docs/flow.md:21-23`, `scripts/flow.py:37`.
- The mod reads one file of the CLI's, `.temper/view.json`, and makes exactly the 20 reviewed `$` calls: `scripts/check-mod-calls.sh:24-46`.
- The person decides only in a question; the mod counts an answer only on an exact match of header, question and label for the run and step: `docs/flow.md:94-96`, `.claude/CLAUDE.md` ("One flow").
- Gate logic lives in the CLI, never in a prompt; hooks fail open except on a detected violation; a stage command is a door, not a flow: `.claude/CLAUDE.md` "Known mistakes".
- The flow with the mod equals the flow without it: `scripts/e2e/run.ts:27-31`.
- The self test never touches a real `.temper`: `scripts/selftest/test-temper.sh:20-22`, `:268-272`.
- The 13 directory rules: `scripts/validate-directory.sh:5-40`; `plugin.json` lists every brief and command: `scripts/validate-panels.py:15-18`.
- The mod works on Claude Code 2.1.287 and type checks with TypeScript 5.6: `.github/workflows/quality.yml:99-119`.

## 7. What I could not determine

- Which job failed in CI runs 304, 305 and 308 to 311 (I read the jobs of 314, 315 and 317 only).
- Why the e2e `maven` scenario does not end at `9a01eff` (it printed nothing in 100 s).
- A clean serial time per case file. My per file numbers are lower bounds taken on a shared machine.
- Whether 256 KiB is a hard rule of the plugin directory today; the only source is the changelog.
- How many CPUs the CI runner has, which sets what a matrix or the parallel runner can gain.
- Whether anything outside this repository calls `scripts/temper` as a bash file or parses its text output (the commit hook and the guards do, inside the repository).
