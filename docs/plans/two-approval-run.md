# A run that asks twice: the plan for a fast, cheap Temper

**Status:** Proposed (for the owner to accept, change or reject)
**Date:** 2026-11-16
**Base:** the head of pull request #115 (`10e965a`, version 9.8.5, all 10 CI checks green). Every `file:line` below
is of that commit.
**After this proposal:** the owner chose to build it in one pass, as one pull request, and to release the result as
9.8.5. The brief for that build is `docs/plans/one-go/README.md`. Where this page says 9.8.5 it means the head of
pull request #115, which is the base of that build and was never released; users have 9.8.4.

## 1. The plan on one page

Today a Temper feature run costs 4.5 to 4.7 times what plain Claude Code costs, takes 7 to 10 times as long, and stops
to ask 8 times on a clean run and 13 times on average, though only two of those questions decide anything. That is
measured on small Python tasks; the one measured Java run was far worse.

This plan makes a run ask twice (approve what will be built, approve the commit), repairs a failure in the stage where
it happened, finds a fault at the earliest moment, and aims at about 2 times the cost and 4.5 times the time of plain
Claude Code. The two questions are certain: they were prototyped in the code. The dollars and minutes are a target
that one test of about $40 confirms or lowers in the first weeks.

It is eight releases. You can stop after any of them and keep what it gave. From the second release on, a check in CI
stops questions, agents, options and config lines from growing back.

### Today against after

| | Temper today | After the plan | How sure |
|---|---|---|---|
| Dialogs on a clean feature run | 8 (6 with one Build group); 13 on average in live runs | 2, plus 1 or 2 when the request leaves rules open | certain: prototyped |
| Dialogs on a clean bug run | 4 | 2 | by design |
| Dialogs to repair one Review finding | 4 | 0 | by design |
| Repeats of the same failed step | no bound (40 to 131 in four scripted runs) | 2 per failure, 6 per run, then one question | by design |
| Cost of a clear feature, against plain Claude Code | 4.5 to 4.7 times | at most 2 times | target; rests on the model test |
| Time of a clear feature | 6.7 to 9.8 times | at most 4.5 times | target; arithmetic on measured parts |
| A vague feature | the same as a clear one | at most 3 times the cost, 4.5 times the time | target |
| A bug | 1.25 to 1.35 times the cost, 1.85 to 2.9 times the time | at most 1.5 and 2.5 times | holds today on clean runs |
| Steps back to Plan from a fault that was knowable before Build | both failed real runs | none | target; proven on scripted broken projects |

Plain Claude Code on the same tasks: $0.43 to $0.49 and 88 to 99 s for a feature, $0.36 and 46 to 48 s for a bug
(`docs/evidence/bench-2026-11.md:380-383`). Temper will not match that time. A run with an approval, tests written
first and a review has a floor of about 3 times, and the plan does not promise less.

### What you give up

Between the approval and the commit you are no longer asked at each group, at Build, at Review and at Check. A passed
check moves on by itself. You keep three ways to look: "Ask me at every stage" at the approval, a setting that makes
that the default, and Esc, after which `/temper:temper` asks the question of the stage the run is at.

### The releases

| # | Release | You get | Working days |
|---|---|---|---|
| 0 | 9.8.5 without its regressions | PR #115 merged with 16 defects fixed and 4 defaults flipped | 5 to 7 |
| 1 | Measure, and stop failing correct work | CI in about 10 minutes; a scorecard; the "before" numbers and the model test; a first run that passes on correct code | 8 to 12 |
| 2 | Two approvals | one approval before code, one at the commit; one budget for repeats | 14 to 18 |
| 3 | The cards, and no hand back | each approval shows what it approves; a failure no longer hands the run to the main session; a bug run asks twice | 11 to 16 |
| 4 | Repair where it happened | a finding is fixed in its stage, with no dialog and no second full Review | 13 to 17 |
| 5 | A lean front | Plan writes half as much; Design becomes questions; the planner's model chosen by test | 11 to 16 |
| 6 | Faults found early | an environment check in the first seconds; each check once per tree; limits from the project's own times | 16 to 22 |
| 7 | A smaller surface | 2 listed commands, about 10 config lines, docs that match | 8 to 12 |

After release 2 you have the run you asked for, at today's cost. After release 5 you have the cost target. Section 7
gives each release its changes and its pass line.

### What it costs, and when it is done

About 86 to 120 working days of one person in total, CI waits included, and about $300 to $400 of benchmark runs.
Releases 0 to 2 are 27 to 37 of those days and about $100. The calendar may be much shorter: Claude sessions made the
16 commits of PR #115 in one day. What binds is CI (30 to 60 minutes a round until release 1) and your review, so
your own time is the decisions of section 2, a look at each release, and the manual release list.

The plan is done after release 7. What comes after (section 7, "Later") is a list of separate proposals, each of which
needs its own measured reason. If a release misses its pass line twice, stop and plan that release again; do not start
the next.

