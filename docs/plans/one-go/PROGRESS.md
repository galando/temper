# Progress of the one pass build

- Branch: `claude/fervent-shannon-gtbnuf`
- Pull request: 117, a draft
- Made of: `7c7a1c1` (main, 9.8.4), `10e965a` (pull request 115, the base), `e88f105` (tip of ccr-88156f39-u643ta, plan and kit)
- Watch: one check is scheduled; the next is due 2026-11-17 09:17 UTC
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
| WP08 | done | `d3f46ff` | 2026-11-17 | the defects of pull request 115 fixed, removed or made safe in four lanes against tests other agents wrote; expected to fail 92 (72 selftest, 20 scenarios); two caps above their final |
| WP09 | done | `b5a8c0a` | 2026-11-17 | every carrier of a verdict prints `VERDICT: <scope> <verdict>`; go, the driver and the loop read it; integrate-fail off the list, which holds 91 (72 selftest, 19 scenarios); prompt_bytes above its final |
| WP10 | doing | | | tests `b17aa3b` |
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
| 2 | `7f2dade` | 2026-11-17 | PASS (selftest 835 s, end to end shards 1376, 1258, 1405 and 1628 s, while the WP08 lanes ran beside it); review: 21 plus 3 findings fixed | 2655 | 113 (93 selftest, 20 e2e) |
| 3 | `8afc67a` | 2026-11-17 | PASS (selftest 2822 pass, XFAIL 72); review: 8 findings fixed in the merge `0f83802` | 2449 | 92 (72 selftest, 20 e2e) |

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
- 2026-11-16 the container restarted while the phase 2 gate, the phase 2 review and the WP08 test writers ran; the review and the test writers were resumed from their journals, the gate run again. The restart brought Claude Code 2.1.326, whose `AgentInfo` type refused a fake of `tests/mod/driver-wiring.test.ts` under `plugin validate --strict` (a line of the base); fixed in `0543f3b`.
- 2026-11-17 phase 2 review: 21 findings confirmed, 4 refuted, all fixed in the merges of `p2fixa` to `p2fixd`: the drift options carry ids beside them (`drift_ids`), the case 40 walker reaches `group.change`, the run summary counts no task gate as a launch, counts the question `next` hands the carrier and counts each step back, a `final` of the floor or of the caps is never removed, the bench counts steps back to Plan and blocked tasks, the broken scenarios read the card from the view and want a rerun at once on the same tree, a list line for a mode its scenario never runs is stale, and `check_changed_tests` and `check_done` lost five ways to pass a change unseen. Their checkers found three more (a listed name `,` that covered six expects, a looser D06 expect, the caps `final` gap), fixed in the merge `7f2dade`.
- 2026-11-17 phase 2 review: D60d passed at the head without its promise; its reader now wants a Review launch first after the restore, so `selftest:D60d` is on the list for WP11 and the list holds 113 (93 selftest, 20 e2e).
- 2026-11-17 phase 2 review: `view-fixtures.ts` is 192,283 bytes; the view `armed-review-pass` moved to `view-fixtures-2.ts` (72,413).
- 2026-11-17 for WP22: broken-flaky may never pass as WP22 step 9 is written. `MOCK_RED` fails every suite run with no filter on every tree, so "the same command has a pass on the base tree" never holds; WP22 must count a failure known at the base as that pass, or the fixture changes. The fixture now keys the late flaky test on the tree of the code folder (`HEAD:backend`), not `HEAD^{tree}` as the spec of WP06 says.
- 2026-11-17 for WP13 and WP16: group-fail asks `build.pass` after the approval in plain and mod mode, which is D01's promise; the D06 expect can pass only once D01 holds.
- 2026-11-17 `check_changed_tests.py` reads a TypeScript `expect(` call for at most 40 lines and counts parentheses outside quoted strings only; neither limit bites today.
- 2026-11-17 WP08, caps above their `final`, for the owner (note 5 of `done.md` part F; no `final` moved): `option_labels` measures 72 against 71 (the new label "It is the code" of M9), `config_comment_keys` measures 48 against 46 (the commented `# build:` and `# evidence:` blocks of M8, which the spec asks for).
- 2026-11-17 WP08: the floor of small-change moved in its package commit: `launch_total` 8 to 7 (the Check agent left `launches`) and `suite_runs` 3 to 4, because M7 makes Check of a small change the CLI's `check run`, which really runs the suite where the scripted agent only recorded a run; the run moved, it was not added. The replay is unchanged (9.8.4 10 questions, 9.8.5 9, with the policy 5); `check_floor.py --final` still fails on the replay's questions 9 (final 3) and loops recommended 1 (final 0), which later packages own.
- 2026-11-17 WP08: the package 4 line of `CHANGELOG.md` still says the mod allows a push to a `temper-backup/` branch, which M12 removed; for WP31. `docs/mod.md` "Person only calls" does not list `doctor --write`; for WP31.
- 2026-11-17 WP08: `tests/mod/audit.test.ts` has no kind for `doctor ... --write` and no view fixture holds the option `add-setup`, so the audit does not check the setup question's call; WP21 removes that question.
- 2026-11-17 WP08: case 9 fails three checks with `_walk_to_commit: command not found` when run alone, because the helper lives in `temper-cases-8.sh`; it fails the same way at the base and passes in the whole run.
- 2026-11-17 WP08: a byte compiled `scripts/__pycache__/guardrails-snippet.cpython-313.pyc` makes case 1 fail (a shipped file names a project settings file); anyone who runs `py_compile` over `scripts/` meets it.
- 2026-11-17 WP08: `temper-cases-8.sh:359` and `scripts/e2e/replay.ts:309` still append a second `autonomy:` block (spec trap 2); under the merging reader of M8 they pass and no replay number moved, so they were left.
- 2026-11-17 WP08: M13 (c) sets `shown_block` as a side effect of `setup_offer` and the failed plan question reads it afterwards; WP21 removes that code.
- 2026-11-17 WP08: the rewrite of case 22 `:37` removed the only selftest of the JDK range quote, the JaCoCo line quote and the naming of an absent file (listed in `changed-tests.md`).
- 2026-11-17 WP08: CI found case 27 `the question shows the proposed block whole` red where Postgres is not installed: it read `temper next` without the fake pg tools on PATH; fixed in `8afc67a`.
- 2026-11-17 phase 3 review: 8 findings confirmed, 3 refuted, all fixed in the merge `0f83802`: the mod guards `.temper/check/ahead.json` too (Check adopted its rows without a run), only the preflight's own time out is "not checked" (a command that exits 124 by itself fails), D56a calls `gate plan` itself so it fails without M16, fix-breaks-suite wants `build.fail` after `review.fail`, the M10 question shows the setup block whole while it offers it, and three lines of docs and help.
- 2026-11-17 CI: case 2 failed once on `8519148` and passed on a rerun of the failed jobs (run 44034578084); it passed locally three times. A flake, not a fix.
- 2026-11-17 the container restarted while the WP09 builder ran its checks; it was resumed and ran every Done when command again after the CLI's last change.
- 2026-11-17 WP09: `prompt_bytes` measures 307,886 against its final of 307,712 (13 bytes of room were left before the package; the marker rule went into three pages). No final moved.
- 2026-11-17 WP09: a marker printed into a pipe that a reader closed early (`| grep -q`) turned the call into exit 141; the one helper `_verdict` ignores SIGPIPE. `verify quick` missed this (it ran case file 50 alone), the whole selftest found it in cases 1 and 25.
- 2026-11-17 WP09: integrate-fail could not pass in driver mode, because its scripted person stopped by answering nothing, which the driver counts as a hand back; it now ends at the same question with `stopAt`, its asserts unchanged. group-fail and group-fail-twice stop the same way, for WP16.
- 2026-11-17 WP09: the spec names no marker for a task gate that parks its group on a merge conflict; it prints `task:N FAIL`, so the driver does not hand back there.
- 2026-11-17 decisions taken by me, after the owner's instruction to settle decisions alone: (1) a cap above its final is never raised; later packages lower it where they touch its files, and WP32 cuts what is still above below its final before the final gate. (2) U23 is decided at WP32. (3) WP10: `state init` removes the budget record too; `budget.py room <key>` prints one JSON object; the grep of its Done when leaves out `scripts/selftest`, which keeps the old names on purpose; a step back to Plan spends only when the Build gate failed (the person's own choice otherwise); a call refused later has spent its repeat, as the spec says.
- 2026-11-16 WP00: the clone was shallow; `git fetch --unshallow origin` made `7c7a1c1` reachable for the replay.

