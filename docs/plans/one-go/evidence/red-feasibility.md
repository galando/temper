# Red team review of plan draft v1: feasibility, effort and order

Reviewed: `scratchpad/plan-draft-v1.md`. Read with it: `understand/_crosscheck.md`, `understand/dev-efficiency.md`, the
ten verifier reports (`v-pr115.md` arrived last; M1 and section 6 were revised against it), and the three independent plans
(`alt-smallest.md`, `alt-person.md`, `alt-clean-slate.md`). The tree at `/home/user/temper` is `10e965a`; I read code
there and wrote nothing. No CLI, no test suite was run.

Marks: **[code]** I read it at the cited line of `10e965a`. **[counted]** I counted it with a command.
**[v-...]** a verifier report says it. **[est]** my estimate, with its basis.

## 0. Verdict

The mechanisms are real: every one I checked is in the code or in a verifier's clone. The plan is not yet honest
about effort or order. Summed at the verifiers' own sizes it is about 85 to 120 working days, not 56 to 80. Three
things block it as written: the unattended default promises a repair that is built two stages later; the two dialog
pass line fails on every Maven, Gradle and Rust project and on an unstable mutation score; and the effort table hides
that stages 1 and 2 are about twice their stated size. The order needs the nine moves of section 5.

## 1. Blockers

### B1. Decision 2 and item 2a depend on 4f, which ships two stages later

- **Draft:** decision 2: "It may repair a critical or high finding in place once per stage". Stage 2 makes the armed
  run the default. Repair in place is 4f, in stage 4.
- **Problem:** between stage 2 and stage 4 no repair in place exists. The draft does not say what the default run does
  with an open High finding in that time. The code today loops Review to Build by itself for any open finding at
  medium or above (`scripts/flow.py:1166-1169` [code]), each loop a fix pass and a whole second Review, $0.40 to $0.50.
  7 of 18 measured runs had two or more Reviews (crosscheck row 13). So in about 4 runs of 10 the new default either
  spends that silently or stops and asks, and the pass line "bench mean at most 4" depends on which.
- **Change to the plan text:**
  1. Add to 2a: "Until 4f ships, a finding at a `review.block-on` level takes the existing loop back to Build once per
     run as the CLI's own action, counted by 2h; a second one stops and asks. A finding below that level is listed in
     the commit question."
  2. Decision 2: replace "It may repair a critical or high finding in place once per stage" with "From stage 2: one
     counted loop back to Build for a blocking finding. From the release that carries 4f: one repair in place per
     stage instead."
  3. Move 4f (with the first half of 4d) to directly after stage 2 (section 7 below).

### B2. The stage 2 pass line "a clean scripted run: 2 dialogs" fails on three stacks and on a noisy measure

- **Draft:** stage 2 pass line; 4d ("A missing tool is information") and 4e (mutation) sit in stage 4.
- **Problem, each read in the code:**
  - Check has no coverage command for Rust, Maven or Gradle (`scripts/check_run.py:139-144` [v-checks-once-early]),
    so the coverage row fails with `recorded coverage 'none'` (`scripts/temper:3904-3913` [code]). The policy parks on
    exactly that text (`measurement_gap`, `scripts/flow.py:880-885`; `:1178-1179` [code]). Every default run on those
    stacks stops at Check with correct code: at least 3 dialogs, never 2.
  - The mutation row fails below 70 (`scripts/temper:3918-3927` [code]; the default is in the code, not the template).
    That is not a measurement gap, so the policy loops Check to Build by itself (`scripts/flow.py:1180` [code]). The
    score moved between 50%, 75% and 80% on one unchanged tree (crosscheck section 5 row 9). So the new default loops
    on noise: a fix pass, a Review and a Check for nothing.
- **Change to the plan text:** add to stage 2: "2i. Check does not fail correct code. A missing coverage tool passes
  its row with the hint, as the mutation row already does for `not measured` (`scripts/temper:3929-3930`). A mutation
  score below the threshold is information until 4e shows it stable. The policy never loops on either." Take the
  sentence "A missing tool is information" out of 4d. Add a Maven scenario and a no-coverage scenario to the stage 2
  floor. Size: about 1 day [est: two rows, one policy branch, cases 1, 8, 13, 15, 28].

### B3. The effort table is 30% to 100% low, and its unit is not stated

- **Draft:** section 0 table: 3-5, 6-9, 12-16, 10-14, 20-28, 5-8 days.
- **Problem:** see section 4. Where a verifier gave days, the draft's stage total is below the sum of its own items
  (stage 4: four of nine items already sum to 15 to 21 days [v-repair-in-place, v-failure-budget]). Where no verifier
  gave days (2a, 2c, 2e, 2g, 4b, 4c, 4d, all of stage 3) the draft gives no basis. The unit is also open: all 16
  commits of PR #115 (+4,085 lines, 58 files) carry one date, 08:41 to 21:25 [counted: `git log origin/main..HEAD`],
  and its 14 CI runs add up to about 546 minutes [dev-efficiency 1.2]. Writing code is not what binds this project:
  CI rounds, verification, the bench and the owner's decisions are. PR #115 is the proof: one day of work, 16 defects
  to fix before it can merge [v-pr115].