### What you decide now

The eight decisions of section 2. I recommend approving releases 0 to 2 now, and the rest when the scorecard of
release 1 has its numbers.

## 2. What you decide

1. **The promise and the default.** The promise becomes: "You approve the intent and the plan in one question before
   any code is written, and you approve the commit." After the approval a passed check moves on by itself. "Ask me at
   every stage" stays as the second option; one key (`run.default: to-commit | ask | never-unattended`) makes it the
   default or forbids unattended runs, and an existing `autonomy.enabled: false` means `ask`. Recommended: yes.
2. **What a rule may do after the approval.** A closed list. It may: move past a passed check, and make one counted
   repair per failed check. Until release 4 that repair is one loop back to Build; from release 4 it is a fix in the
   stage, committed by the CLI on the run's branch, with the checks run again. It may never: plan again, change a
   gate's command, the intent or the approved file set, skip a check, accept a finding, answer a scope drift, write
   the config, push, open a pull request or make the final commit. A plan that touches a sensitive path
   (`autonomy.park-on-touch`: auth, payment, billing) is risk H, is named in the approval, and nothing there is
   repaired by rule. A High or critical finding gets the one repair; a Medium one is listed at the commit question.
   Recommended: yes. This settles PR #115, whose policy plans again by itself against four documents.
3. **Checks are judged against the project, not against fixed numbers.** A missing coverage tool is shown as "not
   measured", never as failed and never as passed. Coverage may not drop (changed lines where the data exists, else
   the total against the base). A time limit is three times the measured time on the base. The planted bug score is
   information until it is stable (it moved between 50% and 80% on one unchanged tree). Recommended: yes. Today a
   project at 55% coverage fails Check with correct code (`scripts/temper:3864`).
4. **The front of the run.** One route. Design concerns become questions in front of the approval, not a stage. The
   planner runs on a cheaper model below risk H if the test of release 1 shows equal results. The separate spec route
   of ADR 0017 is not built. Builders run on Sonnet (about 100 s faster a run for about $0.25) unless you prefer
   cents. Recommended: yes.
5. **What existing users see change.** Defaults move into code. On the first run after the upgrade one question offers
   to remove config lines that only repeat old defaults: the template copied `coverage-threshold: 80`,
   `phases.design: true` and five packs into every project, and this repository's own config still says
   `block-on: [critical]`. In release 7 the listing shrinks to `/temper:temper` and `/temper:fix`. Recommended: yes.
6. **The plugin directory: still a goal?** It sets the 256 KiB file limit (`scripts/temper` has 1,640 bytes left),
   forbids the host call that would let a handed over run return to the mod by itself, took 16 of the 33 releases of
   version 9, refused 9.8.0, and takes mods only from Verified organizations. The plan assumes yes and stays inside
   its rules. A no would shorten releases 1 and 7.
7. **PR #115.** Fix 16 defects on its branch, flip 4 defaults, merge as 9.8.5 (section 6). Recommended: yes.
8. **Scope.** Approve releases 0 to 2 now. Recommended: yes.

## 3. What a run looks like after the plan

**A clear request.** You type it. One planner writes the tasks and their tests. One card appears; you click "Approve
and build". Tests are written and locked, one builder works test first, Review and the CLI's checks run side by side.
One card shows the result; you click "Commit". Two dialogs.

**A vague request.** The same, with one dialog first that asks the rules the request left open (two dialogs when
there are more than four). This is the one place where Temper measurably beats a plain prompt: rules met rose from
73% to 98% (`docs/evidence/bench-2026-11.md:146-149`).

**A failed check.** The class of the failure picks the step. An environment fault stops the run with the fix on offer
and launches no agent. A code fault gets one repair in the stage where it happened, and the checks run again on the
new tree. If that fails, one question shows what was tried. A failed check is never run again unchanged: the tree, the
command, the environment or the limit must differ.

**A first run on an existing project.** In the first seconds the CLI reads the tool versions and services the project
asks for. Your suite runs once on the current code, in the place Build will use; its time sets the limits and its
coverage sets the floor. A red suite is one question before any planner is paid for.

**A bug fix.** Two dialogs: the root cause with the proposed fix, then the commit.

**Without the mod.** The same dialogs, the same checks, the same repairs: every change of this plan lives in the CLI
and in `temper go`, which both carriers read (`scripts/e2e/run.ts:28-31` holds them equal). The mod removes the model
from the main session ($0.28 to $0.97 a run); it is never the only way to a gain.

### The approval, as the CLI will draw it