## Follow ups of pull request 115

- [ ] U1 (WP25): a plan patch keeps the marks of a failed fix, so the next failure still blames the command.
- [ ] U2 (WP25, WP21): a patched command skips the plan's checks, a Validate patched to `true` passes, the patch is not shown as a change of the approved plan.
- [ ] U3 dropped: `evidence void` is read in one place only; WP30 removes claimed runs and WP22 counts "run it anyway".
- [ ] U4 (WP08 the test, done; WP22 the key and a record of every reuse): the store of reused passes had no test; its key has no tool versions.
- [ ] U5 (WP09): `temper go` reports a failed group check or `integrate` as an error, so the mod hands the run back.
- [ ] U6 (WP11): after one stop the run asks at every stage for good.
- [ ] U7 (WP11, with the budget of WP10): the policy stops where the question recommends a retry.
- [ ] U8 (WP11): an unattended run cannot end in a pull request.
- [ ] U9 dropped as its own item: every group failure question has five options; WP10 and WP25 rebuild that question.
- [ ] U10 (WP21): the preflight runs under the temp folder, Build inside the project.
- [ ] U11 (WP21): any failure no pattern names passes as "needs new code".
- [ ] U12 (WP21): a gate call that is ended leaves its worktree and its running command.
- [ ] U13 (WP20): the proposed setup line `. .venv/bin/activate` fails in every worktree.
- [x] U14 (WP08): the environment agent's normal "no draft" result is a failed call; gone with the agent (M13).
- [ ] U15 (WP21): a failed preflight row goes whole into the question.
- [ ] U16 (WP21): the wrong reason on a red Maven base.
- [ ] U17 dropped: the proposal treats any mention of a variable as "the code reads it"; the block is shown whole (M13).
- [ ] U18 (WP29, WP20): secrets are masked by name only; `3.10` reaches a command as `3.1`.
- [x] U19 (WP08): three run files are not in the exclude list and outlive the run.
- [ ] U20 (WP08 its own lines, done; WP18 `agents/review.md:27`; WP31 the rest): documents that disagree with the code.
- [ ] U21 (WP08 the policy run, done; WP07 the scripted promises, done; WP30 the fixture): no end to end test ran the policy, a failing preflight, a setup block or a plan patch; the shared selftest fixture counts claimed runs.
- [ ] U22 (WP16): the mod counts a typed answer of at most 100 characters; the CLI takes 2,000.
- [ ] U23 kept as shipped (WP32 names it in the pull request text, for the owner): the Interfaces check matches any `send(msg)`.
- [ ] U24 (WP25): the plan digest has three copies that must agree.
- [x] U25 (WP08): the policy's tests ran without `park-on-touch`; the merging reader of M8 keeps it.
- [ ] U26 (WP21): at Check the setup offer reads the Plan stage's stored faults.
- [ ] U27 (WP21): the preflight skip row is written outside the CLI's lock.
- [x] U28 (WP01): a generated copy of test helpers with its own rule.
- [ ] U29 dropped: housekeeping of the pull request page; the one pull request's text is WP32's.