- **Change to the plan text:** replace the effort column with section 4's figures; state the unit ("one person's
  working days with CI at the round time of that stage"); add three columns per stage: CI rounds expected, bench
  dollars and hours, owner decisions needed first. Add one line under the table: "At the pace PR #115 was written,
  calendar time is set by CI, the bench and review, so 0a (the CI change) is first."

## 2. Major findings

| # | Draft item | Problem | Evidence | Exact change |
|---|---|---|---|---|
| M1 | Stage 0, merge list | The list is not the verifier's list, and the draft says the verifier wins. `v-pr115.md` has 16 must fix (pM1 to pM16) and 4 flips (pF1 to pF4); its follow ups are pU1 to pU29 | (a) **Missing from the draft:** pM10 (a SETUP fault at Check recommends the same repair without end, default path), pM14 (three new files that decide gate rows are not in the mod's guarded list, `rules.ts:108-122`; the draft's "run file list" bullet is pU19, another list), pM15 (a command over 300 s fails the plan gate as an environment fault, default path), pF4 (the preflight runs every task Test on the base, with no total limit). pM11 (the commit gate's own row has no "Check again") is a dead end of an armed run today; the draft leaves it to 2a. (b) **In the draft, not must fix there:** `evidence resolve` (not in its list; on main, usage text "commit or note", `origin/main:scripts/temper:1616` [code]); the mod's typed answer and its cap (pU22; on main: `origin/main:hooks/temper-mod/core/answers.ts:81`, and `context_check` has the same shape at `origin/main:scripts/flow.py:2096-2097` [code]); the fix branch (the PR touches no line of `driver.ts` [counted: `git diff --stat origin/main...HEAD -- hooks`]). 2g lists those three mod defects again. (c) **Worded differently:** pM8 is "the reader merges a repeated key", not "refuses"; pF2 is "the row passes with a note"; pM13 is "do not offer the environment agent in 9.8.5"; pM12 is "remove the exception"; pM1 is a dead end, not only a relaunch (the group branches are gone after the first PASS, `scripts/temper:3430`) | Replace the stage 0 bullets by v-pr115's table, with its fixes and its tests: pM1 to pM16, pF1, pF2, pF4; pF3 kept. Move `evidence resolve` to 4f and the three mod defects to 2g. Add v-pr115's two conditions: the policy path as one end to end scenario in CI, and one selftest for the reuse store. For pM9 state the choice: a new option and a new `task gate` flag (about 10 files [dev-efficiency 2.1], and bytes in `scripts/temper`), or ENV only on the runner's own exits 125 and 127 (no option; alt-smallest) |
| M2 | 1a, and the order of stages 0 and 1 | The cheap half of 1a is workflow text only and should land before the stage 0 fixes | `quality.yml` has no `concurrency:`, no path filter, a serial unit job and one serial e2e job with a 60 minute limit [code]. PR #115: 4 of 14 runs green, 4 lost at 60 minutes [dev-efficiency 1.2]. alt-clean-slate also puts CI before the PR | New "Stage 0a (0.5 to 1 day, its own pull request to main): cancel superseded runs, one e2e job per mode, the unit job as a matrix over the parallel runner's groups, a time limit per e2e scenario." Stage 0 becomes 0b |
| M3 | 1b "split `view-fixtures.ts`" | A split is not needed and room is needed in stage 0 already | The file is written with `json.dumps(views, indent=1)` (`scripts/selftest/make-view-fixtures.sh:328` [code]). Printed one view per line it is 186,745 bytes, not 259,060: 72 KB free from one changed line [counted, in memory only]. Stage 0's flip changes fixture views and the file has 3,084 bytes left | 1b: replace "split `view-fixtures.ts`" with "print the fixtures one view per line (72 KB free)" and move it to 0a. Not checked: that `tsc` and the mod tests accept the long lines |
| M4 | 1b "at least 40 KB free" | A 15% extraction of the bash CLI before any user gain; stages 0 to 2 need a few KB | 2a removes a line, 2d changes one string, 2h is one line per call site with the code in `loop_step.py` [v-auto-advance 6, v-one-approval 2, v-failure-budget 6.1]. Decision 4 decides whether the cap exists at all | 1b: "Ask decision 4 first. If the directory stays: each stage frees what it adds plus 8 KB before it starts, beginning with `_review_code` (`scripts/temper:3765-3809`). Rule: `scripts/temper` only shrinks." Also add: "split `CHANGELOG.md` by major version" (15,188 bytes left, 5 to 10 KB a release [dev-efficiency 1.5]: it hits the cap during stage 2) |
| M5 | 1f | Sized as part of 6 to 9 days; alone it is 3 to 5. "The tests select by id" is 149 selftest lines and 126 mod test lines of pure churn | [dev-efficiency 2.1, 5: "M"]; 642 option entries in the fixtures [v-mod-driver 4.2]; I count 89 selftest lines and 69 mod test lines with "Recommended" alone [counted] | 1f: "Protocol and consumers now (flow.py, go.py `slim()`, runview.ts, driver.ts, the policy, the e2e person). Tests move to ids only when their question changes. `replay.ts` keeps the label rule, because it also drives 9.8.4." |
| M6 | 1g | Redundant with later items, and it hides a test rewrite | `autonomy.budget.*` is replaced by 2h; the `autonomy.enabled` text is rewritten by 2a's documents; `--exit` appears on 119 lines of 11 case files (60 in case 1, 26 in case 2, 17 in case 9) [counted] | Delete 1g. Add to 1e: "a selftest that every template key is read by code, with a list of the keys known dead today." Move the claimed runs conversion to 5b |
| M7 | 1d and section 7 | "Nothing records how often today; 1d will" is hollow for 2d: 2d ships one stage after 1d, and a record is local to each user | [draft section 7; `scripts/temper:1448` code] | Move 1d into the 9.8.5 release (stage 0b) and have it count a change typed, or a loop back, at the Intent question. Section 7: "1d will show it on the owner's own runs only; 2d ships with its guard conditions, not on that data." |
| M8 | 1e | Set from today's fixtures, the floor is 7 where a person meets 8, and 2b's gain cannot be seen | The fixtures write `reviewed: auto`, which no Plan agent is told to write (`scripts/e2e/project.ts:4`; crosscheck row 2) | 1e: "First make the fixtures write `reviewed: pending` and add a `default-run` scenario. Set the floor on merged 9.8.5, as an exact compare with a separate ceiling [v-targets-scorecard 2.3]. Count dialogs, launches by type, loop backs, hand backs, and suite and scenario test runs (a counter file the fixture's test command appends to)." |
| M9 | Stage 1 pass line "CI under 12 minutes" | No margin | e2e is 30:27 for three modes in series, so about 10 minutes a mode before setup; case file 5 alone did not finish in 520 s on a shared machine; the same unit job took 24.7 to 33.1 minutes on one day [dev-efficiency 1.1, 1.2] | "Median under 12 minutes and no run over 20; e2e in two shards per mode; case file 5 split." |
| M10 | 2g | One line hides a rewrite: "The hand back causes become a closed list of named kinds, each one step" | 14 causes at 31 `handback(` sites; it needs new CLI subcommands for three raw git calls, an agent each for the small change and the depth review (against 1e's agent cap), and the page's "stop after one step"; no mechanism returns a run to the driver today [v-mod-driver sections 2, 3] | Split. "2g-1 (1 day, first in stage 2): `group gate` and `integrate` print one verdict marker; `go.py:108-109` and `driver.ts:261, 432` read it." "2g-2 (4 to 6 days [est], second release of stage 2, after 1f): the named kinds." Without 2g-1, 2a moves every failed group check into the main session's model [v-auto-advance section 3] |
| M11 | 2h | It must land before 2a, and a refusal must not be an exit 1 | Under an armed run a limit that only moves the recommendation is the real bound [v-failure-budget 1.3]; a `BLOCKED` call is an `error` in `go.py:108-114` [code] and so a hand back | 2h: "Before 2a. The flow reads the budget and offers no call the budget would refuse. An existing `loops.max-per-type` or `fix.max-loops` is read as the new budget's value." |
| M12 | 2a "Prototyped in a clone on eight states" | True of 6 of the 11 patch items | Items 3, 8, 9, 10, 11 are "not prototyped" [v-auto-advance section 6]: arming when Design follows, the severity list, the failed `integrate`, the commit question's new options | 2a: add "the Design variant, the failed `integrate` path and the commit question's options are not prototyped". See M16 for the cheapest way to drop the Design variant |
| M13 | 2c | No verifier tested it, and its stated reason is wrong | 2d's rule already requires intent.md to exist [v-one-approval section 3 table], so 2d does not need 2c. TRIVIAL today is a word the agent returns and the page branches on (`agents/intent.md:17-20`, `commands/temper.md:176-179` [code]); a CLI verdict needs a new call, a state mark, a flow action, and the driver's and the guard's handling (`rules.ts:35-50, 463-464`) | 2c: delete "(it must land before 2d ...)". Add its mechanism and "1.5 to 2.5 days [est], second release of stage 2". |
| M14 | 2e, with 2d | 2e is two medium items, and 2d must not ship without the first | Today's panel shows counts, not the criteria (`scripts/panel.py:91-137` [v-one-approval 5]); launches and models are computed only inside Build (`flow.py:1558-1610`); the commit question shows no finding [v-repair-in-place correction 6]; the driver cuts a panel to one row a section (`driver.ts:84-88`) | Split. "2e-1 (with 2d, same release): `temper panel plan` lists the criteria one line each, the files by group and the tests; the plain session shows it. 2e-2 (second release): the mod's drawing above the dialog, launches and models, the commit numbers." |
| M15 | 2b | Step 1 alone may remove little | The template's own example holds one `ignore` and one `gap` line (`templates/plan.md:5-7`); how often real plans hold one is not determined [v-one-approval section 4] | Stage 2 pass line: "2 dialogs with a clean map; still 2 with a flagged map once the approval carries the lines (2b step 2)." |
| M16 | 3c | Its cheap half belongs before 2a | With Design in the run, arming is a second, unprototyped variant (`flow.py:681-689, 726-730` [code]); `has_design()` is one function (`flow.py:251-266`); with Design off by default the stage 0 Design hold matters only for a run that asked for Design | Move to stage 2, before 2a: "Design runs only when asked (`has_design()`); its concerns are Blocking questions written by Plan." The hold at the plan gate stays in stage 3 |
| M17 | 3f | Depends on 3e's result, changes a guard write table (`rules.ts:255-262`), and buys "under 30 s and a few cents" beyond 2d | [v-lean-front section 5] | "3f only if 3e puts both agents on one model and a bench arm shows the gain; otherwise stage 6." The stage 3 pass line must not assume it |
| M18 | 3d, 3h | 3d is the mitigation for 2d's known cost and adds an agent type; half of 3h has no measured reason | A correction after 2d costs a full Plan pass, $0.75 to $1.13 [v-one-approval section 3]; the brief for three more agents adds input tokens with no evidence of a gain | Put 3d first in stage 3 and raise the agent cap by one in the same commit. 3h: keep "the CLI draws the remaining panels"; move "the brief goes to Intent, the acceptance writer and the reviewer" to stage 6 |
| M19 | Section 2 table against section 0 table | Two different pass lines for a clear feature (2 and 3 times in section 2; 2.5 and 4 in section 0), and the verifier's is a third | [v-targets-scorecard verdict]: time at most 3 is "not reachable as an expected value"; honest lines are 2 and 4.5 with a Sonnet builder, or 1.5 and 5.5 with Haiku | One table. Use the verifier's lines. Stage 3's pass line gets a structural half that work can guarantee (launches for a clear request, no Design launch, Plan output tokens) and a measured half with the rule fixed before the A/B |
| M20 | 4a | Benefit not measured, and one fact is wrong | No retry in 18 runs was caused by the model [v-build-one-tree section 8]. "Two attempts stay as the bound": the bound is three (`scripts/temper:3161` `>= 3`; the stronger model from attempt 3, `scripts/tasks_md.py:210` [code]) | Move 4a to stage 6 with the entry condition "1d's records show task gate failures a repair would have saved". Correct the sentence to "three attempts" |
| M21 | 4c | It hides a dependency and a design decision | Its last sentence needs a failure class, which is 4g. "One owner of the suite command" changes the plan contract and meets the Maven rows: the plan gate forces `mvn verify` with JaCoCo (`scripts/gate_rows.py:149-155`) while `detect` gives `mvn -q test` (`scripts/check_run.py:141`) [v-checks-once-early 3, 4]. The saving on a clean run is one or two suite runs, about 0 s on the bench | Split 4c: "4c-1, the digest (a defect today: `check ahead` discards its own run)." "4c-2, one owner of the suite command: only after one real slow project is measured (bench round 5 of v-targets-scorecard, its M5)." Move the last sentence to 4g |
| M22 | 4d | Two parts with different dependencies | Coverage by changed lines is ready for 1 stack kind of 9; "total against the base" needs 4b's baseline in its coverage form [v-checks-once-early section 5] | "4d-1: `integrate` runs the suite and the locked acceptance tests; the acceptance failure path moves to the Build gate. 4d-2, after 4b: the coverage rule." |
| M23 | 4h | The author of an amendment is missing | The CLI can write only the mechanical case; three of five cases need a model, and that is 3d's agent; four stored values move, not two [v-failure-budget 4.2, 4.3] | 4h: "By the CLI for a blocked task whose file an earlier task declares and for a missing Validate. By the revise agent of 3d for the rest. It moves `plan_hash` twice, `approved_files` and `approved-tasks.json`." |
| M24 | 4i | Three rows for faults no measured run has shown, against the plan's own section 5 | "No report shows one in a measured run" [v-failure-budget 5.3]; each row counts against 1e's cap | 4i: keep "a group with no Validate" and let `plan patch` insert the line (0.5 day). Move the other rows to stage 6 |
| M25 | Every stage | Release costs are in no stage | A 70 box manual list gates every merge (`docs/mods-testing.md:8` [dev-efficiency 2.4]); 9 or more decision records change (0009, 0011, 0012, 0013, 0016, 0017, 0018 and two or three new) [v-auto-advance 8, v-repair-in-place, v-lean-front 9] | Add to stage 1: "the manual list becomes the driver mode e2e plus a smoke of ten boxes." Add to each stage its decision records by number |

## 3. Minor findings

1. **Section 2, "held by the e2e equality check (scripts/e2e/run.ts:27-31)".** That check compares the plain trace
   with the `mod` trace only; the driver's trace is not compared [code]. Add the driver's dialogs and launches to the
   floor, equal to plain's.
2. **1c, "hand backs".** The logs hold whether a run left the driver and what it cost, not how many hand backs or why
   [v-targets-scorecard 1.2]. That needs a line the mod writes, and the mod has no file write among its 20 reviewed
   calls. Word 1c as "handed back: yes or no, main session turns and dollars".
3. **2a, the second option.** After 2a the scripted person arms every run, so the "Ask me at every stage" path has no
   end to end run unless a second person exists. See section 8.
4. **2d and 5a.** The `draft` word of 5a must stop after Intent; 2d's rule moves on to Plan. Add "the run was started
   as a draft" to 2d's list of conditions when 5a lands.
5. **Stage 0 pass line, "a default run asks no more than 9.8.4".** Name the proof: `scripts/e2e/ab-replay.sh` and the
   floor of 1e. Neither is in CI today [code: `quality.yml` runs `run.ts all` only].
6. **3e, "about 4 hours and $75".** The verifier's bench rounds 2 and 3 (its M2 and M3) with the rerun after the contract cut are $69 to
   $93 and 5 to 7 hours; the acceptance writer arm of 3g is $25 more [v-targets-scorecard section 4].
7. **5c, 5d.** No verifier tested "the six stack packs nothing loads" or the dormant list. Each removal needs a grep
   that shows no reader, in the commit.

## 4. Effort, added up

Unit: one person's working days, CI waits included. S = 1 to 2, M = 3 to 4, as the verifiers use them
(v-build-one-tree section 8; v-repair-in-place "M to L: 7 to 9"). A figure with a source is the verifier's; **[est]**
is mine from the verifier's own list of patch steps, test files and documents.

| Stage | Draft | Items and their sizes | Sum as drafted | After the changes of this review |
|---|---|---|---|---|
| 0 | 3 to 5 | v-pr115: 16 fixes of under 20 lines each, 4 flips, about 20 selftest cases, 1 or 2 e2e scenarios, one fixture regeneration. It gives no days and expects 1 or 2 CI runs; this PR had 4 green of 14. The draft's own list adds `evidence resolve` across 8 test files | 5 to 8 [est] | 0a 0.5 to 1; 0b 4 to 6 (v-pr115's list, with 1d): **5 to 7** |
| 1 | 6 to 9 | 1a 2 to 3 (S for the workflow [dev-efficiency 5], plus splitting case files 5 and 6); 1b 2 to 4 [est]; 1c 1 to 2 [v-targets-scorecard 1.3] plus bench round 1 of v-targets-scorecard ($40 to $50, 3 to 4 hours); 1d 0.5 to 1; 1e 1 to 2 [v-targets-scorecard M0]; 1f 3 to 5 [dev-efficiency: M]; 1g 1.5 to 3 [est] | 11 to 20 | 1g gone, 1b small, tests by id later: **8 to 12** |
| 2 | 12 to 16 | 2a 5 to 7 [est: 11 patch steps, about 30 files, the size of 4f less its new commands]; 2b 3 to 4 [v-one-approval: S, then S to M]; 2c 1.5 to 2.5 [est]; 2d 3 to 4 [v-one-approval: M]; 2e 4 to 6 [v-one-approval: M, plus the commit numbers]; 2f 1 to 2 [est]; 2g 5 to 8 [est]; 2h 2 [v-failure-budget S2] | 24 to 35 | Two releases: 2A **14 to 18** (2g-1 1, 2h 2, Design off 1, 2b step 1 1, 2a 5 to 7, 2d 3 to 4, 2e-1 1.5 to 2, 2i 1), 2B **11 to 16** |
| 3 | 10 to 14 | 3a 1.5 to 2; 3b 2 to 3; 3c 3 to 4; 3d 2 to 3; 3e 1 to 1.5 and the bench; 3f 3 to 4; 3g 1 to 3; 3h 2 to 3 (all [est]; v-lean-front gives no days) | 15 to 23 | 3c's first half moved to 2A, 3f gated, half of 3h out: **11 to 16**, plus about $100 to $120 of bench |
| 4 | 20 to 28 | 4f 7 to 9 [v-repair-in-place]; 4g 3 to 4, 4h 4 to 6, 4i 0.5 to 1, plan patch repairs 0.75 [v-failure-budget 6]; 4a 1 to 3 [v-build-one-tree: 5b is 3]; 4b 4 to 5, 4c 4 to 5, 4d 5 to 7, 4e 0.5 to 2 [est: v-checks-once-early lists 8 patch steps and about 14 case files and gives no days] | 30 to 43 | Two releases: 4-I **13 to 17**, 4-II **16 to 22** (4a and most of 4i out) |
| 5 | 5 to 8 | 5a 2 to 3; 5b 2 to 3 (15 keys are read at 2 to 4 sites each [dev-efficiency 3]); 5c 1; 5d 1 to 2; 5e 2 to 3 [est] | 8 to 12 | With the claimed runs conversion: **8 to 12** |
| Total | 56 to 80 | | 93 to 141 | **86 to 120** |

