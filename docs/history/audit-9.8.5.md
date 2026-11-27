---
description: "The independent audit of the build of Temper 9.8.5 and the outcome of every finding"
nav_exclude: true
---

# The audit of 9.8.5, and the outcome of every finding

This is the account of the independent audit of the build: what the build set out to do, what it made, and the
outcome of every finding of the audit, by its id. The checked summary of the build is `docs/history/build-9.8.5.md`. The plan is `docs/plans/one-go/` (its README holds the brief); the working papers
of the packages are `docs/plans/one-go/wp/`; the follow ups of pull request 115 are listed with their state in
`docs/plans/one-go/PROGRESS.md`. The definition of done is `docs/plans/one-go/done.md`.

## What 9.8.5 is

1. A feature run asks twice: one approval of intent and plan before any code is written, and one question at the
   commit. Between them a passed check moves on by rule, a failed check gets one counted repair in its stage, and
   repeats are budgeted (2 a failure, 6 a run). "Ask me at every stage" is the second option of the approval and
   keeps the old flow.
2. A bug run (`/temper:fix`) asks twice too: the root cause with its proposed fix, and the commit.
3. Tools, services and the suite are checked once before the change; every verdict names the tree it judged.
4. Defaults live in code; the config template has 21 lines; stack packs, three skills and unread machinery are gone.
   Two commands are listed: `/temper:temper` and `/temper:fix`; the stage commands are doors that went.
5. An old config still works (`autonomy.enabled: false` reads as `run.default: ask`); a saved run of 9.8.4 or the
   base goes on to the commit question; the installed commit hook still blocks.

## The build in numbers

From `3f186d4` (WP00, the baseline) to the head of this pull request. 33 packages done, 0 blocked. The selftest
grew from 2879 passing assertions at the baseline to 3561 at the builder's final verification (3089 s), every
scripted scenario in every mode agreed with its recorded counts (150 e2e runs), and the mod's suite passed 2003
tests. The bench ran with a real model: round (b), 18 runs, all 18 ended done at the commit, 213 of 213 hidden
tests passed; a bug run asked 2 dialogs and launched 3 agents; feature runs asked a median of 5 to 6.5.

## The independent audit, and the outcome of every finding

Two auditors worked the branch blind (`docs/plans/one-go/audit-2026-11-21.md` and `-low.md`, branch
`ccr-88156f39-u643ta`, at `ec1caee`), on the builder's code at `57b4cb6` and again on its last fixes. Their
findings were worked in packages: F (CI, caps, records) and E (environment, upgrade) landed first; V (verdict
integrity), A (the approval), C (the cards) and S (stops and budget) landed after, merged with their conflicts
resolved; R (repair and plan) was salvaged part-done at a usage-quota wall. The rest of this section is the
ledger, by finding id.

### Closed in the builder's own last fixes (`57b4cb6`..`84af64b`, with F and E)

