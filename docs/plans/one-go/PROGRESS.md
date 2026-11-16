# Progress of the one pass build

- Branch: `claude/fervent-shannon-gtbnuf`
- Pull request: 117, a draft
- Made of: `7c7a1c1` (main, 9.8.4), `10e965a` (pull request 115, the base), `e88f105` (tip of ccr-88156f39-u643ta, plan and kit)
- Watch: one check is scheduled; the next is due 2026-11-16 23:04 UTC
- Bench: allowed by the owner's first message, on this session's own model access; the live smoke too

## Baseline

Tools: bun 1.4.4, node 22.23.4, Python 3.13.18, tsc 6.0.2, Claude Code 2.1.325 (types made with 2.1.287), 4 CPUs.

| Check | Result | Seconds |
|---|---|---|
| `quality-check.sh` | All checks passed | 6 |
| `validate-docs.sh` | PASS 10, FAIL 0 | 0 |
| `validate-readme.sh` | PASS 5, FAIL 0 | 0 |
| `validate-plugin.sh` | PASS 31, FAIL 0 | 1 |
| `validate-panels.py` | pass | 0 |
| `validate-directory.sh` | OK | 4 |
| `selftest/test-validate-directory.sh` | PASS 77, FAIL 0 | 22 |
| `check-mod-calls.sh` | OK, 20 calls | 4 |
| `selftest/test-check-mod-calls.sh` | PASS 24, FAIL 0 | 2 |
| `check-known-limits.sh` | PASS 20, FAIL 0 | 1 |
| `claude plugin test .` | 1774 tests across 40 files, all pass | 37 |
| `claude plugin validate --strict .` | Validation passed | 5 |
| `tsc -p tsconfig.mod.json` (types made with 2.1.287) | no output | 3 |
| `e2e/ab-replay.sh` | 9.8.4 against the base: questions 8, 8, 4; launches 10, 7, 7; agent minutes 191, 92, 92 | 51 |
| selftest, parallel (`run-selftest.sh`) | PASS 2879, FAIL 0 | 882 |
| end to end, `run.ts all` (one process) | 69 mode lines PASS, 23 flows identical, e2e: all passed | 2498 |
| after WP01: case file 6 alone | PASS 114, FAIL 0 (no assertion of case file 5 runs twice) | 278 |
| after WP01: `verify.sh quick` with case file 5 touched | PASS | 811 |
| after WP01: bytes | `view-fixtures.ts` 187,069; `view-fixtures-2.ts` 57,975; `CHANGELOG.md` 109,834; `scripts/temper` and `scripts/flow.py` unchanged | |
| after WP02: `scripts/temper` | 214,545 bytes (45,959 freed); one quoted heredoc left; the capture of 43 states equal to the base | |
| after WP03: flow modules | `flow.py` 13,377; `flow_base.py` 12,650; `flow_run.py` 22,454; `flow_ask.py` 54,466; `flow_work.py` 32,007; `flow_build.py` 42,599; `flow_commit.py` 15,335; `flow_view.py` 15,785; capture and traces equal to the base | |
| CI after WP01 and WP02 | the run of `63cfed7` green in 12 min 20 s of wall time; the run of `3c00a7c` was cancelled by the next push; the step `Type check the mod` green | 740 |
| bytes | `scripts/temper` 260,504; `scripts/flow.py` 205,631; `CHANGELOG.md` 246,956; `view-fixtures.ts` 259,060; `view-fixtures-2.ts` 78,629 | |

## Packages