Where the draft is too low: stage 2 (about half), stage 1 (about half), stage 4 (about two thirds), stage 3 (about
two thirds). Where it is too high: nowhere. I found no stage whose items sum below the draft's figure. For
scale, alt-clean-slate sizes the same two mechanisms of stage 4 at 3 weeks and 3 to 4 weeks (30 to 35 days) and the
whole road at 20 to 23 weeks.

## 5. The critical path and the order changes

What gates what, from the code and the reports:

```
0a CI workflow + compact fixtures
  -> 0b PR #115 fixed (with 1d)            -> 9.8.5
  -> 1a rest, 1e floor (faithful fixtures), 1c scorecard and bench round 1, 1f ids, 1b small
  -> 2A: 2g-1 verdicts -> 2h counter -> Design off by default -> 2b step 1 -> 2a -> 2d with 2e-1 -> 2i
  -> 4-I: 4d-1 (checks at the end of Build) -> 4f (repair in place)
  -> 2B and stage 3 (3a, 3b can ride beside 2A; 3d first; 3e after 3a to 3c)
  -> bench round 5 (one real slow project)
  -> 4-II: 4c-1, 4b, 4d-2, 4g, 4h
  -> 5, then 6
```

Moves, each with its reason:

1. **The workflow half of 1a before stage 0.** It costs half a day and cuts every later round from 30 to 60 minutes
   to about 10 (M2).