| Finding | Outcome |
|---|---|
| NEW-FLOW-2 | Fixed (365eafba, 1e2e3938): the one time notice and the `config.tidy` answer are kept in `temper-marks.json` in the clone; case 73 proves it. |
| NEW-FLOW-5 | Fixed (744541bc): more password shapes hidden in what is shown. |
| R0-R1-4 / U18 | Fixed (744541bc): `3.10` reaches a command and `config get` prints it as written; the masking half is kept as shipped, its shapes listed in PROGRESS.md. Verified again at the merge. |
| R0-R1-5, DEVIATIONS-8 | Fixed (af429d8c): the two scorecard figures the plan names are named as not computable from the kept bench data. |
| R0-R1-6 | Fixed (a64fc3a4): the bench gate's pass lines are held by a case. |
| R0-R1-9 | Fixed (30f10917): the Design half of row D45 has its assertion (`D45b`, case 44). |
| R6-1 | Fixed (637b040f): the environment check reads the JVM's version line, not its first line. |
| R6-2 | Fixed (2f3df837): a new failing test named like an old one is a new fail line. |
| R6-4 | Fixed (28b7253e): the environment check is held to 5 s as a whole. |
| R6-5 | Fixed (7ff5cde0): a green baseline resolves the base's failure record. |
| R6-7 | Fixed (1c02b934): the CHANGELOG's line agrees — a red suite is asked when its result is known. |
| R7-2, R7-4 | Fixed (cce76f6c): the upgrade from 9.8.4 with every gate computed; `D60` says what it proves; a run saved at Check or the commit keeps the Review 9.8.4 gave it (S widened the migration, below). |
| R7-5 | Fixed (e497a6bd): `docs/mods-testing.md` follows the flow of 9.8.5. |
| BLACKBOX-4 | Fixed (0273a3be): the environment check tries the services the project's files ask for. |
| TESTS-1, TESTS-3, R0-R1-3, DEVIATIONS-3 | Fixed (248796b7, c1724bfe): CI fails a size above its final, every shard compares the floor, and CI runs the cheap steps of `verify.sh` it left out. |
| TESTS-2, TESTS-5 | Fixed (57315b7f, 0afd75df): the second base holds for every test file the branch added, the missing rows are listed, and `D84` carries the "Proves less" note of what the checker cannot see. |
| R0-R1-1, DEVIATIONS-5 | Fixed (c5664b88): eight end-to-end shards, a limit of 20 minutes; the median-under-12 line is named as missed under "Not done". |
| R0-R1-2, DEVIATIONS-2 | Recorded (77713e96, and the WP32 line of PROGRESS.md): a caps row above its final is never printed ok. On 2026-11-27 the owner raised the three finals to the measure, each with an entry in `scripts/caps.json`. |
| DEVIATIONS-9 | Fixed (72483540 and later): the help text, the commands page and the owner lines agree with the tree; verified again at the merge (including `temper-help.txt` and `docs/commands.md`). |
| DEVIATIONS-7 | Resolved by the later work: the bench, the model test and the last steps of WP32 ran and are recorded. |

### Package V — verdict integrity (merged)

| Finding | Outcome |
|---|---|
| NEW-RULES-1 (high) | Fixed (0955785): a row counts at a locked claim only when its command is the owner's; `evidence run -- true` under the claim passes nothing. Case 92 (written at the merge; the agent's probe file 990 was replaced by it). |
| NEW-RULES-2 | Fixed (10b633b): `state set spec_path` repairs a lost value only; a copy of the spec folder and a rewritten slug are refused. Case 92. |
| NEW-FLOW-4 | Fixed (46f3491): the view's compile, lint and security markers draw only from a counted row (`runs.counts`). Case 92. |
| DEVIATIONS-1 (high), R2-5, TESTS-4, RULES-10, the state-clear guard, the status-writer filter | Closed in the completion package (the last section), except RULES-10 and the `state clear` guard: the next release. |

### Package A — the approval (merged)

| Finding | Outcome |
|---|---|
| R2-4 | Fixed (b287298): a stale approval advances nothing; the branch call carries the digest the card showed. |
| NEW-RULES-3 | Fixed (cfe35f7): the approving first call and the spec branch and commit before it map only to the person's answer; the mod's guard has its test (`tests/mod/guard.test.ts`). |
| R2-3, RULES-7 | Fixed (0df1dfb): the group titles, the task titles and the Cases lines are bound (`shown_hash` in the state). |
| BLACKBOX-1, NEW-FLOW-1, RULES-8, RULES-9, R3-5, R3-6 | Closed in the completion package (the last section), except RULES-9: the next release. |

### Package C — the cards (merged)

| Finding | Outcome |
|---|---|
| R3-1, BLACKBOX-7 | Fixed (71797af, 9ae6784): an rca.md with no CAUSE or no FIX is nothing to approve; the question offers the root cause agent again. |
| R3-2, BLACKBOX-5 | Fixed (9ae6784): the approval card keeps a criterion's lines and its `proposed` mark. |
| R3-3, BLACKBOX-2 | Fixed (9ae6784, and the e2e of 71797af): the stop card's WHAT WAS TRIED counts the question's own repeats; the two checks can fail. |
| R3-7 | Fixed (9ae6784): the reading is not Check's alone. |
| BLACKBOX-6, BLACKBOX-8 | Fixed (9ae6784): a stop at a passed stage says WHY IT STOPPED; the SPENT numbers count as `run_summary` counts. |
| NEW-FLOW-3 (sites 3-5), BLACKBOX-9 | Partly held: the fixes these name are in the tree, but only some have their own assertions (case 92 and the e2e of 71797af cover three of the five sites); the rest stay open in the completion package. |