```
APPROVE BEFORE ANY CODE IS WRITTEN                      login-lockout · risk M
You asked: "lock accounts after too many failed logins"

WHAT WILL BE TRUE (5 criteria; each gets a test written and locked first)
 1. 5 failed logins in 15 min lock the account for 15 min
 2. A locked account gets 423 and the unlock time
 3. A successful login resets the count
 4. The lock is per account, not per IP
 5. Admins are locked like everyone else
YOUR ANSWERS: lock after 5 tries in 15 min; lock per account
ASSUMED (no rule given): admins are locked like everyone else
NOT IN SCOPE: unlock by email, CAPTCHA, limits per IP

WHAT WILL CHANGE (4 files; any other file asks you first)
 Group 1  the lockout rule    + src/auth/lockout.ts  + test/auth/lockout.test.ts
 Group 2  the login endpoint  ~ src/auth/login.ts    ~ test/auth/login.test.ts
 LEFT OUT ON PURPOSE: src/admin/login.ts
 SENSITIVE PATH IN THE PLAN: src/auth/

HOW IT IS CHECKED
 your suite: npm test (48 s, passes on the current code); coverage may not drop below 71%

FROM HERE: about 7 min (from this project's earlier runs). You are asked again
only if a check still fails after one repair, and at the commit. Nothing is pushed.
```

Options: "Approve and build (Recommended)", "Change something", "Ask me at every stage", "More options". Today the
same decision shows a count of criteria and two file counts (`scripts/panel.py:129-137`). The commit card lists
criteria met, the suite, coverage, open findings by level, and everything a rule decided since the approval.

## 4. Where Temper is today: ten causes

| # | Cause | Size | Where |
|---|---|---|---|
| A | A question after every passed check | 6 dialogs plus one per Build group; only the plan approval and the commit decide anything | `scripts/flow.py:635, 673, 749, 784, 817, 1763-1766, 2338` |
| B | The planner is the money | Plan on Opus: $0.75 to $1.13 and 143 to 246 s a pass, more than a whole plain run. Half of the bytes it writes into files are read by no script and no later agent. With Design it is 64% to 83% of a run's dollars | `docs/evidence/bench-2026-11.md:275-277, 354-357` |
| C | Design is a second Opus stage no later agent reads | 88 to 116 s, $0.48 to $0.61, one question; in the PR an answered Design question recommends planning again | `scripts/decisions.py:53-69`; `scripts/flow.py:251-266, 733-739` |
| D | A repair is a trip through Build | One Review finding: a fix pass, a second full Review, 4 dialogs, Check again, $0.40 to $0.50. A step back to Plan resets every built task and erases what was tried | `scripts/flow.py:779-784, 1655-1672`; `scripts/temper:1276-1279, 1876-1896` |
| E | Faults are found late | Both failed real runs: a plan written command that could never pass, found after Build. The locked acceptance tests first run at Check, after Review. Check wants 80% coverage of the whole project | `CHANGELOG.md:72-74`; `docs/decisions/0018`; `scripts/check_run.py:656, 725` |
| F | The same tests run again and again | A clean two group run: 4 to 5 suite runs and 5 runs of each scenario test, plus up to 40 planted bug runs at Check | `scripts/task_ops.py:464, 488, 706-708`; `scripts/check_run.py:386, 693, 720` |
| G | A failed Build attempt is thrown away | A failed task gate discards the work and starts a new 122 to 193 s agent; a group rerun reverts every task | `agents/build-task.md:13-14`; `scripts/temper:3150-3161` |
| H | Nothing bounds repeats | `state redo`, `group reopen` and `group fix` are never counted; the shipped `max-total-loops: 4` is read by nothing; 33 places pick a next step under 11 separate limits | `scripts/loop_step.py:20-32`; `scripts/temper:1455-1492` |
| I | A model in the main session | Without the mod, or after any hand back: $0.28 to $0.97 and 22 to 59 turns. A failed `integrate` or group check is read as an error and hands the run over for good | `scripts/go.py:108-114`; `docs/evidence/bench-2026-11.md:441-446` |
| J | The product only grows | In 31 days: question sites 23 to 41, briefs 9 to 13, config keys 38 to 53. Seven "lean" efforts, one measured, all in prompt bytes. CI takes 30 to 60 minutes; one new option touches 10 files | `CHANGELOG.md` 9.7.0 to 9.8.5 |

## 5. The targets and what they rest on

| Class | Cost against plain | Time against plain | Dialogs | Rests on |
|---|---|---|---|---|
| Bug | at most 1.5 times | at most 2.5 times | 2 | already true on clean runs; the plan must not make it worse |
| Clear feature | at most 2 times | at most 4.5 times | 2 | the planner on Sonnet at $0.30 to $0.44 and about 150 s, never yet run; one Sonnet builder at 122 to 134 s (measured); Review beside the checks |
| Vague feature | at most 3 times | at most 4.5 times | 3 or 4 | the same, plus Intent and the acceptance writer at about $0.10 each (by subtraction, never measured alone) |

Three things decide whether these hold:

1. **The model, not the contract.** Halving what Plan writes saves a quarter of its output, about $0.14 a pass. Moving
   it to Sonnet saves about half its cost. If the test of release 1 shows worse plans on Sonnet, the planner stays on
   Opus, and the clear feature lands at about 2.5 times, not 2.