2. **Compact fixtures in 0a.** One line, 72 KB (M3).
3. **1d into 9.8.5.** A count needs time to accumulate (M7).
4. **Inside stage 2: verdicts, then the counter, then the default flip.** The flip is safe only on top of both (M10,
   M11).
5. **"Design runs only when asked" before 2a.** It removes an unprototyped variant of 2a (M16).
6. **"Check does not fail correct code" into stage 2.** Without it the pass line fails on three stacks (B2).
7. **4d-1 and 4f directly after 2A, before stage 3.** Decision 2 promises it (B1).
8. **4i's one useful row and the `plan patch` repairs (1.25 days) into stage 2 or 4-I.** Cheap, and they close a way
   into a loop to Plan.
9. **3a and 3b beside stage 2.** They are briefs and six small script edits in files stage 2 does not touch
   [v-lean-front section 7], and the A/B of 3e must run on the cut contract.

Items that hide a rewrite behind one line: 2g (M10), 2e (M14), 4c "one owner of the suite command" (M21), 4h (M23),
1b "40 KB" (M4), 1f "the tests select by id" (M5), 1g "convert the 116 simulated runs" (M6).

## 6. The split of stage 0 against stages 1 and 2

Ids of `v-pr115.md` are written pM1 to pM16 (must fix), pF1 to pF4 (flips) and pU1 to pU29 (follow ups).