### Package S — stops and budget (merged)

| Finding | Outcome |
|---|---|
| R2-1 | Fixed (da93d29): a scope drift of an armed run parks first, then asks; the park is the recorded stop (case 57's rows). |
| R2-2 | Fixed (4abf7c4, 6859f77, 6df627c): at a spent budget the question is `run.budget` with the count, and both questions offer the grant; a failing task's relaunches spend the budget. |
| BLACKBOX-3 | Fixed (6df627c, and the merged `budget_key` in `scripts/card.py`): task and group repeats hold their own keys; the card shows the true attempt count. |
| NEW-RULES-4, NEW-FLOW-6 | Fixed (6859f77): the group fix compares with the project's prefix; a file named like the kept copy of the config is seen by the scope check. |
| R4-6, R7-2 | Fixed (f8f632b): ADR 0021 names `run.budget`; a run saved past its Review is rewound to its Review (the migration widened in `scripts/state_ops.py`). |
| R6-3 | The next release (the owner's decision of 2026-11-26). |

### The CI blocker the audit's row D45b found at the merge

The third call of an approving answer, `temper spec commit`, died on GitHub's runners with `Author identity
unknown`: `scripts/spec_ops.py` (where the commit moved in 9.8.0) had none of the identity fallback `scripts/temper`
carries (WP12), and a developer's global git identity hides it locally. Fixed (cherry-picked `bcf1293`; case 91
removes every identity by hand — no local identity, an empty `HOME`, both config files `/dev/null` — and the
commit still lands, as `Temper <temper@localhost>`).

### Package R — repair and plan (salvaged part-done)

The agent worked R4-2, R4-3, R4-4, R5-1 and R5-2 and was widening the tier bound (R5-3) when the usage quota
ended it; its uncommitted tree was salvaged whole (commit `d0e0f56`). An earlier line here said the package was
finished at the merge. It was not: the salvage holds the checks of R4-2 and R4-3, the fix of R4-4 (case 44), of R5-1
and R5-2 (`flow_revise.py`, `budget.py`), of R5-3 and of R4-1, but no fix for R4-2 and R4-3 (`scripts/repair_ops.py`
was untouched). Both are fixed in the completion package, the last section. R4-5, R5-4, R5-5 and R5-6 were not
reached: the next release. R4-7 is fixed in two halves.

### The completion package (2026-11-24 to 27): the audit closed, and the merged tree made whole

An independent audit of `57b4cb6` (2026-11-21) wrote 78 findings: 2 High, 38 medium and 38 low, beside the three gaps
the builder's own summary named. Earlier packages were merged without a whole run of the suite. On 2026-11-26 the
owner decided: 9.8.5 ships when every High and medium finding is closed and the tree's own checks are green; the low
findings follow in the next release. Every finding's outcome, by its id. "Held by" means the check was seen red with
the fix undone. "As recorded above" means an earlier table of this page names the commit; it was not read again.

| Finding | Outcome |
|---|---|
| DEVIATIONS-1 (High), R2-5 | Fixed (7830a5a4): the commit card's `last_check` counts a coverage row only as a gate counts it (the gate side was held already); `evidence resolve` speaks of no later release. Case 83, case 92. |
| NEW-RULES-1 (High) | Fixed (09557852). Its checks, case 87, were never green: the locked "test" was a file the shell could not run, so the lock was refused in silence, and the bug run's second test passed. Repaired (e119a94f): the fixture is a script, the row of a re-run through `evidence run` says the exit (no output is kept) instead of nothing. Held by: each of the rule's three sites undone turns the case red. |
| NEW-RULES-2 (medium) | Fixed (10b633b). Case 2 and case 3 assert the guard itself now (d22a0e99): a folder of another slug is refused, the repair of a lost value is taken. Case 84's third assertion runs on a copy of the spec folder, as the audit did. |
| NEW-RULES-4 (medium), NEW-FLOW-6 (low) | Fixed (6859f77), as recorded above. |
| NEW-FLOW-1 (medium) | Fixed (7583c596): the acceptance question is asked again after "Ask me at every stage". The view fixtures were regenerated with it. |
| R0-R1-1, R0-R1-3, TESTS-1, TESTS-3, DEVIATIONS-3, DEVIATIONS-5 (medium) | Fixed (c5664b88, 248796b7, c1724bfe), as recorded above. |
| R0-R1-2, DEVIATIONS-2 (medium) | Closed by the owner's decision of 2026-11-27: the three finals are raised to the measure (gate rows 55 to 81, option labels 71 to 83, question ids 35 to 38), each with its entry in `owner_raises` of `scripts/caps.json`; any other raise still fails. |
| R2-1, R2-2, R2-3, R2-4 (medium) | Fixed (da93d29, 4abf7c4 and 6859f77 and 6df627c, 0df1dfb, b287298). Case 57's two assertions of R2-1 and R2-2 were never green; they read the park call to its end and the drift question's four options now (d22a0e99). |
| R3-1, R3-2, R3-3 (medium), R3-7 (low) | Fixed (71797af, 9ae6784). Case 8 expects the root cause agent again at the start of a bug run (d22a0e99), and the scripted root cause agent of `pyjokes-full` writes `rca.md` as the brief asks (d22a0e99): the scenario ran in a circle to its time limit before. |
| R3-4, RULES-3 (medium) | Fixed (1b606807): the commit hook holds a bug run's start branch before the approval, and `docs/trust.md` says so. Case 58. |
| R4-2 (medium) | Not fixed until 80d6f408: an earlier line of this page said "finished at the merge", and `scripts/repair_ops.py` still knew a test file by one narrow pattern. Now a test file is known by every rule the CLI has and by the plan's own test commands (`repair_ops.test_file`). Case 65 was red first: the repair that emptied `Tests/DemoTests.swift` was committed at Review. |
| R4-3 (medium) | Fixed in the same commit: a proof whose test command names no file is read by the test files the repair changed; the reason a GREEN does not count is said, and carried into the question of the revert. Case 65, red first. |
| R4-4 (medium) | Held by case 44's D05b (`plansensitive`, `planfail`). Held by: with `if r.sensitive()` undone, the case fails. |
| R5-1 (medium) | Fixed in the salvage (d0e0f56, `tier_step`); its assertion was never green, for it asked `temper next` before any gate ran. Case 71 runs the gate first (d22a0e99). Held by: with the fix undone, the case fails. |
| R5-2 (medium) | Fixed in the salvage (`revise_since_pass`, `budget.py`). The budget's half is held by case 71's assertion; the flow's half by a second leg (d22a0e99): after two counted revises of a failed gate and a pass, a note is still the narrow agent's. Held by: each half undone turns its leg red. |
| BLACKBOX-1 (medium) | Fixed (a208a3bb): the commit gate's scope row takes a bug run's approved set from the files `rca.md` names and the recorded regression test. Case 58, red first; with the fix undone, its first assertion fails. |
| BLACKBOX-2, BLACKBOX-3, BLACKBOX-4, BLACKBOX-5 (medium) | Fixed (9ae6784 and 71797af, 6df627c, 0273a3be), as recorded above. |
| DEVIATIONS-7 (medium) | Resolved by the later work, as recorded above. |
| The three gaps | `temper status`: fixed (85a83812, case 2). The rule log through `state redo` and `group continue`: proven closed (case 93; with the log's write undone at either call, the case fails). `state clear` in the middle of a run: left as `docs/trust.md` documents it; the next release (the restart question's own option is that call, so the CLI cannot tell the person's from a session's). |
| R4-1 (low) | Fixed in the salvage (d0e0f56); case 64 passes. |
| R5-3 (low) | Fixed in the salvage. Its bound made every two-group fixture of the selftest invalid; the fixtures record a tier now (d22a0e99: case 5's `gp_base`, cases 6 and 41 through it, the template's example at a medium tier), and case 70 has the trivial and the no-tier legs. |
| R4-7 (low) | Fixed in two halves: the patch replaces a Validate line that holds no command (d0e0f56), and the parser reads only the backquoted command (fa7c672d). |
| R3-5, RULES-8, R3-6, TESTS-4, NEW-RULES-3, NEW-FLOW-2, NEW-FLOW-4, NEW-FLOW-5, R0-R1-4, R0-R1-5, R0-R1-6, R0-R1-9, R6-1, R6-2, R6-4, R6-5, R6-7, R7-2, R4-6, R7-5, BLACKBOX-7, DEVIATIONS-8 | Fixed, as recorded above. |
| R0-R1-8 (low) | The list of the 29 follow-up points of pull request 115, each with its state, is in the pull request text now (D106). |

**A regression of the merged tree, found by the first whole run (0ec33569).** R2-3 bound what the approval card showed
by a second digest, and compared it with `tasks.md` as a file. The plan amendment by rule and the person's plan patch
move the plan's digest and left that one where it was, so after either the Build gate failed on "tasks.md changed
since the approval": the end-to-end scenario `blocked-task-amended` stopped with a question where there should be
none. Both move it now. Held by: two assertions of case 29, red first (`shown=other|row=False`).

**A rule made right (fab2c016).** The start of a task whose group is parked was refused by the budget first ("the
person grants more at the question"), a question granting more could not un-park. The park refuses it now, as it does
`task gate` and `task test`, and no repeat is counted. Held by: case 5's `park: a fourth attempt cannot start`.

**Mac-only lines of the selftest, repaired (d22a0e99).** `printenv` with four names and `paste` with no file read
differently under BSD; two assertions can never see their value on a Mac. They read the same thing everywhere now.
One line stays Mac-only and passes in CI: case 61's "a service that gives no answer" depends on a full listen queue.

**The next release:** NEW-FLOW-3's other assertions, R4-5, R5-4, R5-5, R5-6, R6-3, RULES-9, RULES-10, TESTS-2,
TESTS-5, BLACKBOX-6, BLACKBOX-8, BLACKBOX-9, DEVIATIONS-9, the `state clear` gap, and the team's feedback plan
(`docs/plans/fit-the-repository.md`), in the plan's order.

## What is still open (all of it one list)

- **The next release** (the owner's decision of 2026-11-26: 9.8.5 ships when every High and medium finding is closed
  and the tree's checks are green): NEW-FLOW-3's other assertions, R4-5, R5-4, R5-5, R5-6, R6-3, RULES-9, RULES-10,
  TESTS-2, TESTS-5, BLACKBOX-6, BLACKBOX-8, BLACKBOX-9, DEVIATIONS-9, the `state clear` guard, and the team's
  feedback plan (`docs/plans/fit-the-repository.md`), in the plan's order.
- The three caps that were above their finals (`gate_rows` 55, `option_labels` 71, `question_ids` 35): the owner raised
  them to the measure (81, 83, 38) on 2026-11-27; a further raise needs its own entry in `scripts/caps.json`.
- U23 (the looser Interfaces check): kept as shipped for 9.8.5; a warning in the next release.
- The bench's cost and time lines for every kind of task: missed as measured, and accepted by the owner on 2026-11-27
  (`docs/evidence/bench-accepted-9.8.5.json`), so the bench step of `verify.sh final` passes on those numbers alone.
  The median-under-12 CI line: missed.
- No real Maven or Gradle project was measured; no reader timed the sample cards; the older live smoke checks were
  not run. Each is the owner's to order.
- One line of the selftest passes in CI and fails on a Mac: case 61's "a service that gives no answer" (it depends on
  a full listen queue).