| Id | State | Commit | Date | Note |
|---|---|---|---|---|
| WP00 | done | `2992cad` | 2026-11-16 | baseline green, every number as the kit says |
| WP01 | done | `3f8a47e` | 2026-11-16 | CI in shards with cancel and one gate job, verify.sh, fixtures one view a line, older changelog moved |
| WP02 | done | `a6c5708` | 2026-11-16 | seven modules out of the CLI, output byte equal to the base by the capture of 43 states |
| WP03 | done | `3b037fa` | 2026-11-16 | flow.py a facade over seven modules; the capture of 43 states and the 69 traces equal to the base |
| WP04 | done | `7fe865f` | 2026-11-16 | 35 question ids and 51 option ids in flow_base; the ids of every dialog sit beside it, never inside |
| WP05 | done | `fbc75ec` | 2026-11-16 | floor of default-run 8 dialogs and 6 launches in every mode, fix 4 and 3; caps file, stops list, run summary, replay base 9 questions and 7 launches |
| WP06 | done | `8b57b10` | 2026-11-16 | slow and broken scripted projects, four scenarios on the list, the expected to fail rule of the scenarios; whole selftest PASS 2710 |
| WP07 | done | `3d43388` | 2026-11-16 | case files 43 to 46 and 17 acceptance scenarios written failing first; check_done, check_changed_tests, verify.sh final; expected to fail 112 (92 selftest, 20 scenarios) |
| WP08 | todo | | | |
| WP09 | todo | | | |
| WP10 | todo | | | |
| WP18 | todo | | | |
| WP14 | todo | | | |
| WP11 | todo | | | |
| WP12 | todo | | | |
| WP13 | todo | | | |
| WP15 | todo | | | |
| WP16 | todo | | | |
| WP17 | todo | | | |
| WP19 | todo | | | |
| WP20 | todo | | | |
| WP21 | todo | | | |
| WP22 | todo | | | |
| WP23 | todo | | | |
| WP24 | todo | | | |
| WP25 | todo | | | |
| WP26 | todo | | | |
| WP27 | todo | | | |
| WP28 | todo | | | |
| WP29 | todo | | | |
| WP30 | todo | | | |
| WP31 | todo | | | |
| WP32 | todo | | | |

## Phase gates

| Phase | Commit | Date | Result of `full` | Seconds | Expected to fail |
|---|---|---|---|---|---|
| 1 | `2c48db1` | 2026-11-16 | PASS (selftest 737 s, end to end shards 660, 728, 806 and 522 s, traces kept) | 1625 | no list yet |

## Blockers

None.

## Found on the way