The draft fixes on the PR branch. `v-pr115.md` weighed the three ways (fix on the branch, split the PR, leave it open)
and recommends the first: the commits do not split along features (10 of 16 touch `flow.py`), and the four parts the
later stages build on (the runner, the setup block, the policy, the reuse store) are all in this PR. The three
independent plans trim the PR instead and size it at 2 to 3 days. The two meet: the verifier's own cheap cut is
"switch off, not split" (no environment agent; flip pF1, pF2, pF4).

So the split is right in kind and wrong in content (M1). The rule to write into the plan: **stage 0 holds the
verifier's must fix list and its flips, and nothing else. A defect that is on main too, or that a later stage
rewrites, goes to that stage.**

| Item | In the draft's stage 0? | A regression of the PR? | Where it belongs |
|---|---|---|---|
| pM3, pM4, pM6: the policy never launches the fix agent, plans again by itself, loops for a manual criterion | yes | Only with the policy on (`flow.py:299-301` [code]) | Stage 0b, one commit of three guarded lines. 2a builds on these lines, and they were run in two clones [v-auto-advance, v-pr115] |
| pM5: a step back to Plan leaves the run armed | yes | With the policy; and in any armed run through "Run Plan again" at `flow.py:1621-1633`, which asks without a park [code] | Stage 0b: the one line in `_go_back`. Only the reset inside the renamed option waits for 2a |
| pM1: a failed `integrate` after a fix pass | yes, as a relaunch only | Yes, default path, and a dead end | Stage 0b with v-pr115's fix (stay on the rerun path, return 0, `gate build` judges). Do not remove the rerun: 4f needs it [v-repair-in-place section 2]. This is the one fix to test end to end |
| pM2 and pF1: the lost Review options; the Medium flip | yes, as two bullets | Yes | Stage 0b, one change: the flip at `flow.py:780` and `:1167`, and the condition at `:925` |
| pF2: the Design hold | yes, with another fix | Yes, when Design runs | Stage 0b: the row passes with a note. "Fails only for another answer" is built once, in 3c, at the plan gate |
| pM8: the template's empty keys | yes, as "refuse" | Yes | Stage 0b: comment the two keys; merge a repeated key (`scripts/config_yaml.py:28-29`) |
| pM9, pM16: ENV with no way out; a stored preflight fault | yes | Yes, both dead ends | Stage 0b. For pM9 see the choice in M1 |
| pM10, pM15, pF4 | **no** | Yes, default path | Stage 0b |
| pM11: the commit gate's own row | in 2a | Yes, for an armed run | Stage 0b: a dead end should not wait for the default flip |
| pM12, pM13: the backup push; a setup block without the person's answer | yes | Yes, both new | Stage 0b: remove the push exception; do not offer the environment agent in 9.8.5 |
| pM14: three files outside the mod's guarded list | **no** (the draft has pU19) | Yes | Stage 0b |
| pM7 and the small change at Check | yes | Yes | Stage 0b |
| `evidence resolve` | yes | No: on main, and not in v-pr115's list | 4f |
| The mod's typed answer, its cap, the fix branch | yes | No: on main; pU22 is a follow up | 2g and 2b |