2. **Cents against seconds.** A Sonnet builder is 104 s faster and $0.24 dearer a run than Haiku. The table assumes
   Sonnet (decision 4).
3. **The bench is small.** Every second above is machine time on Python projects under 1,000 lines with a simulated
   person who answers at once. The one real Java run was 4 to 13 times slower per launch. Release 1 adds a scripted
   slow project, and release 6 starts with one real Maven or Gradle project measured.

Every pass line also holds a value floor: hidden tests equal to today's, and at least 95% of the rules met on the
vague tasks. A release that gets cheaper by getting worse does not ship.

## 6. Pull request #115

**Verdict: do not merge the head as it is; fix it on its branch and merge it as 9.8.5.** For a user who changes no
config, the head asks the same number of questions as 9.8.4 and adds loops: a Medium finding now recommends a loop
back to Build, and any answered Design question recommends planning again. Its real gains (the declared environment,
honest failure text, reuse of a passed check, only CLI made runs counting) are sound, and the later releases build on
its command runner, its setup block, its policy code and its reuse store. Splitting it is not worth it: 10 of its 16
commits touch `scripts/flow.py`.

- **Fix 16 defects** (appendix B). Twelve were reproduced in a clone at the head. Seven sit on a default user's path:
  a fix pass that breaks the suite strands the run for good; a passed Review with a Medium finding loses "Accept a
  finding" and "Save for later"; the Check agent's brief still records claimed runs that no longer count; a code bug
  that prints "Connection refused" is judged an environment fault with no way out; an environment fault at Check
  recommends the same repair without end; a plan command over 300 s fails the plan gate with a remedy that cannot
  work; a failed preflight is stored and returned after the environment was repaired.
- **Flip 4 defaults.** A Medium finding recommends "Continue to Check" until release 4 makes a repair cheap. A Design
  answer passes its row with a note. The preflight runs only the Integration line and the group Validates, under one
  total limit. "High blocks Review" is yours to keep; I would keep it.
- **Settle one rule.** Under `autonomy.policy: decide` a failed group check ends in an unattended step back to Plan
  (`scripts/flow.py:1966-1972`). The config template, `reference/autonomy.md`, `docs/grouped-build.md` and ADR 0011 say
  never. Keep the rule: one condition makes the policy stop and ask.
- **Add two tests.** One end to end scenario that walks a policy run through a failed group and a finding; one
  selftest for the reuse store. CI was green because no test walks these paths.

## 7. The releases

Each release ships alone, changes its documents in the same change, keeps a run saved by the release before working
(one selftest each), and has a pass line on the scorecard.

### Release 0. 9.8.5 without its regressions (5 to 7 days)

- **0a, first, as its own small change on main.** Cancel superseded CI runs and split the selftest job: the PR's 14 CI
  runs took about 546 minutes, and 4 were green. Write `scripts/selftest/view-fixtures.ts` one view per line (about
  72 KB freed where 3 KB are left; to be checked against the type check). Move `CHANGELOG.md` entries before 9.7 to
  `docs/history` (15 KB are left under the file limit).
- **0b.** Section 6, on the PR branch. Also keep one line per finished run (dialogs, steps back, launches, seconds) in
  the project: `state clear` deletes those records today (`scripts/temper:1448`), so no installed copy can say how
  often a loop fires.

- **Pass line:** no item of appendix B reproduces; a default scripted run asks no more than 9.8.4 and recommends no
  loop that 9.8.4 did not.

### Release 1. Measure, and stop failing correct work (8 to 12 days)

Nothing here changes how a run flows. Everything after leans on it.

- **1a. CI in about 10 minutes** (a median under 12, none over 20): the selftest split by case file, two end to end
  shards per mode with a step limit per scenario, a docs only path filter, the manifest job pinned to one Claude Code
  version.
- **1b. A scorecard in `bench/`.** Per run: dialogs by stage and kind, steps back, launches by agent type, seconds
  and dollars per agent type, hand backs, seconds to the first decision, permission prompts, hidden tests and rules
  met. The logs already hold all but the steps back. Add two scripted projects that cost no model call: a slow one
  (build file one folder down, a 15 minute fake suite, 55% coverage, no coverage tool) and a broken one (wrong tool
  version, a service down, one failing and one flaky test).
- **1c. The "before" round and the model test.** The six bench tasks on 9.8.5 against plain Claude Code (about $45),
  then Plan and Design on Sonnet against Opus, which needs no code (about $40). This decides the cost target.
- **1d. Checks judged against the project** (decision 3, the part that needs no baseline): a missing coverage tool is
  "not measured"; the planted bug score is information beside Review; neither stops an unattended run nor sends it
  back to Build, as both do today (`scripts/flow.py:1178-1180`).
