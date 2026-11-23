# The build of 9.8.5 — a run that asks twice

This is the summary of the build: what it set out to do, what it made, and the outcome of every finding of the
independent audit, by its id. The plan is `docs/plans/one-go/` (its README holds the brief); the working papers
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
| R0-R1-2, DEVIATIONS-2 | Recorded (77713e96, and the WP32 line of PROGRESS.md): a caps row above its final is never printed ok; the three finals stay above, each with its numbers, for the owner. |
| DEVIATIONS-9 | Fixed (72483540 and later): the help text, the commands page and the owner lines agree with the tree; verified again at the merge (including `temper-help.txt` and `docs/commands.md`). |
| DEVIATIONS-7 | Resolved by the later work: the bench, the model test and the last steps of WP32 ran and are recorded. |

### Package V — verdict integrity (merged)

| Finding | Outcome |
|---|---|
| NEW-RULES-1 (high) | Fixed (0955785): a row counts at a locked claim only when its command is the owner's; `evidence run -- true` under the claim passes nothing. Case 92 (written at the merge; the agent's probe file 990 was replaced by it). |
| NEW-RULES-2 | Fixed (10b633b): `state set spec_path` repairs a lost value only; a copy of the spec folder and a rewritten slug are refused. Case 92. |
| NEW-FLOW-4 | Fixed (46f3491): the view's compile, lint and security markers draw only from a counted row (`runs.counts`). Case 92. |
| DEVIATIONS-1 (high), R2-5, TESTS-4, RULES-10, the state-clear guard, the status-writer filter | Still open — the agent died at the quota wall before these; carried to the completion package (below). |

### Package A — the approval (merged)

| Finding | Outcome |
|---|---|
| R2-4 | Fixed (b287298): a stale approval advances nothing; the branch call carries the digest the card showed. |
| NEW-RULES-3 | Fixed (cfe35f7): the approving first call and the spec branch and commit before it map only to the person's answer; the mod's guard has its test (`tests/mod/guard.test.ts`). |
| R2-3, RULES-7 | Fixed (0df1dfb): the group titles, the task titles and the Cases lines are bound (`shown_hash` in the state). |
| BLACKBOX-1, NEW-FLOW-1, RULES-8, RULES-9, R3-5, R3-6 | Still open — the same quota wall; carried to the completion package. |

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
| R6-3 | Still open (not reached before the wall); carried to the completion package. |

### The CI blocker the audit's row D45b found at the merge

The third call of an approving answer, `temper spec commit`, died on GitHub's runners with `Author identity
unknown`: `scripts/spec_ops.py` (where the commit moved in 9.8.0) had none of the identity fallback `scripts/temper`
carries (WP12), and a developer's global git identity hides it locally. Fixed (cherry-picked `bcf1293`; case 91
removes every identity by hand — no local identity, an empty `HOME`, both config files `/dev/null` — and the
commit still lands, as `Temper <temper@localhost>`).

### Package R — repair and plan (salvaged part-done)

The agent worked R4-2, R4-3, R4-4, R5-1 and R5-2 and was widening the tier bound (R5-3) when the usage quota
ended it; its uncommitted tree was salvaged whole (commit `d0e0f56`) and is finished at the merge. R4-1, R4-5,
R4-7, R5-4, R5-5 and R5-6 were not reached; they stay open, in the completion list below.

## What is still open (all of it one list)

- The completion package, not started at this push (the quota wall; resumed after it): **DEVIATIONS-1** (the card's
  `last_check` coverage filter — the gate side was verified already held), **BLACKBOX-1**, **NEW-FLOW-1**,
  **R2-5**, **TESTS-4**, **RULES-8**, **RULES-9**, **RULES-10**, **R3-5**, **R3-6**, **R6-3**, **R4-1**, **R4-5**,
  **R4-7**, **R5-3** (finish), **R5-4**, **R5-5**, **R5-6**, the rest of **NEW-FLOW-3**, and **BLACKBOX-9**.
- The three caps above their finals (`gate_rows` 81/55, `option_labels` 83/71, `question_ids` 38/35): each is
  restated only in a pull request of its own; CI now blocks further growth.
- The bench's cost and time lines for every kind of task, and the median-under-12 CI line: missed by design,
  `verify.sh final` fails on them.
- No real Maven or Gradle project was measured; no reader timed the sample cards; the older live smoke checks
  were not run. Each is the owner's to order.
- U23 (the looser Interfaces check) is kept as shipped; the choice is the owner's.