Two things v-pr115 asks for that the draft's stage 0 lacks and stage 2 needs: the policy path as an end to end
scenario in CI (no scenario runs what the PR adds: pU21), and one selftest for the reuse store (it has none: pU4).

One thing stage 0 needs that neither names: room. pM1, pM5 and an option for pM9 all land in `scripts/temper`, which
has 1,640 bytes free; the fixture file has 3,084. Hence stage 0a (findings M2 and M3).

## 7. Stage 4 in two releases

| | 4-I: Review and Check do not send the run back | 4-II: faults before Build, each check once, one record |
|---|---|---|
| Items | 4d-1 (suite and locked acceptance tests at `integrate`; the acceptance failure path at the Build gate); 4f (repair in place, with the `evidence resolve` check and the commit hook carve out); the small change at Check uses `check run` | 4c-1 (the digest); 4b (the baseline, three results, the red base question); 4d-2 (the coverage rule); 4g (the failure record); 4h (the amendment); 4c-2 only after round M5 |
| Stands alone? | Yes. It needs 2h's counter and `integrate`'s rerun, both present after 2A | Yes. It needs nothing of 4-I; 4h's judgment cases need 3d |
| Pass line | A High finding at Review is repaired with no dialog and two launches; a failing acceptance test is repaired inside Build and Review launches once; runs with two or more Reviews fall from 7 of 18 to at most 2 of 18 on the same tasks | An environment fault is asked before Plan is launched; a scripted two group run runs the suite 3 times; a step back keeps the failure records; a blocked task whose file an earlier task declares costs no Plan launch |
| Effort | 13 to 17 days | 16 to 22 days |
| Evidence for the gain | Measured: 7 of 18 runs, $0.40 to $0.50 and 4 dialogs a round; three runs at $23 to $38 on acceptance tests | Two real runs, no bench task; the saving on the bench is about 0 s [v-build-one-tree 8, v-checks-once-early 7] |