- **1e. Defaults in code, a template of about 10 lines**, and the one time question of decision 5.
- **1f. Ids in the protocol**, added inside version 1: an id for each question and option and `recommended` as a
  field. `scripts/go.py` passes them on; the policy and the mod's driver select by id. Tests move to ids only when
  their question changes. Today the policy itself matches on the text "(Recommended)" (`scripts/flow.py:1967`).
- **1g. A floor and caps in CI.** The scripted scenarios give dialogs, launches and suite runs with no model call; one
  file holds them, compared exactly. The fixtures are made faithful first: they write `reviewed: auto`, which no real
  planner does, so today's scripted count is 7 where a person meets 8. A second file caps agent briefs (13), question
  sites (53), option labels (71), gate rows, config keys and prompt bytes.
- **Room under the file limit:** each release frees what it adds to `scripts/temper` plus 8 KB, by moving code into
  its Python modules. The known mistake is restated as "gate logic lives in the CLI (the script and its Python
  modules), never in a prompt".

- **Pass line:** both scripted projects pass Check on correct code with no config edit; the "before" table and the
  model test published from the scorecard.

### Release 2. Two approvals (14 to 18 days)

In this order:

- **2a. A verdict is a verdict for every carrier.** `gate`, `group gate` and `integrate` mark a recorded verdict in
  one machine readable way; `scripts/go.py`, the driver (`core/driver.ts:261, 432`) and the command page read it. A
  failed check no longer hands a run to the main session.
- **2b. One budget.** Every repeat counts in the CLI: 2 per failure, 6 per run. The flow reads the budget and never
  offers a call that would be refused; at the limit the run asks and shows the count, and only the person grants
  more. It replaces `loops.max-per-type` and `fix.max-loops`, and the dead `autonomy.budget` keys go.