- 2026-11-16 WP00: the first merge of `10e965a` went as a fast forward; both merges were made again with `--no-ff` before any push, so the history shows two merge commits.
- 2026-11-16 WP01: CI check names change: six checks `temper CLI selftest (shard K of 6)`, four `End to end (shard K of 4)`, and two new jobs `Changed files` and `Gate`; a branch rule should require `Gate` alone (for the owner).
- 2026-11-16 WP01: `quick` runs case files 5, 6 and 31 when case file 5 changed, so it takes about 13 minutes then, as contracts section 10 warns.
- 2026-11-16 WP01: the spec gave 259,060 bytes for the two fixture files together; that is `view-fixtures.ts` alone (the two were 337,689). `check-names.py` reads 51 tracked Python files, not 49.
- 2026-11-16 WP01: `run.ts` now exits 2 for an unknown flag or scenario name; before, an unknown name was a FAIL inside the run.
- 2026-11-16 WP02: the capture also differed between runs on the key of `.temper/preflight.json`, a hash over the fixture's HEAD; the capture writes it as fixed text.
- 2026-11-16 WP02: the optional docstrings of step 4 were not written; the room target was met without them.
- 2026-11-16 WP03: the spec's line ranges were off at four edges, only comments and blank lines; case 13 and case 18 read the flow text through a list `FLOW_FILES` and `_flow_text` of `case-helpers.sh`.
- 2026-11-16 phase 1 review: six findings fixed in `b15f153` (renames in the changes job, the concurrency group on main, two silent runner flags, a dash under a narrow locale, the capture's state file, a doc line); none changed a result.
- 2026-11-16 WP01: the run on `2c48db1` was green in CI in 9 min 12 s of wall time.
- 2026-11-16 WP04: as the spec wrote it, the ids sat inside the reason, name and Blocking dialogs, which the host's question tool refuses when the mod is off; they now sit beside each dialog (`reason_ids`, `answer_ids`, `question_ids`), held by the case `ids: no dialog the CLI writes holds a key the question tool refuses`.
- 2026-11-16 WP04: one assertion of the base changed on purpose, case 16 `go's question keeps only what the answer runs` (the spec adds `move` to what `go` keeps); for `changed-tests.md` when WP07 makes it.
- 2026-11-16 WP04: `view-fixtures.ts` is 199,901 bytes, 99 under the 200,000 of case 32; the next package that grows the view moves views to the second module.
- 2026-11-16 WP04: a defect of the base, not fixed: `contextCheck()` of `runview.ts` reads `c.question` as text while the CLI writes a dict there, so it is always null; the context question still reaches the mod when it is the view's `ask`.
- 2026-11-16 WP05: the faithful fixtures count the Context check dialog, so the replay asks one more question than the page of the base said: 9.8.4 10, the base 9, the base with the policy 5 (it was 8, 8 and 4).
- 2026-11-16 WP05: `done.md` gives no `final` for `question_ids` and `config_comment_keys`; each `final` is today's value (35 and 46).
- 2026-11-16 WP05: the replay entry of the floor bounds only the agent types its `final` names; a scenario's `launches` bound every type.
- 2026-11-16 WP05: a failed `temper gate` call inside an answer now counts as a verdict in the plain loop too, as in the driver.
- 2026-11-16 CI: the run of `ba13ee3` failed case 9 `the CLI and its Python files expand no home folder and read no transcript`, because WP05's `runs.jsonl` matched its `.jsonl` pattern; the case now leaves out lines that name `runs.jsonl` (for `changed-tests.md`). `quick` had not run case files 8 and 9, so from here the whole selftest runs before every progress commit.
- 2026-11-16 WP06: the slow project keeps the replay's pom with JaCoCo bound, because the plan gate's row `maven group verify` refuses a Maven group without it; "no coverage tool" means no coverage command Temper can run.
- 2026-11-16 WP06: `temper init` writes no config, so the fixtures also run `temper config init`, as `/temper:init` does.
- 2026-11-16 WP06: `scripts/check_floor.py` accepts a floor entry with only a `final` while its scenario is on the expected to fail list; `--final` still fails on it.
- 2026-11-16 WP07: `check_changed_tests.py` takes the second base of D84b as the first add on the first parent line (the kit's merge `3f186d4` for `done.md`), not the kit's first cut, which the kit itself rewrote; a change inside a multi line `$( ... )` with no backslash is not detected and is listed by hand.
- 2026-11-16 WP07: the scenario half of the expected to fail rule is not a bash case (the selftest job of CI has no bun); it stays the `verify.sh` step `bun scripts/e2e/xfail.ts --check`, and case 43 asserts that the step is there.
- 2026-11-16 WP07: `verify.sh final` requires every scorecard line to pass, while note 2 of `done.md` expects D91 to miss; a bench round that ran makes `final` red there unless the owner decides otherwise (for WP32).
- 2026-11-16 WP07: five listed scenarios fail in more than the 10 seconds of the spec (integrate-fail driver 30 s, budget-stop 29 s, stop-keeps-mode 26 s, slow-at55 23 s, broken-flaky 22 s); each fails where its promise breaks, after Build starts, so they were left as they are.
- 2026-11-16 WP07: ask-every-stage (D17) passes at the head and had no floor entry; its now counts went into `scripts/e2e/floor.json` (dialogs 8 in every mode), with no `final` in `done.md`.
- 2026-11-16 WP07: D33a is one joined assertion over the 30 stops (26 hold at the head), so one token covers them; every stop's check in `scripts/stops.json` names it.
- 2026-11-16 WP07: rows that differ from their package spec, where the case follows the row: D42 (Teach Me stays in reach at a passed Review with an open Medium finding; WP08), D57a (the Medium finding is named at the commit question; WP08 turns it green only with that), D61 (a GONE key is named once by `temper config show`; WP29).
- 2026-11-16 WP07: passing at the head and so not listed, though `done.md` names a later package: D64b (WP24), D60a, D60b, D60d, D60e; D29b reads the page rule of `commands/temper.md`, because the selftest job cannot run the mod.
- 2026-11-16 WP07: the merges of the first stage (`3c9dd27`, `e5935e8`) carry no attribution lines; they were not rewritten.
- 2026-11-16 WP00: the clone was shallow; `git fetch --unshallow origin` made `7c7a1c1` reachable for the replay.