**4-I goes first.** Its gain is measured and frequent, decision 2 depends on it, and 4f at Check is "a small case"
only once 4d-1 has moved the acceptance tests to Build [v-repair-in-place section 6]. 4-II waits for one measured run
on a real slow project, which also decides 4c-2 and 6d. Inside 4-II the order is 4c-1, 4b, 4d-2, 4g, 4h: the baseline
stores its pass under the new digest, the coverage rule reads the baseline, and the amendment reads the record.

## 8. Stage 3 before stage 4?

**For the draft's order.** Every run pays for the front: Plan is $0.75 to $1.13 of a $1.93 to $2.50 run and about a
quarter of its time; stage 2 saves no dollars with the mod and no machine seconds on the bench. Stage 3 is mostly
briefs, low risk, and its A/B needs bench hours that can pass while other work goes on. 3d is needed by 4h.

**Against it.** The owner's words are "no back and forth between phases". Stage 2 makes the unattended run the
default, and in 7 of 18 measured runs that run meets a second Review. Decision 2 promises a repair that only 4f
builds. The largest lever of stage 3 is an experiment (the model), not engineering, and its result may be "keep
Opus"; the contract cut alone is $0.14 a pass [v-lean-front 1.6]. On a real project a loop costs minutes where the
front costs seconds (a Build task took 25 minutes on the Java run).

**Decision: neither as drafted.** 4-I goes before stage 3; stage 3 goes before 4-II. The cheap part of stage 3 (3a,
3b, then the A/B) runs beside stage 2 and 4-I. Two of the three independent plans put failure handling before the
deep front changes, and all three put the cheap Plan cut early.

## 9. What must be true of the tests and fixtures, stage by stage

| Stage | The scripted person | Fixtures | The floor | Also |
|---|---|---|---|---|
| 0b | Takes the option marked "(Recommended)", as today (`scripts/e2e/scenarios.ts:119-123` [code]) | Compact first, then regenerate | Not yet set; `ab-replay.sh` proves "no more than 9.8.4" | Each defect has a selftest case that fails at `10e965a` [v-pr115 section 2 names each]; one new end to end scenario for the policy path; one selftest for the reuse store |
| 1 | Reads `recommended: true` once 1f lands; `replay.ts` keeps the label rule | `reviewed: pending` in `project.ts`, `pyjokes.ts`, `replay.ts`; a `default-run` scenario | **Set here, on merged 9.8.5**: exact compare, a ceiling beside it; default run 8 dialogs and 6 launches | Case files found by glob: a file left out of the four hand lists is silently not run today [dev-efficiency 2.1 row 7]. The pairs 2 with 3 and 8 with 9 stay one shard |
| 2A | **Two persons.** The default takes the recommended option and now arms every run. A second, "stage by stage", picks that option by id and then the recommended one. `smallChange`, `prAndPipeline`, `threeGroups`, `saveAndResume`, `coveredAndManual`, `designRun`, the fresh review ones, `mavenRun` and the pyjokes ones run under the second [v-auto-advance section 7] | 18 mod test places pin the old label | Lowered in the same commit as each item: 8 to 4 (2a), to 3 (2b), to 2 (2d). A driver row: a failed group check, 0 hand backs | New scenarios: a failed group the fix agent repairs; a failed fix that stops; a manual criterion; a stop and the stage after it; Maven with no coverage command |
| 4-I | The recommended option at a failed Review is the repair | Snaps `review-fail`, `check-fail` and the armed ones | Adds: repairs, and dialogs per repair = 0 | Scenarios in plain and driver mode: a High finding repaired at Review; a failing acceptance test repaired in Build; a repair that made things worse is reverted and asked |
| 3 | Unchanged | A plan with no file tables and no `Traced to`; a simple tier folder with tasks.md only that records a deviation and reaches the commit | Launches for a clear request; the `design` scenario only on an explicit ask | The scorecard splits output tokens by agent before any pass line uses them; the A/B rule is written down before the runs |
| 4-II | Unchanged | A project whose test command leaves `.coverage`; a suite run counter; a Node fixture with jest | Adds: suite runs and scenario test runs per scenario | A broken environment scenario asks before the Plan launch |
| 5 | Unchanged | | Config keys, commands and briefs fall | A selftest that an old config still reads |