- **2c. Design runs only when asked** (the cheap half of release 5's fold).
- **2d. The Context check is asked only when the map flags something.** A clean map passes (10 lines, tested).
- **2e. The approval runs to the commit.** The first option of the plan question approves and lets the run go on;
  passed checks advance as the CLI's own action; "Ask me at every stage" is second
  (`scripts/flow.py:672-689, 1144-1181, 2441-2474`). No table of the mod's guard changes: the choice stays a call of
  the option the person picked. Prototyped on eight states; not yet prototyped: the failed `integrate` and the commit
  options. In the same change: a stop no longer switches the mode off for good (`scripts/temper:4520`), except after a
  skip, an accepted finding or a step back; the commit question carries the pull request options and a way back;
  every stop of an unattended run is a recorded stop with a notice; a blocking finding gets one counted loop back to
  Build, and a second one asks.
- **2f. The approval is bound to what was shown.** Its calls carry the digests of the intent and the plan; the CLI
  refuses on a mismatch, and the Build, Check and commit gates get the row "intent unchanged since the approval". The
  mod refuses writes to `intent.md` from Build on. Before the approval the run writes only its spec folder: no branch
  and no commit.
- **2g. The run leaves Intent by rule; the approval click accepts the intent.** A passed Intent gate with an
  `intent.md` and nothing open moves on as the CLI's own action; the approval's first option writes the acceptance,
  and the CLI's panel shows the criteria one line each. The approval gets "Loop back to Intent". The planner gets the
  request text, which only Intent has today (`scripts/flow.py:1126-1130`). The separate Intent question stays when its
  gate fails, when you typed a note there, after a loop back to it, and for a door. Prototyped: one question where the
  head asks three.
- **2h. Two holes closed before the default changes.** `temper evidence resolve` turns a failed Review gate to PASS
  with any text and no change (reproduced; on main too): it checks its commit. Review's completion row names the
  files it read and the gate compares them with the change: today a reviewer that reads 2 of 14 files passes.
- **Documents in this release:** a decision record that amends ADR 0013; `README.md:30`; `reference/autonomy.md`;
  `docs/flow.md`; the config template; `.claude/CLAUDE.md`.

- **Pass line:** a clean scripted feature run asks 2 dialogs with a clean map and 3 with a flagged one; the bench
  mean is at most 4; no clean run is handed back; hidden tests and rules met equal the "before" round.

### Release 3. The cards, and no hand back (11 to 16 days)

- **3a. The cards of section 3**: a view field that the mod draws above the dialog and the CLI prints as text where no
  mod is loaded; the commit card with its numbers. A flagged Context Map is shown whole in the approval, and its click
  records the answer.
- **3b. The hand back causes become a closed list of named kinds, each one step.** Today there are 31 sites and about
  14 causes; most need no model (a verdict misread, a call that is not the CLI's, Cancel at a question). The mod's
  three live defects go with it: a typed Context check answer is refused, its limit is 100 characters against the
  CLI's 2,000, and a driven fix run gets no branch.
- **3c. `/temper:fix` asks twice**, and its checks start beside Review as a feature run's do
  (`scripts/flow.py:1375-1378`).
- **3d. TRIVIAL is a verdict the CLI records**, with a size bound the commit hook checks, and the one line change is
  made in the same turn.
- **3e. Without the mod, a classic hook holds the write rule until the approval**, if the plugin directory allows it.

- **Pass line:** a clean scripted bug run asks 2 dialogs; a scripted run with one failed group check and one failed
  `integrate` is carried to its question with no hand back; a reader decides each sample card in under a minute.

### Release 4. Repair where it happened (13 to 17 days)

- **4a. The locked acceptance tests run when Build ends**, inside `integrate`. A failure there gets the triage first
  (is the test wrong or the code), in every mode; an environment fault gets the setup question and no fix agent. Today
  they first run at Check, after Review: three runs looped to $23 to $38 on a wrong test.
- **4b. A finding is repaired in its stage.** The reviewer records a whole finding (description, suggestion, whether
  a test can prove it). The CLI opens a repair window as its own action, on named rows, under Build's write rule. A
  fresh Build agent fixes. The CLI makes one commit whose parent is the reviewed tree, then runs `integrate`, the
  Build gate and Check's run on the new tree. A narrow recheck by a reader that did not write the fix confirms each
  finding, and only then is it resolved, by that commit. A repair that made things worse is reverted. A change that
  deletes test lines is never resolved by rule. One repair by rule per stage, one more on your click, then the old
  loop back as the way out. Launches stay at two; four dialogs go to none.
- **4c. Never by rule:** a contested finding, a file outside the plan, a sensitive path, an unfinished Review, an
  environment fault, a check that was not measured, a criterion only you can confirm, an acceptance test the triage
  does not blame on the code.
- **4d.** The plan gate gets the row "a group with no Validate", and `plan patch` can insert a missing one.

- **Pass line:** on the bench, a repaired finding costs no dialog and no second full Review; the share of runs with
  two or more Reviews (7 of 18 today) at most halves.

### Release 5. A lean front (11 to 16 days, about $100 of bench)

Items 5a and 5b touch only briefs and plan rows and can start beside release 2.

- **5a.** At the simple tier Plan writes `tasks.md` only. The plan gate already passes with no `plan.md` (measured);
  the brief still asks for three files.
- **5b.** Elsewhere Plan writes what something reads: a scenario is a name, Covers, Test and one Then line; the file
  tables, Risk Level, Patterns, Dependencies, the diagram copy and the `Cross-Repo` line go; the CLI lists files and
  computes risk. Measured on the one real plan in git: 50% to 56% fewer file bytes.
- **5c.** A revision is a narrow agent on Sonnet that gets the findings or your note and the affected task blocks,
  runs the plan gate, and falls back to a full pass on a second failure. The failed complex run paid five full Opus
  passes.
- **5d.** Design folds into Plan. Concerns become questions shown with the approval; the plan is written under each
  first choice, and the hold "tasks agree with decisions" fails only for another answer. At risk H one fresh review
  round takes the place of the second reading, and the approval offers the unattended run only when that round left no
  open High finding.
- **5e.** The planner's model by tier and risk, from the test of 1c, run again on two tasks after 5a and 5b (about
  $12). The CLI bounds the tier; a sensitive path makes risk H by rule.
- **5f.** The acceptance writer runs beside the first builder if a bench arm without it (about $26) shows it earns
  its place. It is never folded into the builder: the tests that gate the code are written by an agent that does not
  see the builder's work.
- **5g.** The CLI records `code` and `metric` criteria itself. Today they cost a hidden Build "record pass" and a
  Check agent.

- **Pass line:** a clear feature at most 2 times the cost of plain Claude Code and a vague one at most 3 times; no
  rise in blocked tasks or steps back to Plan against the "before" round.
- **Go or no go:** if the Sonnet planner shows worse plans, 5e is dropped and the cost line becomes 2.5.

### Release 6. Faults found early (16 to 22 days)

It starts with one real Maven or Gradle project measured, so the gain is known before the work. PR #115's preflight
and setup block already stop the two failed real runs as they happened; this release does the same for other stacks
and slow suites.

- **6a. An environment check before the first agent**, in under 5 s: the tool versions and services the project's
  files ask for, in the root and one folder down.
- **6b. A baseline when the run starts.** The command the gates will run, in its coverage form, on the current code,
  in the place Build uses, beside Intent. Three results: green, red, unknown. A red base is one question with the
  proposed setup block; "go on anyway" is recorded as your skip, and new failures still fail. Its time sets every
  later limit (three times, doubled once, then asked), and its coverage sets the floor of decision 3.
- **6c. A command the plan itself wrote runs once on the base, by the CLI, after the planner returned**, never inside
  an agent's turn, under Build's limit; a time out is its own class. This replaces the PR's per command preflight and
  its text patterns.
- **6d. One digest, and every verdict names its tree.** The digest is the tree with recorded byproducts left out;
  neither existing one survives a `.coverage` file, so the background check throws its own run away today. Scenario
  tests go through the reuse store. A check that is green on the base and then fails runs once more before any agent,
  and fail then pass is recorded as flaky. A counted "run it anyway" stays, and every reuse is recorded. Whether one
  command should own the suite for `integrate` and Check is decided on the real project's numbers.
- **6e. One failure record**, typed (environment, command, plan, code, not measured) and kept outside the Build
  state, so a step back no longer erases what was tried.
- **6f. A plan amendment in place of a replan, in two calls.** `plan amend`, by rule and logged so: it only adds a
  file the same group already owns to a task. `plan patch`, yours: every command line and every file outside the
  approved set. The approved plan's record is never overwritten; amendments are appended and shown at the commit. A
  full replan keeps built tasks whose approved fields did not change.

- **Pass line:** on the scripted broken project every fault is named before Build with no agent launched for it; on
  the scripted slow project no limit is hit and the suite runs at most three times; the real project measured again.

### Release 7. A smaller surface (8 to 12 days)

- **7a.** Two listed commands. `draft`, `status`, `report`, `init` and `pack` become words of `/temper:temper`; the
  doors go.
- **7b.** Default packs security and tdd; the six stack packs nothing loads and the three skills nobody can call go.
- **7c.** Dormant machinery goes: the OCR text, bands, review memory, the metrics writes, `evidence.claimed-runs`.
- **7d.** At most 12 words a user must learn, one word for "stage", and "armed" and "parked" out of user text.
- **7e.** Getting Started rewritten as one page that matches the product, with the first run on an existing project
  walked through; a one time notice of what changed.

- **Pass line:** 2 listed commands; every config key and every written section has a reader; the 12 places where docs
  and code disagree are gone.

### Later: separate proposals, each on its own measured reason

- A Build task agent that checks its own gate and repairs before it returns. In 18 measured runs no retry was caused
  by the model, so the gain is unshown.
- One front launch for a request that leaves nothing open. It buys under 30 s and changes a guard table.
- The next step after a failed check as one function over the failure record (a rewrite of about 900 lines of
  question logic).
- The flow as data: one spec for stages, rows, questions and keys, with generators for the mod's tables, the template
  and the doc tables.
- The CLI as one Python package, one process per call (process starts are about 31 s of a small run).
- A chain of tasks built in the group's one worktree. A 21 line prototype passed; the gain is on compiled stacks and
  is unmeasured.
- The mod's guard without the parts that exist only for a model in the main session (about 400 lines).

## 8. Rules the plan never breaks

1. Before the approval a run writes only its spec folder and Temper's own run files: no project file, no branch, no
   commit.
2. The approval is of what was shown; a later change to the intent or the plan fails the gates until you approve again.
3. Only an option you picked starts an unattended run; a step back, a skip or an accepted finding ends it.
4. An unattended run never plans again, changes a gate's command, the intent or the approved file set, skips a check,
   accepts a finding, writes the config, pushes, opens a pull request or makes the final commit.
5. Every verdict is computed by the CLI from runs the CLI made or you confirmed, and names the tree it judged.
6. A failure's class picks the next step, never a verdict. A check that was not measured is shown as not measured.
7. Tests come first, and the tests that gate the code are written and locked by an agent that did not write it.
8. A finding is resolved only by the CLI, for a commit the CLI made, after its checks passed on that tree and a
   reader that did not write the fix confirmed it.
9. Every repeat is counted in the CLI against one budget; only you grant more.
10. You decide only in a question dialog, and the commit question lists everything a rule decided since the approval.
11. Each of these holds in the CLI or the commit hook with the mod off. Where only the mod holds something (that a
    person clicked), the docs say so.

## 9. What keeps it from growing back

- **A test, not a habit.** A selftest fails on any question after a passed check other than the approval and the
  commit. Every question names the decision it asks for.
- **Caps only you raise.** The floor and cap files of 1g are compared exactly; a change that raises one fails CI.
  Raising a cap is a pull request of its own with your approval. A second file lists the stops that must stay, so the
  caps cannot be met by removing a safety stop.
- **A release gate in run units.** The scorecard of the last bench round is a committed file; a release ships only
  when it holds its pass line. Targets are never set in prompt bytes again.
- **Removal first.** Before a fault found in a run adds a row, a question, a key or an agent, the change shows that
  the failing step cannot be removed or merged. The rule goes into `.claude/CLAUDE.md`, which every building session
  loads.
- **A freeze.** While the plan runs and for 60 days after, no new stage, agent or question outside it.

## 10. Not in the plan, on purpose

- No second route (ADR 0017 as written): one route with skips the CLI decides from facts it holds.
- No further prompt byte diets. Seven were tried; the one measured cut left run time unchanged.
- No new lists of failure text patterns.
- No move of the run into a host workflow: it cannot hold a question in the middle of a run.
- No continuing of finished agents as a base of the design. It rests on a host call seen in one version, and it costs
  a turn in the main session.
- No build on the run's own branch, and no build output shared between worktrees.
- No new stack detection. A project the CLI cannot read is told so in the first lines.

## 11. What could prove the plan wrong

- Plans get worse on a cheaper model or with the smaller contract, and steps back to Plan rise. Release 1 measures it
  before any default changes, and release 5 has a no go line.
- People often correct the intent at the Intent question. Then 2g moves that cost into a second planner pass. Nothing
  records how often today; the run summary of release 0 will, and the separate Intent question can come back as the
  default with one key.
- The narrow recheck of 4b misses a defect a fix causes outside its change. The CLI's runs on the new tree are the
  only mechanical guard, so a project with a thin suite gets less protection than a second full Review gave.
- A wrong digest serves a stale pass. Release 6 keeps a counted "run it anyway" and records every reuse.
- Few users have the mod. The plan keeps every gain in the CLI for that reason, but a run without the mod still pays
  for a model in the main session.
- The numbers do not carry over to real projects. The scripted slow project and one real measurement are the check.
- The effort is larger than stated. Only half of the items were sized by a verifier; the rest are estimates.

## Appendix A. How this plan was made, and the limits of its evidence

Seventeen readers mapped the project at the PR head, one per subsystem, each citing `file:line`; a cross check settled
20 contradictions between them in the code. Ten verifiers tested each mechanism of a first draft against the code,
several with a prototype in a clone (the two approval flow in 31 lines, the unattended default in 18, one worktree
per chain in 21). Three planners wrote independent plans without seeing the draft, and four reviewers attacked it:
on safety, on completeness, on feasibility and order, and by replaying the failed runs through it. Their corrections
are in this text; the working papers are with the owner and are not part of the repository.

Limits: no run was measured live on 9.8.5. Every dollar and second comes from 9.8.0 and 9.8.4 runs on 11 tasks
written by the author, in Python projects of 22 to 583 lines, with a simulated person who approves everything at
once, mostly 2 or 3 runs a cell. Prototypes were run on scripted states; the selftest, the end to end suite and the
mod's tests were not run on them.

## Appendix B. The merge list of pull request #115

| # | What goes wrong | Where |
|---|---|---|
| M1 | After a loop back to Build, a fix pass that breaks the Integration suite strands the run: `integrate` can never pass again, and the fix agent relaunches with no question | `scripts/temper:3316-3327, 3387-3397, 3430`; `scripts/flow.py:1658-1671` |
| M2 | A passed Review with an open Medium finding loses "Accept a finding", "Grill Me", "Teach Me" and "Save for later" | `scripts/flow.py:925-930, 943-947` |
| M3 | Under the policy the group fix agent is never launched | `scripts/flow.py:1754` |
| M4 | The policy steps back to Plan unattended, against four documents | `scripts/flow.py:1966-1972, 2003-2005` |
| M5 | After that step the run stays unattended whatever the person answers, and a passed Design is skipped | `scripts/flow.py:673, 2441-2462`; `scripts/temper:1269-1295` |
| M6 | The policy loops back to Build for a criterion only the person can confirm | `scripts/flow.py:1173-1180` |
| M7 | The Check agent's brief records a claimed test run, which no longer counts; Check cannot pass where the CLI finds no test command | `agents/check.md:30-31`; `scripts/runs.py:30-33` |
| M8 | The template's empty `build:` key discards the documented `build.grouped` block; an appended `autonomy:` block drops `park-on-touch` the same way. The reader should merge a repeated key | `templates/temper.config.default:155`; `scripts/config_yaml.py:27-30` |
| M9 | A code bug that prints "Connection refused" is judged an environment fault; the only options are "Check it again" and "Save for later" | `scripts/flow.py:1857-1870`; `scripts/task_ops.py:761-767` |
| M10 | An environment fault at Check recommends the same repair every round | `scripts/flow.py:837-851` |
| M11 | The commit question says "check again" and has no option that does | `scripts/flow.py:2245-2277` |
| M12 | The mod allows a push to any remote from any source when the destination is a `temper-backup/` branch; nothing uses it | `hooks/temper-mod/core/session.ts:123-134, 154` |
| M13 | A setup block reaches the config without the person seeing it, and the check passes a block that fakes the tool. The environment agent should not be offered | `scripts/flow.py:1200-1204, 1220-1225`; `scripts/preflight.py:227-243`; `scripts/doctor.py:457-483` |
| M14 | Three new files decide gate rows and none is guarded by the mod: the reuse store, `.temper/preflight.json`, `.temper/decisions.json` | `hooks/temper-mod/core/rules.ts:108-122` |
| M15 | A plan command over 300 s fails the plan gate as an "environment fault" | `scripts/preflight.py:31, 80-81` |
| M16 | A failed preflight is stored and returned after the environment was repaired; no option checks again | `scripts/preflight.py:165-171`; `scripts/flow.py:693-701` |

M12 and M14 were found by reading; the others were reproduced at least in part in a clone at the head. A further 29
smaller points can follow the merge.
