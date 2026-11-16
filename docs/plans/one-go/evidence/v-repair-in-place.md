# Verification: repair in place at Review and Check (draft item 3e, decision 5)

Base: `/home/user/temper` at `10e965a` (PR #115 head, 9.8.5). Paths are relative to it; line numbers are of that
commit. Nothing was written or run there. Experiments ran in a clone at
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-v-repair-in-place/repo`
(scripts `exp1.sh`, `exp2.sh`, `exp3.sh` and their `.out` files are beside it). No selftest, e2e or bench run.

Marks: **[code]** read at the cited line. **[ran: Xn]** seen in my clone. **[reader]** from a report, not repeated.

## Verdict

**Feasible with changes.** The mechanism fits the CLI as built: a change at Review that keeps Build's ledger and
verdict already works (the small change window), and the CLI can already prove a new tree at the Review stage
(`temper integrate` reruns when HEAD moved). Four things the draft assumes do not exist and must be built, and one
gate hole must be closed in the same patch:

1. There is no "whole finding" to hand over: a finding is one line in the ledger.
2. A fix cannot be committed at Review or Check on the run's branch: the commit hook refuses it.
3. `temper evidence resolve` takes any text, from any caller, and turns a failed Review gate to PASS with no change.
4. Nothing asks for a test first in place, and the small change path proves nothing on the new tree.
5. `scripts/temper` has 1,640 bytes left under the 256 KiB cap; the patch needs more than that in that file.

---

## 1. What forces a stage transition today

### Gate rows

| Row or rule | Where | Effect |
|---|---|---|
| `no code changed at Review` | `scripts/temper:3847-3857`, snapshot `:3763-3810` | Any tracked file outside `.temper` and `.claude` that differs from the snapshot taken when the run entered Review, or a moved HEAD, fails Review. The row's own text sends the run to Build. The snapshot is taken at `:1037` (entering Review), `:1469` (`state redo review`) and `:4615-4620` (`adhoc close` with a review step) |
| `no blocking findings` | `scripts/temper:3814-3837`, `scripts/findings.py:27-37` | Only a `resolved` or `accepted` mark stops a finding counting. Default block level `critical,high` |
| `RED then GREEN` | `scripts/temper:3633-3645`, `scripts/runs.py:40-45` | The only test first row is in the Build gate. It counts any failing run before any passing run in the whole Build ledger. It is per fix only because the step back empties the ledger |
| The commit gate's stage rows | `scripts/temper:4116-4144` | build, review and check each need PASS or the person's skip. The checkpoint carve out applies only while `next_stage` is `build` (`:4072-4110`). So a code commit on the run's branch at Review is refused: `review gate — FAIL`, `check gate — MISSING` [ran: X5b] |
| No verdict names a tree | `scripts/temper:1834-1851` | A verdict is `{verdict, requirements, ts}`. "What is committed is what was judged" is kept by the write bans and the wipe, not by a record |

### Flow

- `BACK_TO` is the only repair the gate question recommends: `scripts/flow.py:54-55`, `back_opt` `:588-593`, Review
  FAIL `:795`, Review PASS with a medium finding `:779-784`, Check FAIL `:874-875`; the policy takes the same step
  `:1157-1161, 1166-1169, 1180` [code].
- `state loop` then `_go_back`: empties the ledgers of the target stage and every later one
  (`scripts/temper:1275, 1876-1896`), removes their verdicts and skips (`:1289, 1041-1092`), moves the run (`:1290`) [code].
- The fix pass launches only at the Build stage (`scripts/flow.py:1655-1672`); the second Review is a whole Review
  (`scripts/flow.py:1374-1385`; `agents/review.md:31-34` tells it to record every finding again) [code].
- A stage is left only forward, on PASS or a skip (`advance_ok`, `scripts/flow.py:2510-2535`) [code].

### Guard rules (`hooks/temper-mod/core/rules.ts`)

- Review writes the spec folder only (`:277-283`); Check the spec folder and the project notes (`:284-291`); Commit
  the same (`:315-323`). One exception: an open small change window allows any write at its stage (`:46, 251-252`).
- Person only calls: `state loop` (`:492`), `adhoc open` (`:483`), `evidence accept|clear` (`:489`), `override`
  (`:478`). Each passes only as the call the person's answer maps to, or as a call of the CLI's own action (`:460-461`).
- `evidence resolve` is **not** person only (`:489`), and two mod tests list it as a legitimate call of any agent
  (`tests/mod/review-exploits-3.test.ts:106`, `tests/mod/security-round2.test.ts:26`).

### Briefs

`agents/review.md:30-31` ("You do not change code at Review"); `agents/build.md:21-25` (the fix pass exists only
after a `Feedback re-entry:` line).

---

## 2. Is the small change path already "repair in place"?

**In structure, yes. As a repair, no.**

What it does [code, ran: X2, X6]: `adhoc open --stage S` records HEAD and the hash of each dirty file
(`scripts/adhoc_ops.py:83-97`); the mod lets writes through at that stage; `adhoc close` lists the changed files and
the steps owed (`:100-145`): at Review a Review of those files; at Check or Commit that Review, then Check, then the
commit gate; at Build or for docs only the stage's gate. The run does not move, no ledger and no verdict is cleared,
and Build's verdict stays PASS (X2: 4 Build rows before and after).

What it lacks, each checked:

| # | Gap | Evidence |
|---|---|---|
| a | The writer is the main session: the option carries a `do` text, so the mod's driver hands the run back | `scripts/flow.py:905-913`; `hooks/temper-mod/core/driver.ts:294-296` |
| b | The finding stays open. No brief, page or flow step calls `evidence resolve`. After the change and the narrow Review the gate fails the same way and the question recommends the loop back again | grep (only tests, `scripts/e2e/replay.ts:263`, the CLI); [ran: X2] |
| c | No proof on the new tree. `integrate` and `gate build` are not called. At Check the step launches the Check **agent**, not `check run` (`scripts/flow.py:966-971`) [ran: X6]; that agent records `evidence add --exit` rows (`agents/check.md:30-33`), which no gate counts since 9.8.5 (`scripts/runs.py:30-33`). So `gate check` is computed from the CLI rows measured before the change [inferred, not run with an agent] |
| d | No test first | nothing in `scripts/adhoc_ops.py` or `scripts/flow.py:954-974` asks for a run |
| e | The fix cannot be committed on the run's branch before Check passes | [ran: X5b]. So `integrate`'s rerun, which triggers on HEAD (`scripts/temper:3317`), never fires, and the pass cache has no key on a dirty tree (`scripts/run_env.py:133-141`) |
| f | The narrow Review is the full brief (`agents/review.md`, `reference/review.md`, effort high) limited by file name, not by diff; it is not told the earlier findings | prompt line `Ad-hoc change: review only src/a.py.` [ran: X2] |
| g | No count, no bound | no counter in `scripts/adhoc_ops.py` |
| h | Any path may be written, not only the plan's files | `rules.ts:252` returns before the Build rule at `:292-305` |
| i | It is the person's option, under More options at a failed Review, with a reason dialog | [ran: X1] |

What to take from it: the state shape (`adhoc`, `adhoc_done`), the guard fact `guard.adhoc_stage`
(`scripts/flow.py:2832`), the changed file computation, the owed steps and `mark_step`, and the snapshot retake at
close (`scripts/temper:4615-4620`). A repair is that window opened by the CLI's own action, with an agent as the
writer, plus the five things it lacks.

Two existing parts cover most of what is missing:

- **`temper group fix G --commit`** (`scripts/group_fix.py:63-97`): the agent commits nothing, the CLI commits what
  it changed and records the commit as its own, and a fix that changed nothing keeps the check failed (`:79-86`).
- **`temper integrate` after a PASS** (`scripts/temper:3316-3331`): when HEAD moved it runs the Integration suite and
  every scenario test again and appends the rows. It has no stage condition: at the Review stage it added 3 rows to
  Build's kept ledger, `gate build` recomputed PASS, and the run stayed at Review [ran: X3].

---

## 3. The proof that must remain

A repair changes code after Build passed and after Review read it. Each verdict must again be of the tree that will
be committed. All of the following are CLI runs with no model.

| Check | Run on the new tree by | Already exists? |
|---|---|---|
| Integration suite, every scenario `Test:` command, Interfaces | `temper integrate` (`scripts/temper:3316-3331`) | yes, needs a commit |
| Build gate: tasks done, criteria by the **latest** scenario row (`scripts/acceptance.py:259-291`), integration | `temper gate build` on the kept ledger | yes |
| Suite with coverage, scenario commands, locked acceptance tests (digest unchanged), mutation score, a fix's regression proof | `temper check run` (`scripts/check_run.py:678-750`); at Review as `check ahead` before the recheck (`scripts/flow.py:1375-1378`), adopted at Check when the digest matches (`scripts/check_run.py:805-829`) | yes |
| Scope: every changed file is declared, a test, or allowed | commit gate (`scripts/temper:4145-4190`) | yes; the mod's window rule is wider (gap h) |
| Review's own row | retake the snapshot after the repair commit, so anything written after the recheck starts still fails | yes (`:4615-4620`) |

Check's ledger can be kept across a rerun: `tests pass` reads the latest run per claim (`scripts/runs.py:48-56`),
coverage and mutation the last value (`scripts/temper:3904, 3919`), `acceptance evidence` the latest row per scenario
[ran: X7]. One row is loose: `scenarios traced to tests` counts a scenario that ever passed
(`scripts/temper:1966-1978`); X7 showed `2/2 covered` beside a newer failure, with `acceptance evidence` failing the
gate. Make that row read the latest row too.

### When a new failing test is required

Today: always, by accident of the wipe, whatever the finding [reader: flow-loops E12; code
`scripts/temper:1876-1896, 3633-3645`]. That is wrong in both directions: a naming finding has no test to write, and
with the ledger kept the row would ask for nothing.

Rule for a repair:

| Case | RED required? | Proof |
|---|---|---|
| A Review finding the reviewer marked as a behavior defect (new field `proof: test` on the finding row, set by the reviewer, not the fixer) | **Yes.** The CLI runs the new test before the code change and it must fail on an assertion (the task gate's rule, `scripts/task_ops.py:176-192`), then pass after | a RED and a GREEN row tagged with the repair number and the finding id |
| A Review finding marked `proof: none` (name, structure, dead code, a comment) | No | the recheck confirms it; the suite stays green |
| Check: a red suite, a failing scenario, a failing acceptance test | No new one: the CLI's failed row **is** the RED | the same command green in `check run` on the new tree |
| Check: coverage shortfall, surviving mutants | No. The repair is tests for code that already works; they pass at once, and the brief's "RED must really fail" (`agents/build.md:97-98`) cannot be met honestly | the measured value on the new tree |

The fixer may not change `proof: test` to `none`; it can contest a finding (`scripts/findings.py:124-132`), which
keeps it open for the person.

### What must not get weaker

- Only the CLI writes `resolved`, and only for a finding the recheck confirmed. **Today any caller can do it with
  any text**: `temper evidence resolve --stage review --id 1 --fixed-by 'no such commit'` turned a failed Review gate
  to PASS and the question to "Continue to Check (Recommended)", with no file changed [ran: X1;
  `scripts/temper:1617-1663`]. Close this in the same patch: the CLI checks that `--fixed-by` is a commit reachable
  from HEAD and not from the reviewed HEAD, and the mod treats the call as the CLI's own (`rules.ts:489`).
- The fixer never accepts, overrides or skips (as `agents/build.md:110-113` already says).
- Locked acceptance tests stay locked (`scripts/flow.py:1263-1269`).

---

## 4. The recheck

| | Full Review today | Recheck |
|---|---|---|
| Input | every file changed since `base_sha`, each read whole (`agents/review.md:15-18`); `reference/review.md` (17 KB) | the diff from the reviewed HEAD to the repair commit, written by the CLI into the spec folder; the findings the repair answers (id, severity, claim, detail, the fixer's note); the findings still open; the CLI's results on the new tree |
| Model | `sonnet`, effort `high` (`agents/review.md:4-5`) | `sonnet`, effort `medium`. Whether Haiku holds: not determined, never measured |
| Method | all lenses, intent validation, deep doubt | three questions: is each finding fixed; did the changed lines add a defect; was a test weakened or removed. No other lens |
| Output | every finding recorded again | one row per finding id (`recheck #N: fixed` exit 0, or `not fixed` exit 1), new findings only on changed lines, one completion row with the count of ids checked |
| Brief | `agents/review.md` | a `Re-check:` section in the same brief, as `agents/plan-review.md:49` does for the plan, that skips the reference page. No new agent (the manifest and the draft's "no new agent" rule) |

Precedent: the plan review's recheck round (`scripts/flow.py:1294-1302`, `scripts/fresh_review.py:165-190`): a
launch mark (row count and digests), the earlier findings, the changed blocks, and a completion count the CLI
compares (`agents/plan-review.md:80`).

Fall back to a full Review when the diff is large (more than about 300 changed lines or files outside the files the
findings name): the narrow reading is then not narrow.

**How a finding is marked resolved.** `temper repair close` reads the recheck rows written after the launch mark.
For each `fixed` row it writes `resolved {fixed_by: <the repair commit>, recheck: <row>, ts}`. `not fixed` leaves it
open. No model calls `evidence resolve`. The fixer is never the judge of its own fix: the judges are the CLI's
checks and a reader that did not write the change.

**What stops a repair that makes things worse.**

1. The CLI's checks on the new tree (section 3). A row that passed before the repair and fails after it marks the
   repair as worse.
2. The recheck's new blocking findings on changed lines.
3. One comparison in the CLI: fewer open blocking findings than before, and no check that passed now failing. If
   not: the CLI reverts its own repair commit (precedent: the revert commit of `group reopen`,
   `scripts/temper:2750`), runs `integrate` and `gate build` on the reverted tree (the Integration pass is reused by
   tree key, `scripts/run_env.py:121-180`), and asks the person, naming what broke.
4. A repair that changed nothing launches no recheck and asks (as `scripts/group_fix.py:79-86`).
5. The budget below.

---

## 5. The budget

- **One automatic repair per stage per run** (Review, Check), for open critical and high findings. That is decision
  5's "once".
- **One more on the person's click** ("Repair again"), then the option is gone. Two per stage, the value of
  `loops.max-per-type` (`scripts/loop_step.py:20-32`).
- Counted in `feedback-loops.json` by the same function as the steps back, so the flow and the CLI agree (the rule
  `scripts/loop_step.py:8-11` states).
- A repair after which the same finding or the same failed row is open is not recommended again (the rule of
  `same_failure`, `scripts/flow.py:756, 856`).
- When the budget is spent the question offers: Accept a finding, Override and continue, Loop back to Build (kept as
  the way out for a finding that needs a redesign), Save for later.

Worst case with this budget: 4 launches at Review and 4 at Check (a fix agent and a recheck each time). Today's
counted worst case for the same two stages is 4 fix passes and 4 whole Reviews, each with 4 or 5 dialogs
[reader: flow-loops 7.2].

Why one and not two: no measurement shows a second pass helping. The only data point is one run with 6 fix passes
and 3 Reviews at $5.43 against $2.96 and $3.32 for the same task [reader: review-check-commit 5.4].

---

## 6. A Check failure

The flow already sorts Check's failed rows (`scripts/flow.py:822-875`). Repair in place applies to some of them only.

| Failed row | Repair in place? | Fixer's input | Recheck |
|---|---|---|---|
| `tests pass` (a red suite), `scenarios traced to tests`, `acceptance evidence` | Yes, once, no question | the failed row with its whole kept output (the loop carries 600 characters, `scripts/loop_step.py:101-107`) | `check run` on the new tree. When a file that is not a test changed: the narrow recheck of the diff too (Review passed on the tree before it) |
| `coverage >= threshold`, a real shortfall | Yes, once | the uncovered changed lines | `check run` only. A diff of test files alone needs no model (the test pattern is at `scripts/temper:4174`) |
| `mutation score >= threshold` | Not automatically while the score is unstable (50%, 75%, 80% on one tree [reader: review-check-commit 3.6]); offered | the surviving mutants (`scripts/temper:3924-3926`) | `check run` only |
| `acceptance tests written before Build` | Only when the triage says the code is wrong (`scripts/flow.py:1465-1485`) | the triage reason; the tests stay locked | `check run`, and the narrow recheck |
| The same, triage says the test is wrong or cannot tell | No: the person (`rules.ts:485`) | | |
| SETUP fault, a missing measurement, a criterion confirmed by hand, a fix run's `regression proof` | No, as today (`scripts/flow.py:824-863`) | | |

Two points the draft does not make:

- With draft item 3d (the suite with coverage and the locked acceptance tests inside `integrate`), these failures
  are found at Build, where the fix pass already works in place. A Check failure after that comes from a change
  made after Build, which is a Review repair, or from an unstable measure. So do 3d before or with 3e; Check's
  repair is then a small case of the same command.
- The small change path at Check is broken on 9.8.5 by gap c of section 2. Replace its `check` step with
  `check run` whatever else is decided.

---

## 7. The patch, in order

1. **Hold in PR #115** (one line and its tests): `scripts/flow.py:780`, the tuple `("critical", "high", "medium")`
   becomes `("critical", "high")`; the same at `:1167` (the policy) and the text at `:1141`. Section 8 says why.
2. **Make room.** `scripts/temper` is 260,504 bytes, 1,640 under the cap [counted]. Move `_review_code`'s Python
   (`:3765-3809`) into a script first.
3. **The finding carries its text.** `temper evidence add` gets `--detail`, `--fix` and `--proof test|none`
   (`scripts/temper:1513-1532, 1563-1577`); `agents/review.md:35-39` records them. Today a finding is one line
   (`--claim '<file>:<line> <one-line finding>'`), the loop cuts it to 300 characters (`scripts/loop_step.py:115`) and
   the fix prompt to 200 (`scripts/flow.py:1258-1262`).
4. **`scripts/repair_ops.py`** and a thin `temper repair start|commit|close|revert`:
   - `start --stage review|check`: checks the stage, the verdict and the budget; counts the repair; records the
     reviewed HEAD, the tree digest (`scripts/check_run.py:757-772`), the finding ids and the ledger row count;
     opens the window (`adhoc_ops.open_window`).
   - `commit`: the CLI stages the declared files and tests and commits (as `scripts/group_fix.py:75-97`); nothing
     changed is recorded, not an error; closes the window, retakes the Review snapshot, runs `integrate` and
     `gate build`.
   - `close`: reads the recheck rows, writes `resolved`, compares before and after, reverts when worse.
5. **The commit gate**: a third carve out, `repair commit`, beside the checkpoint one (`scripts/temper:4072-4110`):
   a repair is open, the run is at Review or Check on its own branch, and every staged file is declared or a test.
6. **`evidence resolve`** checks its commit (section 3).
7. **`scripts/flow.py`**: `repair_opt` beside `back_opt` (`:588-593`); a new move `repair` in `MOVES` (`:58-59`);
   Review FAIL (`:792-808`), Review PASS (`:779-788`) and Check FAIL (`:874-875`) offer it; an `auto` action before
   `self.ask(stage)` (`:2468-2473`) takes the first repair in every mode; `repair_work` launches the Build agent
   with the findings in full (after calls: `usage add`, `repair commit`), then the recheck (before: `check ahead`;
   after: `repair close`, `gate review`); `policy_move` (`:1157-1180`) repairs before it loops; the small change's
   `check` step becomes `check run` (`:966-971`); the Check question at PASS shows the open findings (`:813-821`).
8. **Briefs**: `agents/build.md` gets "A repair in place" beside "A group fix" (`:27-35`); `agents/review.md` gets
   the three fields, the `Re-check:` section, and its stale default at `:27`.
9. **The mod**: `repair start` is person only unless it is the CLI's own action (`rules.ts:476-497`); a repair
   window applies the Build write rule (`:292-305`) instead of `ALLOW` (`:252`), which needs one more guard fact
   (`scripts/flow.py:2832`, `hooks/temper-mod/core/runview.ts:73, 219`, `hooks/temper-mod/adapter.ts:218`). The
   driver needs no change if the repair is `auto` and `work` actions (`driver.ts:401-435`); its after calls must
   exit 0 on a recorded outcome, because a failed after call is a hand back (`driver.ts:432`).

### Tests

- New selftest case file (`scripts/selftest/temper-cases-32.sh`; 31 exist): the automatic repair at a failed Review;
  the launch prompt holds the whole finding; `repair commit` with and without a change; the carve out passes only
  declared files; `integrate` reran; a `proof: test` finding stays open without a tagged RED and GREEN; `repair
  close` resolves only confirmed ids; a worse repair is reverted and asked; the budget (one automatic, one asked,
  then gone); the same finding open after a repair is not recommended again; each Check row of section 6; a spent
  budget still offers Loop back to Build; `evidence resolve` refuses a commit that does not exist.
- Change: `temper-cases-25.sh:46-48` (the Medium expectation), `temper-cases-28.sh:12-15, 20` (the policy),
  `temper-cases-8.sh:111, 172, 177`, `temper-cases-13.sh:126`, `temper-cases-15.sh:361, 521` (first label at a
  failed Review or Check), `temper-cases-1.sh:72-77`, `temper-cases-2.sh:734-735`, `temper-cases-5.sh:1074` and
  `case-helpers-5.sh:461` (they resolve with `abc`), the small change cases in `temper-cases-9.sh`, `-11.sh`, `-15.sh`.
- Regenerate `scripts/selftest/view-fixtures.ts` and `view-fixtures-2.ts` (`make-view-fixtures.sh`; the snaps
  `review-fail`, `check-fail`, `armed-review-fail`, `armed-check-fail`).
- e2e (`scripts/e2e/scenarios.ts`, both modes): one scenario "a high finding is repaired at Review", one "a red
  suite at Check is repaired"; `scripts/e2e/replay.ts:263` stops calling `evidence resolve` itself.
- Mod tests: `tests/mod/guard.test.ts:146, 285`, `dialog.test.ts:93, 106, 143, 149, 330`, `view.test.ts:95-98, 169-176`,
  `hardening.test.ts:463`, `review-exploits-3.test.ts:106`, `security-round2.test.ts:26`; new cases for the repair
  window's write rule and for `repair start` typed by an agent.

### Docs and decisions

A new decision record (0019): a finding is repaired in its stage; a verdict is of the tree it judged or of a tree
whose difference the CLI checked and a reader rechecked. It amends ADR 0009 (the second carve out) and states that
ADR 0012 point 3 (`docs/decisions/0012-…md:33-35`, "going back clears what is redone") still holds for a step back.
Then `docs/flow.md:52-53, 98-126, 176, 230-233`, `docs/trust.md`, `reference/review.md:242`,
`reference/check.md:150, 163`, `reference/orchestrator-patterns.md:147-150`, `commands/temper.md:161`, the
`.claude/CLAUDE.md` known mistakes line, `CHANGELOG.md`.

### Effort

**M to L: about 7 to 9 working days, 28 to 32 files.** Roughly: CLI and gate 2 days, flow 2, briefs and mod 1,
tests and fixtures 2 to 3, docs half a day; plus CI at 30 to 60 minutes a round.

---

## 8. Should PR #115's "Medium recommends Loop back to Build" be held?

**Yes, hold it until the repair exists.**

- It sends each Medium finding through the full loop: 2 launches, 4 dialogs, a second whole Review, Check again,
  $0.40 to $0.50 [reader: crosscheck section 5 row 3].
- The loop then asks for a failing test first. A Medium finding is often one with no behavior to test, so the Build
  gate cannot pass by the fix alone (`scripts/temper:3633-3645`).
- It causes the regression at that question: "More options" holds only "More options" and "Make a small change"
  [ran: X4]. With "Continue to Check" first again, the branch at `scripts/flow.py:925` applies as on main.
- How often Review raises a Medium finding at 9.8.5: not determined.
- Keep in 9.8.5: the counts in the question text (`scripts/flow.py:786`) and the High block. The High block is the
  larger rise in loops (on main a High finding recommended "Continue to Check"), but the person chose it as a
  correctness default and can accept or override; its rate is also not determined.

---

## 9. Corrections to the draft

1. **3e, "a fix agent with the whole finding".** No whole finding exists. `evidence add` has one `--claim` line
   and no field for a description or a suggestion (`scripts/temper:1513-1532`); `review-context.json` has none
   either [reader]. The reviewer must record more first (patch step 3).
2. **3e, "the CLI resolves it by the fixing commit".** Two faults. A commit at Review or Check on the run's branch
   is refused by the commit hook [ran: X5b], so a carve out is needed. And `evidence resolve` is today an unchecked
   call any agent may make, which passes the gate with no change [ran: X1]. Word it: "the CLI commits the repair;
   a finding is resolved by that commit only after the recheck confirmed it; `evidence resolve` checks its commit".
3. **3e, "Build's ledger is kept".** True and feasible [ran: X2, X3], but say what replaces the wipe: `integrate`,
   `gate build` and `check run` again on the new tree, and a tagged RED and GREEN only for a finding marked testable.
4. **3e treats Review and Check alike.** Check needs no model recheck for a repair of tests only, has rows that
   must never be repaired by rule (section 6), and after 3d most of its failures move to Build. Put 3d before 3e.
5. **Decision 5, "repaired once without asking".** Needs its exclusions: a contested or escalated finding, a fix
   that needs a file outside the plan, `no code changed at Review`, an unfinished Review, an acceptance test the
   triage does not blame on the code, a SETUP fault, a missing measurement, a manual criterion. It also changes
   who may cause a code write at Review, so it needs a decision record and the guard rule.
6. **Decision 5, "carried to the commit question".** The commit question shows no finding today
   (`scripts/flow.py:813-821`); that has to be built.
7. **Section 6, first open point** ("can the driver continue a finished agent ... decides 3e"). It does not decide
   3e. The fixer is a fresh Build agent as today, and the recheck must be a reader that did not write the fix.
8. **Diagnosis row D and the effect of 3e.** Launches do not drop: a repair is still a fix agent and a recheck. What
   drops is 4 dialogs to 0, the Build question, the second whole Review, and the forced failing test. Dollars saved:
   not determined (no document prices a fix pass alone).
9. **WP0, the Medium flip** is right but incomplete: the policy applies the same rule (`scripts/flow.py:1166-1169`)
   and says so in its text (`:1141`).
10. **WP0 is missing two items:** the `evidence resolve` hole (it is on main too), and the small change at Check
    that launches the Check agent whose rows no longer count (`scripts/flow.py:966-971`).
11. **3f's one budget** must count repairs; the number is one automatic and one asked per stage.
12. **Order.** 3e adds code to `scripts/temper`, which has 1,640 bytes free; the draft moves the CLI into a package
    only in WP7b. A small extraction has to come first.

---

## 10. Not determined

- Dollars and seconds of a fix pass alone, and so the saving of a repair over a loop.
- How often Review raises a High or a Medium finding at 9.8.5.
- Whether a Haiku recheck is as reliable as a Sonnet one.
- Whether a second repair pass ever helps.
- Whether the stale Check verdict after a small change at a passed Check happens in a real run (inferred from the
  code; I launched no agent).
- How the mod's guard treats a commit made by the CLI at Review with the in-agent commit hook of the guardrails
  pack (I tested the native hook only).