When to set the floor of 1e: after the fixtures are faithful and on the merged 9.8.5, not before stage 0 and not
from today's fixtures. From then on it only moves in the commit that moves the count.

## 10. The three independent plans against the draft

| | Draft v1 | alt-smallest | alt-person | alt-clean-slate |
|---|---|---|---|---|
| First | Fix PR #115, 3 to 5 days | Cut PR #115, M | Settle PR #115, 2 days | Instruments and a 10 minute CI, 3 to 4 days; then PR #115 trimmed, 2 to 3 days |
| Before any user gain | 6 to 9 days of foundations | Record and ceiling, S to M | Record and budget file, 2 days | The same step 0 |
| Dialogs | Stage 2, 12 to 16 days | One approval M; intent by rule S | 5 days, then the cards 4 days | 1.5 to 2 weeks, ids included |
| Then | Lean front, then no back and forth | Plan cut and A/B; checks once; one repair and a cap | **Repair, then the baseline, then Plan cost** | Plan cut, then faults early (3 weeks), repair in place (3 to 4 weeks), one builder, **the front agent last** |
| Total | 56 to 80 days and stage 6 | 17 to 20 days | 34 days | 20 to 23 weeks |

What the three agree on and the draft does not: (1) trim the PR, do not repair all of it; (2) the record and the
ceiling come second and cost about two days, with no 40 KB extraction and no dead knob work in front; (3) the cheap
Plan cut is early and the deep front change is late or left out; (4) two of three put repair before the front.
Where the draft is better than all three: it has verifier prototypes for 2a, 2b and 2d, and it keeps every gain in
the CLI for a user without the mod.

## 11. What to cut, or move to stage 6

| Item | Why | Where |
|---|---|---|
| 1g | Redundant with 2a and 2h; hides a rewrite of about 119 test lines | One selftest in 1e; the rest in 5b |
| 1b "40 KB" | No stage before 4-I needs it | As needed, after decision 4 |
| Stage 0: the three mod defects, `evidence resolve` | On main too; not in v-pr115's must fix list | 2g, 4f |
| 4a | No model caused retry in 18 runs | Stage 6, on 1d's records |
| 4i, three of four rows | Never seen in a measured run | Stage 6 |
| 4c-2 "one owner of the suite command" | One or two suite runs on a clean run; about 0 s on the bench; a contract change | After bench round 5 |
| 3f | Depends on 3e; touches a guard table; under 30 s | Stage 6 unless 3e and a bench arm say otherwise |
| 3h, the brief for three more agents | No measured gain | Stage 6 |
| 2g-2, 2c, 2f, 2e-2 | Not needed for 2 dialogs | The second release of stage 2 |

## 12. What I checked in the code myself, and what I did not determine

Checked at `10e965a`: the head and the byte counts (`scripts/temper` 260,504; `view-fixtures.ts` 259,060;
`flow.py` 205,631); the policy's rules at Review and Check (`flow.py:1144-1181`); `park` (`scripts/temper:4512-4537`);
the group fix guard (`flow.py:1754`); the `go.py` and driver verdict rules; the coverage and mutation rows
(`scripts/temper:3904-3930`); the task attempt bound; the TRIVIAL path; `quality.yml`; the e2e person and
`run.ts:27-31`; that the guard allows the calls of any action of the CLI (`hooks/temper-mod/adapter.ts:231`), which
is what 2d's `work` action leans on; the three mod defects against `origin/main`; the dates of the PR's commits.

Not determined: whether the compact fixtures pass `tsc` and the mod tests; the size of stage 0's fixes in bytes of
`scripts/temper`; days for anything marked [est]; how often a real plan's map holds a flagged line; whether
`PYTHONDONTWRITEBYTECODE=1` steadies the mutation score (alt-smallest cites a reader; I did not find it in a verifier
report, so B2 asks for "information only" instead). `v-pr115.md` arrived after my first pass. M1 and section 6 follow it. Where my first pass differed (I had pM5 as
not reachable once the policy never steps back) the verifier's reading and the code at `flow.py:1621-1633` won.
